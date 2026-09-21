-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912180925  Name: release_component_count_reconcile_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.release_policy
set expected_components=24,
    notes=notes || ' Active release count reconciled after Public Server Renderer became canonical and Public LKG Publisher moved from retired to compatibility lifecycle.',
    updated_at=now()
where id=1;

update private.remediation_program
set evidence = evidence || jsonb_build_object('release_manifest_reconciled',true,'canonical_components',22,'compatibility_components',2,'active_components',24),
    updated_at=now()
where stage_no in (1,2,13);
