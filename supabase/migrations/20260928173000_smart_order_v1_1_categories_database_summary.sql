-- SMART ORDER v1.1.0 candidate: dynamic menu categories + 30-day database summary.
-- Additive, tenant-scoped, backward-compatible. Frozen v1.0.0 remains untouched.

create or replace function private.tenant_menu_categories_json(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_categories jsonb;
begin
  select case
    when jsonb_typeof(c.settings->'menu_categories')='array'
         and jsonb_array_length(c.settings->'menu_categories')>0
      then c.settings->'menu_categories'
    else null
  end
  into v_categories
  from private.tenant_runtime_config c
  where c.tenant_id=p_tenant_id
  limit 1;

  if v_categories is not null then
    return v_categories;
  end if;

  select coalesce(
    jsonb_agg(x.category order by x.first_order,x.category),
    '[]'::jsonb
  )
  into v_categories
  from (
    select trim(m.category) category,min(m.display_order) first_order
    from public.menu_items m
    where m.tenant_id=p_tenant_id
      and nullif(trim(m.category),'') is not null
    group by trim(m.category)
  ) x;

  if jsonb_array_length(coalesce(v_categories,'[]'::jsonb))=0 then
    return '["Nasi","Lauk","Minuman","Jus Buah"]'::jsonb;
  end if;
  return v_categories;
end
$$;

update private.tenant_runtime_config c
set settings=jsonb_set(
  coalesce(c.settings,'{}'::jsonb),
  '{menu_categories}',
  private.tenant_menu_categories_json(c.tenant_id),
  true
),
updated_at=now()
where not (coalesce(c.settings,'{}'::jsonb) ? 'menu_categories');

create or replace function public.admin_console_save_category_tenant(
  p_tenant_id uuid,
  p_token text,
  p_old_name text,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email extensions.citext;
  v_old text;
  v_name text;
  v_categories jsonb;
  v_next jsonb;
  v_exists boolean:=false;
  v_found boolean:=false;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  v_name:=left(regexp_replace(trim(coalesce(p_name,'')),'\s+',' ','g'),60);
  v_old:=left(regexp_replace(trim(coalesce(p_old_name,'')),'\s+',' ','g'),60);

  if v_name='' then return jsonb_build_object('ok',false,'error','category_name_required'); end if;
  if lower(v_name)='semua' then return jsonb_build_object('ok',false,'error','category_name_reserved'); end if;

  v_categories:=private.tenant_menu_categories_json(p_tenant_id);

  select exists(
    select 1
    from jsonb_array_elements_text(v_categories) x(value)
    where lower(trim(x.value))=lower(v_name)
      and (v_old='' or lower(trim(x.value))<>lower(v_old))
  ) into v_exists;
  if v_exists then return jsonb_build_object('ok',false,'error','category_exists'); end if;

  if v_old='' then
    v_next:=v_categories || jsonb_build_array(v_name);
  else
    select coalesce(jsonb_agg(
      case when lower(trim(x.value))=lower(v_old) then to_jsonb(v_name) else to_jsonb(x.value) end
      order by x.ord
    ),'[]'::jsonb),
    bool_or(lower(trim(x.value))=lower(v_old))
    into v_next,v_found
    from jsonb_array_elements_text(v_categories) with ordinality x(value,ord);

    if not coalesce(v_found,false) then
      return jsonb_build_object('ok',false,'error','category_not_found');
    end if;

    update public.menu_items
    set category=v_name,updated_at=now()
    where tenant_id=p_tenant_id
      and lower(trim(category))=lower(v_old);
  end if;

  update private.tenant_runtime_config
  set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{menu_categories}',v_next,true),
      updated_at=now()
  where tenant_id=p_tenant_id and enabled;

  if not found then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  perform private.sync_tenant_public_settings_projection(p_tenant_id);

  return jsonb_build_object(
    'ok',true,
    'tenant_id',p_tenant_id,
    'categories',v_next,
    'renamed_from',nullif(v_old,''),
    'saved_name',v_name
  );
end
$$;

create or replace function public.admin_console_save_menu_tenant(
  p_tenant_id uuid,
  p_token text,
  p_menu jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email extensions.citext;
  v_id text;
  v_name text;
  v_category text;
  v_canonical_category text;
  v_categories jsonb;
  v_row public.menu_items%rowtype;
  v_slug text;
  v_order integer;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_menu is null or jsonb_typeof(p_menu)<>'object' then return jsonb_build_object('ok',false,'error','invalid_menu'); end if;

  select slug into v_slug
  from private.platform_tenants
  where id=p_tenant_id and status='active';
  if v_slug is null then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  v_name:=left(trim(coalesce(p_menu->>'name','')),120);
  if v_name='' then return jsonb_build_object('ok',false,'error','name_required'); end if;

  v_id:=left(trim(coalesce(p_menu->>'id','')),160);
  if v_id='' then v_id:=v_slug||'-menu-'||replace(gen_random_uuid()::text,'-',''); end if;

  if exists(select 1 from public.menu_items where id=v_id and tenant_id<>p_tenant_id) then
    return jsonb_build_object('ok',false,'error','menu_id_conflict');
  end if;

  v_categories:=private.tenant_menu_categories_json(p_tenant_id);
  v_category:=left(regexp_replace(trim(coalesce(p_menu->>'category','')),'\s+',' ','g'),60);
  if v_category='' then v_category:=coalesce(v_categories->>0,'Lauk'); end if;
  if lower(v_category)='semua' then return jsonb_build_object('ok',false,'error','category_name_reserved'); end if;

  select x.value into v_canonical_category
  from jsonb_array_elements_text(v_categories) x(value)
  where lower(trim(x.value))=lower(v_category)
  limit 1;

  if v_canonical_category is null then
    v_canonical_category:=v_category;
    v_categories:=v_categories||jsonb_build_array(v_canonical_category);
    update private.tenant_runtime_config
    set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{menu_categories}',v_categories,true),
        updated_at=now()
    where tenant_id=p_tenant_id and enabled;
  end if;

  v_order:=greatest(0,coalesce((p_menu->>'display_order')::integer,
    (select coalesce(max(display_order),0)+1 from public.menu_items where tenant_id=p_tenant_id)));

  insert into public.menu_items(
    id,name,category,price,description,image_url,is_favorite,is_visible,
    is_available,display_order,updated_by,updated_at,availability_note,availability_updated_at,tenant_id
  ) values(
    v_id,v_name,v_canonical_category,
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
  perform private.sync_tenant_public_settings_projection(p_tenant_id);
  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row),'categories',v_categories,'tenant_id',p_tenant_id);
exception when unique_violation then
  return jsonb_build_object('ok',false,'error','display_order_conflict');
end
$$;

create or replace function public.admin_console_database_summary_tenant(
  p_tenant_id uuid,
  p_token text,
  p_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_email extensions.citext;
  v_days integer;
  v_tz text;
  v_count bigint:=0;
  v_top_customer jsonb:='null'::jsonb;
  v_top_items jsonb:='[]'::jsonb;
  v_busiest jsonb:='null'::jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;

  v_days:=greatest(1,least(365,coalesce(p_days,30)));
  select coalesce(timezone,'Asia/Jakarta') into v_tz
  from private.tenant_runtime_config
  where tenant_id=p_tenant_id and enabled;
  if v_tz is null then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;

  with all_orders as (
    select o.id,o.created_at,o.customer_name,o.items
    from public.orders o
    where o.tenant_id=p_tenant_id
      and o.created_at>=now()-(v_days||' days')::interval
    union all
    select a.id,a.created_at,a.customer_name,a.items
    from public.order_history_archive a
    where a.tenant_id=p_tenant_id
      and a.created_at>=now()-(v_days||' days')::interval
      and not exists(
        select 1 from public.orders o
        where o.tenant_id=p_tenant_id and o.id=a.id
      )
  )
  select count(*) into v_count from all_orders;

  with all_orders as (
    select o.id,o.created_at,o.customer_name,o.items
    from public.orders o
    where o.tenant_id=p_tenant_id
      and o.created_at>=now()-(v_days||' days')::interval
    union all
    select a.id,a.created_at,a.customer_name,a.items
    from public.order_history_archive a
    where a.tenant_id=p_tenant_id
      and a.created_at>=now()-(v_days||' days')::interval
      and not exists(select 1 from public.orders o where o.tenant_id=p_tenant_id and o.id=a.id)
  ),
  ranked as (
    select trim(customer_name) name,count(*) orders
    from all_orders
    where nullif(trim(customer_name),'') is not null
    group by trim(customer_name)
    order by count(*) desc,trim(customer_name)
    limit 1
  )
  select coalesce(
    (select jsonb_build_object('name',name,'orders',orders) from ranked),
    'null'::jsonb
  ) into v_top_customer;

  with all_orders as (
    select o.id,o.created_at,o.customer_name,o.items
    from public.orders o
    where o.tenant_id=p_tenant_id
      and o.created_at>=now()-(v_days||' days')::interval
    union all
    select a.id,a.created_at,a.customer_name,a.items
    from public.order_history_archive a
    where a.tenant_id=p_tenant_id
      and a.created_at>=now()-(v_days||' days')::interval
      and not exists(select 1 from public.orders o where o.tenant_id=p_tenant_id and o.id=a.id)
  ),
  item_totals as (
    select
      coalesce(nullif(trim(i.value->>'name'),''),'Menu') name,
      sum(greatest(1,coalesce((i.value->>'quantity')::integer,1))) units
    from all_orders o
    cross join lateral jsonb_array_elements(coalesce(o.items,'[]'::jsonb)) i(value)
    group by coalesce(nullif(trim(i.value->>'name'),''),'Menu')
    order by units desc,name
    limit 2
  )
  select coalesce(
    jsonb_agg(jsonb_build_object('name',name,'units',units) order by units desc,name),
    '[]'::jsonb
  ) into v_top_items
  from item_totals;

  with all_orders as (
    select o.id,o.created_at
    from public.orders o
    where o.tenant_id=p_tenant_id
      and o.created_at>=now()-(v_days||' days')::interval
    union all
    select a.id,a.created_at
    from public.order_history_archive a
    where a.tenant_id=p_tenant_id
      and a.created_at>=now()-(v_days||' days')::interval
      and not exists(select 1 from public.orders o where o.tenant_id=p_tenant_id and o.id=a.id)
  ),
  hours as (
    select extract(hour from created_at at time zone v_tz)::integer hour,count(*) orders
    from all_orders
    group by 1
    order by orders desc,hour
    limit 1
  )
  select coalesce(
    (select jsonb_build_object(
      'hour',hour,
      'label',lpad(hour::text,2,'0')||':00–'||lpad(hour::text,2,'0')||':59',
      'orders',orders
    ) from hours),
    'null'::jsonb
  ) into v_busiest;

  return jsonb_build_object(
    'ok',true,
    'tenant_id',p_tenant_id,
    'period_days',v_days,
    'period_start',now()-(v_days||' days')::interval,
    'generated_at',now(),
    'transaction_count',v_count,
    'top_customer',v_top_customer,
    'top_items',v_top_items,
    'busiest_hour',v_busiest
  );
end
$$;

revoke all on function public.admin_console_save_category_tenant(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_console_save_category_tenant(uuid,text,text,text) to service_role;

revoke all on function public.admin_console_database_summary_tenant(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.admin_console_database_summary_tenant(uuid,text,integer) to service_role;
