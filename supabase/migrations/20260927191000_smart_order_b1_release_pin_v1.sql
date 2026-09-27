-- SMART ORDER B1: release pin after canonical identity deployment
begin;

update private.production_change_control
set baseline_version='dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
    note=coalesce(note,'') || E'\nB1 deployed commit 00f4a624d84c041b7d6f0990a281a7954a91b0b8; previous production dpl_7mcP2FXfvhwqS16Ld5S9Yk2FkP5Y retained for rollback.',
    updated_at=now()
where component in ('public-site','admin-site','kds-site','database-site');

update private.release_component_registry
set expected_version='dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
    deployment_ref='dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
    rollback_ref='vercel-deployment:dpl_7mcP2FXfvhwqS16Ld5S9Yk2FkP5Y',
    last_verified_at=now(),
    notes=coalesce(notes,'') || E'\nB1 release pin: commit 00f4a624d84c041b7d6f0990a281a7954a91b0b8.'
where component_key in ('public_site','admin_site','kds_site','database_site','kds_redirect');

update private.platform_tenant_resources
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'deployment_id','dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
      'source_commit','00f4a624d84c041b7d6f0990a281a7954a91b0b8',
      'verified_state','READY'
    ),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and provider='vercel' and role='unified_app';

update private.platform_prototypes
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'b1_git_sha','00f4a624d84c041b7d6f0990a281a7954a91b0b8',
      'b1_deployment_id','dpl_4aReqWZcexyCzdCcgvcik4UmrfmZ',
      'b1_rollback_deployment','dpl_7mcP2FXfvhwqS16Ld5S9Yk2FkP5Y',
      'b1_gate','passed',
      'b1_pinned_at',now()
    ),
    updated_at=now()
where organization_id='35f13d7e-8bca-4245-be49-e083555832db'
  and prototype_key='smart-order-sdb-platform-v1'
  and status='draft';

commit;
