-- SMART ORDER B1: final canonical deployment pin after legacy-root redirect fix
begin;

update private.production_change_control
set baseline_version='dpl_5YZjx6BkNkanxaf1djcACaXQiTm1',
    note=coalesce(note,'') || E'\nB1 final runtime pin: commit ad6822d626b9461ede9fbf571ea620650c62ddd8; immediate rollback dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ.',
    updated_at=now()
where component in ('public-site','admin-site','kds-site','database-site');

update private.release_component_registry
set expected_version='dpl_5YZjx6BkNkanxaf1djcACaXQiTm1',
    deployment_ref='dpl_5YZjx6BkNkanxaf1djcACaXQiTm1',
    rollback_ref='vercel-deployment:dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
    last_verified_at=now(),
    notes=coalesce(notes,'') || E'\nB1 final runtime pin after canonical legacy-root redirect fix.'
where component_key in ('public_site','admin_site','kds_site','database_site','kds_redirect');

update private.platform_tenant_resources
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'deployment_id','dpl_5YZjx6BkNkanxaf1djcACaXQiTm1',
      'source_commit','ad6822d626b9461ede9fbf571ea620650c62ddd8',
      'rollback_deployment_id','dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
      'verified_state','READY'
    ),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and provider='vercel' and role='unified_app';

update private.platform_prototypes
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'b1_git_sha','ad6822d626b9461ede9fbf571ea620650c62ddd8',
      'b1_deployment_id','dpl_5YZjx6BkNkanxaf1djcACaXQiTm1',
      'b1_rollback_deployment','dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
      'b1_gate','passed',
      'b1_legacy_root_redirect','verified',
      'b1_pinned_at',now()
    ),
    updated_at=now()
where organization_id='35f13d7e-8bca-4245-be49-e083555832db'
  and prototype_key='smart-order-sdb-platform-v1'
  and status='draft';

commit;
