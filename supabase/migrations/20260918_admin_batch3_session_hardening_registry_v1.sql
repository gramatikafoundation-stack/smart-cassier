-- ADMIN Batch 3 final session hardening registry alignment.
-- Scope: release-control metadata only.

update private.release_component_registry
set expected_version='v32',
    expected_sha256='142f2f8a107bb3ac07460846718751c049fb4af03485d28aae8bb4af441b5594',
    deployment_ref='edge-version:v32',
    rollback_ref='edge-version:v31',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 3 final session hardening: persistent ADMIN token fallback removed; stale localStorage ADMIN tokens purged on cashier loader bootstrap. v31 retained as rollback.'
where component_key='admin_cashier_loader';

update private.production_change_control
set baseline_version='v32',
    baseline_sha256='142f2f8a107bb3ac07460846718751c049fb4af03485d28aae8bb4af441b5594',
    updated_at=now()
where component='admin-cashier-loader';

update private.release_component_registry
set expected_version='v16',
    expected_sha256='c59b0996b63c0979f55d9898aeea333f8c417b7f91fe6793572f853bb28c9f1b',
    deployment_ref='edge-version:v16',
    rollback_ref='edge-version:v15',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 3 final session hardening: Database UI now reads ADMIN token from sessionStorage only. v15 retained as rollback.'
where component_key='admin_database_ui';

update private.production_change_control
set baseline_version='v16',
    baseline_sha256='c59b0996b63c0979f55d9898aeea333f8c417b7f91fe6793572f853bb28c9f1b',
    updated_at=now()
where component='admin-database-ui';
