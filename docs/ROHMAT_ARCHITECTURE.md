# Rohmat Architecture Contract

## Canonical roles

- **GitHub `gramatikafoundation-stack/Rohmat-Master`** is the single source of truth for application source, Vercel configuration, Supabase Edge Function source, migrations, release metadata, and rollback references. The active integration branch is `freeze-prep`.
- **Vercel** is deployment/runtime only. Canonical projects:
  - Admin: `studio-pengelola-rohmat` from `apps/admin`
  - Public: `rohmat-pesan-bayar-publik` from `apps/public`
  - KDS: `rohmat-kds-printer` from `apps/kds`
- **Supabase project `yybhpmjuywjxqurrrrxl`** is the operational backend/source of truth for database, auth/session, RLS, RPC/API, Edge Functions, design-system state, orders, menu, settings, and sync workers.
- **Google Sheets** is reporting mirror only. It is not authoritative storage.
- **PostHog** is analytics/monitoring only. It is not application state.
- **Figma** is design/UX reference only. Production changes must land in GitHub before release.

## Release path

`audit → edit source → commit/PR → preview/runtime verification → production → release baseline`

Direct production-only edits are emergency recovery steps and must be reconciled back to GitHub immediately.

## Deployment isolation

A change to one app must not trigger unnecessary deploys of the other apps.

- `apps/admin/**` → Admin only
- `apps/public/**` → Public only
- `apps/kds/**` → KDS only
- root package/lock changes may trigger all affected apps

## Backend boundary

Frontend code under `apps/**` must not contain Supabase service-role secrets or become a second database/backend. Privileged operations stay behind Supabase RPC/Edge Functions.

## Canonical URLs

- Admin: https://studio-pengelola-rohmat.vercel.app/
- Public: https://rohmat-pesan-bayar-publik.vercel.app/
- KDS: https://rohmat-kds-printer.vercel.app/

## Non-canonical Vercel projects

Diagnostic, preview, path-test, base64-test, replica, and other historical projects are not production authorities. Do not point canonical domains at them except for a documented recovery action. Deletion is intentionally not automated because it is destructive.
