-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260910185814  Name: route_sheet_sync_cron_through_edge_worker
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

select cron.unschedule('rohmat_sheet_sync_worker') where exists (select 1 from cron.job where jobname='rohmat_sheet_sync_worker');
select cron.schedule(
  'rohmat_sheet_sync_worker',
  '* * * * *',
  $$select (extensions.http_post('http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-worker-v1?token=rohmat-sheet-cron-2026-v1','{}','application/json')).status;$$
);
