# Production Manifest

## Canonical production projects

| Component | Project / Ref | Production URL / Contract |
|---|---|---|
| Public | Vercel `prj_3JC9wVT3viMvinKvdG6hBucDhEGY` | `https://rohmat-pesan-bayar-publik.vercel.app` |
| Admin | Vercel `prj_CIEgIyyKRSrYahxDLkiK6m78wZ9Y` | `https://studio-pengelola-rohmat.vercel.app` |
| KDS | Vercel `prj_vv1eioBBQdyto7a0QdRz3v2F3oFW` | `https://rohmat-kds-printer.vercel.app` |
| Supabase | `yybhpmjuywjxqurrrrxl` | region `ap-southeast-1` |

## Current freeze-preparation baseline

- Git repository: `gramatikafoundation-stack/Rohmat-Master` (Private)
- Working integration branch: `freeze-prep`
- Public canonical deployment source: `apps/public/api/render.js` + `apps/public/vercel.json`
- Admin canonical deployment source: `apps/admin/api/render.js` + `apps/admin/vercel.json`
- KDS canonical production source: `apps/kds/*` on `freeze-prep`
- Public renderer production: `rohmat-public-production-v21` v7 (LKG-primary)
- Public runtime production: `rohmat-public-element-runtime-v64` v18 + Smart OCR v6 in LKG
- KDS BFF backend production: `rohmat-kds-api` v6, contract `kds-api-v6`, device-bound HttpOnly session design
- KDS BFF bound-login migration tracked at `supabase/migrations/20260913_kds_bff_bound_login_v1.sql`
- KDS BFF source tracked at `supabase/functions/rohmat-kds-api/index.ts`
- Public settings contract: `site_settings_public_v2` cache table with RLS
- Public point-in-time acceptance: two independent 100-request batches, 200/200 HTTP 200 total, 0 timeout, 0 HTTP 5xx
- KDS candidate GitHub Actions source/security gate: PASS
- KDS production security verification refreshed on 2026-09-13 after Git/Vercel cutover.

## Original four freeze blockers — current status

1. **Source/Git consolidation** — KDS CUTOVER PASS; broader Public/Admin reproducibility work remains part of the final freeze program.
2. **KDS HttpOnly BFF frontend** — **PRODUCTION PASS.** Canonical KDS uses same-origin `/api/kds`; privileged KDS tokens are not stored in browser storage. The backend `rohmat-kds-api` issues device-bound `__Host-rohmat_kds` cookies with `HttpOnly; Secure; SameSite=Strict; Path=/`.
3. **KDS hardcoded identity** — **PRODUCTION PASS.** Canonical production `/login` has an empty email field and no prefilled operator identity.
4. **Native Vercel security headers** — **KDS PRODUCTION PASS.** Canonical KDS responses were verified to include CSP with `frame-ancestors 'none'`, HSTS, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, and `Permissions-Policy`. Public/Admin source configuration exists; their broader production native-header cutover remains a separate final-freeze gate.

## KDS production evidence

- Production branch: `freeze-prep`
- Production project: `prj_vv1eioBBQdyto7a0QdRz3v2F3oFW`
- Canonical URL: `https://rohmat-kds-printer.vercel.app`
- Production `/login`: HTTP 200; identity field not prefilled.
- Production `/api/kds`: same-origin server route present; non-POST request returns HTTP 405 with `Allow: POST`.
- Browser runtime: `login.js` and `app.js` use `/api/kds` with same-origin credentials and do not expose a privileged KDS session token to JavaScript storage.
- Native security headers verified on canonical KDS response after production cutover.

## Remaining freeze gates

1. Public/Admin Git-preview and reproducible production-source linkage.
2. Public/Admin native Vercel security-header cutover and response verification.
3. Complete Git/CI coverage and canonical source inventory for remaining critical runtime assets.
4. Public clean certification window, clone rehearsals, DR gate, and final Stage 15 audit must pass before `rohmat-master-clone-v1.0` is tagged.
