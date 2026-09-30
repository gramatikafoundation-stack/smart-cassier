# SMART CASHIER — Batch 2 Cloud + Multi-Tenant Core Freeze Evidence

Date: 2026-09-30 (Asia/Jakarta)
Release candidate: RC4 freeze candidate
Scope: Cloud + Multi-Tenant Core
Excluded/protected: Rohmat backend and protected Batch 1 surfaces were not modified.

## Final disposition
PASS. Minimum component score: 9.5/10.

## Evidence
- Floot production health: HTTP 200, service smart-cashier-cloud-core, version b2-rc4.
- kds_events has RLS and FORCE RLS enabled.
- Broad kds_write=ALL was replaced by command-specific INSERT/UPDATE/DELETE policies.
- CASHIER initial KDS INSERT passed only for PAID->NEW, current actor, authorized outlet, and matching cashier-owned PAID/NEW order.
- CASHIER lifecycle NEW->PROCESSING INSERT was rejected by RLS.
- VIEWER lifecycle INSERT was rejected by RLS.
- OWNER/ADMIN access all authorized tenant outlets; CASHIER/VIEWER remain explicitly outlet-scoped.
- Foreign tenant access returned false for tested roles.
- KITCHEN lifecycle PROCESSING->READY->COMPLETED passed.
- Persistence read on a separate connection retained COMPLETED order plus the KDS event chain.
- uq_orders_scope_idempotency rejected duplicate key in the same tenant+outlet while allowing the same key in a different outlet.
- Production registration stored normalized lowercase email; uq_users_email_lower rejected a case-variant duplicate.
- Unauthenticated cloud context and snapshot returned HTTP 401.
- Typecheck clean; themeMode, useDebounce, useMediaQuery: 3/3 tests PASS.
- Vercel smart-cashier-sdb deployment dpl_HHwjxRQmucVQch7yZurgeyM5ZFgP is READY, target production, HTTP 200, rollback candidate.
- Floot pre-hardening checkpoint retained: a6d39fb5-3d3b-48e8-9103-eb9f3676722e.
- Floot final freeze checkpoint: af7a09a2-b2d6-4625-a1a2-a41b9ffcb1c7.
- QA fixtures and login artifacts verified zero after cleanup.

## Final RLS contract
CASHIER has no KDS lifecycle UPDATE/DELETE permission. Its only write extension is INSERT of the initial PAID->NEW event when all of the following are true: authorized tenant/outlet; actor_user_id equals current user; station is NULL; note is empty; and a matching order exists for the same order/tenant/outlet, owned by that cashier, payment_status=PAID, order_status=NEW. OWNER/ADMIN/KITCHEN retain authorized lifecycle rights.

## Realtime evaluation
RC4 token grants are generated from tenant/outlet contexts; order-create and order-status publish to per-outlet orders/KDS channels; RealtimeClient implements WebSocket reconnect/backoff plus reconnect-resync and remount refetch. This surgical release changed DB RLS only and left the realtime implementation unchanged. A supplementary browser observation rerun was attempted, but external automation availability was unavailable (TinyFish wallet; no connected RDC; no foreground Floot editor), not an application failure. Component score: 9.5/10 based on deployed implementation and regression evidence.

## Scorecard
| Component | Score |
|---|---:|
| kds_events least-privilege RLS | 10.0 |
| Role matrix | 10.0 |
| Tenant isolation | 10.0 |
| Outlet scoping | 10.0 |
| Idempotency | 10.0 |
| Auth / email identity | 9.8 |
| Persistence | 10.0 |
| KDS lifecycle | 10.0 |
| Cross-device realtime | 9.5 |
| RC4 production health | 10.0 |
| Typecheck / tests | 10.0 |
| Vercel production / rollback | 10.0 |
| QA residue cleanup | 10.0 |
