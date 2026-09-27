-- SMART ORDER B2.2 foundation: tenant/runtime/data/auth hardening
-- Backward-compatible stage. Final legacy closure + signed-QR cutover is a later B2 migration.
begin;

-- 1. Close the only remaining table-level RLS gap without exposing new privileges.
alter table private.kds_realtime_channels enable row level security;
revoke all on table private.kds_realtime_channels from anon, authenticated;

-- 2. Freeze row-shape invariants. NOT VALID constraints protect new rows while
-- allowing the one pre-B2 8-hour Admin session to age out naturally.
do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='private.admin_sessions'::regclass and conname='admin_sessions_token_hash_shape_b2') then
    alter table private.admin_sessions
      add constraint admin_sessions_token_hash_shape_b2
      check (token_hash ~ '^[a-f0-9]{64}$');
  end if;
  if not exists(select 1 from pg_constraint where conrelid='private.admin_sessions'::regclass and conname='admin_sessions_expiry_order_b2') then
    alter table private.admin_sessions
      add constraint admin_sessions_expiry_order_b2
      check (expires_at > created_at);
  end if;
  if not exists(select 1 from pg_constraint where conrelid='private.admin_sessions'::regclass and conname='admin_sessions_kds_fingerprint_b2') then
    alter table private.admin_sessions
      add constraint admin_sessions_kds_fingerprint_b2
      check (session_scope <> 'kds' or client_fingerprint_hash is not null);
  end if;
  if not exists(select 1 from pg_constraint where conrelid='private.admin_sessions'::regclass and conname='admin_sessions_max_ttl_b2') then
    alter table private.admin_sessions
      add constraint admin_sessions_max_ttl_b2
      check (expires_at <= created_at + interval '6 hours') not valid;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='private.tenant_table_qr_signatures'::regclass and conname='tenant_table_qr_number_b2') then
    alter table private.tenant_table_qr_signatures
      add constraint tenant_table_qr_number_b2 check (table_number between 1 and 200);
  end if;
  if not exists(select 1 from pg_constraint where conrelid='private.tenant_table_qr_signatures'::regclass and conname='tenant_table_qr_hash_b2') then
    alter table private.tenant_table_qr_signatures
      add constraint tenant_table_qr_hash_b2 check (signature_hash ~ '^[a-f0-9]{64}$');
  end if;
  if not exists(select 1 from pg_constraint where conrelid='private.tenant_runtime_config'::regclass and conname='tenant_runtime_single_origin_contract_b2') then
    alter table private.tenant_runtime_config
      add constraint tenant_runtime_single_origin_contract_b2 check (
        not (settings ? 'canonical_origin') or (
          public_origin = settings->>'canonical_origin'
          and admin_origin = settings->>'canonical_origin'
          and kds_origin = settings->>'canonical_origin'
          and settings->'surface_routes'->>'public' = '/'
          and settings->'surface_routes'->>'admin' = '/admin'
          and settings->'surface_routes'->>'kds' = '/kds'
          and settings->'surface_routes'->>'database' = '/database'
          and settings->>'database_url' = (settings->>'canonical_origin') || '/database'
        )
      );
  end if;
end $$;

create unique index if not exists tenant_origin_aliases_one_canonical_b2
  on private.tenant_origin_aliases(tenant_id)
  where enabled and alias_kind='canonical';

-- 3. Additive tenant context contract. Existing keys remain unchanged.
create or replace function public.master_prototype_tenant_context(p_tenant_id uuid)
returns jsonb
language sql
stable security definer
set search_path=''
as $$
select jsonb_build_object(
  'ok',true,
  'tenant_id',t.id,
  'tenant_slug',t.slug,
  'tenant_name',t.name,
  'organization_id',t.organization_id,
  'business_name',c.business_name,
  'merchant_name',c.merchant_name,
  'locale',c.locale,
  'currency',c.currency,
  'timezone',c.timezone,
  'public_origin',c.public_origin,
  'admin_origin',c.admin_origin,
  'kds_origin',c.kds_origin,
  'canonical_origin',nullif(c.settings->>'canonical_origin',''),
  'database_url',nullif(c.settings->>'database_url',''),
  'surface_routes',coalesce(c.settings->'surface_routes','{}'::jsonb),
  'table_count',c.table_count,
  'require_table_qr_signature',c.require_table_qr_signature,
  'qris_asset',c.qris_asset,
  'storage_static_bucket',c.storage_static_bucket,
  'storage_payment_bucket',c.storage_payment_bucket,
  'settings',c.settings,
  'enabled',c.enabled
)
from private.platform_tenants t
join private.tenant_runtime_config c on c.tenant_id=t.id
where t.id=p_tenant_id
  and t.status='active'
  and c.enabled
limit 1
$$;
revoke all on function public.master_prototype_tenant_context(uuid) from public,anon,authenticated;
grant execute on function public.master_prototype_tenant_context(uuid) to service_role;

create or replace function public.master_prototype_runtime_context(
  p_tenant_id uuid default null::uuid,
  p_origin text default null::text,
  p_app_kind text default null::text
)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  v jsonb;
  v_origin jsonb;
  v_enforce boolean;
  v_ref uuid;
begin
  if p_app_kind is not null and p_app_kind not in ('public','admin','kds','database') then
    return jsonb_build_object('ok',false,'error','invalid_app_kind');
  end if;

  if p_tenant_id is not null then
    select public.master_prototype_tenant_context(p_tenant_id) into v;
    if not coalesce((v->>'ok')::boolean,false) then
      return jsonb_build_object('ok',false,'error','tenant_not_resolved');
    end if;

    if nullif(trim(coalesce(p_origin,'')),'') is not null then
      select public.master_prototype_resolve_origin(p_origin,p_app_kind) into v_origin;
      if not coalesce((v_origin->>'ok')::boolean,false) then
        return jsonb_build_object('ok',false,'error','origin_not_registered');
      end if;
      if (v_origin->>'tenant_id')::uuid<>p_tenant_id then
        return jsonb_build_object('ok',false,'error','origin_tenant_mismatch');
      end if;
      return v || jsonb_build_object(
        'resolution','explicit_tenant_id+registered_origin',
        'resolved_origin',v_origin->>'resolved_origin',
        'surface_route',v_origin->>'surface_route',
        'origin_verified',true,
        'compat_fallback',false
      );
    end if;

    return v || jsonb_build_object(
      'resolution','explicit_tenant_id',
      'origin_verified',false,
      'compat_fallback',false
    );
  end if;

  if nullif(trim(coalesce(p_origin,'')),'') is not null then
    select public.master_prototype_resolve_origin(p_origin,p_app_kind) into v;
    if coalesce((v->>'ok')::boolean,false) then
      return v || jsonb_build_object(
        'resolution','registered_origin',
        'origin_verified',true,
        'compat_fallback',false
      );
    end if;
    return v;
  end if;

  select enforce_client_rls into v_enforce
  from private.platform_tenancy_state where id=1;

  if coalesce(v_enforce,false) then
    return jsonb_build_object('ok',false,'error','explicit_tenant_required');
  end if;

  v_ref:=private.reference_tenant_id();
  select public.master_prototype_tenant_context(v_ref) into v;
  if coalesce((v->>'ok')::boolean,false) then
    return v || jsonb_build_object(
      'resolution','reference_compatibility_bridge',
      'origin_verified',false,
      'compat_fallback',true
    );
  end if;
  return jsonb_build_object('ok',false,'error','reference_tenant_unavailable');
end
$$;
revoke all on function public.master_prototype_runtime_context(uuid,text,text) from public,anon,authenticated;
grant execute on function public.master_prototype_runtime_context(uuid,text,text) to service_role;

-- 4. Scope isolation: KDS tokens must never authorize Admin-only session/superadmin paths.
create or replace function private.tenant_is_super_from_token(p_tenant_id uuid,p_token text)
returns boolean
language sql
stable security definer
set search_path=''
as $$
select exists(
  select 1
  from private.admin_sessions s
  join private.tenant_memberships tm
    on tm.tenant_id=s.tenant_id
   and lower(tm.email)=lower(s.email::text)
  where s.tenant_id=p_tenant_id
    and s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at>now()
    and s.session_scope='admin'
    and tm.is_active
    and tm.role='superadmin'
)
$$;
revoke all on function private.tenant_is_super_from_token(uuid,text) from public,anon,authenticated;
grant execute on function private.tenant_is_super_from_token(uuid,text) to service_role;

create or replace function public.admin_password_session_info_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email extensions.citext; v_role text; v_name text;
begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false);
  end if;
  select s.email,tm.role,coalesce(au.display_name,'')
    into v_email,v_role,v_name
  from private.admin_sessions s
  join private.tenant_memberships tm
    on tm.tenant_id=s.tenant_id
   and lower(tm.email)=lower(s.email::text)
   and tm.is_active
  left join public.admin_users au on au.email=s.email
  where s.tenant_id=p_tenant_id
    and s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and s.session_scope='admin'
  limit 1;
  if v_email is null then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object(
    'ok',true,'email',v_email::text,'display_name',v_name,
    'role',v_role,'tenant_id',p_tenant_id,'session_scope','admin'
  );
end
$$;
revoke all on function public.admin_password_session_info_tenant(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_password_session_info_tenant(uuid,text) to service_role;

create or replace function public.admin_password_session_info_bound_tenant(
  p_tenant_id uuid,p_token text,p_fingerprint_hash text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email extensions.citext; v_role text; v_name text; v_scope text;
begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$'
     or p_fingerprint_hash is null or p_fingerprint_hash !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false);
  end if;
  select s.email,tm.role,coalesce(au.display_name,''),s.session_scope
    into v_email,v_role,v_name,v_scope
  from private.admin_sessions s
  join private.tenant_memberships tm
    on tm.tenant_id=s.tenant_id
   and lower(tm.email)=lower(s.email::text)
   and tm.is_active
  left join public.admin_users au on au.email=s.email
  where s.tenant_id=p_tenant_id
    and s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and s.session_scope in ('admin','kds')
    and (
      (s.session_scope='admin' and (s.client_fingerprint_hash is null or s.client_fingerprint_hash=p_fingerprint_hash))
      or
      (s.session_scope='kds' and s.client_fingerprint_hash=p_fingerprint_hash)
    )
  limit 1;
  if v_email is null then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object(
    'ok',true,'email',v_email::text,'display_name',v_name,
    'role',v_role,'tenant_id',p_tenant_id,'session_scope',v_scope,
    'fingerprint_bound',v_scope='kds' or exists(
      select 1 from private.admin_sessions s
      where s.tenant_id=p_tenant_id
        and s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
        and s.client_fingerprint_hash is not null
    )
  );
end
$$;
revoke all on function public.admin_password_session_info_bound_tenant(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_password_session_info_bound_tenant(uuid,text,text) to service_role;

-- 5. New Admin logins are 6h, tenant-bound and capped to three sessions.
create or replace function public.admin_password_login_tenant(p_tenant_id uuid,p_email text,p_password text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext; v_role text; v_name text; v_hash text;
  v_token text; v_exp timestamptz;
begin
  if p_email is null or p_password is null or length(p_password)>256 then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;
  if not exists(
    select 1 from private.platform_tenants t
    join private.tenant_runtime_config c on c.tenant_id=t.id
    where t.id=p_tenant_id and t.status='active' and c.enabled
  ) then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  select au.email,tm.role,au.display_name,ap.password_hash
    into v_email,v_role,v_name,v_hash
  from private.tenant_memberships tm
  join public.admin_users au on lower(au.email::text)=lower(tm.email)
  join private.admin_passwords ap on ap.email=au.email
  where tm.tenant_id=p_tenant_id
    and lower(tm.email)=lower(trim(p_email))
    and tm.is_active and au.is_active
  limit 1;

  if v_hash is null or extensions.crypt(p_password,v_hash)<>v_hash then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;
  if v_hash ~ '^\$2[aby]\$[0-9]{2}\$' and split_part(v_hash,'$',3)::int<12 then
    update private.admin_passwords
      set password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',12)),updated_at=now()
      where email=v_email;
  end if;

  delete from private.admin_sessions where expires_at<=now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_exp:=now()+interval '6 hours';
  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash,tenant_id)
  values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp,'admin',null,p_tenant_id);

  delete from private.admin_sessions s
  where s.tenant_id=p_tenant_id and s.email=v_email and s.session_scope='admin'
    and s.token_hash not in (
      select s2.token_hash from private.admin_sessions s2
      where s2.tenant_id=p_tenant_id and s2.email=v_email and s2.session_scope='admin'
      order by s2.expires_at desc limit 3
    );

  return jsonb_build_object(
    'ok',true,'token',v_token,'email',v_email::text,
    'display_name',coalesce(v_name,''),'role',v_role,
    'expires_at',v_exp,'tenant_id',p_tenant_id,'session_scope','admin',
    'fingerprint_bound',false
  );
end
$$;
revoke all on function public.admin_password_login_tenant(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_password_login_tenant(uuid,text,text) to service_role;

create or replace function public.admin_password_login_bound_tenant(
  p_tenant_id uuid,p_email text,p_password text,p_fingerprint_hash text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext; v_role text; v_name text; v_hash text;
  v_token text; v_exp timestamptz;
begin
  if p_email is null or p_password is null or length(p_password)>256
     or p_fingerprint_hash is null or p_fingerprint_hash !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;
  if not exists(
    select 1 from private.platform_tenants t
    join private.tenant_runtime_config c on c.tenant_id=t.id
    where t.id=p_tenant_id and t.status='active' and c.enabled
  ) then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  select au.email,tm.role,au.display_name,ap.password_hash
    into v_email,v_role,v_name,v_hash
  from private.tenant_memberships tm
  join public.admin_users au on lower(au.email::text)=lower(tm.email)
  join private.admin_passwords ap on ap.email=au.email
  where tm.tenant_id=p_tenant_id
    and lower(tm.email)=lower(trim(p_email))
    and tm.is_active and au.is_active
  limit 1;

  if v_hash is null or extensions.crypt(p_password,v_hash)<>v_hash then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;
  if v_hash ~ '^\$2[aby]\$[0-9]{2}\$' and split_part(v_hash,'$',3)::int<12 then
    update private.admin_passwords
      set password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',12)),updated_at=now()
      where email=v_email;
  end if;

  delete from private.admin_sessions where expires_at<=now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_exp:=now()+interval '6 hours';
  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash,tenant_id)
  values(
    encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp,'admin',
    p_fingerprint_hash,p_tenant_id
  );

  delete from private.admin_sessions s
  where s.tenant_id=p_tenant_id and s.email=v_email and s.session_scope='admin'
    and s.token_hash not in (
      select s2.token_hash from private.admin_sessions s2
      where s2.tenant_id=p_tenant_id and s2.email=v_email and s2.session_scope='admin'
      order by s2.expires_at desc limit 3
    );

  return jsonb_build_object(
    'ok',true,'token',v_token,'email',v_email::text,
    'display_name',coalesce(v_name,''),'role',v_role,
    'expires_at',v_exp,'tenant_id',p_tenant_id,'session_scope','admin',
    'fingerprint_bound',true
  );
end
$$;
revoke all on function public.admin_password_login_bound_tenant(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_password_login_bound_tenant(uuid,text,text,text) to service_role;

-- 6. Defense in depth on Admin history; a KDS-scoped token is rejected in the database too.
create or replace function public.admin_order_history_snapshot_tenant(
  p_tenant_id uuid,p_token text,p_limit integer default 500,p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_session jsonb;
  v_email extensions.citext;
  v_limit integer:=greatest(1,least(coalesce(p_limit,500),1000));
  v_offset integer:=greatest(0,coalesce(p_offset,0));
  v_rows jsonb; v_total bigint; v_health jsonb;
begin
  v_session:=public.admin_password_session_info_tenant(p_tenant_id,p_token);
  if not coalesce((v_session->>'ok')::boolean,false) then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  v_email:=(v_session->>'email')::extensions.citext;

  with all_orders as (
    select o.id,o.public_order_code,o.created_at,o.updated_at,o.customer_name,o.customer_whatsapp,
      o.service_mode,o.table_number,o.items,o.item_count,o.total_amount,o.payment_method,
      o.payment_status,o.order_status,o.payment_submitted_at,o.verified_at,o.kitchen_sent_at,
      o.kds_received_at,o.preparing_at,o.ready_at,o.completed_at,o.customer_note,o.order_source,
      o.cashier_actor,o.cash_received,o.change_amount,'live'::text storage_state
    from public.orders o where o.tenant_id=p_tenant_id
    union all
    select a.id,a.public_order_code,a.created_at,a.updated_at,a.customer_name,a.customer_whatsapp,
      a.service_mode,a.table_number,a.items,a.item_count,a.total_amount,a.payment_method,
      a.payment_status,a.order_status,a.payment_submitted_at,a.verified_at,a.kitchen_sent_at,
      a.kds_received_at,a.preparing_at,a.ready_at,a.completed_at,a.customer_note,a.order_source,
      a.cashier_actor,a.cash_received,a.change_amount,'archive'::text storage_state
    from public.order_history_archive a where a.tenant_id=p_tenant_id
  ), page as (
    select * from all_orders order by created_at desc limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]'::jsonb)
    into v_rows from page p;

  select count(*) into v_total from (
    select id from public.orders where tenant_id=p_tenant_id
    union all
    select id from public.order_history_archive where tenant_id=p_tenant_id
  ) q;

  begin
    v_health:=public.get_sheet_sync_health_tenant(p_tenant_id);
  exception when others then
    v_health:=jsonb_build_object('enabled',false,'error','sheet_health_unavailable','tenant_id',p_tenant_id);
  end;

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'rows',v_rows,'total',v_total,
    'limit',v_limit,'offset',v_offset,'generated_at',now(),'sheet_sync',v_health
  );
end
$$;
revoke all on function public.admin_order_history_snapshot_tenant(uuid,text,integer,integer) from public,anon,authenticated;
grant execute on function public.admin_order_history_snapshot_tenant(uuid,text,integer,integer) to service_role;

commit;
