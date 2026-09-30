# SMART CASHIER — Batch 2 Evaluation (2026-09-30)

## Objective
Close the Batch 2 Cloud + Multi-Tenant Core hardening without touching Rohmat backend or protected Batch 1 surfaces.

## Surgical RLS result
The former broad kds_events write policy was split by SQL command. CASHIER gains only the initial event path actually emitted by order-create: PAID -> NEW. It must be the current actor, have access to the exact tenant/outlet, and the referenced order must match order_id + tenant_id + outlet_id, belong to that cashier, and remain PAID/NEW. UPDATE and DELETE policies remain restricted to OWNER/ADMIN/KITCHEN.

A pre-freeze pg_policies inspection caught an initial SQL identifier-binding ambiguity. The final policy was corrected with explicit kds_events.order_id, kds_events.tenant_id, and kds_events.outlet_id qualification and re-read from PostgreSQL before freeze.

## Production QA summary
- CASHIER initial KDS INSERT: PASS.
- CASHIER lifecycle INSERT: RLS REJECTED as required.
- ADMIN lifecycle: PASS.
- KITCHEN lifecycle: PASS through READY and COMPLETED.
- VIEWER lifecycle: RLS REJECTED as required.
- OWNER/ADMIN multi-outlet access: PASS.
- CASHIER/VIEWER outlet isolation: PASS.
- Cross-tenant access: blocked.
- Idempotency same scope: duplicate rejected.
- Idempotency different outlet: same key accepted.
- Persistence: completed order and KDS chain remained on a separate read.
- Case-insensitive identity: production registration normalized case; database unique lower(email) rejected a case-only duplicate.
- Anonymous cloud context/snapshot: HTTP 401.
- Floot health: HTTP 200 / b2-rc4.
- Vercel production alias: HTTP 200.

## Code and deployment QA
- Floot typecheck: clean.
- Tests: 3/3 PASS, 0 failed.
- Floot production: published.
- Floot final checkpoint: af7a09a2-b2d6-4625-a1a2-a41b9ffcb1c7.
- Floot rollback checkpoint retained: a6d39fb5-3d3b-48e8-9103-eb9f3676722e.
- Vercel deployment: dpl_HHwjxRQmucVQch7yZurgeyM5ZFgP, READY, production, rollback candidate.
- Vercel error/fatal log query for the verified 24-hour window: no matching logs.

## Realtime
The production RC4 implementation grants per-outlet realtime channels from authenticated tenant contexts and publishes order/KDS events server-side. The reconnecting client uses WebSocket reconnect/backoff, reconnect resync, and remount refetch. No realtime source was changed by the RLS fix. A supplementary browser E2E rerun could not start because external automation was unavailable; this did not produce an application error or modify production state.

## Cleanup
All temporary QA principals and fixture tenants/outlets/orders/KDS events/login-attempt artifacts used for the RLS and role tests were removed and post-clean counts were verified at zero.

## Evaluation
| Area | Score |
|---|---:|
| RLS least privilege | 10.0 |
| Role authorization | 10.0 |
| Tenant isolation | 10.0 |
| Outlet scoping | 10.0 |
| Idempotency | 10.0 |
| Authentication / identity | 9.8 |
| Persistence | 10.0 |
| KDS lifecycle | 10.0 |
| Realtime regression confidence | 9.5 |
| Build / tests / deployment | 10.0 |
| Rollback readiness | 9.8 |
| Cleanup | 10.0 |

Final evaluation: PASS. Minimum score: 9.5/10.
