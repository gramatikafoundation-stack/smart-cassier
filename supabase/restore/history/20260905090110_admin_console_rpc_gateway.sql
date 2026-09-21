-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905090110  Name: admin_console_rpc_gateway
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.admin_email_from_token(p_token text)
returns extensions.citext
language sql
stable
security definer
set search_path = ''
as $$
  select au.email
  from private.admin_sessions s
  join public.admin_users au on au.email = s.email
  where s.token_hash = encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at > now()
    and au.is_active
  limit 1
$$;

create or replace function private.admin_is_super_from_token(p_token text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from private.admin_sessions s
    join public.admin_users au on au.email=s.email
    where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
      and s.expires_at>now()
      and au.is_active
      and au.role='superadmin'
  )
$$;

create or replace function public.admin_console_snapshot(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_settings jsonb;
  v_menu jsonb;
  v_orders jsonb;
  v_team jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  select to_jsonb(s) into v_settings
  from public.site_settings s where s.id=1;

  select coalesce(jsonb_agg(to_jsonb(m) order by m.display_order asc, m.name asc),'[]'::jsonb)
    into v_menu
  from public.menu_items m;

  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at desc),'[]'::jsonb)
    into v_orders
  from (
    select * from public.orders order by created_at desc limit 100
  ) o;

  select coalesce(jsonb_agg(jsonb_build_object(
      'email',a.email::text,
      'display_name',a.display_name,
      'role',a.role,
      'is_active',a.is_active,
      'is_protected',a.is_protected,
      'created_at',a.created_at
    ) order by a.created_at asc),'[]'::jsonb)
    into v_team
  from public.admin_users a;

  return jsonb_build_object(
    'ok',true,
    'settings',coalesce(v_settings,'{}'::jsonb),
    'menu',v_menu,
    'orders',v_orders,
    'team',v_team
  );
end;
$$;

create or replace function public.admin_console_update_settings(p_token text, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_row public.site_settings%rowtype;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then return jsonb_build_object('ok',false,'error','invalid_patch'); end if;

  update public.site_settings s set
    business_name = case when p_patch ? 'business_name' then left(coalesce(p_patch->>'business_name',''),120) else s.business_name end,
    welcome_text = case when p_patch ? 'welcome_text' then left(coalesce(p_patch->>'welcome_text',''),240) else s.welcome_text end,
    motto = case when p_patch ? 'motto' then left(coalesce(p_patch->>'motto',''),240) else s.motto end,
    hero_image_url = case when p_patch ? 'hero_image_url' then nullif(left(coalesce(p_patch->>'hero_image_url',''),1000),'') else s.hero_image_url end,
    photo_position = case when p_patch ? 'photo_position' and (p_patch->>'photo_position') in ('left','right','top') then p_patch->>'photo_position' else s.photo_position end,
    content_position = case when p_patch ? 'content_position' and (p_patch->>'content_position') in ('left','center','right') then p_patch->>'content_position' else s.content_position end,
    content_width = case when p_patch ? 'content_width' and (p_patch->>'content_width') in ('compact','balanced','wide') then p_patch->>'content_width' else s.content_width end,
    element_order = case when p_patch ? 'element_order' and jsonb_typeof(p_patch->'element_order')='array' then p_patch->'element_order' else s.element_order end,
    theme_preset = case when p_patch ? 'theme_preset' then left(coalesce(p_patch->>'theme_preset',''),60) else s.theme_preset end,
    color_outer = case when p_patch ? 'color_outer' then left(coalesce(p_patch->>'color_outer',''),20) else s.color_outer end,
    color_panel = case when p_patch ? 'color_panel' then left(coalesce(p_patch->>'color_panel',''),20) else s.color_panel end,
    color_primary = case when p_patch ? 'color_primary' then left(coalesce(p_patch->>'color_primary',''),20) else s.color_primary end,
    color_accent = case when p_patch ? 'color_accent' then left(coalesce(p_patch->>'color_accent',''),20) else s.color_accent end,
    color_text = case when p_patch ? 'color_text' then left(coalesce(p_patch->>'color_text',''),20) else s.color_text end,
    color_muted = case when p_patch ? 'color_muted' then left(coalesce(p_patch->>'color_muted',''),20) else s.color_muted end,
    typography = case when p_patch ? 'typography' and jsonb_typeof(p_patch->'typography')='object' then p_patch->'typography' else s.typography end,
    merchant_name = case when p_patch ? 'merchant_name' then left(coalesce(p_patch->>'merchant_name',''),120) else s.merchant_name end,
    payment_instructions = case when p_patch ? 'payment_instructions' then left(coalesce(p_patch->>'payment_instructions',''),500) else s.payment_instructions end,
    qris_image_url = case when p_patch ? 'qris_image_url' then nullif(left(coalesce(p_patch->>'qris_image_url',''),1000),'') else s.qris_image_url end,
    qris_enabled = case when p_patch ? 'qris_enabled' then coalesce((p_patch->>'qris_enabled')::boolean,false) else s.qris_enabled end,
    updated_by = null,
    updated_at = now()
  where s.id=1
  returning s.* into v_row;

  return jsonb_build_object('ok',true,'settings',to_jsonb(v_row));
end;
$$;

create or replace function public.admin_console_save_menu(p_token text, p_menu jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_id text;
  v_name text;
  v_row public.menu_items%rowtype;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_menu is null or jsonb_typeof(p_menu) <> 'object' then return jsonb_build_object('ok',false,'error','invalid_menu'); end if;

  v_name := left(trim(coalesce(p_menu->>'name','')),120);
  if length(v_name) < 1 then return jsonb_build_object('ok',false,'error','name_required'); end if;
  v_id := left(trim(coalesce(p_menu->>'id','')),160);
  if v_id='' then v_id := 'menu-' || replace(gen_random_uuid()::text,'-',''); end if;

  insert into public.menu_items(id,name,category,price,description,image_url,is_favorite,is_visible,display_order,updated_by,updated_at)
  values(
    v_id,
    v_name,
    case when coalesce(p_menu->>'category','') in ('Nasi','Lauk','Minuman','Jus Buah') then p_menu->>'category' else 'Lauk' end,
    greatest(0,coalesce((p_menu->>'price')::integer,0)),
    left(coalesce(p_menu->>'description',''),600),
    nullif(left(coalesce(p_menu->>'image_url',''),1000),''),
    coalesce((p_menu->>'is_favorite')::boolean,false),
    coalesce((p_menu->>'is_visible')::boolean,true),
    greatest(0,coalesce((p_menu->>'display_order')::integer,999)),
    null,
    now()
  )
  on conflict (id) do update set
    name=excluded.name,
    category=excluded.category,
    price=excluded.price,
    description=excluded.description,
    image_url=excluded.image_url,
    is_favorite=excluded.is_favorite,
    is_visible=excluded.is_visible,
    display_order=excluded.display_order,
    updated_by=null,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row));
exception when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end;
$$;

create or replace function public.admin_console_set_menu_visible(p_token text, p_id text, p_visible boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_email extensions.citext; v_row public.menu_items%rowtype;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  update public.menu_items set is_visible=coalesce(p_visible,false),updated_by=null,updated_at=now() where id=p_id returning * into v_row;
  if v_row.id is null then return jsonb_build_object('ok',false,'error','menu_not_found'); end if;
  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row));
end;
$$;

create or replace function public.admin_console_update_order(p_token text, p_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_old public.orders%rowtype;
  v_row public.orders%rowtype;
  v_now timestamptz := now();
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_old from public.orders where id=p_id;
  if v_old.id is null then return jsonb_build_object('ok',false,'error','order_not_found'); end if;

  if p_action='verify' then
    update public.orders set payment_status='verified',order_status='confirmed',verified_at=v_now,verified_by=null,kitchen_sent_at=v_now,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'payment_verified',v_old.order_status,'confirmed','Pembayaran dikonfirmasi dan pesanan diteruskan ke KDS.',null);
  elsif p_action='reject' then
    update public.orders set payment_status='rejected',order_status='awaiting_payment',verified_at=null,verified_by=null,kitchen_sent_at=null,updated_at=v_now where id=p_id returning * into v_row;
    insert into public.order_events(order_id,event_type,from_status,to_status,note,actor_id)
    values(p_id,'payment_rejected',v_old.order_status,'awaiting_payment','Pembayaran ditolak untuk diperiksa ulang.',null);
  else
    return jsonb_build_object('ok',false,'error','invalid_action');
  end if;

  return jsonb_build_object('ok',true,'order',to_jsonb(v_row));
end;
$$;

create or replace function public.admin_console_add_admin(p_token text, p_email text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_pw jsonb;
begin
  if not private.admin_is_super_from_token(p_token) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  if p_password is null or length(p_password)<12 or length(p_password)>256 then return jsonb_build_object('ok',false,'error','password_invalid'); end if;
  v_email := lower(trim(coalesce(p_email,'')))::extensions.citext;
  if position('@' in v_email::text)=0 then return jsonb_build_object('ok',false,'error','email_invalid'); end if;

  insert into public.admin_users(email,display_name,role,is_active,is_protected,created_by)
  values(v_email,split_part(v_email::text,'@',1),'admin',true,false,null)
  on conflict (email) do update set is_active=true;

  v_pw := public.admin_password_set_for_admin(p_token,v_email::text,p_password);
  if coalesce((v_pw->>'ok')::boolean,false) is not true then
    delete from public.admin_users where email=v_email and is_protected=false;
    return jsonb_build_object('ok',false,'error',coalesce(v_pw->>'error','password_set_failed'));
  end if;

  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.admin_console_remove_admin(p_token text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_email extensions.citext;
begin
  if not private.admin_is_super_from_token(p_token) then return jsonb_build_object('ok',false,'error','forbidden'); end if;
  v_email := lower(trim(coalesce(p_email,'')))::extensions.citext;
  if exists(select 1 from public.admin_users where email=v_email and is_protected) then return jsonb_build_object('ok',false,'error','protected_admin'); end if;
  delete from private.admin_sessions where email=v_email;
  delete from private.admin_passwords where email=v_email;
  delete from public.admin_users where email=v_email and is_protected=false;
  return jsonb_build_object('ok',true);
end;
$$;

revoke all on function public.admin_console_snapshot(text) from public;
revoke all on function public.admin_console_update_settings(text,jsonb) from public;
revoke all on function public.admin_console_save_menu(text,jsonb) from public;
revoke all on function public.admin_console_set_menu_visible(text,text,boolean) from public;
revoke all on function public.admin_console_update_order(text,uuid,text) from public;
revoke all on function public.admin_console_add_admin(text,text,text) from public;
revoke all on function public.admin_console_remove_admin(text,text) from public;

grant execute on function public.admin_console_snapshot(text) to anon, authenticated;
grant execute on function public.admin_console_update_settings(text,jsonb) to anon, authenticated;
grant execute on function public.admin_console_save_menu(text,jsonb) to anon, authenticated;
grant execute on function public.admin_console_set_menu_visible(text,text,boolean) to anon, authenticated;
grant execute on function public.admin_console_update_order(text,uuid,text) to anon, authenticated;
grant execute on function public.admin_console_add_admin(text,text,text) to anon, authenticated;
grant execute on function public.admin_console_remove_admin(text,text) to anon, authenticated;
