create extension if not exists pgcrypto with schema extensions;

drop policy if exists rdc_recovery_select_by_key on public.rdc_recovery_devices;
drop policy if exists rdc_recovery_update_by_key on public.rdc_recovery_devices;

create policy rdc_recovery_select_by_key
on public.rdc_recovery_devices
for select
to anon
using (
  recovery_key_hash = encode(
    extensions.digest(
      convert_to(coalesce((current_setting('request.headers', true)::json ->> 'x-recovery-key'), ''), 'UTF8'),
      'sha256'
    ),
    'hex'
  )
);

create policy rdc_recovery_update_by_key
on public.rdc_recovery_devices
for update
to anon
using (
  recovery_key_hash = encode(
    extensions.digest(
      convert_to(coalesce((current_setting('request.headers', true)::json ->> 'x-recovery-key'), ''), 'UTF8'),
      'sha256'
    ),
    'hex'
  )
)
with check (
  recovery_key_hash = encode(
    extensions.digest(
      convert_to(coalesce((current_setting('request.headers', true)::json ->> 'x-recovery-key'), ''), 'UTF8'),
      'sha256'
    ),
    'hex'
  )
);

grant select, update on public.rdc_recovery_devices to anon;
