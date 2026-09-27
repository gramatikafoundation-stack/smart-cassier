-- DR-only final identity reconciliation for untracked production control-plane state.
-- No credentials, tokens, QR signatures or transactional data are introduced here.
update private.platform_tenants
set slug='warung-nasi',
    name='Warung Nasi',
    source_prototype_key='smart-cassier-platform-v1',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'role','initial_tenant',
      'business_name','Warung Nasi',
      'legacy_site_settings_id',1
    ),
    updated_at=now()
where id='d8bb901c-7399-485b-8743-b319fde148ac';

create or replace function private.reference_tenant_id()
returns uuid
language sql
stable security definer
set search_path=private,public
as $$
  select id from private.platform_tenants
  where slug='warung-nasi' and status='active'
  order by created_at limit 1
$$;
revoke all on function private.reference_tenant_id() from public,anon,authenticated;
grant execute on function private.reference_tenant_id() to service_role;
