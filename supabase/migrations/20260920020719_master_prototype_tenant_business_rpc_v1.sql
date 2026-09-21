-- ROHMAT MASTER PROTOTIPE v1
-- Phase 5: tenant-scoped business RPCs for Admin, KDS, cashier and public order gateway.
-- Additive RPC names permit candidate verification before legacy production cutover.

alter table private.tenant_runtime_config
  add column if not exists table_count integer not null default 20,
  add column if not exists require_table_qr_signature boolean not null default true;
update private.tenant_runtime_config c
set table_count=20,
    require_table_qr_signature=coalesce(
      case when (c.settings->>'require_table_qr_signature') in ('true','false')
        then (c.settings->>'require_table_qr_signature')::boolean end,
      true
    )
where c.tenant_id=private.reference_tenant_id();

create or replace function private.tenant_settings_json(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
select coalesce(c.settings,'{}'::jsonb) || jsonb_build_object(
  'tenant_id',c.tenant_id,
  'business_name',c.business_name,
  'merchant_name',c.merchant_name,
  'public_url',c.public_origin,
  'admin_url',c.admin_origin,
  'kds_url',c.kds_origin,
  'qris_image_url',coalesce(c.qris_asset,c.settings->>'qris_image_url'),
  'locale',c.locale,
  'currency',c.currency,
  'timezone',c.timezone,
  'table_count',c.table_count,
  'require_table_qr_signature',c.require_table_qr_signature,
  'updated_at',c.updated_at
)
from private.tenant_runtime_config c
where c.tenant_id=p_tenant_id and c.enabled
limit 1
$$;
revoke all on function private.tenant_settings_json(uuid) from public,anon,authenticated;
grant execute on function private.tenant_settings_json(uuid) to service_role;

create or replace function private.sync_tenant_public_settings_projection(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare s jsonb; c private.tenant_runtime_config%rowtype;
begin
  select * into c from private.tenant_runtime_config where tenant_id=p_tenant_id and enabled;
  if c.tenant_id is null then raise exception 'tenant_unavailable'; end if;
  s:=private.tenant_settings_json(p_tenant_id);
  insert into public.tenant_site_settings_public_v1(
    tenant_id,business_name,welcome_text,motto,hero_image_url,public_url,
    merchant_name,payment_instructions,qris_image_url,qris_enabled,
    require_table_qr_signature,typography,design_system,updated_at
  ) values(
    p_tenant_id,
    c.business_name,
    coalesce(s->>'welcome_text',''),
    coalesce(s->>'motto',''),
    nullif(s->>'hero_image_url',''),
    c.public_origin,
    c.merchant_name,
    coalesce(s->>'payment_instructions',''),
    coalesce(c.qris_asset,nullif(s->>'qris_image_url','')),
    coalesce((s->>'qris_enabled')::boolean,false),
    c.require_table_qr_signature,
    coalesce(s->'typography','{}'::jsonb),
    coalesce(s->'design_system','{}'::jsonb),
    c.updated_at
  )
  on conflict(tenant_id) do update set
    business_name=excluded.business_name,
    welcome_text=excluded.welcome_text,
    motto=excluded.motto,
    hero_image_url=excluded.hero_image_url,
    public_url=excluded.public_url,
    merchant_name=excluded.merchant_name,
    payment_instructions=excluded.payment_instructions,
    qris_image_url=excluded.qris_image_url,
    qris_enabled=excluded.qris_enabled,
    require_table_qr_signature=excluded.require_table_qr_signature,
    typography=excluded.typography,
    design_system=excluded.design_system,
    updated_at=excluded.updated_at;
end
$$;
revoke all on function private.sync_tenant_public_settings_projection(uuid) from public,anon,authenticated;
grant execute on function private.sync_tenant_public_settings_projection(uuid) to service_role;

create or replace function public.admin_console_snapshot_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_settings jsonb;
  v_menu jsonb;
  v_orders jsonb;
  v_team jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  v_settings:=coalesce(private.tenant_settings_json(p_tenant_id),'{}'::jsonb);

  select coalesce(jsonb_agg(to_jsonb(m) order by m.display_order,m.name),'[]'::jsonb)
    into v_menu
  from public.menu_items m
  where m.tenant_id=p_tenant_id;

  select coalesce(jsonb_agg(x.item order by x.created_at desc),'[]'::jsonb)
    into v_orders
  from (
    select o.created_at,to_jsonb(o)||jsonb_build_object('storage_state','live') item
      from public.orders o where o.tenant_id=p_tenant_id
    union all
    select a.created_at,to_jsonb(a)||jsonb_build_object('storage_state','archive') item
      from public.order_history_archive a where a.tenant_id=p_tenant_id
    order by created_at desc limit 500
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'email',tm.email,
    'display_name',coalesce(au.display_name,split_part(tm.email,'@',1)),
    'role',tm.role,
    'is_active',tm.is_active,
    'is_protected',tm.role='superadmin',
    'created_at',tm.created_at
  ) order by tm.created_at),'[]'::jsonb)
  into v_team
  from private.tenant_memberships tm
  left join public.admin_users au on lower(au.email::text)=lower(tm.email)
  where tm.tenant_id=p_tenant_id;

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'email',v_email::text,
    'settings',v_settings,'menu',v_menu,'orders',v_orders,'team',v_team
  );
end
$$;
revoke all on function public.admin_console_snapshot_tenant(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_console_snapshot_tenant(uuid,text) to service_role;

create or replace function public.admin_console_update_settings_tenant(
  p_tenant_id uuid,p_token text,p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_patch jsonb:='{}'::jsonb;
  v_settings jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_patch is null or jsonb_typeof(p_patch)<>'object' then
    return jsonb_build_object('ok',false,'error','invalid_patch');
  end if;

  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
    into v_patch
  from jsonb_each(p_patch)
  where key=any(array[
    'business_name','welcome_text','motto','hero_image_url','photo_position','content_position',
    'content_width','element_order','theme_preset','color_outer','color_panel','color_primary',
    'color_accent','color_text','color_muted','typography','merchant_name','payment_instructions',
    'qris_image_url','qris_enabled','admin_design','kds_design','design_system',
    'require_table_qr_signature','google_sheet_url'
  ]);

  update private.tenant_runtime_config c
  set business_name=case when v_patch?'business_name'
        then left(coalesce(v_patch->>'business_name',''),120) else c.business_name end,
      merchant_name=case when v_patch?'merchant_name'
        then left(coalesce(v_patch->>'merchant_name',''),120) else c.merchant_name end,
      qris_asset=case when v_patch?'qris_image_url'
        then nullif(left(coalesce(v_patch->>'qris_image_url',''),1000),'') else c.qris_asset end,
      require_table_qr_signature=case when v_patch?'require_table_qr_signature'
        then coalesce((v_patch->>'require_table_qr_signature')::boolean,false)
        else c.require_table_qr_signature end,
      settings=coalesce(c.settings,'{}'::jsonb)||v_patch,
      updated_at=now()
  where c.tenant_id=p_tenant_id and c.enabled;

  if not found then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;
  perform private.sync_tenant_public_settings_projection(p_tenant_id);
  v_settings:=private.tenant_settings_json(p_tenant_id);
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'settings',v_settings);
exception when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end
$$;
revoke all on function public.admin_console_update_settings_tenant(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_console_update_settings_tenant(uuid,text,jsonb) to service_role;

create or replace function public.admin_console_update_admin_design_page_tenant(
  p_tenant_id uuid,p_token text,p_page text,p_design jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare s jsonb; d jsonb;
begin
  if private.tenant_admin_email_from_token(p_tenant_id,p_token) is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if p_page is null or p_page!~'^[a-z0-9_-]{1,40}$' or jsonb_typeof(p_design)<>'object' then
    return jsonb_build_object('ok',false,'error','invalid_design');
  end if;
  s:=coalesce((select settings from private.tenant_runtime_config where tenant_id=p_tenant_id),'{}'::jsonb);
  d:=coalesce(s->'admin_design','{}'::jsonb);
  d:=jsonb_set(d,array[p_page],p_design,true);
  update private.tenant_runtime_config
     set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{admin_design}',d,true),updated_at=now()
   where tenant_id=p_tenant_id and enabled;
  return jsonb_build_object('ok',true,'admin_design',d,'tenant_id',p_tenant_id);
end
$$;
revoke all on function public.admin_console_update_admin_design_page_tenant(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_console_update_admin_design_page_tenant(uuid,text,text,jsonb) to service_role;

create or replace function public.admin_console_save_menu_tenant(
  p_tenant_id uuid,p_token text,p_menu jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_id text;
  v_name text;
  v_row public.menu_items%rowtype;
  v_slug text;
  v_order integer;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_menu is null or jsonb_typeof(p_menu)<>'object' then return jsonb_build_object('ok',false,'error','invalid_menu'); end if;
  select slug into v_slug from private.platform_tenants where id=p_tenant_id and status='active';
  if v_slug is null then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  v_name:=left(trim(coalesce(p_menu->>'name','')),120);
  if v_name='' then return jsonb_build_object('ok',false,'error','name_required'); end if;
  v_id:=left(trim(coalesce(p_menu->>'id','')),160);
  if v_id='' then v_id:=v_slug||'-menu-'||replace(gen_random_uuid()::text,'-',''); end if;

  if exists(select 1 from public.menu_items where id=v_id and tenant_id<>p_tenant_id) then
    return jsonb_build_object('ok',false,'error','menu_id_conflict');
  end if;
  v_order:=greatest(0,coalesce((p_menu->>'display_order')::integer,
    (select coalesce(max(display_order),0)+1 from public.menu_items where tenant_id=p_tenant_id)));

  insert into public.menu_items(
    id,name,category,price,description,image_url,is_favorite,is_visible,
    is_available,display_order,updated_by,updated_at,availability_note,availability_updated_at,tenant_id
  ) values(
    v_id,v_name,
    case when coalesce(p_menu->>'category','') in ('Nasi','Lauk','Minuman','Jus Buah')
      then p_menu->>'category' else 'Lauk' end,
    greatest(0,coalesce((p_menu->>'price')::integer,0)),
    left(coalesce(p_menu->>'description',''),600),
    coalesce(left(p_menu->>'image_url',1000),''),
    coalesce((p_menu->>'is_favorite')::boolean,false),
    coalesce((p_menu->>'is_visible')::boolean,true),
    coalesce((p_menu->>'is_available')::boolean,true),
    v_order,null,now(),coalesce(p_menu->>'availability_note',''),now(),p_tenant_id
  )
  on conflict(id) do update set
    name=excluded.name,category=excluded.category,price=excluded.price,
    description=excluded.description,image_url=excluded.image_url,
    is_favorite=excluded.is_favorite,is_visible=excluded.is_visible,
    is_available=excluded.is_available,display_order=excluded.display_order,
    availability_note=excluded.availability_note,availability_updated_at=now(),
    updated_by=null,updated_at=now()
  where public.menu_items.tenant_id=p_tenant_id
  returning * into v_row;

  if v_row.id is null then return jsonb_build_object('ok',false,'error','menu_id_conflict'); end if;
  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row),'tenant_id',p_tenant_id);
exception when unique_violation then
  return jsonb_build_object('ok',false,'error','display_order_conflict');
end
$$;
revoke all on function public.admin_console_save_menu_tenant(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.admin_console_save_menu_tenant(uuid,text,jsonb) to service_role;

create or replace function public.admin_console_set_menu_visible_tenant(
  p_tenant_id uuid,p_token text,p_id text,p_visible boolean
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_row public.menu_items%rowtype;
begin
  if private.tenant_admin_email_from_token(p_tenant_id,p_token) is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  update public.menu_items
     set is_visible=coalesce(p_visible,false),updated_by=null,updated_at=now()
   where tenant_id=p_tenant_id and id=p_id
  returning * into v_row;
  if v_row.id is null then return jsonb_build_object('ok',false,'error','menu_not_found'); end if;
  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row),'tenant_id',p_tenant_id);
end
$$;
revoke all on function public.admin_console_set_menu_visible_tenant(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.admin_console_set_menu_visible_tenant(uuid,text,text,boolean) to service_role;

create or replace function public.admin_console_update_order_tenant(
  p_tenant_id uuid,p_token text,p_id uuid,p_action text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  if private.tenant_admin_email_from_token(p_tenant_id,p_token) is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if not exists(select 1 from public.orders where id=p_id and tenant_id=p_tenant_id) then
    return jsonb_build_object('ok',false,'error','order_not_found');
  end if;
  return jsonb_build_object('ok',false,'error','payment_verification_is_kds_responsibility');
end
$$;
revoke all on function public.admin_console_update_order_tenant(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.admin_console_update_order_tenant(uuid,text,uuid,text) to service_role;

create or replace function public.kds_console_snapshot_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email extensions.citext; v_orders jsonb; v_menu jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select coalesce(jsonb_agg(
    to_jsonb(o)||jsonb_build_object(
      'producer_note',
      concat_ws(' | ',
        nullif(trim(o.producer_note),''),
        'Tanggal pembayaran: '||coalesce(
          case when coalesce(o.proof_date_detected,'')~'^\d{4}-\d{2}-\d{2}$'
            then to_char(to_date(o.proof_date_detected,'YYYY-MM-DD'),'DD/MM/YYYY') end,
          case when o.payment_submitted_at is not null
            then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','DD/MM/YYYY') end,'—'
        ),
        'Waktu pembayaran: '||coalesce(
          nullif(trim(o.proof_time_detected),''),
          case when o.payment_submitted_at is not null
            then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end,'—'
        )||case when coalesce(nullif(trim(o.proof_time_detected),''),
          case when o.payment_submitted_at is not null
            then to_char(o.payment_submitted_at at time zone 'Asia/Jakarta','HH24:MI') end
        ) is not null then ' WIB' else '' end,
        'Nominal pembayaran: Rp '||replace(to_char(coalesce(o.paid_amount,o.total_amount,0),'FM999,999,999,999'),',','.')
      )
    ) order by o.created_at asc),'[]'::jsonb)
  into v_orders
  from public.orders o
  where o.tenant_id=p_tenant_id
    and (
      (o.payment_status='submitted' and o.order_status='payment_review')
      or (o.payment_status='verified' and o.order_status in ('confirmed','preparing','ready','completed'))
    )
    and (o.order_status<>'completed' or o.completed_at>=now()-interval '24 hours')
    and not (o.order_status='completed' and (coalesce(o.kitchen_print_count,0)>0 or o.kds_dismissed_at is not null));

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,'name',m.name,'category',m.category,'price',m.price,
    'is_visible',m.is_visible,'is_available',m.is_available,'display_order',m.display_order
  ) order by m.display_order,m.name),'[]'::jsonb)
  into v_menu
  from public.menu_items m
  where m.tenant_id=p_tenant_id and m.is_visible=true;

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'email',v_email::text,
    'orders',v_orders,'menu',v_menu,'server_time',now()
  );
end
$$;
revoke all on function public.kds_console_snapshot_tenant(uuid,text) from public,anon,authenticated;
grant execute on function public.kds_console_snapshot_tenant(uuid,text) to service_role;

create or replace function public.kds_console_set_available_tenant(
  p_tenant_id uuid,p_token text,p_id text,p_available boolean
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_row public.menu_items%rowtype;
begin
  if private.tenant_admin_email_from_token(p_tenant_id,p_token) is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  update public.menu_items
     set is_available=coalesce(p_available,false),updated_at=now(),updated_by=null
   where tenant_id=p_tenant_id and id=p_id
  returning * into v_row;
  if v_row.id is null then return jsonb_build_object('ok',false,'error','menu_not_found'); end if;
  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row),'tenant_id',p_tenant_id);
end
$$;
revoke all on function public.kds_console_set_available_tenant(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.kds_console_set_available_tenant(uuid,text,text,boolean) to service_role;

create or replace function public.kds_console_order_action_tenant(
  p_tenant_id uuid,p_token text,p_id uuid,p_action text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext; v_actor_id uuid; v_role text;
  v_old public.orders%rowtype; v_row public.orders%rowtype; v_now timestamptz:=now();
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role
    from private.tenant_actor_context(p_tenant_id,p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  select * into v_old from public.orders
   where id=p_id and tenant_id=p_tenant_id for update;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;

  if p_action='verify' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set payment_status='verified',order_status='confirmed',
      verified_at=coalesce(verified_at,v_now),verified_by=v_actor_id,verified_by_email=v_email,
      kitchen_sent_at=coalesce(kitchen_sent_at,v_now),updated_at=v_now
      where id=p_id and tenant_id=p_tenant_id returning * into v_row;
    insert into public.order_events(
      order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id,tenant_id
    ) values(
      p_id,'payment_verified_kds',v_old.order_status,'confirmed',
      'Pembayaran diverifikasi oleh petugas KDS dan pesanan diteruskan ke dapur.',
      v_actor_id,v_email,v_role,'kds',v_old.request_id,p_tenant_id
    );
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row),'tenant_id',p_tenant_id);
  elsif p_action='reject' then
    if v_old.payment_status<>'submitted' or v_old.order_status<>'payment_review' then
      return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set payment_status='rejected',order_status='awaiting_payment',
      verified_at=null,verified_by=null,verified_by_email=null,kitchen_sent_at=null,updated_at=v_now
      where id=p_id and tenant_id=p_tenant_id returning * into v_row;
    insert into public.order_events(
      order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id,tenant_id
    ) values(
      p_id,'payment_rejected_kds',v_old.order_status,'awaiting_payment',
      'Bukti pembayaran ditolak oleh petugas KDS untuk diperiksa atau diulang.',
      v_actor_id,v_email,v_role,'kds',v_old.request_id,p_tenant_id
    );
    return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row),'tenant_id',p_tenant_id);
  end if;

  if v_old.payment_status<>'verified' then
    return jsonb_build_object('ok',false,'error','payment_not_verified');
  end if;

  if p_action='start' then
    if v_old.order_status not in ('confirmed','preparing') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='preparing',preparing_at=coalesce(preparing_at,v_now),updated_at=v_now
      where id=p_id and tenant_id=p_tenant_id returning * into v_row;
  elsif p_action='ready' then
    if v_old.order_status not in ('confirmed','preparing','ready') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='ready',ready_at=coalesce(ready_at,v_now),updated_at=v_now
      where id=p_id and tenant_id=p_tenant_id returning * into v_row;
  elsif p_action='complete' then
    if v_old.order_status not in ('ready','completed') then return jsonb_build_object('ok',false,'error','invalid_status'); end if;
    update public.orders set order_status='completed',completed_at=coalesce(completed_at,v_now),updated_at=v_now
      where id=p_id and tenant_id=p_tenant_id returning * into v_row;
  elsif p_action='print' then
    update public.orders set kitchen_print_count=coalesce(kitchen_print_count,0)+1,
      kitchen_last_printed_at=v_now,updated_at=v_now
      where id=p_id and tenant_id=p_tenant_id returning * into v_row;
  elsif p_action='dismiss' then
    update public.orders set kds_dismissed_at=v_now,updated_at=v_now
      where id=p_id and tenant_id=p_tenant_id returning * into v_row;
  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;

  insert into public.order_events(
    order_id,event_type,from_status,to_status,note,actor_id,actor_email,actor_role,source_app,request_id,tenant_id
  ) values(
    p_id,'kitchen_'||p_action,v_old.order_status,v_row.order_status,
    'Aksi KDS: '||p_action,v_actor_id,v_email,v_role,'kds',v_old.request_id,p_tenant_id
  );
  return jsonb_build_object('ok',true,'request_id',v_old.request_id,'order',to_jsonb(v_row),'tenant_id',p_tenant_id);
end
$$;
revoke all on function public.kds_console_order_action_tenant(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.kds_console_order_action_tenant(uuid,text,uuid,text) to service_role;

create or replace function public.smart_cashier_snapshot_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_email extensions.citext; v_settings jsonb; v_menu jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select jsonb_build_object(
    'business_name',business_name,'merchant_name',merchant_name,'qris_enabled',qris_enabled,
    'qris_image_url',qris_image_url,'updated_at',updated_at
  ) into v_settings
  from public.tenant_site_settings_public_v1
  where tenant_id=p_tenant_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,'name',m.name,'category',m.category,'price',m.price,'image_url',m.image_url,
    'is_available',m.is_available,'is_visible',m.is_visible,'display_order',m.display_order,'updated_at',m.updated_at
  ) order by m.display_order,m.name),'[]'::jsonb)
  into v_menu
  from public.menu_items m
  where m.tenant_id=p_tenant_id and m.is_visible;

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'actor',v_email::text,
    'settings',coalesce(v_settings,'{}'::jsonb),'menu',v_menu,'generated_at',now()
  );
end
$$;
revoke all on function public.smart_cashier_snapshot_tenant(uuid,text) from public,anon,authenticated;
grant execute on function public.smart_cashier_snapshot_tenant(uuid,text) to service_role;

create or replace function public.smart_cashier_create_tenant(
  p_tenant_id uuid,p_token text,p_source text,p_customer_name text,p_service_mode text,
  p_table_number smallint,p_items jsonb,p_payment_method text,p_cash_received integer default null,p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext; v_actor_id uuid; v_role text; v_req jsonb; v_menu public.menu_items%rowtype;
  v_qty integer; v_total integer:=0; v_count integer:=0; v_items jsonb:='[]'::jsonb; v_order public.orders%rowtype;
  v_name text; v_change integer:=0; v_now timestamptz:=now(); v_request_id uuid:=gen_random_uuid(); v_table_count integer;
begin
  select a.email,a.actor_id,a.role into v_email,v_actor_id,v_role
    from private.tenant_actor_context(p_tenant_id,p_token) a;
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select table_count into v_table_count from private.tenant_runtime_config where tenant_id=p_tenant_id and enabled;
  if v_table_count is null then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;
  if p_source not in ('cashier_admin','cashier_kds') then return jsonb_build_object('ok',false,'error','invalid_source'); end if;
  if p_service_mode not in ('dine-in','take-away') then return jsonb_build_object('ok',false,'error','invalid_service_mode'); end if;
  if p_service_mode='dine-in' and (p_table_number is null or p_table_number<1 or p_table_number>v_table_count) then
    return jsonb_build_object('ok',false,'error','invalid_table'); end if;
  if p_service_mode='take-away' then p_table_number:=null; end if;
  if p_payment_method not in ('cash','qris_cashier') then return jsonb_build_object('ok',false,'error','invalid_payment_method'); end if;

  v_name:=left(trim(coalesce(p_customer_name,'')),60);
  if v_name='' then return jsonb_build_object('ok',false,'error','customer_name_required'); end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    return jsonb_build_object('ok',false,'error','empty_cart'); end if;

  for v_req in select value from jsonb_array_elements(p_items)
  loop
    v_qty:=greatest(0,least(50,coalesce((v_req->>'quantity')::integer,0)));
    if v_qty<1 then return jsonb_build_object('ok',false,'error','invalid_quantity'); end if;
    select * into v_menu from public.menu_items
      where tenant_id=p_tenant_id and id=v_req->>'menuId' and is_visible and is_available;
    if v_menu.id is null then return jsonb_build_object('ok',false,'error','menu_unavailable','menuId',v_req->>'menuId'); end if;
    v_total:=v_total+(v_menu.price*v_qty); v_count:=v_count+v_qty;
    if v_count>200 or v_total>100000000 then return jsonb_build_object('ok',false,'error','order_limit_exceeded'); end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'menuId',v_menu.id,'name',v_menu.name,'price',v_menu.price,'quantity',v_qty,'subtotal',v_menu.price*v_qty
    ));
  end loop;

  if p_payment_method='cash' then
    if p_cash_received is null or p_cash_received<v_total then
      return jsonb_build_object('ok',false,'error','insufficient_cash','total',v_total); end if;
    v_change:=p_cash_received-v_total;
  else p_cash_received:=null; v_change:=0; end if;

  insert into public.orders(
    request_id,service_mode,table_number,customer_name,items,item_count,total_amount,payment_method,
    payment_status,order_status,payment_submitted_at,verified_at,verified_by,verified_by_email,kitchen_sent_at,
    customer_note,client_order_id,paid_amount,payment_difference,producer_note,proof_check_status,
    order_source,cashier_actor,cash_received,change_amount,created_at,updated_at,tenant_id
  ) values(
    v_request_id,p_service_mode,p_table_number,v_name,v_items,v_count,v_total,p_payment_method,
    'verified','confirmed',v_now,v_now,v_actor_id,v_email,v_now,left(trim(coalesce(p_note,'')),500),
    'cashier-'||replace(gen_random_uuid()::text,'-',''),v_total,0,
    case when p_payment_method='cash' then 'Pembayaran CASH dikonfirmasi oleh kasir.'
      else 'Pembayaran QRIS kasir dikonfirmasi oleh petugas.' end,
    'cashier_confirmed',p_source,v_email::text,p_cash_received,v_change,v_now,v_now,p_tenant_id
  )
  returning * into v_order;

  return jsonb_build_object(
    'ok',true,'tenant_id',p_tenant_id,'request_id',v_request_id,'order',to_jsonb(v_order),
    'change_amount',v_change,
    'receipt',jsonb_build_object(
      'payment_code',v_order.public_order_code,'customer_name',v_order.customer_name,
      'service_mode',v_order.service_mode,'table_number',v_order.table_number,'created_at',v_order.created_at,
      'items',v_order.items,'total_amount',v_order.total_amount
    )
  );
exception when others then
  return jsonb_build_object('ok',false,'error','cashier_create_failed','detail',sqlerrm);
end
$$;
revoke all on function public.smart_cashier_create_tenant(uuid,text,text,text,text,smallint,jsonb,text,integer,text) from public,anon,authenticated;
grant execute on function public.smart_cashier_create_tenant(uuid,text,text,text,text,smallint,jsonb,text,integer,text) to service_role;

create or replace function public.verify_table_qr_signature_tenant(
  p_tenant_id uuid,p_table integer,p_signature text
)
returns boolean
language sql
security definer
set search_path=''
as $$
select case
  when not exists(
    select 1 from private.tenant_runtime_config c
    where c.tenant_id=p_tenant_id and c.enabled
  ) then false
  when coalesce((
    select c.require_table_qr_signature from private.tenant_runtime_config c
    where c.tenant_id=p_tenant_id and c.enabled
  ),true)=false then
    p_table between 1 and coalesce((
      select c.table_count from private.tenant_runtime_config c
      where c.tenant_id=p_tenant_id
    ),0)
  else exists(
    select 1 from private.tenant_table_qr_signatures q
    join private.tenant_runtime_config c on c.tenant_id=q.tenant_id
    where q.tenant_id=p_tenant_id
      and q.table_number=p_table
      and p_table between 1 and c.table_count
      and q.is_active
      and q.signature_hash=encode(extensions.digest(coalesce(p_signature,''),'sha256'),'hex')
      and coalesce(p_signature,'')~'^[a-f0-9]{32}$'
  )
end
$$;
revoke all on function public.verify_table_qr_signature_tenant(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.verify_table_qr_signature_tenant(uuid,integer,text) to service_role;

create or replace function public.consume_order_rate_limit_tenant(
  p_tenant_id uuid,p_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare recent_attempts integer;
begin
  if p_fingerprint is null or char_length(p_fingerprint)<>64 then return false; end if;
  if not exists(select 1 from private.platform_tenants where id=p_tenant_id and status='active') then return false; end if;
  perform pg_advisory_xact_lock(hashtext(p_tenant_id::text||':'||p_fingerprint));
  delete from private.order_rate_limits
   where tenant_id=p_tenant_id and fingerprint=p_fingerprint and attempted_at<now()-interval '1 day';
  select count(*) into recent_attempts
    from private.order_rate_limits
   where tenant_id=p_tenant_id and fingerprint=p_fingerprint and attempted_at>=now()-interval '10 minutes';
  if recent_attempts>=5 then return false; end if;
  insert into private.order_rate_limits(fingerprint,tenant_id) values(p_fingerprint,p_tenant_id);
  return true;
end
$$;
revoke all on function public.consume_order_rate_limit_tenant(uuid,text) from public,anon,authenticated;
grant execute on function public.consume_order_rate_limit_tenant(uuid,text) to service_role;

create or replace function public.integration_record_event_tenant(
  p_tenant_id uuid,p_request_id uuid,p_service_key text,p_operation text,p_direction text,p_outcome text,
  p_http_status integer default null,p_latency_ms integer default null,p_entity_type text default null,
  p_entity_id text default null,p_error_code text default null,p_metadata jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_id bigint;
begin
  if p_request_id is null then raise exception 'request_id_required'; end if;
  if not exists(select 1 from private.platform_tenants where id=p_tenant_id and status='active') then
    raise exception 'tenant_unavailable'; end if;
  if not exists(select 1 from private.integration_registry where service_key=p_service_key and enabled) then
    raise exception 'unknown_service_key'; end if;
  insert into private.integration_events(
    request_id,service_key,operation,direction,outcome,http_status,latency_ms,
    entity_type,entity_id,error_code,metadata,tenant_id
  ) values(
    p_request_id,p_service_key,left(coalesce(p_operation,''),100),p_direction,p_outcome,p_http_status,p_latency_ms,
    left(p_entity_type,50),left(p_entity_id,160),left(p_error_code,100),
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('tenant_id',p_tenant_id),p_tenant_id
  ) returning id into v_id;
  return v_id;
end
$$;
revoke all on function public.integration_record_event_tenant(uuid,uuid,text,text,text,text,integer,integer,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.integration_record_event_tenant(uuid,uuid,text,text,text,text,integer,integer,text,text,text,jsonb) to service_role;
