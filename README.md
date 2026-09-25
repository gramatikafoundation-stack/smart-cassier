# SMART CASSIER — Rohmat Master Prototype

Canonical source for the unified SMART DIGITAL FOR BUSINESS cashier platform.

## Current authority

- Repository: `gramatikafoundation-stack/smart-cassier`
- Canonical branch: `main`
- Vercel project: `smart-cassier` (`prj_5xph62xWBNqRRR3MZ3bgA0qZU9NK`)
- Canonical origin: `https://smart-cassier.vercel.app`
- Supabase project: `smart-cassier-platform` (`xrepmvbccalzhlcznrff`, `ap-southeast-1`)
- Reference tenant: `warung-nasi`
- Surface routing: Public `/`, Admin `/admin`, KDS `/kds`
- Deployment region: Vercel `sin1`

Historical repositories, deployments, and the former `yybhpmjuywjxqurrrrxl` backend are retained only as recovery/history evidence. They are not current production authority.

## Architecture

The platform uses one canonical source and one shared multi-tenant runtime. Tenant-specific differences are configuration/data, not source forks.

- `apps/public` — customer ordering/payment surface
- `apps/admin` — management studio
- `apps/kds` — kitchen display system
- `supabase` — migrations and Edge Function source
- `prototype` — tenant validation and provisioning rehearsal
- `tests` — integrated freeze gates
- `ops` — production/release/security records
- `docs` — architecture and release evidence

## Release rule

A production freeze is valid only after the integrated Batch 5 gates pass: source/contract, tenant isolation, browser stress, mobile/tablet/desktop, Public→Admin→KDS data contract, cache semantics, asset/link scan, security review, rollback rehearsal, and canonical production validation.

The release path is:

`audit → surgical patch → branch/CI → review/merge → exact-main production deploy → canonical E2E → freeze evidence`

See `docs/batch5-integrated-freeze-20260925.md` for the current gate record.
