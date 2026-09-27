-- SMART ORDER B1: unified single-origin resolver for four surfaces
begin;

create or replace function public.master_prototype_resolve_origin(
  p_origin text,
  p_app_kind text default null::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_origin text;
  v private.tenant_origin_aliases%rowtype;
  c private.tenant_runtime_config%rowtype;
  t private.platform_tenants%rowtype;
  v_public_brand text;
  v_public_hero text;
  v_effective_kind text;
  v_surface_route text;
begin
  v_origin:=private.normalize_https_origin(p_origin);
  if v_origin is null then
    return jsonb_build_object('ok',false,'error','invalid_origin');
  end if;

  if p_app_kind is not null and p_app_kind not in ('public','admin','kds','database') then
    return jsonb_build_object('ok',false,'error','invalid_app_kind');
  end if;

  select * into v
  from private.tenant_origin_aliases a
  where a.origin=v_origin
    and a.enabled
    and (
      p_app_kind is null
      or a.app_kind=p_app_kind
      or (
        a.alias_kind='canonical'
        and (
          (p_app_kind='public' and (a.metadata->'unified_routes') ? '/')
          or (p_app_kind='admin' and (a.metadata->'unified_routes') ? '/admin')
          or (p_app_kind='kds' and (a.metadata->'unified_routes') ? '/kds')
          or (p_app_kind='database' and (a.metadata->'unified_routes') ? '/database')
        )
      )
    )
  order by
    case
      when p_app_kind is not null and a.app_kind=p_app_kind then 0
      when a.alias_kind='canonical' then 1
      else 2
    end,
    a.id
  limit 1;

  if v.id is null then
    return jsonb_build_object('ok',false,'error','tenant_not_resolved');
  end if;

  select * into t
  from private.platform_tenants
  where id=v.tenant_id and status='active';

  select * into c
  from private.tenant_runtime_config
  where tenant_id=v.tenant_id and enabled;

  if t.id is null or c.tenant_id is null then
    return jsonb_build_object('ok',false,'error','tenant_unavailable');
  end if;

  v_effective_kind:=coalesce(p_app_kind,v.app_kind);
  v_surface_route:=coalesce(
    c.settings->'surface_routes'->>v_effective_kind,
    case v_effective_kind
      when 'public' then '/'
      when 'admin' then '/admin'
      when 'kds' then '/kds'
      when 'database' then '/database'
      else '/'
    end
  );

  if v_effective_kind='public' then
    select s.business_name,s.hero_image_url
      into v_public_brand,v_public_hero
    from public.tenant_site_settings_public_v1 s
    where s.tenant_id=t.id
    limit 1;
  end if;

  v_public_brand:=coalesce(nullif(trim(v_public_brand),''),c.business_name,c.merchant_name);

  return jsonb_build_object(
    'ok',true,
    'tenant_id',t.id,
    'tenant_slug',t.slug,
    'app_kind',v_effective_kind,
    'surface_route',v_surface_route,
    'business_name',case when v_effective_kind='public' then v_public_brand else c.business_name end,
    'merchant_name',case when v_effective_kind='public' then v_public_brand else c.merchant_name end,
    'hero_image_url',case when v_effective_kind='public' then nullif(trim(v_public_hero),'') else null end,
    'locale',c.locale,
    'currency',c.currency,
    'timezone',c.timezone,
    'public_origin',private.normalize_https_origin(c.public_origin),
    'admin_origin',private.normalize_https_origin(c.admin_origin),
    'kds_origin',private.normalize_https_origin(c.kds_origin),
    'database_url',nullif(c.settings->>'database_url',''),
    'qris_asset',c.qris_asset,
    'storage_static_bucket',c.storage_static_bucket,
    'storage_payment_bucket',c.storage_payment_bucket,
    'table_count',c.table_count,
    'require_table_qr_signature',c.require_table_qr_signature,
    'resolved_origin',v.origin,
    'alias_kind',v.alias_kind
  );
end
$function$;

comment on function public.master_prototype_resolve_origin(text,text) is
'SMART ORDER single-domain resolver: one canonical origin resolves public, admin, kds, and database surfaces by path contract while preserving fail-closed origin lookup.';

commit;
