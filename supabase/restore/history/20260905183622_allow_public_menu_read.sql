-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905183622  Name: allow_public_menu_read
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

grant select on table public.site_settings to anon;
grant select on table public.menu_items to anon;

drop policy if exists public_read_site_settings on public.site_settings;
create policy public_read_site_settings
on public.site_settings
for select
to anon
using (id = 1);

drop policy if exists public_read_visible_menu on public.menu_items;
create policy public_read_visible_menu
on public.menu_items
for select
to anon
using (is_visible = true);
