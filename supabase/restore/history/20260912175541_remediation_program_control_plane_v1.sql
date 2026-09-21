-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912175541  Name: remediation_program_control_plane_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.remediation_program (
  stage_no smallint primary key check(stage_no between 1 and 15),
  stage_key text not null unique,
  title text not null,
  priority text not null check(priority in ('P0','P1','P2','P3','GATE')),
  status text not null check(status in ('pending','in_progress','blocked','verified')),
  acceptance_criteria jsonb not null default '[]'::jsonb,
  blocker text,
  evidence jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table private.remediation_program enable row level security;
drop policy if exists remediation_program_deny_clients on private.remediation_program;
create policy remediation_program_deny_clients on private.remediation_program for all to anon,authenticated using(false) with check(false);
revoke all on private.remediation_program from public,anon,authenticated;
grant select on private.remediation_program to service_role;

insert into private.remediation_program(stage_no,stage_key,title,priority,status,acceptance_criteria,blocker,evidence) values
(1,'public_reliability','Reliability Situs Publik','P0','in_progress','["100 consecutive requests without 5xx/timeout","rolling 1h availability >= 99%","rolling 24h availability >= 99.9%"]'::jsonb,'Cold/request-time Vercel Lambda still intermittently returns HTTP 500; editable Vercel source unavailable.',jsonb_build_object('warm_acceptance','100/100 HTTP 200','rolling_1h','33.333% at last certification','rolling_24h','~27% at last certification','warmup_experiment','retired_not_effective')),
(2,'public_rendering','Arsitektur Rendering Situs Publik','P0','blocked','["last-known-good fallback available","storefront remains available during upstream failure","cache/static delivery replaces request-time dependency","zero renderer 500 in acceptance run"]'::jsonb,'Full cutover requires editable Vercel render.js/source or Git repository; neither is currently accessible.',jsonb_build_object('lkg','implemented','lkg_hash','5e0e717fa07b23ccd373a0ccd8a64e7788c682cb6c11f9a3e9895e4ac1cea9cc','cutover','pending')),
(3,'sre_observability','Monitoring, Health Check & SRE','P0','verified','["rolling per-service SLO","healthy/degraded/critical state","latest-state cannot mask historical outage","global health gated by reliability"]'::jsonb,null,jsonb_build_object('rolling_slo','active','operational_states','active','public_current_state','critical')),
(4,'kds_session','KDS Security & Session Architecture','P1','blocked','["HttpOnly Secure SameSite cookie primary","no privileged token in localStorage","no direct sensitive browser RPC","server logout invalidates session"]'::jsonb,'KDS static source cannot be safely redeployed with current source access.',jsonb_build_object('bff','rohmat-kds-api v5 exists','legacy_client','still active')),
(5,'kds_realtime','KDS Realtime & Efficiency','P1','blocked','["Realtime primary","fallback polling >=30s","order and stock changes propagate without manual refresh"]'::jsonb,'KDS static source cannot be safely redeployed with current source access.',jsonb_build_object('current_polling_seconds',2,'backend_reference_cache','active')),
(6,'frontend_headers','Browser & Frontend Response Security','P1','blocked','["response-level CSP","frame-ancestors","HSTS","nosniff","Referrer-Policy","Permissions-Policy"]'::jsonb,'Requires Vercel source/config deployment changes.',jsonb_build_object('runtime_compensating_controls','active')),
(7,'least_privilege_public_data','API/Data Exposure & Least Privilege','P1','blocked','["Public no longer uses site_settings select=*","only public-safe fields exposed","no frontend regression"]'::jsonb,'Public static client currently depends on site_settings?select=*; revoking column access now would break production.',jsonb_build_object('public_view','site_settings_public_v1 exists')),
(8,'sheet_writer_reliability','Google Sheets Writer Reliability','P1','in_progress','["dead outbox = 0","invalid ACK = 0 over certification window","writer failures <1%","retry recovery >=99%"]'::jsonb,'Apps Script writer source is external; backend retry/consistency layers are active but writer-side locking/ACK implementation needs source access.',jsonb_build_object('current_consistency','5/5','current_outbox','clean')),
(9,'public_refactor','Public Frontend Refactoring','P2','blocked','["single canonical frontend baseline","no malformed CSS","minimal MutationObservers","historical patches retired from runtime"]'::jsonb,'Requires editable frontend source/Git repository.',jsonb_build_object('current_state','patch-chain active')),
(10,'ux_e2e','UX, Accessibility & Functional QA','P2','in_progress','["keyboard navigation","mobile flow","loading/error/empty states","full order-to-KDS-to-Sheets functional path","no regression"]'::jsonb,'Full real-browser E2E/Lighthouse is unavailable in current execution environment; semantic/runtime and server invariants are already active.',jsonb_build_object('ux_contract','healthy','db_invariants','healthy')),
(11,'privacy_governance','Privacy, Retention & Data Governance','P2','pending','["PII classification","documented retention matrix","safe automatic retention rules","payment proof lifecycle","Sheets retention policy"]'::jsonb,null,'{}'::jsonb),
(12,'disaster_recovery','Backup, Disaster Recovery & Business Continuity','P2','in_progress','["offsite logical DB backup","Storage backup","checksum manifest","isolated full restore drill","measured RPO/RTO"]'::jsonb,'Current Free-plan project lacks managed downloadable backup/PITR; full external dump+storage restore path not yet available through connected tools.',jsonb_build_object('checkpoint','active','weekly_fixture_drill','active','full_offsite_restore','pending')),
(13,'git_cicd','Git & CI/CD Deployment Engineering','P2','blocked','["Git source of truth","PR checks","preview deployment","automated acceptance","controlled production promotion"]'::jsonb,'Connected GitHub account currently exposes zero repositories; Vercel projects are not Git-connected.',jsonb_build_object('git_repositories_visible',0,'release_manifest_control','active')),
(14,'housekeeping','Storage, Legacy Code & Database Housekeeping','P3','pending','["test artifacts removed after dependency check","retired endpoints catalogued/removed where safe","unused resources reviewed with evidence","no regression"]'::jsonb,null,jsonb_build_object('known_static_test','rohmat-static/test.html','unused_indexes_info',21)),
(15,'final_audit','Final End-to-End Audit','GATE','pending','["no P0/P1 unresolved","all major dimensions >=9.0","Security >=9.3","Reliability >=9.5","Data integrity >=9.5","overall >=9.3"]'::jsonb,'Runs only after stages 1-14 meet their gates.','{}'::jsonb)
on conflict(stage_no) do update set stage_key=excluded.stage_key,title=excluded.title,priority=excluded.priority,status=excluded.status,acceptance_criteria=excluded.acceptance_criteria,blocker=excluded.blocker,evidence=excluded.evidence,updated_at=now();

create or replace function private.remediation_program_status()
returns jsonb
language sql
stable security definer
set search_path=''
as $$
select jsonb_build_object(
  'verified',count(*) filter(where status='verified'),
  'in_progress',count(*) filter(where status='in_progress'),
  'blocked',count(*) filter(where status='blocked'),
  'pending',count(*) filter(where status='pending'),
  'p0_open',count(*) filter(where priority='P0' and status<>'verified'),
  'stages',jsonb_agg(jsonb_build_object('stage',stage_no,'key',stage_key,'title',title,'priority',priority,'status',status,'blocker',blocker,'evidence',evidence) order by stage_no)
) from private.remediation_program;
$$;
revoke all on function private.remediation_program_status() from public,anon,authenticated;
grant execute on function private.remediation_program_status() to service_role;
