-- Batch 5 final freeze hardening.
-- Canonical production has cut over to the service-role Edge resolver.
-- Direct client execution is no longer required.
revoke execute on function public.master_prototype_resolve_origin(text,text) from anon,authenticated;
grant execute on function public.master_prototype_resolve_origin(text,text) to service_role;
