-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913160959  Name: privacy_least_privilege_phase2
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

-- Tighten browser-facing privileges without changing service-role behavior.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.runtime_asset_backups
  FROM anon, authenticated;
GRANT SELECT ON TABLE public.runtime_asset_backups TO anon, authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.site_settings_admin_runtime_v1
  FROM anon, authenticated;
GRANT SELECT ON TABLE public.site_settings_admin_runtime_v1 TO anon, authenticated;

-- Legacy direct KDS RPCs are no longer used by the canonical KDS frontend.
REVOKE EXECUTE ON FUNCTION public.kds_snapshot(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.kds_update_order(text, uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.kds_set_availability(text, text, boolean, text) FROM anon;
