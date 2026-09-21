create or replace function private.request_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path to 'private','public'
as $function$
declare
  headers jsonb := '{}'::jsonb;
  raw text;
  v uuid;
  v_origin text;
begin
  begin
    headers := coalesce(current_setting('request.headers', true)::jsonb, '{}'::jsonb);
  exception when others then
    headers := '{}'::jsonb;
  end;

  raw := nullif(trim(coalesce(headers->>'x-sdb-tenant-id','')),'');
  if raw is not null then
    begin
      v := raw::uuid;
    exception when invalid_text_representation then
      v := null;
    end;
    if v is not null and exists(
      select 1
      from private.platform_tenants t
      join private.tenant_runtime_config c on c.tenant_id=t.id
      where t.id=v and t.status='active' and c.enabled
    ) then
      return v;
    end if;
  end if;

  raw := nullif(trim(coalesce(headers->>'origin','')),'');
  if raw is null then
    raw := nullif(trim(coalesce(headers->>'referer','')),'');
    if raw is not null then
      raw := substring(raw from '^(https://[^/]+)');
    end if;
  end if;

  v_origin := private.normalize_https_origin(raw);
  if v_origin is null then
    return null;
  end if;

  select a.tenant_id
    into v
  from private.tenant_origin_aliases a
  join private.platform_tenants t on t.id=a.tenant_id
  join private.tenant_runtime_config c on c.tenant_id=a.tenant_id
  where a.origin=v_origin
    and a.enabled
    and t.status='active'
    and c.enabled
  order by case when a.alias_kind='canonical' then 0 else 1 end, a.id
  limit 1;

  return v;
end
$function$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.admin_users au
      where au.email = lower(coalesce((select auth.jwt() ->> 'email'), ''))::extensions.citext
        and au.is_active
    )
    and exists (
      select 1
      from private.tenant_memberships tm
      where tm.tenant_id = private.client_tenant_id()
        and lower(tm.email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
        and tm.is_active
        and tm.role in ('admin','superadmin')
    );
$function$;
