-- DR-only reconciliation of a retired historical recovery table.
-- public.rdc_recovery_devices existed in Sep-19 history but is absent from the current
-- production schema. Drop it only in the final reconstructed state so DR matches live.

drop table if exists public.rdc_recovery_devices cascade;
