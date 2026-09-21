-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912174928  Name: public_reliability_warmup_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.public_warmup_state (
  id smallint primary key default 1 check(id=1),
  enabled boolean not null default true,
  interval_minutes integer not null default 2 check(interval_minutes between 1 and 10),
  target_url text not null default 'https://rohmat-pesan-bayar-publik.vercel.app/',
  note text not null default 'Temporary keepalive until cached/static public rendering replaces request-time Lambda dependency',
  updated_at timestamptz not null default now()
);
alter table private.public_warmup_state enable row level security;
drop policy if exists public_warmup_state_deny_clients on private.public_warmup_state;
create policy public_warmup_state_deny_clients on private.public_warmup_state for all to anon,authenticated using(false) with check(false);
revoke all on private.public_warmup_state from public,anon,authenticated;
grant select on private.public_warmup_state to service_role;
insert into private.public_warmup_state(id,enabled,interval_minutes) values(1,true,2) on conflict(id) do update set enabled=true,interval_minutes=2,updated_at=now();

create or replace function private.invoke_public_warmup()
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_enabled boolean; v_url text; v_id bigint;
begin
  select enabled,target_url into v_enabled,v_url from private.public_warmup_state where id=1;
  if not coalesce(v_enabled,false) then return null; end if;
  select net.http_get(url=>v_url,headers=>jsonb_build_object('User-Agent','Rohmat-Warmup/1.0','Cache-Control','no-cache'),timeout_milliseconds=>12000) into v_id;
  return v_id;
end
$$;
revoke all on function private.invoke_public_warmup() from public,anon,authenticated;
grant execute on function private.invoke_public_warmup() to service_role;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname='rohmat_public_warmup_temp';
exception when others then null; end $$;
select cron.schedule('rohmat_public_warmup_temp','*/2 * * * *','select private.invoke_public_warmup();');
