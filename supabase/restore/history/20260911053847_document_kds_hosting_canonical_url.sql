-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911053847  Name: document_kds_hosting_canonical_url
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

comment on column public.site_settings.kds_url is 'Canonical KDS browser URL. KDS HTML is hosted on Vercel; Supabase Edge Functions are API/redirect only.';
