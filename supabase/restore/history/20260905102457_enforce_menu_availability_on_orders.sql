-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905102457  Name: enforce_menu_availability_on_orders
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.enforce_order_menu_availability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_menu_id text;
  v_bad text[] := '{}';
begin
  if new.items is null or jsonb_typeof(new.items) <> 'array' then
    return new;
  end if;

  for v_item in select * from jsonb_array_elements(new.items)
  loop
    v_menu_id := coalesce(v_item->>'menuId', v_item->>'id');
    if v_menu_id is null or not exists (
      select 1
      from public.menu_items m
      where m.id = v_menu_id
        and m.is_visible = true
        and coalesce(m.is_available,true) = true
    ) then
      v_bad := array_append(v_bad, coalesce(v_menu_id,'menu-tidak-valid'));
    end if;
  end loop;

  if array_length(v_bad,1) is not null then
    raise exception using
      errcode = 'P0001',
      message = 'Salah satu menu sedang habis atau tidak tersedia: ' || array_to_string(v_bad, ', ');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_order_menu_availability on public.orders;
create trigger trg_enforce_order_menu_availability
before insert on public.orders
for each row execute function private.enforce_order_menu_availability();
