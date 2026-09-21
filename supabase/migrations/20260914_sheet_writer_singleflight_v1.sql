create table if not exists private.sheet_writer_lease (
  id smallint primary key check (id = 1),
  locked_by uuid,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

insert into private.sheet_writer_lease(id, locked_by, locked_until)
values (1, null, null)
on conflict (id) do nothing;

alter table private.sheet_writer_lease enable row level security;
revoke all on private.sheet_writer_lease from public, anon, authenticated;
grant all on private.sheet_writer_lease to service_role;

create or replace function public.sheet_writer_try_acquire_lease(
  p_run_id uuid,
  p_ttl_seconds integer default 115
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_acquired boolean := false;
  v_ttl integer := greatest(30, least(coalesce(p_ttl_seconds, 115), 180));
begin
  if p_run_id is null then
    return false;
  end if;

  update private.sheet_writer_lease
     set locked_by = p_run_id,
         locked_until = now() + pg_catalog.make_interval(secs => v_ttl),
         updated_at = now()
   where id = 1
     and (
       locked_until is null
       or locked_until <= now()
       or locked_by = p_run_id
     );

  v_acquired := found;
  return v_acquired;
end
$function$;

create or replace function public.sheet_writer_release_lease(p_run_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_released boolean := false;
begin
  if p_run_id is null then
    return false;
  end if;

  update private.sheet_writer_lease
     set locked_by = null,
         locked_until = null,
         updated_at = now()
   where id = 1
     and locked_by = p_run_id;

  v_released := found;
  return v_released;
end
$function$;

revoke all on function public.sheet_writer_try_acquire_lease(uuid, integer) from public, anon, authenticated;
revoke all on function public.sheet_writer_release_lease(uuid) from public, anon, authenticated;
grant execute on function public.sheet_writer_try_acquire_lease(uuid, integer) to service_role;
grant execute on function public.sheet_writer_release_lease(uuid) to service_role;

create or replace function private.dispatch_sheet_sync_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_enabled boolean;
  v_writer_url text;
  v_token text;
begin
  select enabled, writer_url
    into v_enabled, v_writer_url
    from public.sheet_sync_config
   where id = 1;

  if coalesce(v_enabled, false) is not true or coalesce(v_writer_url, '') = '' then
    return new;
  end if;

  select decrypted_secret
    into v_token
    from vault.decrypted_secrets
   where name = 'rohmat_sheet_sync_cron_token_v2'
   limit 1;

  if coalesce(v_token, '') = '' then
    return new;
  end if;

  perform net.http_post(
    url := 'https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-sheet-sync-worker-v1',
    body := jsonb_build_object(
      'source', 'outbox_trigger',
      'event_id', new.event_id,
      'idempotency_key', new.idempotency_key,
      'request_id', new.request_id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Rohmat-Cron-Token', v_token
    ),
    timeout_milliseconds := 1000
  );

  return new;
exception when others then
  return new;
end
$function$;

comment on table private.sheet_writer_lease is 'Single-flight lease ensuring only one canonical sheet writer invocation reaches Google Apps Script at a time.';
comment on function public.sheet_writer_try_acquire_lease(uuid, integer) is 'Service-role-only atomic lease acquisition for the canonical sheet writer worker.';
comment on function public.sheet_writer_release_lease(uuid) is 'Service-role-only release for the canonical sheet writer worker.';