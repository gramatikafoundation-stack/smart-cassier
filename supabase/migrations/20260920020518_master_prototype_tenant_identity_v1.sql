-- ROHMAT MASTER PROTOTIPE v1
-- Phase 4: tenant-scoped identity/session and platform context RPCs.
-- New RPC names are additive; legacy Rohmat RPCs remain untouched until candidate cutover is verified.

create or replace function public.master_prototype_tenant_context(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
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

create or replace function private.tenant_admin_email_from_token(p_tenant_id uuid,p_token text)
returns extensions.citext
language sql
stable
security definer
set search_path=''
as $$
select s.email
from private.admin_sessions s
join private.tenant_memberships tm
  on tm.tenant_id=s.tenant_id
 and lower(tm.email)=lower(s.email::text)
 and tm.is_active
where s.tenant_id=p_tenant_id
  and s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
  and s.expires_at>now()
limit 1
$$;
revoke all on function private.tenant_admin_email_from_token(uuid,text) from public,anon,authenticated;
grant execute on function private.tenant_admin_email_from_token(uuid,text) to service_role;

create or replace function private.tenant_is_super_from_token(p_tenant_id uuid,p_token text)
returns boolean
language sql
stable
security definer
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
    and tm.is_active
    and tm.role='superadmin'
)
$$;
revoke all on function private.tenant_is_super_from_token(uuid,text) from public,anon,authenticated;
grant execute on function private.tenant_is_super_from_token(uuid,text) to service_role;

create or replace function private.tenant_actor_context(p_tenant_id uuid,p_token text)
returns table(email extensions.citext,actor_id uuid,role text,display_name text)
language sql
stable
security definer
set search_path=''
as $$
select s.email,u.id,tm.role,coalesce(au.display_name,split_part(s.email::text,'@',1))
from private.admin_sessions s
join private.tenant_memberships tm
  on tm.tenant_id=s.tenant_id
 and lower(tm.email)=lower(s.email::text)
 and tm.is_active
left join public.admin_users au on au.email=s.email
left join auth.users u on lower(u.email)=lower(s.email::text)
where s.tenant_id=p_tenant_id
  and s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
  and s.expires_at>now()
limit 1
$$;
revoke all on function private.tenant_actor_context(uuid,text) from public,anon,authenticated;
grant execute on function private.tenant_actor_context(uuid,text) to service_role;

create or replace function public.admin_password_login_tenant(
  p_tenant_id uuid,p_email text,p_password text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_role text;
  v_name text;
  v_hash text;
  v_token text;
  v_exp timestamptz;
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

  if v_hash ~ '^\$2[aby]\$[0-9]{2}\$'
     and split_part(v_hash,'$',3)::int<12 then
    update private.admin_passwords
      set password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',12)),updated_at=now()
      where email=v_email;
  end if;

  delete from private.admin_sessions where expires_at<=now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_exp:=now()+interval '8 hours';
  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash,tenant_id)
  values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp,'admin',null,p_tenant_id);

  return jsonb_build_object(
    'ok',true,'token',v_token,'email',v_email::text,
    'display_name',coalesce(v_name,''),'role',v_role,
    'expires_at',v_exp,'tenant_id',p_tenant_id,'session_scope','admin'
  );
end
$$;
revoke all on function public.admin_password_login_tenant(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_password_login_tenant(uuid,text,text) to service_role;

create or replace function public.kds_bff_login_bound_tenant(
  p_tenant_id uuid,p_email text,p_password text,p_fingerprint_hash text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_role text;
  v_name text;
  v_hash text;
  v_token text;
  v_exp timestamptz;
begin
  if p_email is null or p_password is null or length(p_password)>256 then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;
  if p_fingerprint_hash is null or p_fingerprint_hash !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false,'error','invalid_fingerprint');
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

  delete from private.admin_sessions where expires_at<=now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_exp:=now()+interval '4 hours';
  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash,tenant_id)
  values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp,'kds',p_fingerprint_hash,p_tenant_id);

  delete from private.admin_sessions s
   where s.tenant_id=p_tenant_id and s.email=v_email and s.session_scope='kds'
     and s.token_hash not in (
       select s2.token_hash from private.admin_sessions s2
        where s2.tenant_id=p_tenant_id and s2.email=v_email and s2.session_scope='kds'
        order by s2.expires_at desc limit 3
     );

  return jsonb_build_object(
    'ok',true,'token',v_token,'email',v_email::text,
    'display_name',coalesce(v_name,''),'role',v_role,
    'expires_at',v_exp,'tenant_id',p_tenant_id,'session_scope','kds'
  );
end
$$;
revoke all on function public.kds_bff_login_bound_tenant(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.kds_bff_login_bound_tenant(uuid,text,text,text) to service_role;

create or replace function public.admin_password_session_info_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email extensions.citext; v_role text; v_name text;
begin
  select a.email,a.role,a.display_name into v_email,v_role,v_name
  from private.tenant_actor_context(p_tenant_id,p_token) a;
  if v_email is null then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object(
    'ok',true,'email',v_email::text,'display_name',coalesce(v_name,''),
    'role',v_role,'tenant_id',p_tenant_id
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
declare v_email extensions.citext; v_role text; v_name text;
begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$'
     or p_fingerprint_hash is null or p_fingerprint_hash !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false);
  end if;
  select s.email,tm.role,coalesce(au.display_name,'')
    into v_email,v_role,v_name
  from private.admin_sessions s
  join private.tenant_memberships tm
    on tm.tenant_id=s.tenant_id and lower(tm.email)=lower(s.email::text) and tm.is_active
  left join public.admin_users au on au.email=s.email
  where s.tenant_id=p_tenant_id
    and s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and (s.session_scope<>'kds' or s.client_fingerprint_hash is null or s.client_fingerprint_hash=p_fingerprint_hash)
  limit 1;
  if v_email is null then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object(
    'ok',true,'email',v_email::text,'display_name',v_name,
    'role',v_role,'tenant_id',p_tenant_id
  );
end
$$;
revoke all on function public.admin_password_session_info_bound_tenant(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_password_session_info_bound_tenant(uuid,text,text) to service_role;

create or replace function public.admin_password_logout_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  delete from private.admin_sessions
   where tenant_id=p_tenant_id
     and token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');
  return jsonb_build_object('ok',true);
end
$$;
revoke all on function public.admin_password_logout_tenant(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_password_logout_tenant(uuid,text) to service_role;

create or replace function public.admin_password_change_tenant(
  p_tenant_id uuid,p_token text,p_current_password text,p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email extensions.citext; v_hash text; v_keep text;
begin
  if not private.admin_password_is_strong(p_new_password) then
    return jsonb_build_object('ok',false,'error','new_password_weak');
  end if;
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','session_invalid'); end if;
  select password_hash into v_hash from private.admin_passwords where email=v_email;
  if v_hash is null or extensions.crypt(coalesce(p_current_password,''),v_hash)<>v_hash then
    return jsonb_build_object('ok',false,'error','current_password_invalid');
  end if;
  update private.admin_passwords
    set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),updated_at=now()
    where email=v_email;
  v_keep:=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');
  delete from private.admin_sessions where email=v_email and token_hash<>v_keep;
  return jsonb_build_object('ok',true);
end
$$;
revoke all on function public.admin_password_change_tenant(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_password_change_tenant(uuid,text,text,text) to service_role;

create or replace function public.admin_password_set_for_admin_tenant(
  p_tenant_id uuid,p_token text,p_email text,p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_target extensions.citext;
begin
  if not private.tenant_is_super_from_token(p_tenant_id,p_token) then
    return jsonb_build_object('ok',false,'error','forbidden');
  end if;
  if not private.admin_password_is_strong(p_new_password) then
    return jsonb_build_object('ok',false,'error','new_password_weak');
  end if;
  select au.email into v_target
  from private.tenant_memberships tm
  join public.admin_users au on lower(au.email::text)=lower(tm.email)
  where tm.tenant_id=p_tenant_id
    and lower(tm.email)=lower(trim(p_email))
    and tm.is_active and au.is_active
  limit 1;
  if v_target is null then return jsonb_build_object('ok',false,'error','admin_not_found'); end if;
  insert into private.admin_passwords(email,password_hash,updated_at)
  values(v_target,extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),now())
  on conflict(email) do update
    set password_hash=excluded.password_hash,updated_at=now();
  delete from private.admin_sessions where email=v_target;
  return jsonb_build_object('ok',true);
end
$$;
revoke all on function public.admin_password_set_for_admin_tenant(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_password_set_for_admin_tenant(uuid,text,text,text) to service_role;

create or replace function public.admin_console_add_admin_tenant(
  p_tenant_id uuid,p_token text,p_email text,p_password text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email extensions.citext; v_pw jsonb;
begin
  if not private.tenant_is_super_from_token(p_tenant_id,p_token) then
    return jsonb_build_object('ok',false,'error','forbidden');
  end if;
  if p_password is null or length(p_password)<12 or length(p_password)>256 then
    return jsonb_build_object('ok',false,'error','password_invalid');
  end if;
  v_email:=lower(trim(coalesce(p_email,'')))::extensions.citext;
  if position('@' in v_email::text)=0 then return jsonb_build_object('ok',false,'error','email_invalid'); end if;

  insert into public.admin_users(email,display_name,role,is_active,is_protected,created_by)
  values(v_email,split_part(v_email::text,'@',1),'admin',true,false,null)
  on conflict(email) do update set is_active=true;

  insert into private.tenant_memberships(tenant_id,email,role,is_active)
  values(p_tenant_id,v_email::text,'admin',true)
  on conflict(tenant_id,email) do update set role='admin',is_active=true,updated_at=now();

  v_pw:=public.admin_password_set_for_admin_tenant(p_tenant_id,p_token,v_email::text,p_password);
  if coalesce((v_pw->>'ok')::boolean,false) is not true then
    delete from private.tenant_memberships where tenant_id=p_tenant_id and lower(email)=lower(v_email::text);
    return jsonb_build_object('ok',false,'error',coalesce(v_pw->>'error','password_set_failed'));
  end if;
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id);
end
$$;
revoke all on function public.admin_console_add_admin_tenant(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_console_add_admin_tenant(uuid,text,text,text) to service_role;

create or replace function public.admin_console_remove_admin_tenant(
  p_tenant_id uuid,p_token text,p_email text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email text;
begin
  if not private.tenant_is_super_from_token(p_tenant_id,p_token) then
    return jsonb_build_object('ok',false,'error','forbidden');
  end if;
  v_email:=lower(trim(coalesce(p_email,'')));
  if exists(
    select 1 from private.tenant_memberships
    where tenant_id=p_tenant_id and lower(email)=v_email and role='superadmin' and is_active
  ) then return jsonb_build_object('ok',false,'error','protected_admin'); end if;
  delete from private.admin_sessions where tenant_id=p_tenant_id and lower(email::text)=v_email;
  update private.tenant_memberships set is_active=false,updated_at=now()
   where tenant_id=p_tenant_id and lower(email)=v_email;
  return jsonb_build_object('ok',true);
end
$$;
revoke all on function public.admin_console_remove_admin_tenant(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_console_remove_admin_tenant(uuid,text,text) to service_role;

create or replace function public.admin_console_transfer_superadmin_tenant(
  p_tenant_id uuid,p_token text,p_new_email text,p_new_password text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_current extensions.citext; v_target text; v_pw jsonb;
begin
  v_current:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_current is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if not private.tenant_is_super_from_token(p_tenant_id,p_token) then
    return jsonb_build_object('ok',false,'error','forbidden');
  end if;
  v_target:=lower(trim(coalesce(p_new_email,'')));
  if position('@' in v_target)=0 then return jsonb_build_object('ok',false,'error','email_invalid'); end if;

  if not exists(select 1 from private.tenant_memberships where tenant_id=p_tenant_id and lower(email)=v_target and is_active) then
    if p_new_password is null or length(p_new_password)<12 then
      return jsonb_build_object('ok',false,'error','password_required_for_new_admin');
    end if;
    insert into public.admin_users(email,display_name,role,is_active,is_protected)
    values(v_target::extensions.citext,split_part(v_target,'@',1),'admin',true,false)
    on conflict(email) do update set is_active=true;
    insert into private.tenant_memberships(tenant_id,email,role,is_active)
    values(p_tenant_id,v_target,'admin',true)
    on conflict(tenant_id,email) do update set is_active=true,updated_at=now();
    v_pw:=public.admin_password_set_for_admin_tenant(p_tenant_id,p_token,v_target,p_new_password);
    if coalesce((v_pw->>'ok')::boolean,false) is not true then
      return jsonb_build_object('ok',false,'error',coalesce(v_pw->>'error','password_set_failed'));
    end if;
  end if;

  update private.tenant_memberships
     set role='admin',updated_at=now()
   where tenant_id=p_tenant_id and lower(email)=lower(v_current::text) and lower(email)<>v_target;
  update private.tenant_memberships
     set role='superadmin',is_active=true,updated_at=now()
   where tenant_id=p_tenant_id and lower(email)=v_target;
  delete from private.admin_sessions
   where tenant_id=p_tenant_id and lower(email::text) in (lower(v_current::text),v_target);
  return jsonb_build_object('ok',true,'previous_superadmin',v_current::text,'new_superadmin',v_target,'tenant_id',p_tenant_id);
end
$$;
revoke all on function public.admin_console_transfer_superadmin_tenant(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_console_transfer_superadmin_tenant(uuid,text,text,text) to service_role;
