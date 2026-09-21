-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260913063424  Name: freeze_sunday_public_runtime_v18_release_alignment
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.release_component_registry
set expected_version='v18',
    expected_sha256='e3928618de34e7afcf46e0701c5017f0292f3949413a1b4c2231f54ae65fc5e4',
    rollback_ref='edge:rohmat-public-element-runtime-v64:v17',
    notes='Freeze remediation runtime snapshot. Uses site_settings_public_v2 for design and payment configuration; no raw site_settings fetches remain in Public runtime.',
    last_verified_at=now()
where component_key='public_runtime';

update private.production_change_control
set baseline_version='v18',
    baseline_sha256='e3928618de34e7afcf46e0701c5017f0292f3949413a1b4c2231f54ae65fc5e4',
    note='Freeze remediation: Public runtime consolidated snapshot v18 with least-privilege site_settings_public_v2 contract.',
    updated_at=now()
where component='public-runtime';

update private.remediation_program
set status='in_progress',
    blocker='Public client is fully migrated to site_settings_public_v2, including main HTML, typography, design-system, and payment runtime. Full raw site_settings revoke remains blocked by legacy Admin Vercel source that still reads raw design_system/kds_url.',
    evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object(
      'public_runtime_version','v18',
      'public_runtime_sha256','e3928618de34e7afcf46e0701c5017f0292f3949413a1b4c2231f54ae65fc5e4',
      'runtime_raw_site_settings_pos',0,
      'public_contract_rest_status',200,
      'public_contract_bytes',5029,
      'excluded_fields',jsonb_build_array('admin_url','kds_url','google_sheet_url','admin_design','kds_design','updated_by'),
      'verified_at',now()
    ),
    updated_at=now()
where stage_no=7;

update private.remediation_program
set blocker='Browser-facing Vercel responses still do not forward native CSP/X-Frame-Options/Referrer-Policy/Permissions-Policy from the upstream renderer. Requires editable Vercel source/config; runtime/meta controls remain compensating controls.',
    evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object('upstream_renderer_headers',true,'browser_facing_native_headers',false,'verified_at',now()),
    updated_at=now()
where stage_no=6;

update private.remediation_program
set status='in_progress',
    blocker='HttpOnly KDS BFF v5 is implemented and hardened, but the live Vercel KDS HTML still stores the privileged session token in localStorage and directly calls RPC. Existing Supabase KDS app functions are redirects, not a same-origin secure UI. Editable KDS Vercel source/router is required for final migration.',
    evidence=coalesce(evidence,'{}'::jsonb) || jsonb_build_object('kds_bff_version','v5','http_only_cookie_backend_ready',true,'live_vercel_localstorage_token',true,'live_hardcoded_identity',true,'same_origin_proxy_available',false,'verified_at',now()),
    updated_at=now()
where stage_no=4;
