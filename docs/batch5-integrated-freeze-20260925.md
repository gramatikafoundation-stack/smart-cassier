# Batch 5 — Integrated QA, Stress, Security & Freeze Gate

Date: 2026-09-25
Scope: all unified SMART CASSIER surfaces and release boundaries.

## Acceptance contract

Freeze is fail-closed. A release is eligible only when all applicable gates pass with no unresolved P0/P1:

1. cross-surface Public/Admin/KDS browser E2E;
2. order data propagation contract into Admin and KDS;
3. tenant isolation positive and negative tests;
4. mobile/tablet/desktop layout, browser-error, network-error, and touch-target checks;
5. cold/warm cache semantics;
6. Supabase security advisor and effective privilege review;
7. internal link/asset scan;
8. rollback rehearsal;
9. source↔main↔deployment provenance;
10. canonical production validation after deployment.

## Defects found by Batch 5

- Public confirmation interaction performed expensive dialog construction synchronously and produced reproducible INP spikes around 680 ms. It was moved behind the existing after-paint scheduler.
- OCR prewarm began too late for the current production backend. Worker prewarm now begins non-blockingly at the transition into menu and is forced by confirmation if still needed.
- Public QA fixtures still referenced the former Supabase backend/tenant, so some historical green tests were not representative of current production. The harness now targets `xrepmvbccalzhlcznrff` and tenant `d8bb901c-7399-485b-8743-b319fde148ac`.
- Admin branding depended on stale environment/runtime identity while Public/KDS used the current tenant public projection. Admin now resolves canonical business name from `tenant_site_settings_public_v1` with safe fallback.
- Prototype/release validators described the former split deployment and backend. They now represent the unified platform while retaining support for intentionally split tenant origins.

## Measured local/production evidence before release

- Runtime memory stress: 33 navigation cycles; heap growth about 72 KB against 750 KB limit; listener/node/document/frame growth 0; browser errors 0.
- Performance after patch: desktop INP p75/max 56/56 ms; mobile at 2× CPU p75/max 88/144 ms; browser errors 0.
- OCR current tenant: prewarmed 4428 ms; warm reuse 654 ms; both verified merchant/date/time/amount; page errors 0.
- RUM v3: stage/source/viewport-aware payloads captured; PII leak false.
- 9 surface×viewport combinations: HTTP 200, no horizontal overflow, no page/subresource errors, required touch controls >=44 px.
- Cache: Public and Admin demonstrated edge MISS→HIT; KDS HTML retains client no-store; KDS v4 assets are one-year immutable.
- Link/asset scan: 15 relevant resources checked; 0 broken after connection hints were excluded from asset semantics.
- Tenant isolation: canonical origin resolves reference tenant; foreign origin and fake tenant ID fail with `tenant_not_resolved`; client RLS enforcement is enabled.
- Order propagation fixture: one isolated cash/verified/confirmed QA order triggered order-event and sheet-outbox integration and matched Admin/KDS selection contracts; fixture and all generated records were removed before sheet processing.

## Security review

Security findings are interpreted by effective exposure, not warning count alone. See `ops/batch5-security-review-20260925.md`. No warning is silently waived; intentional exceptions require explicit evidence and remain visible.

## Release automation

`.github/workflows/batch5-integrated-freeze-gate.yml` runs source and browser/stress gates on the Batch 5 branch/PR. Only an exact `main` push may deploy production, and canonical cross-surface + HTTP/cache/asset gates run after that deploy.
