-- Full Admin navigation/channel hardening alignment.
-- Runtime state already active in production; this migration records the verified baselines in source control.

update private.release_component_registry
set expected_version='v88',
    expected_sha256='0d3eb20e1a2966e941604ecf75fe74d5aa12793a9f606582cc654933eb67a1ae',
    deployment_ref='edge-version:v88',
    rollback_ref='edge-version:v87',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Full Admin navigation/channel audit: 23/23 subnavigation routes covered; legacy Theme Preview execution removed; gateway compatibility shim restores upstream shell; versioned Style/Visual/Cashier assets; final canonical gateway originCache=upstream.'
where component_key='admin_renderer';

update private.release_component_registry
set expected_version='v58',
    expected_sha256='2f9a6d3dfe4bed15043e9b969f88e72a0f893998c8842d9515c2d7bc86370b04',
    deployment_ref='edge-version:v58',
    rollback_ref='edge-version:v57',
    last_verified_at=now()
where component_key='admin_runtime';

update private.release_component_registry
set expected_version='v36',
    expected_sha256='9e3a6da02f9bc5febe65851d55958be4eebdd88506fe4543e83dabcac5cb6e3e',
    deployment_ref='edge-version:v36',
    rollback_ref='edge-version:v35',
    last_verified_at=now()
where component_key='admin_cashier_loader';

update private.release_component_registry
set expected_version='v19',
    expected_sha256='4713ced768b10ad51417d425bd67dc0584bbe9e5d59b5972b0145fa2160577bc',
    deployment_ref='edge-version:v19',
    rollback_ref='edge-version:v18',
    last_verified_at=now()
where component_key='admin_database_ui';

update private.production_change_control
set baseline_version='v88',
    baseline_sha256='0d3eb20e1a2966e941604ecf75fe74d5aa12793a9f606582cc654933eb67a1ae',
    updated_at=now()
where component='admin-renderer';

update private.production_change_control
set baseline_version='v58',
    baseline_sha256='2f9a6d3dfe4bed15043e9b969f88e72a0f893998c8842d9515c2d7bc86370b04',
    updated_at=now()
where component='admin-runtime';

update private.production_change_control
set baseline_version='v36',
    baseline_sha256='9e3a6da02f9bc5febe65851d55958be4eebdd88506fe4543e83dabcac5cb6e3e',
    updated_at=now()
where component='admin-cashier-loader';

update private.production_change_control
set baseline_version='v19',
    baseline_sha256='4713ced768b10ad51417d425bd67dc0584bbe9e5d59b5972b0145fa2160577bc',
    updated_at=now()
where component='admin-database-ui';
