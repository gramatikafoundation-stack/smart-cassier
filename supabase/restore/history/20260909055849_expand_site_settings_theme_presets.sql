-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909055849  Name: expand_site_settings_theme_presets
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.site_settings drop constraint if exists site_settings_theme_preset_check;
alter table public.site_settings add constraint site_settings_theme_preset_check check (theme_preset = any (array['warm-green'::text,'elegant-red'::text,'modern-yellow'::text,'professional-blue'::text,'premium-navy'::text,'coffee-brown'::text,'energetic-orange'::text,'royal-purple'::text,'teal-fresh'::text,'monochrome'::text,'sage-soft'::text,'olive-natural'::text,'beige-minimal'::text,'black-gold'::text,'grey-modern'::text,'turquoise-bright'::text,'burgundy-classic'::text,'pastel-pink'::text,'custom'::text]));
