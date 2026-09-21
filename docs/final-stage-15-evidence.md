# Final Stage 15 — Evidence Ledger

Status: **IN PROGRESS / FAIL-CLOSED**. This document records verified evidence only; unresolved gates are never converted to PASS by waiver.

## 1. Source control and reproducibility

- Repository: `gramatikafoundation-stack/Rohmat-Master`
- Canonicalization branch: `freeze-prep`
- Canonical critical-source checkpoint: `4686678f48c5bf98cda1c36bb89b770c282e11ea`
- `Freeze Source Gates` run `34769680602`: **PASS**
- `Clone Rehearsal` run `34769680611`: **PASS**
- Deterministic clone rehearsal A: **PASS / zero source edits**
- Deterministic clone rehearsal B: **PASS / zero source edits**
- Application source present for Public, Admin, and KDS.
- Registered critical Edge Function source is versioned and Deno type-checked by CI.

## 2. Database/release engineering checkpoint

Release baseline: `rohmat-prod-2026-09-13-r17-ci-pass`

| Evidence | Value | State |
|---|---|---|
| Migration head | `20260913160959` | PASS |
| Schema fingerprint | `38bd5cc06e3e161f7f62d95f4f76b3c1f4146b4387d344faf245dbf1102a3581` | PASS |
| Cron fingerprint | `d03fe98b98b26e86a195b04d54218eaaec50126c2887cc1cab950ebb61e39716` | PASS |
| Manifest fingerprint | `d24b6373b10484a7e7e31dd2f1f67dd93dbf908d16736efabaf878cf6d9de21a` | PASS |
| Registered components | `25/25` | PASS |
| Critical components | `23` | PASS |
| Missing SHA fingerprints | `0` | PASS |
| Missing rollback refs | `0` | PASS |
| Change-control drift | `0` | PASS |
| Missing runtime backups | `0` | PASS |
| Duplicate/malformed migrations | `0/0` | PASS |
| Release policy CI state | `freeze_source_gates_pass` | PASS |
| Direct production changes allowed | `false` | PASS |

## 3. Canonical deployments

### Public

- URL: `https://rohmat-pesan-bayar-publik.vercel.app`
- Canonical deployment: `dpl_8whZS773bxTfwSw4kizsKTiGLY7u`
- Rollback: `dpl_GzunTDaLoQhASbDGh98T9NifVQy8`
- Source: Git / `freeze-prep`
- HTTP state: 200
- Native CSP/frame protections/HSTS/Referrer-Policy/Permissions-Policy/X-Content-Type-Options: **PASS**
- Public LKG + Smart OCR v6 markers: **PASS**

### KDS

- URL: `https://rohmat-kds-printer.vercel.app`
- Canonical deployment: `dpl_3koN3zGSYaTE2zFgr4QkuM7Hd3Uq`
- Rollback: `dpl_EeTJjouE6sgswxJheTBz4e6tqwow`
- Source: Git / `freeze-prep`
- HTTP state: 200
- Native CSP/frame protections/HSTS/Referrer-Policy/Permissions-Policy/X-Content-Type-Options: **PASS**
- Same-origin HttpOnly BFF contract: **PASS**

### Admin

- URL: `https://studio-pengelola-rohmat.vercel.app`
- Current canonical deployment: `dpl_BLvG6kGuskbENMy3LzMFvNDvgbPN`
- Rollback: `dpl_82XtYjzkAEvgJKirXFSDBsdNvWo6`
- Current Vercel project Git link: **ABSENT**
- Current canonical response remains legacy and does not yet expose the complete native response-header security contract.
- Git-built secure candidate exists and is READY: `dpl_BGJLzF3JRHFbN2ZWQ3AeT6mjMLqk`, commit `57615162d8da9b333843c5f4027720b118b580a0`.
- Canonical Admin Git cutover: **PENDING — BLOCKING FINAL FREEZE**
- Raw `site_settings` production policy revocation: **PENDING until Admin cutover**

## 4. Data, integration, performance and UX

At the current preflight checkpoint:

- Integration contracts: **PASS**
- Sheet consistency: **PASS** (`5/5` active targets consistent)
- Sheet outbox failed/dead/stale: **0/0/0**
- Frontend performance budget: **PASS**
- Frontend UX contract: **PASS**
- Visible menu: `36`
- Visible menu missing images: `0`
- Invalid visible menu: `0`
- QRIS configuration: **PASS**
- Canonical navigation targets: **PASS**
- Recovery checkpoint: **PASS**
- Built-in recovery drill: **PASS**

## 5. Reliability certification

Current 1h window: Admin, KDS, Order Gateway, and Public are all **100%**.

The rolling Public 24h certification is not yet clean because historical failures remain inside the window:

- Public 24h samples at checkpoint: `276`
- Successful: `246`
- Availability: `89.13%`
- Required 24h target: `99.9%`
- Latest failed Public probe: `2026-09-13 06:00:14.567543 UTC` / `2026-09-13 13:00:14.567543 WIB`
- Earliest possible clean 24h gate: after `2026-09-14 13:00:14.567543 WIB`, assuming no later failure.

State: **PENDING — BLOCKING FINAL FREEZE**.

## 6. Release preflight

A real preflight validation was captured under release label `rohmat-master-clone-v1.0-prep`.

- Maintainability: PASS
- Integration: PASS
- Sheet consistency: PASS
- Performance: PASS
- UX: PASS
- Outbox: PASS
- Reliability: FAIL due solely to rolling Public historical failures still in the 24h SLO window
- Overall preflight: **FAIL-CLOSED / expected at this checkpoint**

No override or waiver has been applied.

## 7. Disaster recovery / full clone infrastructure

Built-in logical recovery checks are healthy, but Final Stage 15 requires a genuinely isolated infrastructure target. No disposable Supabase branch/project is currently provisioned.

State: **PENDING — BLOCKING FINAL FREEZE**.

The isolated rehearsal must prove at least:

1. migrations replay without source edits;
2. canonical Edge Functions can be deployed from repository source;
3. configuration can be supplied from clone config/environment rather than hardcoded merchant edits;
4. representative schema/data integrity checks pass;
5. Public/Admin/KDS application builds resolve against the isolated backend contract;
6. teardown/rollback is documented.

## 8. Final gate status

| Gate | State |
|---|---|
| Canonical source completeness | PASS |
| Source/type/security CI | PASS |
| Deterministic clone A/B | PASS |
| Database/release fingerprints | PASS |
| Public canonical Git production | PASS |
| KDS canonical Git production | PASS |
| Admin canonical Git production | **PENDING** |
| Admin least-privilege revocation | **PENDING** |
| Isolated full DR/clone rehearsal | **PENDING** |
| Clean rolling 24h reliability | **PENDING** |
| Passing final preflight/postflight | **PENDING** |
| Final Stage 15: 0 unresolved P0/P1 | **PENDING** |
| Merge `freeze-prep -> main` | BLOCKED until all above PASS |
| Tag `rohmat-master-clone-v1.0` | BLOCKED until all above PASS |

## 9. Freeze rule

Do not merge/tag merely because current endpoints are healthy. Final freeze is allowed only after Admin canonical Git cutover, isolated restore/clone rehearsal, rolling reliability certification, and passing preflight/postflight have all produced auditable evidence.
