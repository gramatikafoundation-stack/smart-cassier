-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912170931  Name: release_engineering_control_plane_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.release_policy (
  id smallint primary key check (id=1),
  expected_components integer not null check (expected_components>0),
  source_control_mode text not null,
  git_repo_connected boolean not null default false,
  ci_status text not null,
  require_preflight boolean not null default true,
  require_postflight boolean not null default true,
  direct_production_changes_allowed boolean not null default false,
  required_checks jsonb not null default '[]'::jsonb,
  notes text,
  updated_at timestamptz not null default now()
);

create table if not exists private.release_component_registry (
  component_key text primary key,
  display_name text not null,
  component_type text not null check (component_type in ('vercel-production','edge-function','database','external','pipeline')),
  canonical_target text not null,
  expected_version text not null,
  expected_sha256 text,
  deployment_ref text,
  rollback_ref text not null,
  lifecycle text not null default 'canonical' check (lifecycle in ('canonical','compatibility','historical','retired')),
  critical boolean not null default true,
  change_control_component text,
  source_mode text not null,
  last_verified_at timestamptz not null default now(),
  notes text,
  constraint release_component_sha_shape check (expected_sha256 is null or expected_sha256 ~ '^[0-9a-f]{64}$')
);

create table if not exists private.release_baseline (
  id smallint primary key check (id=1),
  release_label text not null,
  migration_head text not null,
  schema_fingerprint text not null check (schema_fingerprint ~ '^[0-9a-f]{64}$'),
  cron_fingerprint text not null check (cron_fingerprint ~ '^[0-9a-f]{64}$'),
  manifest_fingerprint text not null check (manifest_fingerprint ~ '^[0-9a-f]{64}$'),
  captured_at timestamptz not null default now(),
  notes text
);

create table if not exists private.release_validation_runs (
  id bigint generated always as identity primary key,
  release_label text not null,
  phase text not null check (phase in ('preflight','postflight','manual')),
  ok boolean not null,
  checks jsonb not null,
  created_at timestamptz not null default now()
);

alter table private.release_policy enable row level security;
alter table private.release_component_registry enable row level security;
alter table private.release_baseline enable row level security;
alter table private.release_validation_runs enable row level security;

drop policy if exists release_policy_deny_client_all on private.release_policy;
create policy release_policy_deny_client_all on private.release_policy as restrictive for all to anon, authenticated using (false) with check (false);
drop policy if exists release_component_registry_deny_client_all on private.release_component_registry;
create policy release_component_registry_deny_client_all on private.release_component_registry as restrictive for all to anon, authenticated using (false) with check (false);
drop policy if exists release_baseline_deny_client_all on private.release_baseline;
create policy release_baseline_deny_client_all on private.release_baseline as restrictive for all to anon, authenticated using (false) with check (false);
drop policy if exists release_validation_runs_deny_client_all on private.release_validation_runs;
create policy release_validation_runs_deny_client_all on private.release_validation_runs as restrictive for all to anon, authenticated using (false) with check (false);

revoke all on private.release_policy, private.release_component_registry, private.release_baseline, private.release_validation_runs from public, anon, authenticated;
grant select, insert, update on private.release_policy, private.release_component_registry, private.release_baseline, private.release_validation_runs to service_role;
grant usage, select on sequence private.release_validation_runs_id_seq to service_role;

insert into private.release_policy(id,expected_components,source_control_mode,git_repo_connected,ci_status,require_preflight,require_postflight,direct_production_changes_allowed,required_checks,notes,updated_at)
values(1,22,'manifest_snapshot',false,'prepared_unconnected',true,true,false,
  '["migration_head","schema_fingerprint","cron_fingerprint","manifest_fingerprint","rollback_refs","change_control","integration_contracts","data_consistency","reliability","performance","ux","production_health"]'::jsonb,
  'Git repository is not currently accessible through the connected GitHub integration. Production releases are therefore guarded by immutable deployment references, migration history, component hashes, rollback references, and automated health contracts until Git-backed CI/CD is connected.',now())
on conflict(id) do update set expected_components=excluded.expected_components,source_control_mode=excluded.source_control_mode,git_repo_connected=excluded.git_repo_connected,ci_status=excluded.ci_status,require_preflight=excluded.require_preflight,require_postflight=excluded.require_postflight,direct_production_changes_allowed=excluded.direct_production_changes_allowed,required_checks=excluded.required_checks,notes=excluded.notes,updated_at=now();

insert into private.release_component_registry(component_key,display_name,component_type,canonical_target,expected_version,expected_sha256,deployment_ref,rollback_ref,lifecycle,critical,change_control_component,source_mode,notes)
values
('public_site','Public Ordering','vercel-production','https://rohmat-pesan-bayar-publik.vercel.app/','dpl_5Y7HfRNoWJja5cW3Nu2Tc3h6ZVb6',null,'dpl_5Y7HfRNoWJja5cW3Nu2Tc3h6ZVb6','vercel:dpl_5kesjBudPoQozTPkGXU5Hzf4iQ8S','canonical',true,'public-site','vercel-deployment','Immutable Vercel production deployment; previous production deployment recorded for rollback.'),
('admin_site','Admin Studio','vercel-production','https://studio-pengelola-rohmat.vercel.app','dpl_BLvG6kGuskbENMy3LzMFvNDvgbPN',null,'dpl_BLvG6kGuskbENMy3LzMFvNDvgbPN','vercel:dpl_82XtYjzkAEvgJKirXFSDBsdNvWo6','canonical',true,'admin-site','vercel-deployment','Immutable Vercel production deployment; previous production deployment recorded for rollback.'),
('kds_site','Kitchen Display','vercel-production','https://rohmat-kds-printer.vercel.app','dpl_5YBzH2dArd4sRy18vrEL7LX6uMe9',null,'dpl_5YBzH2dArd4sRy18vrEL7LX6uMe9','vercel:dpl_8zsAoZCSST7z4qTyfMQQWAwXiazw','canonical',true,'kds-site','vercel-deployment','Immutable Vercel production deployment; previous production deployment recorded for rollback.'),
('database_core','Supabase PostgreSQL','database','yybhpmjuywjxqurrrrxl','current-schema',null,null,'migration-history+recovery-checkpoint','canonical',true,'database-core','migration','Schema source of truth is Supabase migration history; data recovery is covered by recovery controls.'),
('order_gateway','Order Gateway','edge-function','create-order','v10','be73a450f8db17a02df1740124f9432661e13d8d953980c7438120b18fc457a5',null,'edge-version:9','canonical',true,'order-gateway','supabase-edge-version','Canonical public order gateway.'),
('order_core','Order Core','edge-function','create-order-v6','v6','71b7ed9f4be796d6c0184d9cb53585417e93d568ca22970e78d10675879a3521',null,'edge-version:5','canonical',true,'order-core','supabase-edge-version','Server-side order creation core.'),
('kds_api','KDS API','edge-function','rohmat-kds-api','v5','2df577e9e732989fcedafa737413a65064e8b215cc62ad8a4e03be90a786734a',null,'edge-version:4','canonical',true,'kds-api','supabase-edge-version','KDS API with fingerprint-bound session controls.'),
('smart_cashier','Smart Cashier','edge-function','rohmat-smart-cashier-v1','v5','0f7bedd4359371b968e67763bdde4d14dc4bcceabb9e53d9676bc66832ff8f8f',null,'edge-version:4','canonical',true,'smart-cashier','supabase-edge-version','Canonical Smart Cashier API.'),
('sheet_worker','Sheets Worker','edge-function','rohmat-sheet-sync-worker-v1','v6','9ceab1cc877820cf8e4db58b499cd3d4fea828f9abecde32de17b88e948810a6',null,'edge-version:5','canonical',true,'sheets-worker','supabase-edge-version','Retry/fallback worker with consistency validation.'),
('sheet_dispatch','Sheets Fast Dispatcher','edge-function','rohmat-sheet-sync-dispatch-v1','v2','491d4e5a037f729e624fc15101e3863bea4603e169921dbfe4302906d01ab4f7',null,'edge-version:1','canonical',true,'sheet-dispatch','supabase-edge-version','Authenticated near-real-time outbox dispatcher.'),
('secure_api','Secure Admin API','edge-function','rohmat-secure-api-v1','v7','8b0d7a9bd7bc6b5506cf089874f6e9e57d59f1d0cf42fd4013bcf02f3a287ead',null,'edge-version:6','canonical',true,'secure-api','supabase-edge-version','Privileged Admin RPC gateway.'),
('public_runtime','Public Compatibility Runtime','edge-function','rohmat-public-element-runtime-v64','v17','d301ef606dcd75fb167ebb12dcbb1fce5d64e2898959484dad0c072d7632735d',null,'runtime_backup:public:public-element-runtime-v64-v13-pre-referrer','canonical',true,'public-runtime','supabase-edge-version','Browser security, performance and UX compatibility runtime.'),
('admin_runtime','Admin Compatibility Runtime','edge-function','rohmat-admin-style-runtime-v59','v47','b706ae6af6c3184915ead242d552ca74b4dc2b52700fcbd7b25a8b230137431b',null,'runtime_backup:public:admin-style-runtime-v59-v45-pre-referrer','canonical',true,'admin-runtime','supabase-edge-version','Admin security, performance and UX compatibility runtime.'),
('admin_visual_editor','Admin Visual Editor','edge-function','rohmat-admin-visual-editor-v1','v12','a89044626150b0e822f14d778ddf8339b149541cb86e2d6d9d0493d4be4350e8',null,'runtime_backup:public:admin-visual-editor-v1-v7','canonical',true,'admin-visual-editor','supabase-edge-version','Visual editor extension.'),
('admin_cashier_loader','Admin Cashier Loader','edge-function','rohmat-admin-cashier-loader-v1','v7','ea4ad8795a581f051daa6212bb17b5f0732e6fa2bcdb34862486f6e9d6d3feab',null,'runtime_backup:public:admin-cashier-loader-v6-perf-backup','canonical',true,'admin-cashier-loader','supabase-edge-version','Versioned Admin cashier addon.'),
('admin_database_ui','Admin Database UI','edge-function','rohmat-admin-database-ui-v1','v10','62ba018f9cf0b217df2f79ea89b18acc9f6be920e24afba00046a04c97f71d96',null,'runtime_backup:public:admin-database-ui-v9-perf-backup','canonical',true,'admin-database-ui','supabase-edge-version','Versioned Admin database addon.'),
('admin_kds_ui','Admin KDS UI','edge-function','rohmat-admin-kds-ui-v1','v6','7a9c38d9e1af5819c5112d184760ee84bf65c87c5ae99dfec7f3d3b7ae7d2aed',null,'runtime_backup:public:admin-kds-ui-v5-perf-backup','canonical',true,'admin-kds-ui','supabase-edge-version','Versioned Admin KDS addon.'),
('reliability_probe','Reliability Probe','edge-function','rohmat-env-capability-check-v1','v6','f3e52275263583351817f5b60d1514a47e65551fc88b644f52d4c91543829c03',null,'edge-version:5','canonical',true,'reliability-probe','supabase-edge-version','Retired capability slot repurposed as authenticated reliability probe.'),
('kds_redirect','KDS Compatibility Redirect','edge-function','rohmat-kds-production-v2','v5','b89df8ab2a72990674e3025cc59a115383de3207abca4e8d3fa1253c7a1031de',null,'edge-version:4','compatibility',false,'kds-redirect','supabase-edge-version','Compatibility redirect only; canonical KDS is Vercel.'),
('qris_download','QRIS Download','edge-function','rohmat-qris-download','v1','a5b78fad832a5322851f28c4498cbb81214f28f05dcbd17bedc2c6e413076ed1',null,'edge-version:1','canonical',true,'qris-download','supabase-edge-version','Stable QRIS download endpoint.'),
('sheet_writer','Google Sheets Writer','external','https://script.google.com/macros/s/AKfycbwJgyD676R8PcLnETjhPKGHwm56e0k5EkqMz23OPNWhxMf-MOrUwEDR0waxKbYcjizz/exec','event-driven-v2',null,null,'writer-version:event-driven-v1','canonical',true,'google-writer','external-version','Authenticated Apps Script reporting mirror writer.'),
('sheet_pipeline','Sheets Outbox Pipeline','pipeline','sheet_sync_outbox','event-driven',null,null,'outbox+reconciliation','canonical',true,'sheet-sync','database-pipeline','Transactional outbox + fast dispatcher + worker + reconciliation.')
on conflict(component_key) do update set display_name=excluded.display_name,component_type=excluded.component_type,canonical_target=excluded.canonical_target,expected_version=excluded.expected_version,expected_sha256=excluded.expected_sha256,deployment_ref=excluded.deployment_ref,rollback_ref=excluded.rollback_ref,lifecycle=excluded.lifecycle,critical=excluded.critical,change_control_component=excluded.change_control_component,source_mode=excluded.source_mode,last_verified_at=now(),notes=excluded.notes;

insert into private.production_change_control(component,component_type,locked,baseline_version,baseline_sha256,canonical_target,allowed_change_scope,note,updated_at)
values
('public-site','vercel-production',true,'dpl_5Y7HfRNoWJja5cW3Nu2Tc3h6ZVb6',null,'https://rohmat-pesan-bayar-publik.vercel.app/','explicit-target-only','Release baseline pinned to immutable Vercel deployment.',now()),
('admin-site','vercel-production',true,'dpl_BLvG6kGuskbENMy3LzMFvNDvgbPN',null,'https://studio-pengelola-rohmat.vercel.app','explicit-target-only','Release baseline pinned to immutable Vercel deployment.',now()),
('kds-site','vercel-production',true,'dpl_5YBzH2dArd4sRy18vrEL7LX6uMe9',null,'https://rohmat-kds-printer.vercel.app','explicit-target-only','Release baseline pinned to immutable Vercel deployment.',now()),
('public-runtime','edge-function',true,'v17','d301ef606dcd75fb167ebb12dcbb1fce5d64e2898959484dad0c072d7632735d','rohmat-public-element-runtime-v64','public-target-only','Acceptance-tested Public runtime baseline.',now()),
('admin-runtime','edge-function',true,'v47','b706ae6af6c3184915ead242d552ca74b4dc2b52700fcbd7b25a8b230137431b','rohmat-admin-style-runtime-v59','admin-target-only','Acceptance-tested Admin runtime baseline.',now()),
('sheets-worker','edge-function',true,'v6','9ceab1cc877820cf8e4db58b499cd3d4fea828f9abecde32de17b88e948810a6','rohmat-sheet-sync-worker-v1','sheets-only','Consistency-aware retry worker baseline.',now()),
('smart-cashier','edge-function',true,'v5','0f7bedd4359371b968e67763bdde4d14dc4bcceabb9e53d9676bc66832ff8f8f','rohmat-smart-cashier-v1','cashier-target-only','Fingerprint-bound Smart Cashier baseline.',now()),
('order-gateway','edge-function',true,'v10','be73a450f8db17a02df1740124f9432661e13d8d953980c7438120b18fc457a5','create-order','order-ingress-only','Canonical order gateway baseline.',now()),
('order-core','edge-function',true,'v6','71b7ed9f4be796d6c0184d9cb53585417e93d568ca22970e78d10675879a3521','create-order-v6','order-core-only','Canonical order core baseline.',now()),
('kds-api','edge-function',true,'v5','2df577e9e732989fcedafa737413a65064e8b215cc62ad8a4e03be90a786734a','rohmat-kds-api','kds-api-only','Fingerprint-bound KDS API baseline.',now()),
('sheet-dispatch','edge-function',true,'v2','491d4e5a037f729e624fc15101e3863bea4603e169921dbfe4302906d01ab4f7','rohmat-sheet-sync-dispatch-v1','sheets-only','Authenticated fast dispatcher baseline.',now()),
('qris-download','edge-function',true,'v1','a5b78fad832a5322851f28c4498cbb81214f28f05dcbd17bedc2c6e413076ed1','rohmat-qris-download','payment-assets-only','Stable QRIS download endpoint.',now()),
('reliability-probe','edge-function',true,'v6','f3e52275263583351817f5b60d1514a47e65551fc88b644f52d4c91543829c03','rohmat-env-capability-check-v1','reliability-only','Authenticated synthetic reliability probe.',now()),
('admin-cashier-loader','edge-function',true,'v7','ea4ad8795a581f051daa6212bb17b5f0732e6fa2bcdb34862486f6e9d6d3feab','rohmat-admin-cashier-loader-v1','admin-cashier-only','Versioned Admin cashier addon.',now()),
('admin-database-ui','edge-function',true,'v10','62ba018f9cf0b217df2f79ea89b18acc9f6be920e24afba00046a04c97f71d96','rohmat-admin-database-ui-v1','admin-database-only','Versioned Admin database addon.',now()),
('admin-kds-ui','edge-function',true,'v6','7a9c38d9e1af5819c5112d184760ee84bf65c87c5ae99dfec7f3d3b7ae7d2aed','rohmat-admin-kds-ui-v1','admin-kds-only','Versioned Admin KDS addon.',now())
on conflict(component) do update set component_type=excluded.component_type,locked=true,baseline_version=excluded.baseline_version,baseline_sha256=excluded.baseline_sha256,canonical_target=excluded.canonical_target,allowed_change_scope=excluded.allowed_change_scope,note=excluded.note,updated_at=now();

update private.integration_registry set contract_version='sheet-worker-v6',updated_at=now() where service_key='sheet_worker';

create or replace function private.release_schema_fingerprint()
returns text
language sql
stable
security definer
set search_path=''
as $$
with parts as (
  select 'column|'||c.table_schema||'.'||c.table_name||'|'||c.ordinal_position||'|'||c.column_name||'|'||c.data_type||'|'||c.is_nullable||'|'||coalesce(c.column_default,'') as x
  from information_schema.columns c
  where c.table_schema in ('public','private','internal_rpc')
  union all
  select 'constraint|'||n.nspname||'.'||cl.relname||'|'||co.conname||'|'||pg_catalog.pg_get_constraintdef(co.oid,true)
  from pg_catalog.pg_constraint co join pg_catalog.pg_class cl on cl.oid=co.conrelid join pg_catalog.pg_namespace n on n.oid=cl.relnamespace
  where n.nspname in ('public','private','internal_rpc')
  union all
  select 'trigger|'||n.nspname||'.'||cl.relname||'|'||t.tgname||'|'||pg_catalog.pg_get_triggerdef(t.oid,true)
  from pg_catalog.pg_trigger t join pg_catalog.pg_class cl on cl.oid=t.tgrelid join pg_catalog.pg_namespace n on n.oid=cl.relnamespace
  where n.nspname in ('public','private','internal_rpc') and not t.tgisinternal
  union all
  select 'function|'||n.nspname||'.'||p.proname||'('||pg_catalog.pg_get_function_identity_arguments(p.oid)||')|'||pg_catalog.pg_get_functiondef(p.oid)
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','internal_rpc')
)
select encode(extensions.digest(coalesce(string_agg(x,E'\n' order by x),'empty'),'sha256'),'hex') from parts;
$$;

create or replace function private.release_cron_fingerprint()
returns text
language sql
stable
security definer
set search_path=''
as $$
select encode(extensions.digest(coalesce(string_agg(jobname||'|'||schedule||'|'||active::text||'|'||command,E'\n' order by jobname),'empty'),'sha256'),'hex')
from cron.job where jobname like 'rohmat_%';
$$;

create or replace function private.release_manifest_fingerprint()
returns text
language sql
stable
security definer
set search_path=''
as $$
with x as (
 select component_key||'|'||display_name||'|'||component_type||'|'||canonical_target||'|'||expected_version||'|'||coalesce(expected_sha256,'')||'|'||coalesce(deployment_ref,'')||'|'||rollback_ref||'|'||lifecycle||'|'||critical::text||'|'||coalesce(change_control_component,'')||'|'||source_mode as s
 from private.release_component_registry
 union all
 select 'policy|'||expected_components||'|'||source_control_mode||'|'||git_repo_connected::text||'|'||ci_status||'|'||require_preflight::text||'|'||require_postflight::text||'|'||direct_production_changes_allowed::text||'|'||required_checks::text from private.release_policy where id=1
)
select encode(extensions.digest(coalesce(string_agg(s,E'\n' order by s),'empty'),'sha256'),'hex') from x;
$$;

create or replace function private.release_engineering_status()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  b private.release_baseline%rowtype;
  p private.release_policy%rowtype;
  v_head text; v_schema text; v_cron text; v_manifest text;
  v_components bigint; v_critical bigint; v_missing_rollback bigint; v_missing_sha bigint; v_missing_runtime_backup bigint; v_change_drift bigint; v_duplicate_migrations bigint; v_bad_migration_versions bigint;
  v_ok boolean;
begin
  select * into p from private.release_policy where id=1;
  select * into b from private.release_baseline where id=1;
  select max(version) into v_head from supabase_migrations.schema_migrations;
  v_schema:=private.release_schema_fingerprint();
  v_cron:=private.release_cron_fingerprint();
  v_manifest:=private.release_manifest_fingerprint();
  select count(*),count(*) filter(where critical),count(*) filter(where critical and coalesce(rollback_ref,'')=''),count(*) filter(where critical and source_mode='supabase-edge-version' and (expected_sha256 is null or expected_sha256 !~ '^[0-9a-f]{64}$'))
  into v_components,v_critical,v_missing_rollback,v_missing_sha from private.release_component_registry where lifecycle in ('canonical','compatibility');
  select count(*) into v_missing_runtime_backup
  from private.release_component_registry r
  where r.rollback_ref like 'runtime_backup:%'
    and not exists(select 1 from public.runtime_asset_backups b2 where b2.name=substring(r.rollback_ref from 16));
  select count(*) into v_change_drift
  from private.release_component_registry r
  left join private.production_change_control c on c.component=r.change_control_component
  where r.change_control_component is not null and (c.component is null or c.locked is distinct from true or c.baseline_version is distinct from r.expected_version or (r.expected_sha256 is not null and c.baseline_sha256 is distinct from r.expected_sha256) or c.canonical_target is distinct from r.canonical_target);
  select count(*)-count(distinct version) into v_duplicate_migrations from supabase_migrations.schema_migrations;
  select count(*) into v_bad_migration_versions from supabase_migrations.schema_migrations where version !~ '^[0-9]{14}$';
  v_ok:=p.id=1 and b.id=1 and v_components=p.expected_components and v_missing_rollback=0 and v_missing_sha=0 and v_missing_runtime_backup=0 and v_change_drift=0 and v_duplicate_migrations=0 and v_bad_migration_versions=0 and b.migration_head=v_head and b.schema_fingerprint=v_schema and b.cron_fingerprint=v_cron and b.manifest_fingerprint=v_manifest and p.require_preflight and p.require_postflight and not p.direct_production_changes_allowed;
  return jsonb_build_object(
    'ok',v_ok,
    'release_label',b.release_label,
    'migration_head',jsonb_build_object('expected',b.migration_head,'actual',v_head,'ok',b.migration_head=v_head),
    'schema_fingerprint',jsonb_build_object('ok',b.schema_fingerprint=v_schema,'actual',v_schema),
    'cron_fingerprint',jsonb_build_object('ok',b.cron_fingerprint=v_cron,'actual',v_cron),
    'manifest_fingerprint',jsonb_build_object('ok',b.manifest_fingerprint=v_manifest,'actual',v_manifest),
    'components',jsonb_build_object('registered',v_components,'expected',p.expected_components,'critical',v_critical,'missing_rollback',v_missing_rollback,'missing_sha',v_missing_sha,'missing_runtime_backup',v_missing_runtime_backup,'change_control_drift',v_change_drift),
    'migrations',jsonb_build_object('duplicates',v_duplicate_migrations,'malformed_versions',v_bad_migration_versions),
    'source_control',jsonb_build_object('mode',p.source_control_mode,'git_repo_connected',p.git_repo_connected,'ci_status',p.ci_status,'direct_production_changes_allowed',p.direct_production_changes_allowed),
    'captured_at',b.captured_at
  );
end;
$$;

create or replace function private.release_preflight_status()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare m jsonb; i jsonb; s jsonb; r jsonb; p jsonb; u jsonb; v_failed bigint; v_dead bigint; v_stale bigint; v_ok boolean;
begin
  m:=private.release_engineering_status();
  i:=private.integration_contract_status();
  s:=private.sheet_sync_consistency_summary();
  r:=private.reliability_status();
  p:=private.frontend_performance_summary();
  u:=private.frontend_ux_contract_status();
  select count(*) filter(where status='failed'),count(*) filter(where status='dead'),count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes') into v_failed,v_dead,v_stale from public.sheet_sync_outbox;
  v_ok:=coalesce((m->>'ok')::boolean,false) and coalesce((i->>'ok')::boolean,false) and coalesce((s->>'ok')::boolean,false) and coalesce((r->>'ok')::boolean,false) and coalesce((p->>'ok')::boolean,false) and coalesce((u->>'ok')::boolean,false) and v_failed=0 and v_dead=0 and v_stale=0;
  return jsonb_build_object('ok',v_ok,'maintainability',m,'integration',i,'sheet_consistency',s,'reliability',r,'performance',p,'ux',u,'outbox',jsonb_build_object('failed',v_failed,'dead',v_dead,'stale',v_stale));
end;
$$;

create or replace function private.capture_release_baseline(p_release_label text,p_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_head text; v_schema text; v_cron text; v_manifest text;
begin
  if coalesce(trim(p_release_label),'')='' then raise exception 'release_label_required'; end if;
  select max(version) into v_head from supabase_migrations.schema_migrations;
  v_schema:=private.release_schema_fingerprint(); v_cron:=private.release_cron_fingerprint(); v_manifest:=private.release_manifest_fingerprint();
  insert into private.release_baseline(id,release_label,migration_head,schema_fingerprint,cron_fingerprint,manifest_fingerprint,captured_at,notes)
  values(1,p_release_label,v_head,v_schema,v_cron,v_manifest,now(),p_notes)
  on conflict(id) do update set release_label=excluded.release_label,migration_head=excluded.migration_head,schema_fingerprint=excluded.schema_fingerprint,cron_fingerprint=excluded.cron_fingerprint,manifest_fingerprint=excluded.manifest_fingerprint,captured_at=now(),notes=excluded.notes;
  return jsonb_build_object('ok',true,'release_label',p_release_label,'migration_head',v_head,'schema_fingerprint',v_schema,'cron_fingerprint',v_cron,'manifest_fingerprint',v_manifest);
end;
$$;

create or replace function private.capture_release_validation(p_release_label text,p_phase text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v jsonb; v_ok boolean;
begin
  if p_phase not in ('preflight','postflight','manual') then raise exception 'invalid_phase'; end if;
  v:=private.release_preflight_status(); v_ok:=coalesce((v->>'ok')::boolean,false);
  insert into private.release_validation_runs(release_label,phase,ok,checks) values(p_release_label,p_phase,v_ok,v);
  return jsonb_build_object('ok',v_ok,'release_label',p_release_label,'phase',p_phase,'checks',v);
end;
$$;

revoke all on function private.release_schema_fingerprint(), private.release_cron_fingerprint(), private.release_manifest_fingerprint(), private.release_engineering_status(), private.release_preflight_status(), private.capture_release_baseline(text,text), private.capture_release_validation(text,text) from public, anon, authenticated;
grant execute on function private.release_schema_fingerprint(), private.release_cron_fingerprint(), private.release_manifest_fingerprint(), private.release_engineering_status(), private.release_preflight_status(), private.capture_release_baseline(text,text), private.capture_release_validation(text,text) to service_role;

create or replace function private.refresh_production_health_state()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_routes boolean; v_writer boolean; v_locks boolean; v_outbox boolean; v_failed bigint; v_dead bigint; v_stale bigint; v_sensitive bigint;
  v_checks jsonb; v_healthy boolean; v_integration jsonb; v_integration_ok boolean; v_consistency jsonb; v_consistency_ok boolean;
  v_reliability jsonb; v_reliability_ok boolean; v_performance jsonb; v_performance_ok boolean; v_ux jsonb; v_ux_ok boolean; v_maint jsonb; v_maint_ok boolean;
begin
  select (public_url='https://rohmat-pesan-bayar-publik.vercel.app/' and admin_url='https://studio-pengelola-rohmat.vercel.app' and kds_url='https://rohmat-kds-printer.vercel.app') into v_routes from public.site_settings where id=1;
  select coalesce(enabled,false) and coalesce(writer_url,'') like 'https://script.google.com/macros/s/%/exec' into v_writer from public.sheet_sync_config where id=1;
  select coalesce(bool_and(locked),false) into v_locks from private.production_change_control;
  select count(*) filter(where status='failed'),count(*) filter(where status='dead'),count(*) filter(where status in ('pending','processing') and created_at<now()-interval '5 minutes') into v_failed,v_dead,v_stale from public.sheet_sync_outbox;
  v_outbox:=(v_failed=0 and v_dead=0 and v_stale=0);
  select count(*) into v_sensitive from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE');
  v_integration:=private.integration_contract_status(); v_integration_ok:=coalesce((v_integration->>'ok')::boolean,false);
  v_consistency:=private.sheet_sync_consistency_summary(); v_consistency_ok:=coalesce((v_consistency->>'ok')::boolean,false);
  v_reliability:=private.reliability_status(); v_reliability_ok:=coalesce((v_reliability->>'ok')::boolean,false);
  v_performance:=private.frontend_performance_summary(); v_performance_ok:=coalesce((v_performance->>'ok')::boolean,false);
  v_ux:=private.frontend_ux_contract_status(); v_ux_ok:=coalesce((v_ux->>'ok')::boolean,false);
  v_maint:=private.release_engineering_status(); v_maint_ok:=coalesce((v_maint->>'ok')::boolean,false);
  v_checks:=jsonb_build_object('canonical_routes',coalesce(v_routes,false),'writer_enabled',coalesce(v_writer,false),'change_control_locked',coalesce(v_locks,false),'sheet_outbox_clean',coalesce(v_outbox,false),'sheet_failed',coalesce(v_failed,0),'sheet_dead',coalesce(v_dead,0),'sheet_stale',coalesce(v_stale,0),'sheet_consistency',v_consistency,'sheet_consistency_ok',v_consistency_ok,'anon_public_security_definer',coalesce(v_sensitive,0),'integration_contracts',v_integration,'integration_contracts_ok',v_integration_ok,'reliability',v_reliability,'reliability_ok',v_reliability_ok,'frontend_performance',v_performance,'frontend_performance_ok',v_performance_ok,'frontend_ux',v_ux,'frontend_ux_ok',v_ux_ok,'maintainability',v_maint,'maintainability_ok',v_maint_ok);
  v_healthy:=coalesce(v_routes,false) and coalesce(v_writer,false) and coalesce(v_locks,false) and coalesce(v_outbox,false) and coalesce(v_sensitive,0)=0 and v_integration_ok and v_consistency_ok and v_reliability_ok and v_performance_ok and v_ux_ok and v_maint_ok;
  insert into private.production_health_state(id,healthy,checks,checked_at) values(1,v_healthy,v_checks,now()) on conflict(id) do update set healthy=excluded.healthy,checks=excluded.checks,checked_at=excluded.checked_at;
  return jsonb_build_object('healthy',v_healthy,'checks',v_checks,'checked_at',now());
end;
$$;
