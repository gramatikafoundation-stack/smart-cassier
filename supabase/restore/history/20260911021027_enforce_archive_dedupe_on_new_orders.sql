-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911021027  Name: enforce_archive_dedupe_on_new_orders
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.enforce_archived_order_dedupe()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if new.client_order_id is not null and exists (
    select 1 from public.order_history_archive a where a.client_order_id = new.client_order_id
  ) then
    raise exception using errcode='23505', message='Identitas pesanan ini sudah pernah diproses.';
  end if;

  if new.payment_proof_sha256 is not null and new.payment_proof_sha256 <> '' and exists (
    select 1 from public.order_history_archive a where a.payment_proof_sha256 = new.payment_proof_sha256
  ) then
    raise exception using errcode='23505', message='Bukti pembayaran ini sudah pernah digunakan pada pesanan lain.';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_enforce_archived_order_dedupe on public.orders;
create trigger trg_enforce_archived_order_dedupe
before insert on public.orders
for each row execute function public.enforce_archived_order_dedupe();
