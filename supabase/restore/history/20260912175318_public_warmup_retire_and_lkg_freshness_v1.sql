-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912175318  Name: public_warmup_retire_and_lkg_freshness_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

update private.public_warmup_state set enabled=false,note='Retired after acceptance: 100/100 warm-instance requests passed, but scheduled cold requests still produced HTTP 500; root cause requires renderer architecture change.',updated_at=now() where id=1;
do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname='rohmat_public_warmup_temp';
exception when others then null; end $$;

create or replace function private.capture_latest_public_lkg()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare r record; v_hash text; v_valid boolean;
begin
  select id,status_code,content,headers,created
  into r
  from net._http_response
  where status_code=200
    and created>=now()-interval '15 minutes'
    and coalesce(headers->>'x-rohmat-public','')='v21'
    and length(content)>=70000
    and position('<!doctype html>' in lower(left(content,80)))>0
    and position('rohmat-public-element-runtime-v64' in content)>0
    and position('rohmat-cart-qris-runtime-v72' in content)>0
  order by created desc,id desc limit 1;
  if r.id is null then
    return jsonb_build_object('ok',false,'error','no_fresh_valid_public_response_found');
  end if;
  v_hash:=encode(extensions.digest(convert_to(r.content,'UTF8'),'sha256'),'hex');
  v_valid:=length(r.content) between 70000 and 120000;
  insert into private.public_render_lkg(id,html,body_sha256,body_bytes,source_request_id,source_status,source_marker,captured_at,validated,validation_note)
  values(1,r.content,v_hash,length(r.content),r.id,r.status_code,r.headers->>'x-rohmat-public',r.created,v_valid,'Validated from live Public HTTP 200 response with required runtime markers')
  on conflict(id) do update set html=excluded.html,body_sha256=excluded.body_sha256,body_bytes=excluded.body_bytes,source_request_id=excluded.source_request_id,source_status=excluded.source_status,source_marker=excluded.source_marker,captured_at=excluded.captured_at,validated=excluded.validated,validation_note=excluded.validation_note
  where private.public_render_lkg.source_request_id is distinct from excluded.source_request_id;
  return jsonb_build_object('ok',v_valid,'request_id',r.id,'bytes',length(r.content),'sha256',v_hash,'marker',r.headers->>'x-rohmat-public','captured_at',r.created);
end
$$;
revoke all on function private.capture_latest_public_lkg() from public,anon,authenticated;
grant execute on function private.capture_latest_public_lkg() to service_role;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname='rohmat_public_lkg_capture';
exception when others then null; end $$;
select cron.schedule('rohmat_public_lkg_capture','*/5 * * * *','select private.capture_latest_public_lkg();');
