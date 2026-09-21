-- Simplify DATABASE navigation to exactly Riwayat and Spreadsheet.
-- Backend sync/mapping logic is intentionally retained but no longer exposed as Admin pages.

update private.release_component_registry
set expected_version='v89',
    expected_sha256='2849096f0b60940e15e186739786914a52aaf0d017cbb5dd1832cfc876da1716',
    deployment_ref='edge-version:v89',
    rollback_ref='edge-version:v88',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'DATABASE navigation simplified to exactly Riwayat and Spreadsheet. Sync/mapping backend logic retained but no longer exposed as Admin pages.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v89',
    baseline_sha256='2849096f0b60940e15e186739786914a52aaf0d017cbb5dd1832cfc876da1716',
    updated_at=now()
where component='admin-renderer';
