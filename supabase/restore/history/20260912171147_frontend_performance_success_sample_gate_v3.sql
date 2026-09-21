-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912171147  Name: frontend_performance_success_sample_gate_v3
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.frontend_performance_summary()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with latest_any as (
 select distinct on(service_key) service_key,status_code,latency_ms,payload_bytes,cache_control,measured_at
 from private.frontend_performance_samples order by service_key,measured_at desc
), latest_success as (
 select distinct on(service_key) service_key,status_code,latency_ms,payload_bytes,cache_control,measured_at
 from private.frontend_performance_samples
 where status_code between 200 and 399
 order by service_key,measured_at desc
), rolling as (
 select service_key,
        round(percentile_cont(0.5) within group(order by latency_ms)::numeric,1) median_latency_ms,
        count(*) samples
 from private.frontend_performance_samples
 where measured_at>now()-interval '30 minutes'
   and status_code between 200 and 399
 group by service_key
), lm as (
 select s.service_key,s.status_code,s.latency_ms,s.payload_bytes,s.cache_control,s.measured_at,r.median_latency_ms,r.samples,
        a.status_code as last_observed_status,a.measured_at as last_observed_at
 from latest_success s
 left join rolling r using(service_key)
 left join latest_any a using(service_key)
), a as (
 select count(*) filter(where image_url like 'http://127.0.0.1:54321/storage/v1/object/public/rohmat-assets/menu-cache/%') direct_storage,
 count(*) filter(where image_url like '%/functions/v1/rohmat-menu-photo%') proxy_urls,
 count(*) total_images from public.menu_items where coalesce(image_url,'')<>''
), s as (
 select count(*) cached_objects,count(*) filter(where metadata->>'cacheControl' like '%31536000%') year_cache
 from storage.objects where bucket_id='rohmat-assets' and name like 'menu-cache/%'
), m as (
 select coalesce(jsonb_object_agg(service_key,jsonb_build_object(
   'status',status_code,
   'latest_success_latency_ms',latency_ms,
   'median_latency_30m_success_ms',median_latency_ms,
   'successful_samples_30m',samples,
   'payload_bytes',payload_bytes,
   'cache_control',cache_control,
   'latest_success_at',measured_at,
   'last_observed_status',last_observed_status,
   'last_observed_at',last_observed_at
 )),'{}'::jsonb) metrics,
 count(*) count_services,
 count(*) filter(where measured_at>now()-interval '15 minutes') fresh_success_services,
 count(*) filter(where coalesce(samples,0)>=2) sampled_services,
 count(*) filter(where coalesce(median_latency_ms,999999)<=5000) median_latency_budget_ok,
 count(*) filter(where (service_key='public_web' and payload_bytes<=100000) or (service_key='admin_web' and payload_bytes<=100000) or (service_key='kds_web' and payload_bytes<=10000)) payload_budget_ok
 from lm
)
select jsonb_build_object(
 'ok', a.proxy_urls=0 and a.direct_storage=a.total_images and a.total_images=36 and s.cached_objects=36 and s.year_cache=36 and m.count_services=3 and m.fresh_success_services=3 and m.sampled_services=3 and m.median_latency_budget_ok=3 and m.payload_budget_ok=3,
 'menu_images',jsonb_build_object('total',a.total_images,'direct_storage',a.direct_storage,'proxy_urls',a.proxy_urls,'cached_objects',s.cached_objects,'year_cache',s.year_cache),
 'budgets',jsonb_build_object('fresh_success_services',m.fresh_success_services,'sampled_services',m.sampled_services,'median_latency_budget_ok',m.median_latency_budget_ok,'payload_budget_ok',m.payload_budget_ok,'expected_services',3,'median_latency_30m_success_max_ms',5000,'successful_sample_freshness_minutes',15,'public_max_bytes',100000,'admin_max_bytes',100000,'kds_login_max_bytes',10000),
 'latest_success',m.metrics,
 'note','HTTP failures/timeouts remain evaluated by Reliability; Performance requires a fresh successful sample for every frontend.'
) from a,s,m;
$$;
