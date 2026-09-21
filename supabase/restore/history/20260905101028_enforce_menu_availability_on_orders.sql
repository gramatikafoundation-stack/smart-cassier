-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905101028  Name: enforce_menu_availability_on_orders
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.enforce_order_item_availability()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_bad_count integer;
begin
  select count(*) into v_bad_count
  from jsonb_array_elements(new.items) as x
  left join public.menu_items m on m.id = x->>'menuId'
  where m.id is null or m.is_visible is not true or m.is_available is not true;

  if v_bad_count > 0 then
    raise exception 'Salah satu menu sedang habis atau tidak tersedia. Silakan perbarui menu dan pilih kembali.' using errcode='P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_order_item_availability on public.orders;
create trigger trg_enforce_order_item_availability
before insert on public.orders
for each row execute function public.enforce_order_item_availability();
