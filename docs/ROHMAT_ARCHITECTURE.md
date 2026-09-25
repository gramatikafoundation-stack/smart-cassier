# SMART CASSIER Architecture Contract

## Canonical authorities

- **GitHub**: `gramatikafoundation-stack/smart-cassier` is the source/release authority.
- **Vercel**: project `prj_5xph62xWBNqRRR3MZ3bgA0qZU9NK` (`smart-cassier`) is the unified web runtime.
- **Supabase**: `xrepmvbccalzhlcznrff` (`smart-cassier-platform`, `ap-southeast-1`) is the operational data/auth/RLS/RPC/Edge Function source of truth.
- **Google Sheets**: reporting mirror only; never authoritative application state.
- **PostHog**: observability/analytics only.
- **Figma**: design reference only; release changes must land in Git first.

## Unified surface topology

Canonical origin: `https://smart-cassier.vercel.app`.

| Surface | Canonical route | Boundary |
| --- | --- | --- |
| Public | `/` | Public ordering/runtime |
| Admin | `/admin` | Management studio; noindex; session-gated operations |
| KDS | `/kds` | Kitchen display; noindex; same-origin HttpOnly BFF |
| KDS login | `/kds/login` | KDS authentication |
| KDS BFF | `/api/kds` | Same-origin privileged boundary |

The reference tenant currently uses one unified origin for all three surfaces. Tenant configuration validation supports either one unified origin or three distinct origins, but never an ambiguous two-origin topology.

## Multi-tenant boundary

Tenant resolution is explicit and fail-closed. Operational queries must carry or resolve a tenant identifier and remain tenant-scoped. Current tenancy enforcement is active (`enforce_client_rls=true`). New tenants reuse canonical source and shared platform infrastructure; they do not require source edits, source clones, or separate Supabase projects.

## Security boundary

Frontend source under `apps/**` must never contain the Supabase service-role secret. Privileged database/storage operations remain behind tenant-aware RPCs/Edge Functions. KDS privileged sessions remain server-side/HttpOnly. Public bootstrap data comes only from least-privilege projections/resolvers.

## Release path

`audit → edit source → deterministic source gates → browser/stress gates → merge main → exact-main Vercel production deploy → canonical cross-surface E2E → freeze evidence`

Batch 5 CI is defined in `.github/workflows/batch5-integrated-freeze-gate.yml`.
