create or replace function public.kds_record_observability(
  p_metric text,
  p_value double precision,
  p_action text default 'unknown',
  p_http_status integer default null,
  p_rating text default 'good',
  p_release_id text default 'unknown',
  p_request_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_id bigint;
begin
  if p_metric not in ('API_MS','JSERR','NAV_TTFB','LONGTASK') then
    raise exception 'invalid_metric';
  end if;
  if p_value is null or p_value < 0 or p_value >= 1000000 then
    raise exception 'invalid_value';
  end if;
  if p_rating not in ('good','needs-improvement','poor') then
    raise exception 'invalid_rating';
  end if;
  if p_http_status is not null and (p_http_status < 100 or p_http_status > 599) then
    raise exception 'invalid_status';
  end if;
  if char_length(coalesce(p_action,'')) not between 1 and 64
     or char_length(coalesce(p_release_id,'')) not between 1 and 64
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'invalid_payload';
  end if;

  insert into private.kds_observability_samples
    (request_id,metric,value,action,http_status,rating,release_id,metadata)
  values
    (p_request_id,p_metric,p_value,left(p_action,64),p_http_status,p_rating,left(p_release_id,64),coalesce(p_metadata,'{}'::jsonb))
  returning id into v_id;

  return v_id;
end
$$;

revoke all on function public.kds_record_observability(text,double precision,text,integer,text,text,uuid,jsonb)
from public, anon, authenticated;
grant execute on function public.kds_record_observability(text,double precision,text,integer,text,text,uuid,jsonb)
to service_role;
