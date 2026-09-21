do $do$
declare
  existing_job bigint;
begin
  select jobid into existing_job from cron.job where jobname='public_rum_prune_daily' limit 1;
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
  perform cron.schedule(
    'public_rum_prune_daily',
    '17 2 * * *',
    $cmd$select private.prune_public_rum_samples(interval '30 days');$cmd$
  );
end
$do$;
