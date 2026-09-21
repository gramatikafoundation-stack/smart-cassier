revoke all on schema net from public, anon, authenticated;
revoke all privileges on all functions in schema net from public, anon, authenticated;
revoke all privileges on all tables in schema net from public, anon, authenticated;
revoke all privileges on all sequences in schema net from public, anon, authenticated;

grant usage on schema net to service_role;
grant execute on all functions in schema net to service_role;

revoke execute on function public.master_prototype_resolve_origin(text,text) from public, authenticated;
grant execute on function public.master_prototype_resolve_origin(text,text) to anon, service_role;
