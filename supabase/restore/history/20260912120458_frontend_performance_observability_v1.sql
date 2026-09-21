-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912120458  Name: frontend_performance_observability_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.frontend_performance_samples(
 id bigint generated always as identity primary key,
 service_key text not null check(service_key in ('public_web','admin_web','kds_web')),
 status_code integer,
 latency_ms integer not null check(latency_ms>=0),
 payload_bytes integer not null check(payload_bytes>=0),
 cache_control text,
 measured_at timestamptz not null default now()
);
create index if not exists frontend_performance_samples_service_time_idx on private.frontend_performance_samples(service_key,measured_at desc);
alter table private.frontend_performance_samples enable row level security;
revoke all on private.frontend_performance_samples from public, anon, authenticated;

create or replace function public.frontend_performance_record(p_service_key text,p_status_code integer,p_latency_ms integer,p_payload_bytes integer,p_cache_control text default null)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if current_user not in ('service_role','postgres') then raise exception 'forbidden'; end if;
 insert into private.frontend_performance_samples(service_key,status_code,latency_ms,payload_bytes,cache_control)
 values(p_service_key,p_status_code,greatest(0,p_latency_ms),greatest(0,p_payload_bytes),left(p_cache_control,300));
 delete from private.frontend_performance_samples where measured_at < now()-interval '30 days';
 return true;
end$$;
revoke all on function public.frontend_performance_record(text,integer,integer,integer,text) from public,anon,authenticated;
grant execute on function public.frontend_performance_record(text,integer,integer,integer,text) to service_role;

create or replace function private.frontend_performance_summary()
returns jsonb language sql stable security definer set search_path='' as $$
with latest as (
 select distinct on(service_key) service_key,status_code,latency_ms,payload_bytes,cache_control,measured_at
 from private.frontend_performance_samples order by service_key,measured_at desc
), a as (
 select count(*) filter(where image_url like 'http://127.0.0.1:54321/storage/v1/object/public/rohmat-assets/menu-cache/%') direct_storage,
 count(*) filter(where image_url like '%/functions/v1/rohmat-menu-photo%') proxy_urls,
 count(*) total_images from public.menu_items where coalesce(image_url,'')<>''
), s as (
 select count(*) cached_objects,count(*) filter(where metadata->>'cacheControl' like '%31536000%') year_cache
 from storage.objects where bucket_id='rohmat-assets' and name like 'menu-cache/%'
), m as (
 select coalesce(jsonb_object_agg(service_key,jsonb_build_object('status',status_code,'latency_ms',latency_ms,'payload_bytes',payload_bytes,'cache_control',cache_control,'measured_at',measured_at)),'{}'::jsonb) metrics,
 count(*) count_services from latest
)
select jsonb_build_object(
 'ok', a.proxy_urls=0 and a.direct_storage=a.total_images and a.total_images=36 and s.cached_objects=36 and s.year_cache=36 and m.count_services=3,
 'menu_images',jsonb_build_object('total',a.total_images,'direct_storage',a.direct_storage,'proxy_urls',a.proxy_urls,'cached_objects',s.cached_objects,'year_cache',s.year_cache),
 'latest',m.metrics
) from a,s,m;
$$;
revoke all on function private.frontend_performance_summary() from public,anon,authenticated;
