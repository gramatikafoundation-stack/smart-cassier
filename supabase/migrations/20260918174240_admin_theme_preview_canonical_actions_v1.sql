-- Canonical theme action hardening.
-- Renderer v82 forces Theme Preview v10 and marks non-active themes as SIAP.
-- Theme Preview v10 remains preview-only and no longer intercepts Apply/Draft.

update private.release_component_registry
set expected_version='v82',
    expected_sha256='424b7b64927df5a382800899f29a2346b8e51f49759985adc1a88eec50d011d2',
    deployment_ref='edge-version:v82',
    rollback_ref='edge-version:v81',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Theme UI hardening: canonical 17/17 theme readiness, Theme Preview v10 cache-busted, non-active theme cards marked SIAP, legacy apply interception removed.'
where component_key='admin_renderer';

update private.release_component_registry
set expected_version='v10',
    expected_sha256='9169baf304d8ad1d18d50a060dd4bc3e6162bbfe119b612fab909961d96ac463',
    deployment_ref='edge-version:v10',
    rollback_ref='edge-version:v9',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Legacy Theme Preview no longer intercepts Apply/Draft; remains preview-only. Clarifies 14 visual categories per theme versus 17 ready themes.'
where component_key='admin_theme_preview';

update private.production_change_control
set baseline_version='v82',
    baseline_sha256='424b7b64927df5a382800899f29a2346b8e51f49759985adc1a88eec50d011d2',
    updated_at=now()
where component='admin-renderer';

update private.production_change_control
set baseline_version='v10',
    baseline_sha256='9169baf304d8ad1d18d50a060dd4bc3e6162bbfe119b612fab909961d96ac463',
    updated_at=now()
where component='admin-theme-preview';
