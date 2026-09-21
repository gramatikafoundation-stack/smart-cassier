-- DR-only replay prerequisite.
-- Production writer endpoint is intentionally removed from sanitized restore snapshots.
-- Provide a non-routable HTTPS placeholder so migrations that require a non-null
-- integration_registry canonical_url can replay structurally without production secrets
-- or merchant-specific configuration.

update public.sheet_sync_config
set writer_url = 'https://rohmat-dr-sheet-writer.invalid'
where id = 1
  and writer_url is null;
