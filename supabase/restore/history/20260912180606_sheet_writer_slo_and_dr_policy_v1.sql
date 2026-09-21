-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912180606  Name: sheet_writer_slo_and_dr_policy_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.sheet_writer_slo_summary()
returns jsonb
language sql
stable security definer
set search_path=''
as $$
with w as (
 select
   count(*) filter(where created_at>=now()-interval '1 hour') as n1,
   count(*) filter(where created_at>=now()-interval '1 hour' and outcome='success') as s1,
   count(*) filter(where created_at>=now()-interval '24 hours') as n24,
   count(*) filter(where created_at>=now()-interval '24 hours' and outcome='success') as s24,
   count(*) filter(where created_at>=now()-interval '1 hour' and error_code='writer_ack_invalid') as ack1,
   count(*) filter(where created_at>=now()-interval '24 hours' and error_code='writer_ack_invalid') as ack24,
   max(created_at) filter(where outcome in ('failed','rejected')) as last_failure
 from private.integration_events where service_key='sheet_worker'
), x as (
 select *,case when n1>0 then round(100.0*s1/n1,3) end p1,case when n24>0 then round(100.0*s24/n24,3) end p24 from w
)
select jsonb_build_object(
 'ok_1h',n1>=12 and p1>=99 and ack1=0,
 'ok_24h',n24>=24 and p24>=99 and ack24=0,
 'state',case when n1>=12 and p1>=99 and ack1=0 and n24>=24 and p24>=99 and ack24=0 then 'healthy' when n1>=12 and p1>=99 and ack1=0 then 'recovering' else 'degraded' end,
 'samples_1h',n1,'success_1h',s1,'success_percent_1h',p1,'invalid_ack_1h',ack1,
 'samples_24h',n24,'success_24h',s24,'success_percent_24h',p24,'invalid_ack_24h',ack24,'last_failure',last_failure,
 'targets',jsonb_build_object('success_percent',99,'invalid_ack',0)
) from x;
$$;
revoke all on function private.sheet_writer_slo_summary() from public,anon,authenticated;
grant execute on function private.sheet_writer_slo_summary() to service_role;

create table if not exists private.dr_policy (
 id smallint primary key default 1 check(id=1),
 target_rpo_minutes integer not null default 1440 check(target_rpo_minutes>0),
 target_rto_minutes integer not null default 240 check(target_rto_minutes>0),
 require_offsite_database_backup boolean not null default true,
 require_storage_backup boolean not null default true,
 require_isolated_full_restore boolean not null default true,
 notes text not null,
 updated_at timestamptz not null default now()
);
alter table private.dr_policy enable row level security;
drop policy if exists dr_policy_deny_clients on private.dr_policy;
create policy dr_policy_deny_clients on private.dr_policy for all to anon,authenticated using(false) with check(false);
revoke all on private.dr_policy from public,anon,authenticated;
grant select on private.dr_policy to service_role;
insert into private.dr_policy(id,target_rpo_minutes,target_rto_minutes,notes) values(1,1440,240,'Current target: max 24h data loss and 4h service restoration after catastrophic project loss. Internal checkpoint/drill do not count as offsite backup or full restore evidence.') on conflict(id) do update set target_rpo_minutes=excluded.target_rpo_minutes,target_rto_minutes=excluded.target_rto_minutes,notes=excluded.notes,updated_at=now();

create table if not exists private.dr_restore_evidence (
 id bigint generated always as identity primary key,
 drill_type text not null check(drill_type in ('fixture','database_logical','storage','full_isolated')),
 started_at timestamptz not null,
 completed_at timestamptz,
 ok boolean not null default false,
 measured_rpo_minutes integer,
 measured_rto_minutes integer,
 manifest_hash text,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
alter table private.dr_restore_evidence enable row level security;
drop policy if exists dr_restore_evidence_deny_clients on private.dr_restore_evidence;
create policy dr_restore_evidence_deny_clients on private.dr_restore_evidence for all to anon,authenticated using(false) with check(false);
revoke all on private.dr_restore_evidence from public,anon,authenticated;
grant select,insert on private.dr_restore_evidence to service_role;

insert into private.dr_restore_evidence(drill_type,started_at,completed_at,ok,measured_rto_minutes,manifest_hash,details)
select 'fixture',checked_at,checked_at,ok,case when duration_ms is not null then greatest(1,ceil(duration_ms/60000.0)::int) end,source_hash,jsonb_build_object('method',details->>'method','fixture_residue',details->'fixture_residue')
from private.recovery_drill_state r where id=1 and not exists(select 1 from private.dr_restore_evidence e where e.drill_type='fixture' and e.started_at=r.checked_at);

create or replace function private.dr_readiness_status()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare p private.dr_policy%rowtype; v_cp timestamptz; v_fixture boolean; v_full boolean; v_db boolean; v_storage boolean;
begin
 select * into p from private.dr_policy where id=1;
 select max(created_at) into v_cp from private.recovery_checkpoints;
 select exists(select 1 from private.dr_restore_evidence where drill_type='fixture' and ok and completed_at>=now()-interval '8 days') into v_fixture;
 select exists(select 1 from private.dr_restore_evidence where drill_type='full_isolated' and ok and completed_at>=now()-interval '90 days' and coalesce(measured_rpo_minutes,2147483647)<=p.target_rpo_minutes and coalesce(measured_rto_minutes,2147483647)<=p.target_rto_minutes) into v_full;
 select exists(select 1 from private.dr_restore_evidence where drill_type='database_logical' and ok and completed_at>=now()-interval '2 days') into v_db;
 select exists(select 1 from private.dr_restore_evidence where drill_type='storage' and ok and completed_at>=now()-interval '2 days') into v_storage;
 return jsonb_build_object('operational_recovery_ok',v_cp>=now()-interval '36 hours' and v_fixture,'disaster_ready',v_full and (not p.require_offsite_database_backup or v_db) and (not p.require_storage_backup or v_storage),
 'checkpoint_fresh',v_cp>=now()-interval '36 hours','fixture_drill_fresh',v_fixture,'offsite_database_backup_verified',v_db,'storage_backup_verified',v_storage,'full_isolated_restore_verified',v_full,
 'target_rpo_minutes',p.target_rpo_minutes,'target_rto_minutes',p.target_rto_minutes,'last_checkpoint_at',v_cp);
end
$$;
revoke all on function private.dr_readiness_status() from public,anon,authenticated;
grant execute on function private.dr_readiness_status() to service_role;

update private.remediation_program set evidence=private.sheet_writer_slo_summary(),updated_at=now() where stage_no=8;
update private.remediation_program set evidence=private.dr_readiness_status(),updated_at=now() where stage_no=12;
