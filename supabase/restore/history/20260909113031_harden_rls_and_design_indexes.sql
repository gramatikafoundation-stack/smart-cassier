-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909113031  Name: harden_rls_and_design_indexes
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create index if not exists design_system_versions_restored_from_idx on public.design_system_versions(restored_from);

drop index if exists public.idx_order_history_archive_created_at;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='design_system_versions' and policyname='deny_client_access') then
    create policy deny_client_access on public.design_system_versions for all to anon, authenticated using (false) with check (false);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='order_history_archive' and policyname='deny_client_access') then
    create policy deny_client_access on public.order_history_archive for all to anon, authenticated using (false) with check (false);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='public_site_source_snapshots' and policyname='deny_client_access') then
    create policy deny_client_access on public.public_site_source_snapshots for all to anon, authenticated using (false) with check (false);
  end if;
end $$;
