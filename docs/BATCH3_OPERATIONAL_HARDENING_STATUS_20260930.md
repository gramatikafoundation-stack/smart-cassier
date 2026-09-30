# SMART CASHIER — Batch 3 Operational Hardening Status

Date: 2026-09-30 (Asia/Jakarta)
Baseline: Batch 2 RC4 freeze candidate
Floot production: https://smart-cashier-pos.floot.app
Current production version: b3-rc1
Protected exclusions: Rohmat backend and protected Batch 1 surfaces remain untouched.

## Batch 3A — Auth & Session Operational Hardening

Status: PASS / deployed.

Implemented:
- Database session expiry is now enforced on every authenticated session lookup.
- Active sessions renew both the signed cookie and sessions.expires_at on the same 7-day sliding window.
- Traffic-driven operational maintenance replaces unreliable probabilistic cleanup.
- Maintenance uses a PostgreSQL advisory transaction lock plus ops_maintenance_state so only one due run performs cleanup.
- Expired sessions are removed when maintenance is due.
- Login-attempt retention is 30 days instead of accidental short-window deletion.
- Login lockout remains 5 failures / 15 minutes.
- A successful login resets the effective failure window without deleting historical failed-login rows.
- Registration now creates user + password + session inside one transaction.
- Case-insensitive email uniqueness remains database-enforced.
- Auth/session/logout responses use Cache-Control: no-store.
- Rate-limit responses return Retry-After.
- Session cookie remains HttpOnly, Secure, SameSite=Lax and now includes Priority=High.
- Health release marker advanced from b2-rc4 to b3-rc1.

Database additions:
- public.ops_maintenance_state — internal-only operational state; privileges revoked from PUBLIC and smart_cashier_app.
- login_attempts_email_attempted_idx — supports recent success/failure lookup.

QA evidence:
- Typecheck clean before production promotion.
- 3/3 existing tests PASS.
- Production health HTTP 200 / b3-rc1 / Cache-Control no-store.
- Traffic-driven maintenance QA removed 1 expired-session fixture and 1 >30-day login-attempt fixture and recorded last_status=ok.
- Anonymous session remains HTTP 401 with no-store.
- Expiry predicate test: expired fixture rejected; valid fixture accepted by the same DB predicate used by getServerUserSession.
- Sliding expiry test renewed a valid fixture to a bounded ~7-day expiry.
- Lockout semantics test: four failures + success + one failure => effective failure count 1 while audit rows remain; after four additional failures => effective count 5 with audit rows preserved.
- All Batch 3 QA fixture session/login rows were cleaned to zero.
- Vercel smart-cashier-sdb remains READY; no production error/fatal logs found in the verified 24-hour window.

Rollback anchors:
- Batch 2 final Floot checkpoint: af7a09a2-b2d6-4625-a1a2-a41b9ffcb1c7
- Batch 3A Floot checkpoint: 95b9e2ba-b2eb-4059-a1f4-715c68d5f874
- Vercel deployment: dpl_HHwjxRQmucVQch7yZurgeyM5ZFgP (READY, production, rollback candidate)

## Objective scoring — Batch 3A

| Component | Score | Basis |
|---|---:|---|
| Session expiry enforcement | 10.0 | DB expiry enforced and QA predicate verified |
| Sliding session consistency | 10.0 | Cookie/DB windows aligned; renewal bounded |
| Session cleanup | 9.8 | Traffic-driven due gate verified; no paid scheduler dependency |
| Login abuse protection | 9.8 | Advisory serialization, 5/15 lockout, Retry-After |
| Login audit preservation | 10.0 | Success resets logical window without deleting failures |
| Registration atomicity | 9.8 | User/password/session now one transaction |
| Response cache safety | 10.0 | Auth/session/logout no-store |
| Maintenance concurrency safety | 10.0 | advisory xact lock + due-state gate |
| Maintenance data isolation | 10.0 | ops state not granted to PUBLIC/app role |
| Regression safety | 10.0 | typecheck + 3/3 tests; existing business/KDS contracts unchanged |
| Production health | 10.0 | b3-rc1 HTTP 200 |
| Rollback readiness | 9.8 | immutable prior/final checkpoints + Vercel rollback |

Minimum completed Batch 3A score: 9.8/10.

## Batch 3B — Runtime Efficiency & Observability

Audit found one structural optimization target:
- loadTenantContexts currently performs per-membership outlet/access queries (1 + up to 2N query pattern).
- Planned surgical replacement batches outlets and access rows, capping the path at 3 database queries while preserving the exact TenantContext output and RLS behavior.

Runtime observations before this optimization:
- Database size ~9.4 MB.
- Current DB connections observed: 1.
- Most business tables show >94% index-scan share.
- sessions/login_attempts are small enough that PostgreSQL legitimately chooses sequential scans; no evidence of a scale bottleneck.
- Snapshot endpoint already uses Promise.all for independent data reads.
- Order-create fetches menu records in a single IN query and writes order/items/payment/KDS/audit atomically.

## Current blocker

Floot Free daily build-action quota reached 100/100 immediately before writing the Batch 3B tenant-context optimization. The rejected write did not alter source. The quota resets automatically at 2026-10-01T00:00:00Z (07:00 WIB).

Continuation point after reset:
1. Replace loadTenantContexts N+1 pattern with batched 3-query implementation.
2. Typecheck + role/outlet regression QA.
3. Add structured non-PII operational logging for maintenance/rate-limit events.
4. Perform DB integrity/performance gate and reversible migration drill.
5. Complete DR/restore/incident runbook and immutable Batch 3 freeze evidence.
6. Promote b3-rc2 only after every scored component is >=9.5.

Batch 3 overall is NOT frozen yet; only Batch 3A is complete.
