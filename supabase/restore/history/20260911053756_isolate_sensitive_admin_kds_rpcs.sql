-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911053756  Name: isolate_sensitive_admin_kds_rpcs
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create schema if not exists internal_rpc;
revoke all on schema internal_rpc from public;

alter function public.admin_password_login(text,text) set schema internal_rpc;
alter function public.admin_password_logout(text) set schema internal_rpc;
alter function public.admin_password_session_info(text) set schema internal_rpc;
alter function public.kds_snapshot(text) set schema internal_rpc;
alter function public.kds_update_order(text,uuid,text) set schema internal_rpc;
alter function public.kds_set_availability(text,text,boolean,text) set schema internal_rpc;

create function public.admin_password_login(p_email text, p_password text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select internal_rpc.admin_password_login(p_email,p_password) $$;

create function public.admin_password_logout(p_token text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select internal_rpc.admin_password_logout(p_token) $$;

create function public.admin_password_session_info(p_token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select internal_rpc.admin_password_session_info(p_token) $$;

create function public.kds_snapshot(p_token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select internal_rpc.kds_snapshot(p_token) $$;

create function public.kds_update_order(p_token text, p_id uuid, p_action text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select internal_rpc.kds_update_order(p_token,p_id,p_action) $$;

create function public.kds_set_availability(p_token text, p_id text, p_available boolean, p_note text default ''::text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select internal_rpc.kds_set_availability(p_token,p_id,p_available,p_note) $$;

revoke all on all functions in schema internal_rpc from public, anon, authenticated;
grant usage on schema internal_rpc to anon, service_role;
grant execute on function internal_rpc.admin_password_login(text,text) to anon, service_role;
grant execute on function internal_rpc.admin_password_logout(text) to anon, service_role;
grant execute on function internal_rpc.admin_password_session_info(text) to anon, service_role;
grant execute on function internal_rpc.kds_snapshot(text) to anon, service_role;
grant execute on function internal_rpc.kds_update_order(text,uuid,text) to anon, service_role;
grant execute on function internal_rpc.kds_set_availability(text,text,boolean,text) to anon, service_role;

revoke all on function public.admin_password_login(text,text) from public, authenticated;
revoke all on function public.admin_password_logout(text) from public, authenticated;
revoke all on function public.admin_password_session_info(text) from public, authenticated;
revoke all on function public.kds_snapshot(text) from public, authenticated;
revoke all on function public.kds_update_order(text,uuid,text) from public, authenticated;
revoke all on function public.kds_set_availability(text,text,boolean,text) from public, authenticated;
grant execute on function public.admin_password_login(text,text) to anon, service_role;
grant execute on function public.admin_password_logout(text) to anon, service_role;
grant execute on function public.admin_password_session_info(text) to anon, service_role;
grant execute on function public.kds_snapshot(text) to anon, service_role;
grant execute on function public.kds_update_order(text,uuid,text) to anon, service_role;
grant execute on function public.kds_set_availability(text,text,boolean,text) to anon, service_role;
