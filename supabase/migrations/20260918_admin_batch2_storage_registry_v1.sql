-- ADMIN Batch 2: align storage-retention worker after false-positive fix.
update private.release_component_registry
set expected_version='v12',
    expected_sha256='b3ed82de79a71e19f16d055c7ff0dd20d3ab88c433911045c2599a87d67da7f1',
    deployment_ref='edge-version:v12',
    rollback_ref='edge-version:v11',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 2 canonical storage retention worker; removed nonexistent static canary false-positive while preserving payment-proof retention.'
where component_key='storage_retention_worker';

update private.production_change_control
set baseline_version='v12',
    baseline_sha256='b3ed82de79a71e19f16d055c7ff0dd20d3ab88c433911045c2599a87d67da7f1',
    canonical_target='rohmat-html-test-v1',
    updated_at=now()
where component='storage-retention-worker';
