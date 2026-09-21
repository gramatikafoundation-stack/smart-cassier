-- DR-only deterministic reconstruction of state that production acquired from the
-- scheduled reliability probe between migrations 20260912114809 and 20260912174814.
-- The later SLO migration adds an FK to reliability_probe_state and inserts config
-- for these four canonical services, so an accelerated replay must materialize the
-- service-key parents explicitly instead of depending on wall-clock cron execution.

insert into private.reliability_probe_state(service_key)
values
  ('public_web'),
  ('admin_web'),
  ('kds_web'),
  ('order_gateway')
on conflict (service_key) do nothing;
