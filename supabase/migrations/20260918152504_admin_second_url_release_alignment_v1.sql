-- Align release metadata after switching the active Admin recovery URL.
update private.release_component_registry
set expected_version='v79',
    expected_sha256='8c96cf07976b5f213fdd0ccb202bc0016db42dd6f4a1fe85c5e75f22edac06ca',
    deployment_ref='edge-version:v79',
    rollback_ref='edge-version:v78',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Recovery URL selected: second Vercel deployment origin. Renderer restored from canonical freeze-prep with typography/navigation fixes intact.'
where component_key='admin_renderer';

update private.release_component_registry
set expected_version='v12',
    expected_sha256='1a3d3f0e71bb20e515262e3611609e42bd074aa27635fed5537fe8d79e61bbd7',
    deployment_ref='edge-version:v12',
    rollback_ref='edge-version:v11',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Second Admin deployment origin explicitly allowlisted; no wildcard origins.'
where component_key='secure_api';

update private.release_component_registry
set expected_version='v6',
    expected_sha256='6c5e12b65c9a8b7f3c71161584ea9bf69efe9d171560481aa7a09c966f5d6f85',
    deployment_ref='edge-version:v6',
    rollback_ref='edge-version:v5',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Second Admin deployment origin explicitly allowlisted for Smart Cashier snapshot/create flow.'
where component_key='smart_cashier';

update private.production_change_control
set baseline_version='v79',
    baseline_sha256='8c96cf07976b5f213fdd0ccb202bc0016db42dd6f4a1fe85c5e75f22edac06ca',
    updated_at=now()
where component='admin-renderer';

update private.production_change_control
set baseline_version='v12',
    baseline_sha256='1a3d3f0e71bb20e515262e3611609e42bd074aa27635fed5537fe8d79e61bbd7',
    updated_at=now()
where component='secure-api';

update private.production_change_control
set baseline_version='v6',
    baseline_sha256='6c5e12b65c9a8b7f3c71161584ea9bf69efe9d171560481aa7a09c966f5d6f85',
    updated_at=now()
where component='smart-cashier';
