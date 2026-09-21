# Admin DATABASE ↔ Google Sheets Integration v2

Verified production state on 2026-09-14.

## Canonical counts
- Supabase `orders`: 5 rows.
- Admin DATABASE / Riwayat Pesanan: canonical source returns the same 5 rows.
- Google Sheets `PESANAN`: 5 visible transaction rows, matching the five order IDs/codes in Supabase.

## Spreadsheet presentation correction
- Cleared the basic filter on `PEMESAN`, `PESANAN`, and `KEUANGAN`.
- Unhid the active data rows so history is not visually suppressed.
- Dashboard cell G4 was relabeled from ambiguous `JUMLAH TRANSAKSI` to `TRANSAKSI HARI INI`; G5 remains today's count (3 at verification time), while full history is in `PESANAN` (5 rows at verification time).

## Admin behavior
- `rohmat-admin-database-ui-v1` production version 13.
- `Spreadsheet` subnav opens the actual Google Sheet directly at the `PESANAN` tab (`gid=1102`), with no intermediary page.
- History continues to refresh from Supabase while DATABASE is active.

## Sync pipeline
- Public orders, Smart Cashier Admin, and Smart Cashier KDS all persist to the same `public.orders` source of truth.
- Order INSERT/UPDATE triggers enqueue Google Sheets sync events.
- Event-driven worker remains active, with 10-second fallback drain and reconciliation safety net.
- No pending/processing/failed/dead sync events at final verification.

No unrelated Public/KDS UI, OCR, stock, payment, theme, or authentication behavior was changed by this revision.
