> **SUPERSEDED FOR FINAL ARCHITECTURE (2026-09-20):** Dokumen ini dipertahankan sebagai bukti historis pekerjaan kandidat lama. Keputusan arsitektur final adalah **ROHMAT MASTER PROTOTIPE** dengan logical multi-tenancy di platform Supabase canonical yang sama. Gunakan `docs/rohmat-master-prototype-v1-freeze-20260920.md` sebagai kontrak freeze kanonis. Istilah MASTER CLONE di bawah tidak lagi menjadi arsitektur operasional final.

# MASTER CLONE v1 — Freeze Evidence 2026-09-19

## Status

**MASTER CANDIDATE — NOT FINAL / FAIL-CLOSED**

Production remains unchanged by this freeze branch. No production Supabase schema mutation, Edge Function deletion, Vercel production alias change, or production data deletion is authorized by this candidate.

## Safety boundary

- Candidate branch: `release/master-clone-v1-freeze-20260919`
- Base: `freeze-prep`
- Draft PR: #91
- Production code paths remain untouched until source gates, preview QA, and release gates pass.
- Destructive cleanup of historical Edge Functions/projects is forbidden until dependency evidence proves they are unused.
- Existing production fallbacks are retained only for backward compatibility; clone deployments run with `MASTER_CLONE_STRICT=1` and must fail closed when tenant configuration is incomplete.

## Gate status

| Gate | Status | Evidence / remaining work |
|---|---|---|
| 1. Feature freeze / isolated candidate | PASS | Dedicated release branch + draft PR; no direct production cutover. |
| 2. Tenant parameterization | SOURCE PASS | Clone config schema v2; Public/Admin/KDS runtime env contracts; KDS client no embedded production publishable key; strict-mode guards. Preview still required before merge. |
| 3. Canonical runtime inventory | PASS (non-destructive) | `ops/canonical-edge-functions-v1.json` defines clone allowlist. Historical functions are not deleted during freeze. |
| 4. Security closure | CLONE PASS / PRODUCTION LEGACY EXCEPTION | Fresh-clone pre-bootstrap now installs `pg_net` in `extensions` before migration replay; this pattern was provider-validated transactionally against the existing Lucky project, where pg_net 0.20.4 is non-relocatable and lives in `extensions` with runtime schema `net`. Rohmat production still reports the legacy `pg_net`-in-public warning and is intentionally not drop/recreated. Leaked-password protection is encoded as a mandatory production acceptance gate but cannot be enabled while the organization remains on Supabase Free; Supabase documents it as Pro+ only. |
| 5. Table QR / payment isolation | SOURCE PASS | `require_table_qr_signature=true` mandatory. Different legal payment merchant name requires explicit acknowledgement. Production tenant setting remains unchanged until controlled cutover. |
| 6. Git/source reproducibility | MANUAL ATTESTATION PASS / CI INFRA BLOCK | Independent Windows runner validated Node syntax, strict source-security contract, clone validation/rehearsal, and Deno type-check of all 20 `deploy_on_clone=true` canonical Edge Functions. One real TypeScript contract bug in `create-order-v6` was found and fixed before release. GitHub Actions still terminates without usable step/log evidence and is not falsely marked PASS. |
| 7. Deployment topology / CI-CD | PROVIDER BLOCKED | Three-project topology and selective build filters are correct. Clone-only commits are intentionally canceled by Vercel Ignored Build Step. Source-changing candidate commits remain blocked by Vercel `build-rate-limit`; commit status points to the Vercel plan/rate-limit page, not to an application build error. No production deploy is forced to bypass this. |
| 8. Performance/runtime | CURRENT-WINDOW PASS / FINAL WINDOW PENDING | Latest 24h RUM at recheck: LCP p75 784 ms (7 samples), CLS 0.005 (6), TTFB 238.4 ms (8), INP p75 152 ms (5). Four independent Public browser gates PASS: runtime architecture, 33-cycle memory stress, lifecycle/BFCache, and checkout teardown; 0 browser errors and 0 unexpected writes. INP sample size remains low and must not be overstated. Public HTML is ~112.8 KB; clone contract budget is evidence-rebaselined to 120 KB rather than removing accessibility/SEO. Production budget is not changed by this branch. |
| 9. Spreadsheet provisioning | PRODUCTION PIPELINE PASS / LIVE NEW-CLONE PENDING | Clone schema uses exact production tabs: DASHBOARD, PEMESAN, PESANAN, MENU & STOK, KEUANGAN. Latest production `sheet_worker` rolling 1h and 24h are both 100% (24h: 8293/8293). Five yearly targets are consistent and outbox is clean. A brand-new provider clone Spreadsheet rehearsal remains pending. |
| 10. Two clone rehearsals + final audit | STATIC/LOCAL REHEARSAL PASS / LIVE PROVIDER PENDING | Rehearsal A (id-ID/IDR/Asia-Jakarta) and B (en-SG/SGD/Asia-Singapore) both PASS with zero source edits, strict clone mode, signed table QR, exact five-sheet reporting contract, and 20 canonical clone functions. Live provider clone remains pending because a new Supabase project/branch may be billable and the local runner has no Docker; no paid resource is created silently. |

## Current production reliability certification

Observed on 2026-09-19 during freeze preparation:

- `public_web`: 24h 100%
- `kds_web`: 24h 100%
- `order_gateway`: 24h 100%
- `admin_web`: 1h 100%, but latest checked 24h is 85.417% (246/288) because retained historical 404 failures from 2026-09-18 remain inside the rolling window.
- `sheet_worker`: latest 1h 100% and 24h 100% (8293/8293); the prior two writer failures have naturally aged out of the rolling window without deletion.
- Spreadsheet consistency: 5/5 yearly targets consistent; outbox has no failed/dead/pending rows (latest state: 1376 synced, 16 historical superseded).

Historical failure records MUST NOT be deleted or reset to manufacture a release pass.

## Clone contract v2

Required per tenant:

- independent Public/Admin/KDS origins
- independent Supabase project reference
- independent reporting spreadsheet target
- business name + explicitly acknowledged legal/payment merchant name when different
- locale, currency, IANA timezone
- tenant-specific QRIS asset
- signed table QR enabled
- tenant-specific Storage buckets
- tenant-specific owner bootstrap
- strict runtime environment configuration

The clone validator rejects accidental reuse of Rohmat production Supabase project, production domains, or production spreadsheet.

## Controlled exceptions

### pg_net schema warning

Production `pg_net` is installed in `public` and reports `extrelocatable=false`. The active Sheets pipeline depends on database networking. Moving it requires drop/recreate and is therefore prohibited directly in production during freeze. Resolve only after:
1. isolated restore/rehearsal,
2. empty/no-at-risk queue verification,
3. rollback procedure,
4. post-migration Sheets consistency test.

### Leaked-password protection

Supabase Auth leaked-password protection is currently disabled. This remains an explicit production hardening prerequisite when the applicable Supabase plan/configuration supports enabling it.

### Public INP

Latest low-sample 24h INP is 152 ms p75 (5 samples), below the <=200 ms internal target. This is a current-window PASS with a low-sample caveat; continue collecting RUM rather than declaring a statistically strong long-window pass.

### CI / preview infrastructure

GitHub Actions jobs currently show failure without executed step/log evidence, while local-equivalent source checks performed through repository inspection pass. Vercel candidate deployments report provider `build-rate-limit`. Neither condition is to be bypassed by weakening quality gates.

## Final tag prohibition

Do NOT merge/promote/tag `MASTER CLONE v1.0` while any of the following is true:

- Admin rolling 24h SLO is below configured threshold.
- Sheet Writer rolling 24h certification contains invalid ACK/failure.
- Source/clone CI lacks a valid PASS attestation.
- Candidate preview/E2E has not passed.
- INP acceptance is not satisfied or explicitly re-baselined with evidence.
- Required Supabase security hardening/controlled exceptions are unresolved.
- Two independent clone rehearsals are not evidenced.
- Final Stage 15 audit has unresolved P0/P1 findings.

Only after all gates pass may the candidate be promoted to `freeze-prep`, then `main`, and tagged `master-clone-v1.0.0`.


## Independent manual attestation — 2026-09-19

Performed from an isolated temporary checkout of `release/master-clone-v1-freeze-20260919`; production was not mutated.

- Node syntax/source-security contract: PASS.
- Clone configuration schema v2: PASS.
- Clone rehearsal A/B: PASS, zero source edits.
- Canonical Edge Function type-check: 20/20 PASS using portable Deno after fixing the discovered `create-order-v6` settings projection bug.
- Public runtime architecture browser gate: PASS.
- Public 33-cycle memory stress gate: PASS; listener/node/document/frame deltas remained zero and heap delta stayed inside the configured budget.
- Public lifecycle/BFCache browser gate: PASS.
- Public checkout teardown gate: PASS on fail-closed rerun; an earlier isolated 503 was traced to the local handler's upstream-fetch timeout and did not reproduce.
- Tenant-visible hard-coded Rohmat identity removed from Public accessibility titles/announcements and KDS kitchen-ticket output.
- Clone finalization Public HTML budget rebaselined from 100 KB to 120 KB. Rationale: production document measured ~112.8 KB, with accessibility/SEO runtime materially contributing; current field performance remains strong. Production health budget remains unchanged until controlled cutover/preview validation.
- Local runner has no Docker; latest live isolated Supabase restore is therefore not re-run locally. Prior DR rehearsal evidence remains historical evidence, not a substitute for the final candidate provider/restore gate.


### Provider-compatible pg_net clone bootstrap

Fresh tenant provisioning now runs `clone/pre-bootstrap.sql` before production migration history. It creates `pg_net` with `WITH SCHEMA extensions` and asserts both the extension namespace and the runtime `net` schema before proceeding. The historical migration later uses `CREATE EXTENSION IF NOT EXISTS pg_net`, so it becomes a no-op rather than reinstalling the extension into `public`.

Validation performed against the existing Lucky Supabase project inside an explicit transaction/rollback:
- pg_net version 0.20.4
- extension namespace: `extensions`
- `extrelocatable=false`
- runtime schema `net` present
- no production Rohmat mutation

Lucky also provides historical provider evidence for clone architecture: signed table QR enabled, 20 table signatures, five yearly Spreadsheet targets, and multiple passing Admin/KDS/Cashier functional lifecycle audits. It is NOT counted as the final current-generation clone rehearsal because it predates this candidate and has an older gateway content-type audit failure.

### Stage 15 source audit — current head

Candidate head audit over 59 changed files:
- Rohmat production project-ref leakage in candidate diff: 0
- visible hard-coded `ROHMAT NASI UDUK` leakage in candidate diff: 0
- literal service-role / secret-key leakage in candidate diff: 0
- PR #91 remains draft, open, mergeable, and unmerged
- clone/provision/rehearsal scripts independently syntax-parse PASS
- no source P0/P1 finding identified in the current diff

External release blockers are not reclassified as source PASS:
- GitHub Actions jobs terminate before any steps and expose no job logs.
- Vercel reports `build-rate-limit` for candidate checks.
- Admin 24h SLO still contains historical 404 samples through 2026-09-18 17:05 UTC. Because history is retained, the first honest fully clean 24h check cannot occur until after those samples age out (approximately 2026-09-20 00:10 WIB, assuming subsequent probes remain successful).
- A second current-generation live Supabase clone rehearsal would require creating a new project/branch; no billable resource is created without explicit cost confirmation.
