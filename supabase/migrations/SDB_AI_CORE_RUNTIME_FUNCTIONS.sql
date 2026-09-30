CREATE OR REPLACE FUNCTION public.sdb_ai_admit_request(p_request_id text, p_product_key text, p_tenant_ref text, p_user_subject_hash text, p_task_class text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'sdb_ai', 'pg_temp'
AS $function$
declare
  c sdb_ai.spend_controls%rowtype;
  v_req_1m integer;
  v_req_today integer;
  v_input_month bigint;
  v_output_month bigint;
  v_allowed boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('sdb_ai:'||p_product_key,0));

  select * into c
  from sdb_ai.spend_controls
  where product_key=p_product_key and enabled;

  if not found then
    return jsonb_build_object('allowed',false,'reason','NO_SPEND_CONTROL');
  end if;

  select
    count(*) filter (where created_at >= now()-interval '1 minute')::int,
    count(*) filter (where created_at >= date_trunc('day',now()))::int,
    coalesce(sum(input_tokens) filter (where created_at >= date_trunc('month',now())),0)::bigint,
    coalesce(sum(output_tokens) filter (where created_at >= date_trunc('month',now())),0)::bigint
  into v_req_1m,v_req_today,v_input_month,v_output_month
  from sdb_ai.usage_events
  where product_key=p_product_key;

  v_allowed :=
    v_req_1m < c.requests_per_minute
    and v_req_today < c.daily_request_limit
    and v_input_month < c.monthly_input_token_limit
    and v_output_month < c.monthly_output_token_limit;

  if v_allowed then
    insert into sdb_ai.usage_events(
      request_id,product_key,tenant_ref,user_subject_hash,task_class,status
    ) values (
      p_request_id,p_product_key,p_tenant_ref,p_user_subject_hash,p_task_class,'accepted'
    )
    on conflict(request_id) do nothing;
  end if;

  return jsonb_build_object(
    'allowed',v_allowed,
    'reason',case when v_allowed then 'OK' else 'LIMIT_REACHED' end,
    'usage',jsonb_build_object(
      'requests_last_minute',v_req_1m,
      'requests_today',v_req_today,
      'input_tokens_month',v_input_month,
      'output_tokens_month',v_output_month
    ),
    'limits',jsonb_build_object(
      'requests_per_minute',c.requests_per_minute,
      'daily_request_limit',c.daily_request_limit,
      'monthly_input_token_limit',c.monthly_input_token_limit,
      'monthly_output_token_limit',c.monthly_output_token_limit
    )
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.sdb_ai_estimate_cost(p_model text, p_input_tokens integer, p_output_tokens integer)
 RETURNS numeric
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'sdb_ai', 'pg_temp'
AS $function$
  select round(
    (coalesce(p_input_tokens,0)::numeric * input_usd_per_million
     + coalesce(p_output_tokens,0)::numeric * output_usd_per_million) / 1000000,
    6
  )
  from sdb_ai.model_rates
  where model=p_model;
$function$


CREATE OR REPLACE FUNCTION public.sdb_ai_gateway_config(p_product_key text, p_prompt_key text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'sdb_ai', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'product', to_jsonb(p) - 'created_at' - 'updated_at',
    'prompt', jsonb_build_object(
      'prompt_key', pr.prompt_key,
      'task_class', pr.task_class,
      'instructions', pr.instructions,
      'response_schema', pr.response_schema,
      'version', pr.version
    ),
    'route', jsonb_build_object(
      'primary_model', mr.primary_model,
      'fallback_model', mr.fallback_model,
      'reasoning_effort', mr.reasoning_effort,
      'max_output_tokens', mr.max_output_tokens,
      'max_input_bytes', mr.max_input_bytes
    )
  )
  from sdb_ai.products p
  join sdb_ai.prompt_registry pr
    on pr.product_key=p.product_key
   and pr.prompt_key=p_prompt_key
   and pr.active
  join sdb_ai.model_routes mr
    on mr.task_class=pr.task_class
   and mr.enabled
  where p.product_key=p_product_key
    and p.enabled
  limit 1;
$function$


CREATE OR REPLACE FUNCTION public.sdb_ai_log_usage(p_request_id text, p_product_key text, p_tenant_ref text, p_user_subject_hash text, p_task_class text, p_model text, p_status text, p_input_tokens integer, p_output_tokens integer, p_latency_ms integer, p_estimated_cost_usd numeric, p_error_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'sdb_ai', 'pg_temp'
AS $function$
begin
  insert into sdb_ai.usage_events(
    request_id,product_key,tenant_ref,user_subject_hash,task_class,model,status,
    input_tokens,output_tokens,latency_ms,estimated_cost_usd,error_code
  ) values (
    p_request_id,p_product_key,p_tenant_ref,p_user_subject_hash,p_task_class,p_model,p_status,
    p_input_tokens,p_output_tokens,p_latency_ms,p_estimated_cost_usd,p_error_code
  )
  on conflict (request_id) do update set
    model=excluded.model,
    status=excluded.status,
    input_tokens=excluded.input_tokens,
    output_tokens=excluded.output_tokens,
    latency_ms=excluded.latency_ms,
    estimated_cost_usd=excluded.estimated_cost_usd,
    error_code=excluded.error_code;
end;
$function$


CREATE OR REPLACE FUNCTION public.sdb_ai_preflight(p_product_key text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'sdb_ai', 'pg_temp'
AS $function$
with c as (
  select * from sdb_ai.spend_controls where product_key=p_product_key and enabled
),
u as (
  select
    count(*) filter (where created_at >= now()-interval '1 minute')::int as req_1m,
    count(*) filter (where created_at >= date_trunc('day',now()))::int as req_today,
    coalesce(sum(input_tokens) filter (where created_at >= date_trunc('month',now())),0)::bigint as input_month,
    coalesce(sum(output_tokens) filter (where created_at >= date_trunc('month',now())),0)::bigint as output_month
  from sdb_ai.usage_events
  where product_key=p_product_key
)
select jsonb_build_object(
  'allowed',
    (u.req_1m < c.requests_per_minute)
    and (u.req_today < c.daily_request_limit)
    and (u.input_month < c.monthly_input_token_limit)
    and (u.output_month < c.monthly_output_token_limit),
  'usage',jsonb_build_object(
    'requests_last_minute',u.req_1m,
    'requests_today',u.req_today,
    'input_tokens_month',u.input_month,
    'output_tokens_month',u.output_month
  ),
  'limits',jsonb_build_object(
    'requests_per_minute',c.requests_per_minute,
    'daily_request_limit',c.daily_request_limit,
    'monthly_input_token_limit',c.monthly_input_token_limit,
    'monthly_output_token_limit',c.monthly_output_token_limit
  )
)
from c,u;
$function$


CREATE OR REPLACE FUNCTION public.sdb_ai_usage_summary(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'sdb_ai', 'pg_temp'
AS $function$
select coalesce(jsonb_agg(row_data order by product_key),'[]'::jsonb)
from (
  select product_key,
         count(*)::int as requests,
         count(*) filter (where status='completed')::int as completed,
         count(*) filter (where status='failed')::int as failed,
         count(*) filter (where status='rejected')::int as rejected,
         coalesce(sum(input_tokens),0)::bigint as input_tokens,
         coalesce(sum(output_tokens),0)::bigint as output_tokens,
         coalesce(round(avg(latency_ms))::int,0) as avg_latency_ms
  from sdb_ai.usage_events
  where created_at >= now() - make_interval(days => greatest(1,least(coalesce(p_days,30),365)))
  group by product_key
) row_data;
$function$
