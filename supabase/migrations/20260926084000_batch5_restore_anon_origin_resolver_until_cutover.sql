-- Transitional compatibility only: production Batch 4 still resolves tenant origin via direct RPC.
-- Revoke anon EXECUTE only after the Batch 5 Edge mediator is live on production.
grant execute on function public.master_prototype_resolve_origin(text, text) to anon;
