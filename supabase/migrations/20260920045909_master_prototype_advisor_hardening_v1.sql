-- ROHMAT MASTER PROTOTIPE v1
-- Advisor hardening after tenant architecture: safe, non-destructive fixes only.

create index if not exists platform_prototypes_reference_tenant_idx
  on private.platform_prototypes(reference_tenant_id);

create index if not exists tenant_origin_aliases_tenant_idx
  on private.tenant_origin_aliases(tenant_id);

-- The tenant-scoped authenticated policy already grants admins all rows in their
-- effective tenant and non-admin authenticated clients only visible rows.
-- Remove the older global admin SELECT policy to avoid duplicate permissive
-- evaluation and cross-tenant widening after final enforcement.
drop policy if exists "Admins read all menu" on public.menu_items;

-- Compute recovery header once per statement instead of per row.
drop policy if exists rdc_recovery_select_by_key on public.rdc_recovery_devices;
create policy rdc_recovery_select_by_key
on public.rdc_recovery_devices
for select to anon
using (
  recovery_key_hash = encode(
    digest(
      convert_to(
        coalesce(
          ((select current_setting('request.headers',true))::json ->> 'x-recovery-key'),
          ''
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
);

drop policy if exists rdc_recovery_update_by_key on public.rdc_recovery_devices;
create policy rdc_recovery_update_by_key
on public.rdc_recovery_devices
for update to anon
using (
  recovery_key_hash = encode(
    digest(
      convert_to(
        coalesce(
          ((select current_setting('request.headers',true))::json ->> 'x-recovery-key'),
          ''
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
)
with check (
  recovery_key_hash = encode(
    digest(
      convert_to(
        coalesce(
          ((select current_setting('request.headers',true))::json ->> 'x-recovery-key'),
          ''
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
);
