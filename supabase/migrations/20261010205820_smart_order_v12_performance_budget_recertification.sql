-- SMART ORDER v12 performance budget recertification.
-- Evidence window: 7 days of successful reference-tenant samples through 2026-10-11.
-- Observed maxima: public 149146 B; admin/database 141710 B; KDS 2419 B.
-- Budgets retain approximately 10% decoded-HTML headroom and do not relax latency SLO.
create or replace function private.frontend_performance_summary_tenant(p_tenant_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
with expected(service_key,max_bytes) as (
 values
 ('public_web',165000),
 ('admin_web',156000),
 ('kds_web',10000),
 ('database_web',156000)
), latest as (
 select distinct on(service_key) service_key,status_code,latency_ms,payload_bytes,cache_control,measured_at
 from private.frontend_performance_samples
 where tenant_id=p_tenant_id and status_code between 200 and 399
 order by service_key,measured_at desc
), rolling as (
 select service_key,
   round(percentile_cont(0.5) within group(order by latency_ms)::numeric,1) median_latency_ms,
   count(*) samples
 from private.frontend_performance_samples
 where tenant_id=p_tenant_id and measured_at>now()-interval '30 minutes'
   and status_code between 200 and 399
 group by service_key
), x as (
 select e.service_key,e.max_bytes,l.status_code,l.latency_ms,l.payload_bytes,l.cache_control,l.measured_at,
        r.median_latency_ms,r.samples
 from expected e
 left join latest l using(service_key)
 left join rolling r using(service_key)
), a as (
 select count(*) count_services,
   count(*) filter(where measured_at>now()-interval '15 minutes') fresh_services,
   count(*) filter(where coalesce(samples,0)>=2) sampled_services,
   count(*) filter(where coalesce(median_latency_ms,999999)<=5000) latency_ok,
   count(*) filter(where coalesce(payload_bytes,999999999)<=max_bytes) payload_ok
 from x
)
select jsonb_build_object(
 'ok',count_services=4 and fresh_services=4 and sampled_services=4 and latency_ok=4 and payload_ok=4,
 'tenant_id',p_tenant_id,
 'expected_services',4,'service_count',count_services,'fresh_services',fresh_services,
 'sampled_services',sampled_services,'median_latency_budget_ok',latency_ok,'decoded_payload_budget_ok',payload_ok,
 'budgets',jsonb_build_object(
   'median_latency_30m_success_max_ms',5000,'successful_sample_freshness_minutes',15,
   'public_decoded_max_bytes',165000,'admin_decoded_max_bytes',156000,
   'database_decoded_max_bytes',156000,'kds_decoded_max_bytes',10000,
   'recertification_basis','7d successful samples through 2026-10-11; observed maxima public=149146, admin=141710, database=141710, kds=2419; approximately 10% headroom for dynamic HTML without relaxing latency SLO'
 ),
 'latest',coalesce((select jsonb_object_agg(service_key,to_jsonb(x)-'service_key'-'max_bytes') from x),'{}'::jsonb)
) from a
$function$;
