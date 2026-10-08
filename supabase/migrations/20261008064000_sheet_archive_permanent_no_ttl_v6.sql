-- SMART ORDER master v6: permanent external spreadsheet archive, 30-day application retention.
-- 0 is an explicit sentinel meaning: external spreadsheet PII/data TTL disabled.
alter table private.tenant_writer_config
  drop constraint if exists tenant_writer_config_pii_retention_days_check;

alter table private.tenant_writer_config
  add constraint tenant_writer_config_pii_retention_days_check
  check (pii_retention_days between 0 and 3650);

update private.tenant_writer_config
set pii_retention_days=0, updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'::uuid;

create or replace function public.tenant_sheet_sync_config(p_tenant_id uuid)
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
  'business_name',c.business_name,
  'timezone',c.timezone,
  'enabled',coalesce(w.enabled,false),
  'writer_url',w.writer_url,
  'max_attempts',coalesce(w.max_attempts,10),
  'expected_writer_version',coalesce(w.expected_writer_version,4),
  'pii_retention_days',case when coalesce(w.pii_retention_days,0)=0 then null else w.pii_retention_days end,
  'targets',coalesce((
    select jsonb_agg(jsonb_build_object(
      'year',x.year,
      'spreadsheet_id',x.spreadsheet_id,
      'label',x.label,
      'enabled',x.enabled,
      'expected_tabs',x.expected_tabs
    ) order by x.year)
    from private.tenant_sheet_targets x
    where x.tenant_id=p_tenant_id and x.enabled
  ),'[]'::jsonb)
)
from private.platform_tenants t
join private.tenant_runtime_config c on c.tenant_id=t.id and c.enabled
left join private.tenant_writer_config w on w.tenant_id=t.id
where t.id=p_tenant_id and t.status='active'
limit 1
$$;

revoke all on function public.tenant_sheet_sync_config(uuid) from public,anon,authenticated;
grant execute on function public.tenant_sheet_sync_config(uuid) to service_role;
