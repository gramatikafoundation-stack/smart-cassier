# KDS Speed + Single Login v7 — Pending Frontend Publish

Frozen source state after targeted maintenance on 2026-09-14.

Scope only:
- KDS login race fix source.
- KDS fast tab navigation helper.
- KDS versioned static asset cache policy.
- Supabase `rohmat-kds-api` v7 fast-session backend.

Production status at freeze time:
- Supabase backend v7 is ACTIVE.
- Vercel frontend v6 source is committed but not yet published because the daily Vercel deployment quota is exhausted.
- Admin, Public/OCR, stock logic, order logic, database schema, themes, and unrelated features were not changed.

Do not treat this checkpoint as fully published frontend production until canonical `rohmat-kds-printer.vercel.app` is verified with `X-Rohmat-KDS-UI: instant-nav-single-login-v6`.
