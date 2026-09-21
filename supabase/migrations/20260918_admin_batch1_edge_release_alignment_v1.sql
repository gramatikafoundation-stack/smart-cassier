-- ADMIN Batch 1: align type-safe Edge releases after CI gate repair.
-- Runtime semantics are unchanged; previous active versions become rollback targets.

update private.release_component_registry
set expected_version='v7',
    expected_sha256='b5e3b76d7f86926b12b476be78e55b8350a1444d04dd8170f481e4f9b6716110',
    deployment_ref='edge-version:v7',
    rollback_ref='edge-version:6',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 1 type-compatibility release for Deno 2.9/TypeScript 6; no intended runtime behavior change; v6 retained as rollback.'
where component_key='order_core';

update private.production_change_control
set baseline_version='v7',
    baseline_sha256='b5e3b76d7f86926b12b476be78e55b8350a1444d04dd8170f481e4f9b6716110',
    updated_at=now()
where component='order-core';

update private.release_component_registry
set expected_version='v4',
    expected_sha256='ca52e14384baea742b8dd89ac62e61ae469c4b7b49809717b798eb86f2058d0b',
    deployment_ref='edge-version:v4',
    rollback_ref='edge-version:3',
    last_verified_at=now(),
    notes=coalesce(notes,'') || case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 1 UUID typing release for Deno 2.9/TypeScript 6; no intended dispatch behavior change; v3 retained as rollback.'
where component_key='sheet_dispatch';

update private.production_change_control
set baseline_version='v4',
    baseline_sha256='ca52e14384baea742b8dd89ac62e61ae469c4b7b49809717b798eb86f2058d0b',
    updated_at=now()
where component='sheet-dispatch';
