-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912184014  Name: update_remediation_evidence_r6
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'latest_probe','HTTP 200 / 1814 ms',
      'availability_1h_percent',50,
      'availability_24h_percent',31.461,
      'slo_state','critical-historical-window'
    ),
    blocker='LKG fallback is working and latest Public probe is 200/1814ms. Stage remains open until rolling 1h/24h SLO targets recover naturally from historical failures.',
    updated_at=now()
where stage_no=1;

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'storage_physical_retention','VERIFIED',
      'storage_last_run','PASS due=0 deleted=0 errors=0',
      'storage_test_artifact_removed',true,
      'external_enforcement_pending',1
    ),
    blocker='Only Google Sheets PII retention remains external; Supabase Storage physical retention is now automated and verified.',
    updated_at=now()
where stage_no=11;

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'offsite_recovery_manifest','Google Drive document created',
      'offsite_recovery_manifest_id','1ism2igfjR8WgMHuxAZJsEOMNnw5Kcmq0A6yYvns2XJ0',
      'latest_checkpoint_hash','29a7b57beef4db5934d9b16cb09dc001',
      'post_maintenance_drill','PASS / 3ms / residue 0'
    ),
    blocker='Full PostgreSQL off-site dump, Storage content backup, and isolated full restore remain unverified; recovery manifest is off-site but is not a full backup.',
    updated_at=now()
where stage_no=12;

update private.remediation_program
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'rohmat_static_test_html','REMOVED',
      'static_bucket_remaining','public-lkg-v1.html only',
      'legacy_edge_functions','AUDITED; mass deletion deferred pending dependency proof',
      'unused_indexes','RETAINED pending longer observation'
    ),
    updated_at=now()
where stage_no=14;
