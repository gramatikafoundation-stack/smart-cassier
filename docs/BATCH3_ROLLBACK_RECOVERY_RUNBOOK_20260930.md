# SMART CASHIER — Batch 3 Operational Rollback / Recovery Runbook

Date: 2026-09-30
Applies to: Batch 3A b3-rc1 operational hardening.

## Recovery priority

1. Preserve business data.
2. Restore authentication/session availability.
3. Preserve tenant/outlet isolation and KDS/order invariants.
4. Roll back code before rolling back data unless a database migration itself is the confirmed cause.
5. Never touch Rohmat backend or protected Batch 1 surfaces during SMART CASHIER recovery.

## Known restore anchors

- Pre-Batch-3 code checkpoint: af7a09a2-b2d6-4625-a1a2-a41b9ffcb1c7
- Batch-3A checkpoint: 95b9e2ba-b2eb-4059-a1f4-715c68d5f874
- Vercel production rollback candidate: dpl_HHwjxRQmucVQch7yZurgeyM5ZFgP
- Previous Vercel rollback candidate: dpl_8sjt8WaSr4xPaXwCAHCNUWRCJ5Py
- Canonical Floot URL remains https://smart-cashier-pos.floot.app

## Batch 3A database delta

Added:
- public.ops_maintenance_state
- login_attempts_email_attempted_idx

No business table was dropped or renamed.
No order/payment/KDS schema contract was changed.
No RLS rule from Batch 2 was relaxed.

## Surgical database rollback SQL

Use only if the Batch 3A operational-state objects are confirmed to be the fault AND application code has first been restored to the Batch 2 checkpoint.

```sql
drop index if exists public.login_attempts_email_attempted_idx;
drop table if exists public.ops_maintenance_state;
```

Do not execute this SQL while b3-rc1 source is still active because operationalMaintenance depends on ops_maintenance_state.

## Code rollback

Preferred rollback for an application regression:
1. Restore Floot checkpoint af7a09a2-b2d6-4625-a1a2-a41b9ffcb1c7.
2. Republish the same canonical Floot subdomain.
3. Verify /_api/cloud/health returns the expected Batch 2 version.
4. Verify unauthenticated context/snapshot remain 401.
5. Verify order-create and KDS lifecycle smoke tests before reopening normal traffic.

## Frontend rollback

The Vercel frontend was not changed in Batch 3A. If a simultaneous frontend incident exists, use the last known READY rollback candidate rather than redeploying unrelated source.

## Data recovery rule

Batch 3A migrations are additive. A code rollback does not require deleting operational state. Leaving the table/index in place is the safer default because Batch 2 code ignores them.

## RPO / RTO measurement status

- Code rollback path: technically prepared and checkpointed.
- Frontend rollback path: READY candidate confirmed.
- Full physical database restore: not yet drilled in Batch 3A and must not be claimed as complete.
- Measured RPO/RTO: pending Batch 3C restore drill.

The final Batch 3 freeze gate must not score database DR >=9.5 until a real restore drill or equivalent provider-backed recovery test is evidenced.
