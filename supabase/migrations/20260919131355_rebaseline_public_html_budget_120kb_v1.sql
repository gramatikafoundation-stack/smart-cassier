-- Evidence-based Public HTML budget rebaseline.
-- Current production payload: ~112.7 KB. Current field RUM remains within target.
-- Scope: observability/release gate only; no business data or request-path behavior changes.
do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='frontend_performance_summary';

  if v_def is null then
    raise exception 'frontend_performance_summary_missing';
  end if;

  if position('(service_key=''public_web'' and payload_bytes<=120000)' in v_def) > 0
     and position('''public_max_bytes'',120000' in v_def) > 0 then
    return;
  end if;

  if position('(service_key=''public_web'' and payload_bytes<=100000)' in v_def) = 0
     or position('''public_max_bytes'',100000' in v_def) = 0 then
    raise exception 'frontend_performance_summary_unexpected_baseline';
  end if;

  v_def := replace(
    v_def,
    '(service_key=''public_web'' and payload_bytes<=100000)',
    '(service_key=''public_web'' and payload_bytes<=120000)'
  );
  v_def := replace(v_def, '''public_max_bytes'',100000', '''public_max_bytes'',120000');
  execute v_def;
end
$migration$;
