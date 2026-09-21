-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907193436  Name: remove_obsolete_password_session_rls
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

drop policy if exists "Password superadmins delete team" on public.admin_users;
drop policy if exists "Password superadmins add team" on public.admin_users;
drop policy if exists "Password admins read team" on public.admin_users;
drop policy if exists "Password superadmins update team" on public.admin_users;

drop policy if exists "Password admins delete menu" on public.menu_items;
drop policy if exists "Password admins insert menu" on public.menu_items;
drop policy if exists "Password admins read all menu" on public.menu_items;
drop policy if exists "Password admins update menu" on public.menu_items;
drop policy if exists "public_read_visible_menu" on public.menu_items;

drop policy if exists "Password admins create order events" on public.order_events;
drop policy if exists "Password admins read order events" on public.order_events;

drop policy if exists "Password admins insert orders" on public.orders;
drop policy if exists "Password admins read orders" on public.orders;
drop policy if exists "Password admins update orders" on public.orders;

drop policy if exists "Password admins update site settings" on public.site_settings;
drop policy if exists "public_read_site_settings" on public.site_settings;
