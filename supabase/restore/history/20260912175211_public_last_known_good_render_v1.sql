-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912175211  Name: public_last_known_good_render_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.public_render_lkg (
  id smallint primary key default 1 check(id=1),
  html text not null,
  body_sha256 text not null,
  body_bytes integer not null check(body_bytes>0),
  source_request_id bigint,
  source_status integer not null,
  source_marker text,
  captured_at timestamptz not null default now(),
  validated boolean not null default false,
  validation_note text
);
alter table private.public_render_lkg enable row level security;
drop policy if exists public_render_lkg_deny_clients on private.public_render_lkg;
create policy public_render_lkg_deny_clients on private.public_render_lkg for all to anon,authenticated using(false) with check(false);
revoke all on private.public_render_lkg from public,anon,authenticated;
grant select on private.public_render_lkg to service_role;

create or replace function private.capture_latest_public_lkg()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare r record; v_hash text; v_valid boolean;
begin
  select id,status_code,content,headers
  into r
  from net._http_response
  where status_code=200
    and coalesce(headers->>'x-rohmat-public','')='v21'
    and length(content)>=70000
    and position('<!doctype html>' in lower(left(content,80)))>0
    and position('rohmat-public-element-runtime-v64' in content)>0
    and position('rohmat-cart-qris-runtime-v72' in content)>0
  order by id desc limit 1;
  if r.id is null then
    return jsonb_build_object('ok',false,'error','no_valid_public_response_found');
  end if;
  v_hash:=encode(extensions.digest(convert_to(r.content,'UTF8'),'sha256'),'hex');
  v_valid:=length(r.content) between 70000 and 120000;
  insert into private.public_render_lkg(id,html,body_sha256,body_bytes,source_request_id,source_status,source_marker,captured_at,validated,validation_note)
  values(1,r.content,v_hash,length(r.content),r.id,r.status_code,r.headers->>'x-rohmat-public',now(),v_valid,'Validated from live Public HTTP 200 response with required runtime markers')
  on conflict(id) do update set html=excluded.html,body_sha256=excluded.body_sha256,body_bytes=excluded.body_bytes,source_request_id=excluded.source_request_id,source_status=excluded.source_status,source_marker=excluded.source_marker,captured_at=excluded.captured_at,validated=excluded.validated,validation_note=excluded.validation_note;
  return jsonb_build_object('ok',v_valid,'request_id',r.id,'bytes',length(r.content),'sha256',v_hash,'marker',r.headers->>'x-rohmat-public','captured_at',now());
end
$$;
revoke all on function private.capture_latest_public_lkg() from public,anon,authenticated;
grant execute on function private.capture_latest_public_lkg() to service_role;

create or replace function private.public_render_lkg_status()
returns jsonb
language sql
stable security definer
set search_path=''
as $$
select coalesce((select jsonb_build_object(
  'ok',validated and captured_at>=now()-interval '15 minutes' and body_bytes between 70000 and 120000,
  'validated',validated,'captured_at',captured_at,'body_bytes',body_bytes,'sha256',body_sha256,'source_request_id',source_request_id,'source_status',source_status,'source_marker',source_marker,
  'fresh',captured_at>=now()-interval '15 minutes'
) from private.public_render_lkg where id=1),jsonb_build_object('ok',false,'error','missing_lkg'));
$$;
revoke all on function private.public_render_lkg_status() from public,anon,authenticated;
grant execute on function private.public_render_lkg_status() to service_role;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname='rohmat_public_lkg_capture';
exception when others then null; end $$;
select cron.schedule('rohmat_public_lkg_capture','1-59/2 * * * *','select private.capture_latest_public_lkg();');

select private.capture_latest_public_lkg();
