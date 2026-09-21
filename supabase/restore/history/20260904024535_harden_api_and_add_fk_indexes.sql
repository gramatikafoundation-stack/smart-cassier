-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260904024535  Name: harden_api_and_add_fk_indexes
-- Production-specific credentials, operator identities, and project endpoint were neutralized.


revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

create index if not exists menu_items_updated_by_idx
  on public.menu_items(updated_by) where updated_by is not null;
create index if not exists orders_verified_by_idx
  on public.orders(verified_by) where verified_by is not null;
create index if not exists order_events_actor_id_idx
  on public.order_events(actor_id) where actor_id is not null;
create index if not exists admin_users_created_by_idx
  on public.admin_users(created_by) where created_by is not null;
create index if not exists site_settings_updated_by_idx
  on public.site_settings(updated_by) where updated_by is not null;

drop policy if exists "Public reads visible menu" on public.menu_items;
create policy "Public reads visible menu"
on public.menu_items for select
to anon
using (is_visible);

