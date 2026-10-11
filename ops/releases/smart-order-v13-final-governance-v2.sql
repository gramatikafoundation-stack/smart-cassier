-- SMART ORDER v13 final governance v2 control-plane source
-- App production SHA: e730c3e567255bc992519a05225cc41ac9681ce0
-- App migration head: 20261010210419
-- Governance v2 is control-plane-only and is captured by the release schema fingerprint.

CREATE OR REPLACE FUNCTION private.finalize_master_promotion_v2(p_candidate_key text, p_release_tag text, p_release_git_sha text, p_migration_head text, p_deployment text, p_snapshot_sha256 text, p_clone_contract text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proto private.platform_prototypes%rowtype;
  v_old private.platform_prototypes%rowtype;
  v_old_template private.platform_clone_templates%rowtype;
  v_snap private.master_template_snapshots%rowtype;
  v_ev private.master_clone_rehearsal_evidence%rowtype;
  v_preflight jsonb;
  v_security jsonb;
  v_integration jsonb;
  v_sheets jsonb;
  v_consistency jsonb;
  v_performance jsonb;
  v_ux jsonb;
  v_reliability jsonb;
  v_manifest_id uuid:=extensions.gen_random_uuid();
  v_schema text;
  v_cron text;
  v_release_manifest text;
  v_manifest jsonb;
  v_manifest_sha text;
  v_promotion_base_sha text;
  v_active_count integer;
  v_failed bigint;
  v_dead bigint;
  v_stale bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(2147483001::bigint);

  if coalesce(p_candidate_key,'')='' then raise exception 'candidate_key_required'; end if;
  if coalesce(p_release_tag,'') !~ '^smart-order-sdb-master-v[0-9]+\.[0-9]+\.[0-9]+$' then
    raise exception 'invalid_master_release_tag';
  end if;
  if coalesce(p_release_git_sha,'') !~ '^[0-9a-f]{40}$' then raise exception 'invalid_master_release_git_sha'; end if;
  if coalesce(p_snapshot_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'invalid_snapshot_sha256'; end if;
  if coalesce(p_migration_head,'') !~ '^[0-9]{14}$' then raise exception 'invalid_migration_head'; end if;
  if coalesce(p_deployment,'') !~ '^dpl_[A-Za-z0-9]+$' then raise exception 'invalid_deployment_ref'; end if;
  if coalesce(p_clone_contract,'')='' then raise exception 'clone_contract_required'; end if;

  select * into v_proto
  from private.platform_prototypes
  where prototype_key=p_candidate_key and status='draft'
  for update;

  if v_proto.id is null then raise exception 'master_candidate_not_draft'; end if;
  if coalesce((v_proto.metadata->>'immutable')::boolean,false) then raise exception 'candidate_already_immutable'; end if;
  if coalesce(v_proto.metadata->>'source_git_sha','')<>p_release_git_sha then raise exception 'candidate_git_sha_mismatch'; end if;
  if coalesce(v_proto.metadata->>'source_migration_head','')<>p_migration_head then raise exception 'candidate_migration_head_mismatch'; end if;
  if coalesce(v_proto.metadata->>'vercel_deployment','')<>p_deployment then raise exception 'candidate_deployment_mismatch'; end if;
  if coalesce(v_proto.metadata->>'scope_certification_status','') like 'failed%' then raise exception 'candidate_certification_failed'; end if;

  if (select max(version) from supabase_migrations.schema_migrations)<>p_migration_head then
    raise exception 'live_migration_head_mismatch';
  end if;

  select * into v_snap
  from private.master_template_snapshots
  where prototype_key=p_candidate_key and frozen
  limit 1;

  if v_snap.prototype_key is null then raise exception 'master_snapshot_unavailable'; end if;
  if v_snap.snapshot_sha256<>p_snapshot_sha256 then raise exception 'snapshot_sha_mismatch'; end if;
  if v_snap.source_git_sha<>p_release_git_sha then raise exception 'snapshot_git_sha_mismatch'; end if;
  if v_snap.source_migration_head<>p_migration_head then raise exception 'snapshot_migration_head_mismatch'; end if;

  v_preflight:=private.release_preflight_status_v2(p_candidate_key);
  v_security:=public.master_runtime_security_health_v1(v_proto.reference_tenant_id);
  v_integration:=private.integration_contract_status();
  v_sheets:=private.smart_order_sheet_readiness_v1(v_proto.reference_tenant_id);
  v_consistency:=private.sheet_sync_consistency_summary();
  v_performance:=private.frontend_performance_summary();
  v_ux:=private.frontend_ux_contract_status();
  v_reliability:=private.smart_order_release_reliability_readiness_v2(p_candidate_key,v_proto.reference_tenant_id);

  if not coalesce((private.release_engineering_status()->>'ok')::boolean,false) then raise exception 'release_engineering_not_ready'; end if;
  if not coalesce((v_security->>'ok')::boolean,false) then raise exception 'runtime_security_not_ready'; end if;
  if not coalesce((v_integration->>'ok')::boolean,false) then raise exception 'integration_not_ready'; end if;
  if not coalesce((v_sheets->>'ok')::boolean,false) then raise exception 'sheet_readiness_not_ready'; end if;
  if not coalesce((v_consistency->>'ok')::boolean,false) then raise exception 'sheet_consistency_not_ready'; end if;
  if not coalesce((v_performance->>'ok')::boolean,false) then raise exception 'performance_not_ready'; end if;
  if not coalesce((v_ux->>'ok')::boolean,false) then raise exception 'ux_not_ready'; end if;
  if not coalesce((v_reliability->>'ok')::boolean,false) then raise exception 'candidate_reliability_not_ready'; end if;
  if not coalesce((v_preflight->>'ok')::boolean,false) then raise exception 'release_preflight_not_ready'; end if;

  select count(*) filter(where status='failed'),
         count(*) filter(where status='dead'),
         count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes')
  into v_failed,v_dead,v_stale
  from public.sheet_sync_outbox where tenant_id=v_proto.reference_tenant_id;
  if v_failed<>0 or v_dead<>0 or v_stale<>0 then raise exception 'sheet_outbox_not_clean'; end if;

  select e.* into v_ev
  from private.master_clone_rehearsal_evidence e
  where e.prototype_id=v_proto.id
    and e.prototype_key=p_candidate_key
    and e.template_snapshot_sha256=p_snapshot_sha256
    and e.clone_contract=p_clone_contract
    and e.source_git_sha=p_release_git_sha
    and e.source_migration_head=p_migration_head
    and e.passed and e.residue_zero
    and e.evidence->>'release_tag'=p_release_tag
    and coalesce((e.evidence->>'cleanup_residue')::integer,-1)=0
    and e.checked_at>=now()-interval '30 minutes'
  order by e.checked_at desc
  limit 1;
  if v_ev.id is null then raise exception 'fresh_release_bound_clone_evidence_missing'; end if;

  if exists(
    select 1 from private.platform_tenants
    where source_prototype_key=p_candidate_key
      and (slug like 'v13-release-%' or slug like 'release-cert-%')
  ) then raise exception 'release_bound_clone_residue_present'; end if;

  select count(*) into v_active_count
  from private.platform_prototypes
  where organization_id=v_proto.organization_id and status='active';
  if v_active_count<>1 then raise exception 'unexpected_active_master_count'; end if;

  select * into v_old
  from private.platform_prototypes
  where organization_id=v_proto.organization_id and status='active'
  for update;

  if v_old.id is null then raise exception 'previous_active_master_missing'; end if;
  if v_old.prototype_key=p_candidate_key then raise exception 'candidate_already_active'; end if;

  select * into v_old_template
  from private.platform_clone_templates
  where organization_id=v_proto.organization_id and status='active'
  for update;

  v_promotion_base_sha:=coalesce(
    nullif(v_old.metadata->>'source_snapshot_git_sha',''),
    nullif(v_old.metadata->>'source_git_sha',''),
    nullif(v_old.metadata->>'release_git_sha',''),
    p_release_git_sha
  );

  update private.release_policy
  set source_control_mode='git_master_frozen',
      ci_status='exact_head_local_build_test_pass_e730c3e_no_current_github_actions_run',
      required_checks=jsonb_build_array(
        'migration_head','schema_fingerprint','cron_fingerprint','manifest_fingerprint',
        'rollback_refs','change_control','runtime_security','integration_contracts',
        'sheet_readiness','sheet_consistency','tenant_isolation','kds_idempotency',
        'printer_software','language_contract','performance','ux',
        'candidate_release_reliability','release_bound_clone_rehearsal',
        'single_active_master','immutable_master_manifest','source_release_tag',
        'deployment_binding'
      ),
      notes=coalesce(notes,'') || E'\n2026-10-11 FINAL: v13 promotion uses candidate-bound release reliability; operational rolling 24h history remains preserved.',
      updated_at=now()
  where id=1;

  v_schema:=private.release_schema_fingerprint();
  v_cron:=private.release_cron_fingerprint();
  v_release_manifest:=private.release_manifest_fingerprint();

  v_manifest:=jsonb_build_object(
    'contract','smart-order-master-freeze-v2',
    'prototype_key',p_candidate_key,
    'release_tag',p_release_tag,
    'release_git_sha',p_release_git_sha,
    'promotion_base_sha',v_promotion_base_sha,
    'migration_head',p_migration_head,
    'template_snapshot_sha256',p_snapshot_sha256,
    'clone_evidence_id',v_ev.id,
    'clone_evidence_sha256',v_ev.evidence_sha256,
    'schema_fingerprint',v_schema,
    'cron_fingerprint',v_cron,
    'release_manifest_fingerprint',v_release_manifest,
    'canonical_origin',v_proto.metadata->>'canonical_origin',
    'vercel_deployment',p_deployment,
    'supabase_project_ref',v_proto.supabase_project_ref,
    'tenancy_mode',v_proto.tenancy_mode,
    'architecture','single_domain_four_surface_v1',
    'previous_master_key',v_old.prototype_key,
    'previous_master_release_tag',v_old.release_tag,
    'previous_master_deployment',v_old.metadata->>'vercel_deployment',
    'operational_24h_slo',private.reliability_slo_summary(),
    'candidate_release_qualification',v_reliability,
    'physical_hardware_tested',false,
    'physical_hardware_acceptance','waived_no_hardware_available',
    'immutable',true
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  if v_old_template.id is not null then
    update private.platform_clone_templates
    set status='deprecated',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'superseded_by','smart-order-sdb-master-v13',
          'superseded_at',now(),
          'replacement_release_tag',p_release_tag,
          'rollback_only',true
        )
    where id=v_old_template.id;
  end if;

  update private.platform_prototypes
  set status='deprecated',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'superseded_by',p_candidate_key,
        'superseded_at',now(),
        'replacement_release_tag',p_release_tag,
        'rollback_only',true,
        'historical_master',true
      )
  where id=v_old.id;

  insert into private.platform_clone_templates(
    organization_id,template_key,name,source_tenant_id,status,
    github_repo,github_branch,supabase_isolation_mode,vercel_topology,metadata
  ) values(
    v_proto.organization_id,
    'smart-order-sdb-master-v13',
    'SMART ORDER SDB Master v13.0.0',
    v_proto.reference_tenant_id,
    'active',
    v_proto.github_repo,
    v_proto.github_branch,
    'shared_database_rls',
    'single_domain_four_surface',
    jsonb_build_object(
      'prototype_key',p_candidate_key,
      'release_tag',p_release_tag,
      'release_git_sha',p_release_git_sha,
      'migration_head',p_migration_head,
      'snapshot_sha256',p_snapshot_sha256,
      'freeze_manifest_id',v_manifest_id,
      'freeze_manifest_sha256',v_manifest_sha,
      'architecture','single_domain_four_surface_v1',
      'surface_routes',jsonb_build_object('public','/','admin','/admin','kds','/kds','database','/database'),
      'spreadsheet_provider','google_drive',
      'master_tenant_role','master_tenant',
      'immutable',true
    )
  );

  update private.platform_prototypes
  set name='SMART ORDER SDB Golden Master v13.0.0',
      status='active',
      release_tag=p_release_tag,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'freeze_state','master_frozen',
        'master_version','v13.0.0',
        'promoted_at',now(),
        'immutable',true,
        'master_tenant_role','master_tenant',
        'release_git_sha',p_release_git_sha,
        'source_release_tag',p_release_tag,
        'freeze_manifest_id',v_manifest_id,
        'freeze_manifest_sha256',v_manifest_sha,
        'clone_certification_id',v_ev.id,
        'clone_certification_sha256',v_ev.evidence_sha256,
        'release_bound_clone_contract',p_clone_contract,
        'supersedes_master_key',v_old.prototype_key,
        'previous_master_release_tag',v_old.release_tag,
        'previous_master_deployment',v_old.metadata->>'vercel_deployment',
        'scope_certification_status','golden_master_frozen',
        'remaining_freeze_blocker',null,
        'physical_hardware_tested',false,
        'physical_hardware_acceptance','waived_no_hardware_available'
      )
  where id=v_proto.id and status='draft';

  if not found then raise exception 'master_promotion_update_failed'; end if;

  insert into private.master_freeze_manifests(
    id,prototype_id,prototype_key,release_tag,release_git_sha,promotion_base_sha,
    migration_head,template_snapshot_sha256,clone_evidence_id,clone_evidence_sha256,
    schema_fingerprint,cron_fingerprint,release_manifest_fingerprint,
    canonical_origin,vercel_deployment,supabase_project_ref,tenancy_mode,
    architecture,previous_master_key,manifest,manifest_sha256,promoted_at
  ) values(
    v_manifest_id,v_proto.id,p_candidate_key,p_release_tag,p_release_git_sha,v_promotion_base_sha,
    p_migration_head,p_snapshot_sha256,v_ev.id,v_ev.evidence_sha256,
    v_schema,v_cron,v_release_manifest,
    v_proto.metadata->>'canonical_origin',p_deployment,v_proto.supabase_project_ref,v_proto.tenancy_mode,
    'single_domain_four_surface_v1',v_old.prototype_key,v_manifest,v_manifest_sha,now()
  );

  insert into private.release_baseline(
    id,release_label,migration_head,schema_fingerprint,cron_fingerprint,
    manifest_fingerprint,captured_at,notes
  ) values(
    1,p_release_tag,p_migration_head,v_schema,v_cron,v_release_manifest,now(),
    'Final immutable v13 Golden Master freeze. Application source is pinned to production Git SHA; governance v2 is captured by schema/manifest fingerprints.'
  )
  on conflict(id) do update
  set release_label=excluded.release_label,
      migration_head=excluded.migration_head,
      schema_fingerprint=excluded.schema_fingerprint,
      cron_fingerprint=excluded.cron_fingerprint,
      manifest_fingerprint=excluded.manifest_fingerprint,
      captured_at=excluded.captured_at,
      notes=excluded.notes;

  return jsonb_build_object(
    'ok',true,
    'contract','smart-order-master-freeze-v2',
    'prototype_key',p_candidate_key,
    'status','active',
    'release_tag',p_release_tag,
    'release_git_sha',p_release_git_sha,
    'migration_head',p_migration_head,
    'vercel_deployment',p_deployment,
    'freeze_manifest_id',v_manifest_id,
    'freeze_manifest_sha256',v_manifest_sha,
    'clone_evidence_id',v_ev.id,
    'clone_evidence_sha256',v_ev.evidence_sha256,
    'previous_master_key',v_old.prototype_key,
    'previous_master_status','deprecated',
    'immutable',true
  );
end
$function$
;

CREATE OR REPLACE FUNCTION private.master_freeze_status_v2(p_prototype_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  p private.platform_prototypes%rowtype;
  m private.master_freeze_manifests%rowtype;
  s private.master_template_snapshots%rowtype;
  e private.master_clone_rehearsal_evidence%rowtype;
  v_active_prototypes integer;
  v_active_templates integer;
  v_previous_ok boolean;
  v_v12_deprecated boolean;
  v_guards integer;
  v_engineering jsonb;
  v_preflight jsonb;
  v_runtime jsonb;
  v_ok boolean;
begin
  if p_prototype_key is null then
    select * into p
    from private.platform_prototypes
    where status='active'
      and metadata->>'freeze_state'='master_frozen'
      and coalesce((metadata->>'immutable')::boolean,false)
    order by updated_at desc
    limit 1;
  else
    select * into p
    from private.platform_prototypes
    where prototype_key=p_prototype_key
    limit 1;
  end if;

  if p.id is null then
    return jsonb_build_object('ok',false,'contract','smart-order-master-freeze-v2','error','active_master_not_found');
  end if;

  select * into m
  from private.master_freeze_manifests
  where prototype_id=p.id and prototype_key=p.prototype_key and release_tag=p.release_tag
  order by promoted_at desc limit 1;

  select * into s
  from private.master_template_snapshots
  where prototype_key=p.prototype_key and frozen
  limit 1;

  if m.id is not null then
    select * into e from private.master_clone_rehearsal_evidence where id=m.clone_evidence_id;
  end if;

  select count(*) into v_active_prototypes
  from private.platform_prototypes
  where organization_id=p.organization_id and status='active';

  select count(*) into v_active_templates
  from private.platform_clone_templates
  where organization_id=p.organization_id
    and status='active'
    and metadata->>'prototype_key'=p.prototype_key
    and metadata->>'release_tag'=p.release_tag;

  select exists(
    select 1 from private.platform_prototypes oldp
    where oldp.prototype_key=m.previous_master_key
      and oldp.status='deprecated'
      and coalesce((oldp.metadata->>'rollback_only')::boolean,false)
  ) into v_previous_ok;

  select exists(
    select 1 from private.platform_prototypes
    where prototype_key='smart-order-sdb-platform-v12' and status='deprecated'
  ) into v_v12_deprecated;

  select count(*) into v_guards
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname='private'
    and t.tgname in (
      'trg_master_template_snapshot_immutable_b4',
      'trg_master_clone_rehearsal_evidence_immutable_b4',
      'trg_master_freeze_manifest_immutable_b4',
      'trg_smart_order_master_prototype_immutable_b4',
      'trg_smart_order_master_clone_template_immutable_b4'
    );

  v_engineering:=private.release_engineering_status();
  v_preflight:=private.release_preflight_status_v2(p.prototype_key);
  v_runtime:=public.master_runtime_security_health_v1(p.reference_tenant_id);

  v_ok:=
    p.status='active'
    and p.release_tag is not null
    and p.metadata->>'freeze_state'='master_frozen'
    and coalesce((p.metadata->>'immutable')::boolean,false)
    and p.metadata->>'master_tenant_role'='master_tenant'
    and m.id is not null
    and m.release_git_sha=p.metadata->>'release_git_sha'
    and m.migration_head=s.source_migration_head
    and m.template_snapshot_sha256=s.snapshot_sha256
    and m.manifest_sha256=p.metadata->>'freeze_manifest_sha256'
    and s.frozen
    and e.id=m.clone_evidence_id
    and e.passed and e.residue_zero
    and e.evidence_sha256=m.clone_evidence_sha256
    and e.source_git_sha=m.release_git_sha
    and e.source_migration_head=m.migration_head
    and e.template_snapshot_sha256=m.template_snapshot_sha256
    and e.evidence->>'release_tag'=m.release_tag
    and coalesce((e.evidence->>'cleanup_residue')::integer,-1)=0
    and v_active_prototypes=1
    and v_active_templates=1
    and v_previous_ok
    and v_v12_deprecated
    and v_guards=5
    and coalesce((v_engineering->>'ok')::boolean,false)
    and coalesce((v_runtime->>'ok')::boolean,false)
    and coalesce((v_preflight->>'ok')::boolean,false);

  return jsonb_build_object(
    'ok',v_ok,
    'contract','smart-order-master-freeze-v2',
    'prototype_key',p.prototype_key,
    'status',p.status,
    'release_tag',p.release_tag,
    'release_git_sha',m.release_git_sha,
    'migration_head',m.migration_head,
    'vercel_deployment',m.vercel_deployment,
    'freeze_manifest_id',m.id,
    'freeze_manifest_sha256',m.manifest_sha256,
    'active_prototypes',v_active_prototypes,
    'active_clone_templates',v_active_templates,
    'previous_master_key',m.previous_master_key,
    'previous_master_rollback_only',v_previous_ok,
    'v12_deprecated',v_v12_deprecated,
    'snapshot_frozen',coalesce(s.frozen,false),
    'snapshot_sha256',s.snapshot_sha256,
    'clone_evidence_ok',coalesce(e.passed,false) and coalesce(e.residue_zero,false),
    'clone_evidence_id',e.id,
    'immutable_guards',v_guards,
    'release_engineering',v_engineering,
    'runtime_security',v_runtime,
    'live_preflight',v_preflight,
    'operational_24h_slo',private.reliability_slo_summary()
  );
end
$function$
;

CREATE OR REPLACE FUNCTION private.release_preflight_status_v2(p_prototype_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proto private.platform_prototypes%rowtype;
  m jsonb; i jsonb; s jsonb; c jsonb; r jsonb; ro jsonb; p jsonb; u jsonb; sec jsonb;
  v_failed bigint; v_dead bigint; v_stale bigint; v_ok boolean;
begin
  select * into v_proto
  from private.platform_prototypes
  where prototype_key=p_prototype_key and status in ('draft','active')
  limit 1;

  if v_proto.id is null then
    return jsonb_build_object('ok',false,'error','prototype_candidate_unavailable','prototype_key',p_prototype_key);
  end if;

  m:=private.release_engineering_status();
  i:=private.integration_contract_status();
  s:=private.smart_order_sheet_readiness_v1(v_proto.reference_tenant_id);
  c:=private.sheet_sync_consistency_summary();
  r:=private.smart_order_release_reliability_readiness_v2(p_prototype_key,v_proto.reference_tenant_id);
  ro:=private.reliability_status();
  p:=private.frontend_performance_summary();
  u:=private.frontend_ux_contract_status();
  sec:=public.master_runtime_security_health_v1(v_proto.reference_tenant_id);

  select count(*) filter(where status='failed'),
         count(*) filter(where status='dead'),
         count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes')
  into v_failed,v_dead,v_stale
  from public.sheet_sync_outbox
  where tenant_id=v_proto.reference_tenant_id;

  v_ok:=coalesce((m->>'ok')::boolean,false)
    and coalesce((i->>'ok')::boolean,false)
    and coalesce((s->>'ok')::boolean,false)
    and coalesce((c->>'ok')::boolean,false)
    and coalesce((r->>'ok')::boolean,false)
    and coalesce((p->>'ok')::boolean,false)
    and coalesce((u->>'ok')::boolean,false)
    and coalesce((sec->>'ok')::boolean,false)
    and v_failed=0 and v_dead=0 and v_stale=0;

  return jsonb_build_object(
    'ok',v_ok,
    'contract','smart-order-release-preflight-v2',
    'prototype_key',p_prototype_key,
    'prototype_status',v_proto.status,
    'maintainability',m,
    'runtime_security',sec,
    'integration',i,
    'sheet_readiness',s,
    'sheet_consistency',c,
    'release_reliability',r,
    'operational_reliability_24h',ro,
    'performance',p,
    'ux',u,
    'outbox',jsonb_build_object('failed',v_failed,'dead',v_dead,'stale',v_stale)
  );
end
$function$
;

CREATE OR REPLACE FUNCTION private.smart_order_release_reliability_readiness_v2(p_prototype_key text, p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proto private.platform_prototypes%rowtype;
  v_cutover timestamptz;
  v_expected integer:=5;
  v_recent integer;
  v_healthy integer;
  v_sampled integer;
  v_failures bigint;
  v_operational jsonb;
  v_services jsonb;
begin
  select * into v_proto
  from private.platform_prototypes
  where prototype_key=p_prototype_key
    and reference_tenant_id=p_tenant_id
    and status in ('draft','active')
  limit 1;

  if v_proto.id is null then
    return jsonb_build_object(
      'ok',false,'contract','smart-order-release-reliability-v2',
      'error','prototype_candidate_unavailable',
      'prototype_key',p_prototype_key,'tenant_id',p_tenant_id
    );
  end if;

  begin
    v_cutover:=nullif(v_proto.metadata->>'candidate_checked_at','')::timestamptz;
  exception when others then
    v_cutover:=null;
  end;

  if v_cutover is null then
    return jsonb_build_object(
      'ok',false,'contract','smart-order-release-reliability-v2',
      'error','certified_candidate_cutover_missing',
      'prototype_key',p_prototype_key,'tenant_id',p_tenant_id
    );
  end if;

  with expected(service_key) as (
    values ('public_web'),('admin_web'),('kds_web'),('database_web'),('order_gateway')
  ), state as (
    select e.service_key,s.last_checked_at,s.last_http_status,s.consecutive_failures,s.last_success_at
    from expected e
    left join private.tenant_reliability_probe_state s
      on s.tenant_id=p_tenant_id and s.service_key=e.service_key
  )
  select count(*) filter(where last_checked_at>=now()-interval '15 minutes'),
         count(*) filter(where last_success_at>=now()-interval '15 minutes'
                          and consecutive_failures=0
                          and last_http_status between 200 and 399)
  into v_recent,v_healthy
  from state;

  with expected(service_key) as (
    values ('public_web'),('admin_web'),('kds_web'),('database_web'),('order_gateway')
  ), counts as (
    select e.service_key,
           count(r.*) filter(where r.ok) successes,
           count(r.*) filter(where not r.ok) failures,
           min(r.checked_at) first_probe,
           max(r.checked_at) last_probe
    from expected e
    left join private.reliability_probe_events r
      on r.tenant_id=p_tenant_id
     and r.service_key=e.service_key
     and r.checked_at>=v_cutover
    group by e.service_key
  )
  select count(*) filter(where successes>=3),
         coalesce(sum(failures),0),
         jsonb_agg(
           jsonb_build_object(
             'service_key',service_key,
             'successes',successes,
             'failures',failures,
             'first_probe',first_probe,
             'last_probe',last_probe
           ) order by service_key
         )
  into v_sampled,v_failures,v_services
  from counts;

  v_operational:=private.reliability_slo_summary();

  return jsonb_build_object(
    'ok',v_recent=v_expected and v_healthy=v_expected and v_sampled=v_expected and v_failures=0,
    'contract','smart-order-release-reliability-v2',
    'prototype_key',p_prototype_key,
    'prototype_status',v_proto.status,
    'tenant_id',p_tenant_id,
    'cutover_at',v_cutover,
    'expected_services',v_expected,
    'recent_services',v_recent,
    'healthy_services',v_healthy,
    'services_with_3plus_post_cutover_successes',v_sampled,
    'post_cutover_failures',v_failures,
    'services',coalesce(v_services,'[]'::jsonb),
    'operational_24h_slo',v_operational,
    'note','Operational rolling SLO history is preserved; release qualification is candidate-bound from the certified candidate cutover.'
  );
end
$function$
;

revoke all on function private.smart_order_release_reliability_readiness_v2(text,uuid) from public,anon,authenticated;
revoke all on function private.release_preflight_status_v2(text) from public,anon,authenticated;
revoke all on function private.finalize_master_promotion_v2(text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function private.master_freeze_status_v2(text) from public,anon,authenticated;
grant execute on function private.smart_order_release_reliability_readiness_v2(text,uuid) to service_role;
grant execute on function private.release_preflight_status_v2(text) to service_role;
grant execute on function private.finalize_master_promotion_v2(text,text,text,text,text,text,text) to service_role;
grant execute on function private.master_freeze_status_v2(text) to service_role;
