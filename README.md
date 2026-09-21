# Rohmat Master

Canonical source, deployment contracts, and clone-ready architecture for the Rohmat Nasi Uduk platform.

## Status

**Freeze preparation in progress.** The current working branch is `freeze-prep`. The `main` branch must not be treated as Master Clone v1.0 until all freeze gates pass.

## Target architecture

- `apps/public` — customer ordering and payment storefront
- `apps/admin` — management studio
- `apps/kds` — kitchen display system
- `supabase` — migrations, Edge Functions, policies, and database contracts
- `clone` — merchant-specific provisioning configuration only
- `tests` — smoke, security, contract, and clone-rehearsal tests
- `ops` — production manifest, rollback references, and release runbooks
- `docs` — architecture and freeze-readiness documentation

## Clone principle

Master source must remain unchanged when creating a new merchant clone. Merchant-specific differences are provided only through provisioning/configuration, including business name, URLs, menu data, QRIS, table QR codes, owner bootstrap, Supabase destination, and spreadsheet destination.

## Freeze rule

`MASTER CLONE v1.0` may be tagged only after Public reliability, KDS HttpOnly BFF, native security headers, least-privilege data contracts, Git/CI-CD, DR restore, two independent clone rehearsals, and the final end-to-end audit all pass.
