-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912121518  Name: performance_private_tables_explicit_deny_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

drop policy if exists deny_client_all on private.frontend_asset_route_backup;
create policy deny_client_all on private.frontend_asset_route_backup as restrictive for all to anon,authenticated using(false) with check(false);
drop policy if exists deny_client_all on private.frontend_performance_samples;
create policy deny_client_all on private.frontend_performance_samples as restrictive for all to anon,authenticated using(false) with check(false);
drop policy if exists deny_client_all on private.kds_reference_cache;
create policy deny_client_all on private.kds_reference_cache as restrictive for all to anon,authenticated using(false) with check(false);
