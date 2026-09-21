# KDS Speed + Single Login — Production v6

Verified canonical production state on 2026-09-14.

Targeted scope only:
- Faster KDS tab switching via pointerdown activation.
- Smart Cashier warm preload after app becomes visible and on hover.
- Single-login flow confirms the session cookie before redirecting into KDS.
- Supabase `rohmat-kds-api` v7 fast-session backend remains active.

Verified canonical production indicators:
- `X-Rohmat-KDS-UI: instant-nav-single-login-v6`
- `/fast-nav.js?v=1` is served on canonical KDS.
- `/login.js?v=2` contains `confirmSession()` with bounded retry before redirect.
- No KDS runtime errors were reported in the verification window.

No changes were made to Admin, Public/OCR, business database schema, stock behavior, order workflow, themes, or unrelated features.
