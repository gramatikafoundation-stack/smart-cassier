alter table public.menu_items drop constraint if exists menu_items_category_check;
alter table public.menu_items
  add constraint menu_items_category_check
  check (
    char_length(btrim(category)) between 1 and 60
    and lower(btrim(category)) <> 'semua'
  );

create or replace function public.admin_console_update_settings_tenant(
  p_tenant_id uuid,
  p_token text,
  p_patch jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext;
  v_patch jsonb:='{}'::jsonb;
  v_settings jsonb;
  v_categories jsonb:='[]'::jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_patch is null or jsonb_typeof(p_patch)<>'object' then
    return jsonb_build_object('ok',false,'error','invalid_patch');
  end if;

  if p_patch ? 'menu_categories' then
    if jsonb_typeof(p_patch->'menu_categories') <> 'array' then
      return jsonb_build_object('ok',false,'error','invalid_menu_categories');
    end if;
    select coalesce(jsonb_agg(to_jsonb(x.category) order by lower(x.category)),'[]'::jsonb)
      into v_categories
    from (
      select distinct on (lower(btrim(e.value)))
        left(btrim(e.value),60) as category,
        e.ord
      from jsonb_array_elements_text(p_patch->'menu_categories') with ordinality as e(value,ord)
      where char_length(btrim(e.value)) between 1 and 60
        and lower(btrim(e.value)) <> 'semua'
      order by lower(btrim(e.value)), e.ord
      limit 50
    ) x;
    p_patch:=jsonb_set(p_patch,'{menu_categories}',v_categories,true);
  end if;

  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
    into v_patch
  from jsonb_each(p_patch)
  where key=any(array[
    'business_name','welcome_text','motto','hero_image_url','photo_position','content_position',
    'content_width','element_order','theme_preset','color_outer','color_panel','color_primary',
    'color_accent','color_text','color_muted','typography','merchant_name','payment_instructions',
    'qris_image_url','qris_enabled','admin_design','kds_design','design_system',
    'require_table_qr_signature','google_sheet_url',
    'transaction_payment','language','transaction_settings','language_settings','menu_categories'
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
$function$;

create or replace function public.admin_console_save_menu_tenant(
  p_tenant_id uuid,
  p_token text,
  p_menu jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext;
  v_id text;
  v_name text;
  v_category text;
  v_row public.menu_items%rowtype;
  v_slug text;
  v_order integer;
  v_settings jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_menu is null or jsonb_typeof(p_menu)<>'object' then return jsonb_build_object('ok',false,'error','invalid_menu'); end if;
  select slug into v_slug from private.platform_tenants where id=p_tenant_id and status='active';
  if v_slug is null then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  v_name:=left(trim(coalesce(p_menu->>'name','')),120);
  if v_name='' then return jsonb_build_object('ok',false,'error','name_required'); end if;

  v_category:=left(btrim(coalesce(p_menu->>'category','')),60);
  if v_category='' then return jsonb_build_object('ok',false,'error','category_required'); end if;
  if lower(v_category)='semua' then return jsonb_build_object('ok',false,'error','category_reserved'); end if;

  v_settings:=coalesce(private.tenant_settings_json(p_tenant_id),'{}'::jsonb);
  if not exists(
      select 1 from public.menu_items m
      where m.tenant_id=p_tenant_id and lower(btrim(m.category))=lower(v_category)
    )
    and not exists(
      select 1
      from jsonb_array_elements_text(
        case when jsonb_typeof(v_settings->'menu_categories')='array'
          then v_settings->'menu_categories' else '[]'::jsonb end
      ) c(value)
      where lower(btrim(c.value))=lower(v_category)
    )
  then
    return jsonb_build_object('ok',false,'error','category_not_registered');
  end if;

  v_id:=left(trim(coalesce(p_menu->>'id','')),160);
  if v_id='' then v_id:=v_slug||'-menu-'||replace(gen_random_uuid()::text,'-',''); end if;

  if exists(select 1 from public.menu_items where id=v_id and tenant_id<>p_tenant_id) then
    return jsonb_build_object('ok',false,'error','menu_id_conflict');
  end if;
  v_order:=greatest(1,coalesce((p_menu->>'display_order')::integer,
    (select coalesce(max(display_order),0)+1 from public.menu_items where tenant_id=p_tenant_id)));

  insert into public.menu_items(
    id,name,category,price,description,image_url,is_favorite,is_visible,
    is_available,display_order,updated_by,updated_at,availability_note,availability_updated_at,tenant_id
  ) values(
    v_id,v_name,v_category,
    greatest(0,coalesce((p_menu->>'price')::integer,0)),
    left(coalesce(p_menu->>'description',''),500),
    coalesce(left(p_menu->>'image_url',1000),''),
    coalesce((p_menu->>'is_favorite')::boolean,false),
    coalesce((p_menu->>'is_visible')::boolean,true),
    coalesce((p_menu->>'is_available')::boolean,true),
    v_order,null,now(),left(coalesce(p_menu->>'availability_note',''),160),now(),p_tenant_id
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
when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end
$function$;
