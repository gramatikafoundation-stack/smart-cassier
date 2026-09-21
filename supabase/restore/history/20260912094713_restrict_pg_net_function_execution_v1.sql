-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912094713  Name: restrict_pg_net_function_execution_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

revoke all on function net.http_get(text,jsonb,jsonb,integer) from public,anon,authenticated;
revoke all on function net.http_post(text,jsonb,jsonb,jsonb,integer) from public,anon,authenticated;
revoke all on function net.http_delete(text,jsonb,jsonb,integer,jsonb) from public,anon,authenticated;
grant execute on function net.http_get(text,jsonb,jsonb,integer) to service_role;
grant execute on function net.http_post(text,jsonb,jsonb,jsonb,integer) to service_role;
grant execute on function net.http_delete(text,jsonb,jsonb,integer,jsonb) to service_role;
