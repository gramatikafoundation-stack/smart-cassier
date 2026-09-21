-- Canonicalize all Admin theme previews and full theme application.
-- All 17 theme cards now hydrate visual tokens from private.theme_profiles.
-- Full apply resets visual overrides while retaining content/data and verifies active theme id.

update private.release_component_registry
set expected_version='v81',
    expected_sha256='1b717df418806e8b5854a8fc15ef81731c0ad4e36fb788a8181c433130d4648a',
    deployment_ref='edge-version:v81',
    rollback_ref='edge-version:v80',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Canonical theme catalog: 17/17 Admin preview themes hydrate from private.theme_profiles; apply sends p_token, requires canonical profile, resets visual overrides while retaining content, and verifies active theme id.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v81',
    baseline_sha256='1b717df418806e8b5854a8fc15ef81731c0ad4e36fb788a8181c433130d4648a',
    updated_at=now()
where component='admin-renderer';
