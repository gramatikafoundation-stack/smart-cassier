# Admin DATABASE + Google Sheets Integration — Production v1

Verified on 2026-09-14 (Asia/Jakarta).

## Scope
- Supabase `public.orders` / `public.order_history_archive` remain the canonical source of truth.
- Admin DATABASE > Riwayat Pesanan renders the canonical order snapshot, not a separate copy of Google Sheets data.
- Google Sheets remains an event-driven reporting/reconciliation projection of the same canonical data.
- Public orders, Smart Cashier Admin orders, Smart Cashier KDS orders, and subsequent order-status updates all pass through the same `orders` triggers into `sheet_sync_outbox`.

## Admin DATABASE
- `admin_order_history_snapshot` returns complete canonical order fields, including order code, source, service mode, table, customer, items, totals, payment fields, order status, KDS timestamps, note, cashier, and Sheet sync health.
- `rohmat-admin-database-ui-v1` v12 refreshes active DATABASE history about once per second, plus immediate refresh on local cashier-created/focus/pageshow events.
- UI exposes database transaction count and Sheet synchronization status.

## Google Sheets
- 2026 target spreadsheet: `1rj3kXuBGjQC_bkJXJ_n6Jao7hkco7rpFF7avozcj-Ok`.
- Expected canonical row counts at verification: PEMESAN=5, PESANAN=5, KEUANGAN=5, MENU & STOK=36.
- Google Sheets reads confirmed the same five canonical transactions across Public, Smart Cashier Admin, and Smart Cashier KDS.
- Outbox health at verification: pending=0, processing=0, failed=0, dead=0; consistency=ok.
- Immediate event-trigger dispatch remains enabled.
- Fallback/drain worker uses pg_cron job `rohmat-sheet-sync-drain-10s` every 10 seconds; the previous redundant one-minute worker was removed.
- Eight consecutive job-20 runs were verified `succeeded` at ~10 second intervals.
- Ten-minute reconciliation remains enabled as a consistency safety net.

## Safety
- No existing order rows, payment values, stock values, customer data, or historical transactions were rewritten by this integration revision.
- No Admin/KDS/Public UI outside Admin DATABASE was modified by this revision.
- Google Sheets is not treated as an independent source of truth, preventing two-way divergence.
