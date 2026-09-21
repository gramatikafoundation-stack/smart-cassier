create or replace view private.kds_api_slo_current_v1
with (security_invoker = true)
as
select
  operation,
  count(*)::bigint as sample_count,
  round(avg(latency_ms)::numeric,1) as avg_ms,
  percentile_cont(0.5) within group(order by latency_ms) as p50_ms,
  percentile_cont(0.95) within group(order by latency_ms) as p95_ms,
  round(100.0*count(*) filter(where outcome<>'success')/nullif(count(*),0),2) as error_rate_pct,
  case
    when operation in ('rpc:kds_update_order','rpc:kds_set_availability','cashier_create_order') then 800
    else 600
  end as target_p95_ms,
  (percentile_cont(0.95) within group(order by latency_ms) <=
    case when operation in ('rpc:kds_update_order','rpc:kds_set_availability','cashier_create_order') then 800 else 600 end
  ) as latency_slo_pass,
  (100.0*count(*) filter(where outcome<>'success')/nullif(count(*),0) <= 1.0) as error_slo_pass,
  now()-interval '2 hours' as window_start,
  now() as window_end
from private.integration_events
where service_key='kds_api'
  and created_at>=now()-interval '2 hours'
group by operation;

revoke all on private.kds_api_slo_current_v1 from public, anon, authenticated;
grant select on private.kds_api_slo_current_v1 to service_role;
