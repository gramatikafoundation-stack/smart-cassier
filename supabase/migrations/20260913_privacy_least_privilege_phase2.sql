-- Privacy / least-privilege hardening applied to production on 2026-09-13.
-- Keep browser-facing read contracts, remove unnecessary write/DDL privileges,
-- and retire legacy direct KDS RPC execution from the anon role.

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.runtime_asset_backups
  FROM anon, authenticated;
GRANT SELECT ON TABLE public.runtime_asset_backups TO anon, authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.site_settings_admin_runtime_v1
  FROM anon, authenticated;
GRANT SELECT ON TABLE public.site_settings_admin_runtime_v1 TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.kds_snapshot(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.kds_update_order(text, uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.kds_set_availability(text, text, boolean, text) FROM anon;
