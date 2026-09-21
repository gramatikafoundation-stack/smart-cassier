-- Rebased final typography + navigation hotfix.
-- Preserves latest freeze-prep changes while retaining the validated save/navigation fixes.

update private.release_component_registry
set expected_version='v77',
    expected_sha256='c17713e63372cb0ac8343d760b6f27584d5bb0537f99f7c844adf5276c203be9',
    deployment_ref='edge-version:v77',
    rollback_ref='edge-version:v71',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Rebased typography/navigation hotfix: explicit p_token for canonical publish, publishedVersionId advance verification, 5-72px round-trip, busy/error feedback, and delegated navigation. Rebased on latest freeze-prep to preserve concurrent changes.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v77',
    baseline_sha256='c17713e63372cb0ac8343d760b6f27584d5bb0537f99f7c844adf5276c203be9',
    updated_at=now()
where component='admin-renderer';
