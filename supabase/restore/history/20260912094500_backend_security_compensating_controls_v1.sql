-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912094500  Name: backend_security_compensating_controls_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

-- 1) pg_net compensating control: clients do not need direct schema access.
revoke usage on schema net from public;
grant usage on schema net to service_role;

-- 2) Make legacy duplicate initial-event inserts idempotent.
create or replace function private.dedupe_initial_order_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
begin
  if new.event_type in ('payment_submitted','cashier_order_created')
     and exists (
       select 1 from public.order_events e
       where e.order_id=new.order_id and e.event_type=new.event_type
     ) then
    return null;
  end if;
  return new;
end
$fn$;
revoke all on function private.dedupe_initial_order_event() from public,anon,authenticated;

drop trigger if exists trg_dedupe_initial_order_event on public.order_events;
create trigger trg_dedupe_initial_order_event
before insert on public.order_events
for each row execute function private.dedupe_initial_order_event();

-- 3) Stronger custom-admin password policy; existing hashes/sessions remain untouched.
create or replace function private.admin_password_is_strong(p text)
returns boolean
language sql
immutable
set search_path=''
as $fn$
select p is not null
 and length(p) between 12 and 128
 and p ~ '[A-Z]'
 and p ~ '[a-z]'
 and p ~ '[0-9]'
 and p ~ '[^A-Za-z0-9]'
 and lower(p) !~ '(password|passw0rd|qwerty|123456|123456789|admin123|administrator|superadmin|letmein|welcome|welcome123|iloveyou|asdfgh|nasiuduk|rohmat)'
 and p !~ '(.)\\1\\1\\1';
$fn$;
revoke all on function private.admin_password_is_strong(text) from public,anon,authenticated;

