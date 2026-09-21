-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911065111  Name: explicit_deny_client_sheet_sync_policies
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

drop policy if exists sheet_sync_config_deny_clients on public.sheet_sync_config;
create policy sheet_sync_config_deny_clients on public.sheet_sync_config
for all to anon, authenticated using (false) with check (false);

drop policy if exists sheet_sync_outbox_deny_clients on public.sheet_sync_outbox;
create policy sheet_sync_outbox_deny_clients on public.sheet_sync_outbox
for all to anon, authenticated using (false) with check (false);

drop policy if exists sheet_sync_targets_deny_clients on public.sheet_sync_targets;
create policy sheet_sync_targets_deny_clients on public.sheet_sync_targets
for all to anon, authenticated using (false) with check (false);
