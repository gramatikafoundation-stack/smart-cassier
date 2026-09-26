-- Batch 5 freeze hardening: make intentional client denial explicit.
drop policy if exists "deny_client_access_sheet_writer_lease" on private.sheet_writer_lease;
create policy "deny_client_access_sheet_writer_lease"
on private.sheet_writer_lease
for all
to anon, authenticated
using (false)
with check (false);

drop policy if exists "deny_client_access_public_rum_samples" on public.public_rum_samples;
create policy "deny_client_access_public_rum_samples"
on public.public_rum_samples
for all
to anon, authenticated
using (false)
with check (false);
