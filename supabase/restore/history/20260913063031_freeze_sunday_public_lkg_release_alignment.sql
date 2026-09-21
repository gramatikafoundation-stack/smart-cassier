-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913063031  Name: freeze_sunday_public_lkg_release_alignment
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.release_component_registry
set expected_version='v7',
    expected_sha256='6ebaf0a5ea5ecb552b3cfdf1357348e1d735ec96faddd0f09f3113205305874e',
    rollback_ref='edge:rohmat-public-production-v21:v6',
    notes='Freeze remediation: customer request path is LKG-primary; no request-time site_settings/snapshot REST render. 100/100 certification passed twice.',
    last_verified_at=now()
where component_key='public_renderer';

update private.release_component_registry
set display_name='Public LKG Maintainer',
    expected_version='v9',
    expected_sha256='1396bb3d1bbccf5f212225f8bc68266c847ba16ad2f2ae5eb8329ac6972ec763',
    rollback_ref='edge:rohmat-static-publisher-v1:v7',
    lifecycle='canonical',
    notes='Authenticated LKG integrity/least-privilege maintainer. Idempotently moves storefront queries to site_settings_public_v2 and validates runtime markers.',
    last_verified_at=now()
where component_key='retired_static_publisher';

update private.remediation_program
set status='in_progress',
    blocker='Point-in-time remediation is successful: LKG-primary delivery passed two independent 100/100 HTTP certifications and official probe returned HTTP 200/650ms. Stage remains open only for the clean rolling certification window.',
    evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object(
      'lkg_primary_version','v7',
      'renderer_sha256','6ebaf0a5ea5ecb552b3cfdf1357348e1d735ec96faddd0f09f3113205305874e',
      'acceptance_100_before_lp',jsonb_build_object('completed',100,'http_200',100,'http_5xx',0,'timeouts',0,'errors',0),
      'acceptance_100_after_lp',jsonb_build_object('completed',100,'http_200',100,'http_5xx',0,'timeouts',0,'errors',0),
      'official_probe',jsonb_build_object('status',200,'latency_ms',650,'consecutive_failures',0),
      'certified_at',now()
    ),
    updated_at=now()
where stage_no=1;

update private.remediation_program
set status='in_progress',
    blocker='Request-time REST rendering dependency has been removed and LKG is now the customer delivery primary. Direct Vercel static/CDN origin remains a later source-level improvement because the current Vercel wrapper still returns no-store.',
    evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object(
      'request_path','vercel_lambda -> supabase_edge_lkg -> storage_lkg',
      'request_time_site_settings_rest',false,
      'lkg_primary',true,
      'storage_lkg_validated',true,
      'certified_at',now()
    ),
    updated_at=now()
where stage_no=2;

update private.remediation_program
set status='in_progress',
    blocker='Public storefront has migrated to site_settings_public_v2. Full raw-table revocation is still blocked because the current Admin Vercel source reads raw site_settings through the publishable role.',
    evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object(
      'public_contract','site_settings_public_v2',
      'public_raw_select_star',false,
      'public_raw_typography',false,
      'public_raw_design_system',false,
      'raw_table_revoke_blocked_by','admin_live_source',
      'verified_response_id',3900,
      'verified_at',now()
    ),
    updated_at=now()
where stage_no=7;

update private.remediation_program
set blocker='Connected GitHub account still exposes zero repositories and available connector actions do not provide repository creation. A repository must be created/connected before source consolidation and CI/CD can be completed.',
    evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object('github_visible_repositories',0,'checked_at',now()),
    updated_at=now()
where stage_no=13;
