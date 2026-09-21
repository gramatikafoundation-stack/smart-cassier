-- ROHMAT MASTER PROTOTIPE v1
-- Active Google Apps Script is still Writer-v2 compatible.
-- Production Sheet worker was safely restored to compatibility source after Writer-v4 ack mismatch.
-- The tenant-aware worker remains canonical candidate source and must only be promoted after active Writer v4 is verified.

update private.release_component_registry
set expected_version='v12',
    expected_sha256='4c30fd1ffd6128f4a9ffbf85ad01037700f534120e14442638d1515a3d8d4667',
    deployment_ref='edge-version:v12',
    rollback_ref='edge-version:v11',
    last_verified_at=now(),
    notes=coalesce(notes,'')||E'\nWriter v4 activation deferred: production worker restored to compatibility-safe source after acknowledgement mismatch; candidate source retained in Git.'
where component_key='sheet_worker';

update private.production_change_control
set baseline_version='v12',
    baseline_sha256='4c30fd1ffd6128f4a9ffbf85ad01037700f534120e14442638d1515a3d8d4667',
    note='Writer-v2-compatible worker restored after genuine tenant-v4 acknowledgement mismatch. Promote candidate only after Apps Script Writer v4 is active.',
    updated_at=now()
where component='sheets-worker';

update private.release_policy
set ci_status='current_candidate_ci_pending_external_runner_and_vercel_rate_limit',
    notes=coalesce(notes,'')||E'\nWriter v4 active deployment remains an explicit freeze blocker; compatibility worker restored and production sync protected.',
    updated_at=now()
where id=1;
