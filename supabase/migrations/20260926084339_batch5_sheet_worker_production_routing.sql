do $$
declare
  v_def text;
begin
  select pg_get_functiondef('private.invoke_sheet_sync_worker()'::regprocedure) into v_def;
  if position('http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-worker-v1' in v_def)=0 then
    raise exception 'invoke_sheet_sync_worker_expected_endpoint_missing';
  end if;
  v_def := replace(
    v_def,
    'http://127.0.0.1:54321/functions/v1/rohmat-sheet-sync-worker-v1',
    'https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-sheet-sync-worker-v1'
  );
  execute v_def;

  select pg_get_functiondef('private.dispatch_sheet_sync_event()'::regprocedure) into v_def;
  if position('https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-sheet-sync-worker-v1' in v_def)=0 then
    raise exception 'dispatch_sheet_sync_event_expected_endpoint_missing';
  end if;
  v_def := replace(
    v_def,
    'https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-sheet-sync-worker-v1',
    'https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-sheet-sync-worker-v1'
  );
  execute v_def;
end
$$;

comment on function private.invoke_sheet_sync_worker() is
  'Production-safe sheet sync cron dispatcher. Calls the current project Edge worker using the private cron token.';
comment on function private.dispatch_sheet_sync_event() is
  'Production-safe outbox trigger dispatcher. Calls the current project Edge worker using the private cron token.';
