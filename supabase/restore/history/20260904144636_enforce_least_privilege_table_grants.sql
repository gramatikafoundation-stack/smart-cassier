-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260904144636  Name: enforce_least_privilege_table_grants
-- Production-specific credentials, operator identities, and project endpoint were neutralized.


revoke all on public.admin_users, public.site_settings, public.menu_items,
  public.orders, public.order_events from anon, authenticated;
revoke all on sequence public.order_events_id_seq from anon, authenticated;

grant select (
  id, business_name, welcome_text, motto, hero_image_url, public_url,
  photo_position, content_position, content_width, element_order,
  theme_preset, color_outer, color_panel, color_primary, color_accent,
  color_text, color_muted, typography, merchant_name,
  payment_instructions, qris_image_url, qris_enabled, updated_at
) on public.site_settings to anon;
grant select (
  id, name, category, price, description, image_url,
  is_favorite, is_visible, display_order, updated_at
) on public.menu_items to anon;

grant select on public.site_settings, public.menu_items, public.orders,
  public.order_events, public.admin_users to authenticated;
grant insert, update, delete on public.menu_items to authenticated;
grant update on public.site_settings to authenticated;
grant insert, update on public.orders to authenticated;
grant insert on public.order_events to authenticated;
grant insert, update, delete on public.admin_users to authenticated;
grant usage, select on sequence public.order_events_id_seq to authenticated;

