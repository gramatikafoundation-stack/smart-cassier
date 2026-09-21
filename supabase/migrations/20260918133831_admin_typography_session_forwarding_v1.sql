-- Admin typography/session forwarding hotfix.
-- Scope: release metadata only. Source changes are stored in renderer/KDS source files.

update private.release_component_registry
set expected_version='v74',
    expected_sha256='02c1289085f876ad70aeef4129ed45e9d3cbd74c40493af1ea6f2dbba053b476',
    deployment_ref='edge-version:v74',
    rollback_ref='edge-version:v71',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Hotfix: secure RPC wrapper forwards the already validated session token into RPC args when p_token is omitted; Admin typography renderer now honors canonical 5-72px range.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v74',
    baseline_sha256='02c1289085f876ad70aeef4129ed45e9d3cbd74c40493af1ea6f2dbba053b476',
    updated_at=now()
where component='admin-renderer';
