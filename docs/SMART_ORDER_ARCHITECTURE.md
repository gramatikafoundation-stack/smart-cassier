# SMART ORDER Architecture Contract — Candidate v1

## Identity model

One tenant = one canonical origin = four integrated surfaces.

Canonical candidate: https://smart-order-sdb.vercel.app

- Public: /
- Admin + Smart Cashier: /admin
- KDS: /kds
- Database / Google Sheets control: /database

The tenant is resolved from the host. The requested surface is resolved from the path.
Surface authorization remains independent: Public is public-facing; Admin, KDS, and Database retain their own authorization/session boundaries.

## Data model

Supabase remains the operational source of truth.
Google Sheets are tenant-scoped spreadsheet resources used by the Database surface and sync/reporting pipeline; they are not a separate application origin.

## Deployment model

- One Git source repository
- One unified Vercel project
- One canonical tenant origin
- Shared Supabase multi-tenant backend with RLS
- Tenant-specific Google Sheets resources

## Legacy model

The former Rohmat master used separate Public/Admin/KDS identities.
That topology is deprecated for new tenants and retained only for rollback, audit, and historical evidence.
New clone/provisioning work must target the single-domain/four-surface model.
