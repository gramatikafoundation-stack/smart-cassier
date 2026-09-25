> **Historical notice (2026-09-25):** This checklist records the former split-deployment/pre-unified freeze program. The current release authority is `gramatikafoundation-stack/smart-cassier`, Vercel `smart-cassier`, and Supabase `xrepmvbccalzhlcznrff`. Use `docs/batch5-integrated-freeze-20260925.md` and `ops/production-manifest.md` for the active freeze gate. Historical evidence below is preserved for auditability.

# Rohmat Freeze Checklist

Master may be tagged only when every required gate below passes. This checklist is intentionally fail-closed: a gate stays open until production or an isolated rehearsal proves it.

## P0 / P1 gates

- [x] Public point-in-time reliability: 100/100 requests, repeated twice, no 5xx/timeout.
- [x] Public least-privilege contract moved to `site_settings_public_v2`.
- [x] Public SECURITY DEFINER view finding removed; cache table + RLS now used.
- [x] Payment Smart OCR v6 implemented in production and accepted on real device.
- [ ] Clean rolling 24h reliability certification passes target for every registered production service. Historical Public/Admin/Order Gateway failures remain inside the rolling window and are not waived or deleted.
- [x] KDS privileged token removed from browser storage in production canonical deployment.
- [x] KDS login identity is not hardcoded/prefilled in production canonical deployment.
- [x] KDS same-origin HttpOnly cookie BFF is production canonical.
- [x] KDS native CSP / frame-ancestors / Referrer-Policy / Permissions-Policy are enforced.
- [x] Sheets & Data Consistency Hardening current-state gate PASS: 5 yearly targets, 5/5 consistent, no pending/processing/failed/dead outbox rows.
- [ ] Sheet Writer rolling 24h certification passes: success >=99% and invalid ACK = 0. Current 1h window is healthy; historical failures remain in the 24h window and are not reset.
- [x] Public/Admin native CSP / frame-ancestors / Referrer-Policy / Permissions-Policy production rollout PASS.
- [x] Admin broad raw `site_settings` browser reads removed. Raw SELECT is revoked for `anon` and `authenticated`; browser reads use least-privilege projections.
- [x] Canonical application and critical Edge Function source is committed and reproducible from this repo.
- [x] Public, Admin, and KDS production applications are deployed and current production artifacts are represented by canonical source. Admin production deployment is API-backed rather than Git-triggered because the Vercel project Git integration is not active; source parity is maintained in `freeze-prep`.
- [x] Full isolated disaster restore / clone-infrastructure rehearsal PASS at zero additional cost using local Supabase/Docker in GitHub Actions.
- [x] Clone rehearsal A succeeds with zero source edits.
- [x] Clone rehearsal B succeeds with zero source edits.
- [ ] Final Stage 15 audit passes with 0 unresolved P0/P1 and all Stage 15 acceptance criteria satisfied.

## Canonical source and release engineering evidence — 2026-09-14

- Repository: `gramatikafoundation-stack/Rohmat-Master`.
- Freeze branch: `freeze-prep`.
- Latest Freeze Source Gates PASS on commit `8b7f4e827a729e65832f534b7f6c46b63676647c`.
- Deterministic Clone Rehearsal A/B previously PASS with zero source edits.
- Release baseline: `rohmat-prod-2026-09-14-r19-zero-cost-dr-reconcile`.
- Migration head: `20260913201623` (`cleanup_temporary_dr_migration_export_v1`).
- Schema fingerprint: `38bd5cc06e3e161f7f62d95f4f76b3c1f4146b4387d344faf245dbf1102a3581`.
- Cron fingerprint: `d03fe98b98b26e86a195b04d54218eaaec50126c2887cc1cab950ebb61e39716`.
- Manifest fingerprint: `d24b6373b10484a7e7e31dd2f1f67dd93dbf908d16736efabaf878cf6d9de21a`.
- Release engineering status: PASS (`25/25` components registered, `23` critical, `0` missing SHA, `0` missing rollback refs, `0` change-control drift, `0` malformed/duplicate migration versions).
- Release policy CI status: `freeze_source_gates_pass`.
- Direct production changes: disabled by release policy.

## KDS canonical production evidence

- Canonical URL: `https://rohmat-kds-printer.vercel.app`.
- Canonical production deployment: `dpl_3koN3zGSYaTE2zFgr4QkuM7Hd3Uq`.
- Production source: `freeze-prep`.
- Same-origin BFF `/api/kds`, HttpOnly `__Host-rohmat_kds`, no hardcoded login identity, no privileged browser token.
- Visible menu count: 36/36.
- Native security headers verified.

## Public canonical production evidence

- Canonical URL: `https://rohmat-pesan-bayar-publik.vercel.app`.
- Canonical renderer marker: `X-Rohmat-Public: master-lkg-v2`.
- OCR marker: `X-Rohmat-Public-OCR: smart-v6-4800ms`.
- Native security headers verified.
- Direct raw `site_settings` references: none; public projection remains readable after raw access revocation.

## Admin canonical production evidence — 2026-09-14

- Canonical URL: `https://studio-pengelola-rohmat.vercel.app`.
- Production deployment: `dpl_DMJ47Ry2N1nMMShzhFXmU5STAL53` — READY, target production.
- Production marker: `X-Rohmat-Admin: master-source-v2`.
- Hardened source marker after renderer v21: `X-Rohmat-Admin-Source: db-hardened-packed`.
- Native headers verified: CSP with `frame-ancestors 'none'`, `X-Frame-Options: DENY`, HSTS, Referrer-Policy, Permissions-Policy, X-Content-Type-Options, no-store cache policy.
- `rohmat-admin-render` v21 packs the hardened full Admin runtime into an exact 100,000-character bootstrap envelope; browser decompresses to the full Admin UI, with a full-source fallback endpoint for compatibility.
- Latest performance sample remains within budget; Admin payload and latency budgets PASS.
- Raw `public.site_settings` SELECT privilege is false for both `anon` and `authenticated`; `site_settings_public_v2` and `site_settings_admin_runtime_v1` least-privilege projections remain readable as intended.
- Public and Admin were regression-fetched after revocation and remain HTTP 200.

## Zero-cost isolated DR evidence — 2026-09-14

- GitHub Actions workflow: `DR Restore Rehearsal` run `34798230585`.
- Commit under test: `8b7f4e827a729e65832f534b7f6c46b63676647c`.
- Result: PASS.
- Replayed sanitized canonical production history: 166 migrations plus 5 explicit untracked prerequisites and post-export cleanup.
- Structural contract PASS: 17 public tables, 31 private tables, 2 public views, 57 public functions, 60 private functions, 48 RLS-enabled relations, 58 policies, 25 non-internal triggers, 98 indexes.
- Critical relations/RLS PASS.
- Least-privilege/RPC contract PASS, including raw `site_settings` denied to anon and `order_archive_7d` denied to anon/authenticated.
- Canonical critical Edge Function source presence PASS.
- Restore schema fingerprint: `6a6c855cb9e4991de2b6eb8386dc60b1f3ec087e6ef06b0a89639d06381143a0`.
- `DR_RESTORE_PASS=1` emitted by the isolated runner.
- No paid Supabase branch or other billable infrastructure was created.
- Broader offsite logical-data backup and Storage-content backup remain tracked separately as DR hardening; they are not falsely marked verified by this isolated rehearsal.

## Reliability / health evidence — 2026-09-14 03:50 UTC

- Current probes are successful: Admin 200, Public 200, KDS 200; Order Gateway current 1h state is healthy.
- Frontend performance gate: PASS; payload budgets 3/3, median latency budgets 3/3, fresh successful samples 3/3.
- Rolling 1h availability: all registered production services currently 100%.
- Rolling 24h availability remains fail-closed because historical failures are still present: Admin `95.896%`, Public `97.701%`, Order Gateway `99.611%`; KDS `100%`.
- Sheet Writer current 1h SLO: PASS (`59/59`, 100%, invalid ACK 0).
- Sheet Writer rolling 24h SLO remains recovering: `1290/1334`, `96.702%`, invalid ACK 1; latest recorded failure `2026-09-14T02:37:42.112333Z`.
- These historical records are retained and are not reset merely to obtain a release.
- Maintainability: PASS.
- Integration contracts: PASS.
- Sheet consistency: PASS.
- Frontend UX server/runtime contract: PASS.
- Built-in recovery checkpoint and in-place recovery drill: PASS.

## Sheets/Data Consistency evidence

- Active yearly targets: 5 (2026–2030).
- Every target configured with 5 expected tabs.
- Outbox current state: no pending/processing/failed/dead rows.
- Latest observed synced count: 366; superseded: 5.
- Current-state hardening gate PASS.

## Freeze output

When the remaining fail-closed conditions pass:

1. Obtain clean rolling 24h reliability certification for every registered production service.
2. Obtain clean Sheet Writer 24h certification (`>=99%`, invalid ACK `0`).
3. Re-run final release preflight and capture final release validation evidence.
4. Complete Final Stage 15 with 0 unresolved P0/P1 and all Stage 15 acceptance criteria satisfied.
5. Merge `freeze-prep` to `main`.
6. Tag `rohmat-master-clone-v1.0`.
7. Record final deployment IDs, migration head, production and DR fingerprints, and rollback references.
8. Treat the master source as immutable for merchant-specific requests.
