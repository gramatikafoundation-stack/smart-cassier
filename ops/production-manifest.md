# Production Manifest — Unified SMART CASSIER

## Current canonical production

| Component | Authority |
| --- | --- |
| Git repository | `gramatikafoundation-stack/smart-cassier` |
| Canonical branch | `main` |
| Vercel project | `smart-cassier` — `prj_5xph62xWBNqRRR3MZ3bgA0qZU9NK` |
| Canonical origin | `https://smart-cassier.vercel.app` |
| Vercel region | `sin1` |
| Supabase | `smart-cassier-platform` — `xrepmvbccalzhlcznrff` |
| Supabase region | `ap-southeast-1` |
| Reference tenant | `warung-nasi` — `d8bb901c-7399-485b-8743-b319fde148ac` |

## Pre-Batch-5 validated baseline

- Git SHA: `fd87551ca1142c3cd07db98d52d5647f6b1b5390`
- Vercel production deployment: `dpl_zRmAC9YFQRdh4xCmq9wS1rcDJiDs`
- Deployment source ref: `batch4-kds-hardening-realtime-20260925`
- Batch 4 KDS source gate: PASS
- `main` and baseline SHA: identical
- Supabase project state: ACTIVE_HEALTHY
- KDS API: `rohmat-kds-api` v5, JWT verification enabled

Batch 5 replaces this baseline only after its exact merged `main` SHA is deployed and the canonical production freeze gates pass.

## Rollback

- Immediate predecessor source tested: `a6568a085a0cf157d37b852a763a491b28f1b5ce`.
- Predecessor Admin/KDS gates and tenant rehearsal were runnable in an isolated detached worktree.
- Previous Vercel deployments remain retained; production aliases are not changed during drills.
- Rollback must restore a known-good source/deployment and then re-run cross-surface and data-contract checks.

Historical manifests referring to split Vercel projects or Supabase `yybhpmjuywjxqurrrrxl` are archival evidence only.
