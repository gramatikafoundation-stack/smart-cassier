do $do$
declare existing_job bigint;
begin
  select jobid into existing_job from cron.job where jobname='kds_observability_prune_daily' limit 1;
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
  perform cron.schedule(
    'kds_observability_prune_daily',
    '37 2 * * *',
    $cmd$select private.kds_observability_prune(now()-interval '30 days');$cmd$
  );
end
$do$;
