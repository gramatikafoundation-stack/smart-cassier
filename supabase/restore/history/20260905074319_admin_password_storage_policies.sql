-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905074319  Name: admin_password_storage_policies
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

drop policy if exists "Password admins read asset objects" on storage.objects;
create policy "Password admins read asset objects" on storage.objects
for select to anon
using (bucket_id = 'rohmat-assets' and (select private.is_admin_session()));

drop policy if exists "Password admins upload asset objects" on storage.objects;
create policy "Password admins upload asset objects" on storage.objects
for insert to anon
with check (bucket_id = 'rohmat-assets' and (select private.is_admin_session()));

drop policy if exists "Password admins update asset objects" on storage.objects;
create policy "Password admins update asset objects" on storage.objects
for update to anon
using (bucket_id = 'rohmat-assets' and (select private.is_admin_session()))
with check (bucket_id = 'rohmat-assets' and (select private.is_admin_session()));

drop policy if exists "Password admins delete asset objects" on storage.objects;
create policy "Password admins delete asset objects" on storage.objects
for delete to anon
using (bucket_id = 'rohmat-assets' and (select private.is_admin_session()));

drop policy if exists "Password admins read payment proof objects" on storage.objects;
create policy "Password admins read payment proof objects" on storage.objects
for select to anon
using (bucket_id = 'rohmat-payment-proofs' and (select private.is_admin_session()));
