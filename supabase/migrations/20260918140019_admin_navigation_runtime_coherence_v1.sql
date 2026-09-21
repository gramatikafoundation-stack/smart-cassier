-- Admin navigation runtime coherence release metadata.
-- Runtime logic changes are stored in the corresponding Edge Function sources.

update private.release_component_registry
set expected_version='v78',
    expected_sha256='7bae12eb053736b05f100d2c60b75f854d5b3735ce4baec4bb5ec6b2198d5f2b',
    deployment_ref='edge-version:v78',
    rollback_ref='edge-version:v77',
    last_verified_at=now(),
    notes=coalesce(notes,'')||case when coalesce(notes,'')='' then '' else ' ' end||
      'Navigation recovery: canonical renderer includes secure token forwarding, sessionStorage-only runtime, Mapping Data, Riwayat integration and Smart Cashier routing.'
where component_key='admin_renderer';

update private.release_component_registry
set expected_version='v20',
    expected_sha256='d1a62063be44fe3620f8910d852f956cc1ef1267b035fff9366aaa52b446a070',
    deployment_ref='edge-version:v20',
    rollback_ref='edge-version:v19',
    last_verified_at=now(),
    notes=coalesce(notes,'')||case when coalesce(notes,'')='' then '' else ' ' end||
      'Navigation recovery: visual editor backup normalized to sessionStorage so Public/Admin/Login editor navigation shares the canonical Admin session.'
where component_key='admin_visual_editor';

update private.release_component_registry
set expected_version='v17',
    expected_sha256='36aac4e014f2dff8039b1ab9c2fafd988895bec5e46ebebf73e35a04852bd579',
    deployment_ref='edge-version:v17',
    rollback_ref='edge-version:v16',
    last_verified_at=now(),
    notes=coalesce(notes,'')||case when coalesce(notes,'')='' then '' else ' ' end||
      'Navigation recovery: Database runtime no longer replaces canonical four-button subnavigation and activates only on Riwayat.'
where component_key='admin_database_ui';

update private.release_component_registry
set expected_version='v12',
    expected_sha256='3391ce53dd00213c373f19db15f1128b805802fa7fc5a5098850c33352aef685',
    deployment_ref='edge-version:v12',
    rollback_ref='edge-version:v11',
    last_verified_at=now(),
    notes=coalesce(notes,'')||case when coalesce(notes,'')='' then '' else ' ' end||
      'Navigation recovery: KDS monitor backup normalized to sessionStorage for coherent KDS navigation/session handling.'
where component_key='admin_kds_ui';

update private.production_change_control set baseline_version='v78',baseline_sha256='7bae12eb053736b05f100d2c60b75f854d5b3735ce4baec4bb5ec6b2198d5f2b',updated_at=now() where component='admin-renderer';
update private.production_change_control set baseline_version='v20',baseline_sha256='d1a62063be44fe3620f8910d852f956cc1ef1267b035fff9366aaa52b446a070',updated_at=now() where component='admin-visual-editor';
update private.production_change_control set baseline_version='v17',baseline_sha256='36aac4e014f2dff8039b1ab9c2fafd988895bec5e46ebebf73e35a04852bd579',updated_at=now() where component='admin-database-ui';
update private.production_change_control set baseline_version='v12',baseline_sha256='3391ce53dd00213c373f19db15f1128b805802fa7fc5a5098850c33352aef685',updated_at=now() where component='admin-kds-ui';
