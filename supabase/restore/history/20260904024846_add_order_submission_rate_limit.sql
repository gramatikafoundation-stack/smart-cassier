-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260904024846  Name: add_order_submission_rate_limit
-- Production-specific credentials, operator identities, and project endpoint were neutralized.


create table private.order_rate_limits (
  id bigint generated always as identity primary key,
  fingerprint text not null,
  attempted_at timestamptz not null default now()
);
create index order_rate_limits_fingerprint_time_idx
  on private.order_rate_limits(fingerprint, attempted_at desc);

create or replace function public.consume_order_rate_limit(p_fingerprint text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent_attempts integer;
begin
  if p_fingerprint is null or char_length(p_fingerprint) <> 64 then
    return false;
  end if;
  perform pg_advisory_xact_lock(hashtext(p_fingerprint));
  delete from private.order_rate_limits
    where fingerprint = p_fingerprint
      and attempted_at < now() - interval '1 day';
  select count(*) into recent_attempts
    from private.order_rate_limits
    where fingerprint = p_fingerprint
      and attempted_at >= now() - interval '10 minutes';
  if recent_attempts >= 5 then
    return false;
  end if;
  insert into private.order_rate_limits (fingerprint) values (p_fingerprint);
  return true;
end;
$$;
revoke all on function public.consume_order_rate_limit(text) from public, anon, authenticated;
grant execute on function public.consume_order_rate_limit(text) to service_role;

