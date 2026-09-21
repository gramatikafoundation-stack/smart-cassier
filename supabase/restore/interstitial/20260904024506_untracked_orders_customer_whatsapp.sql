-- Production schema prerequisite that existed outside the tracked migration ledger.
-- The first tracked migration creates public.orders without customer_whatsapp,
-- while tracked migration 20260908033934 already depends on that column.
-- This DR-only interstitial captures that pre-existing production drift explicitly.

alter table public.orders
  add column if not exists customer_whatsapp text;
