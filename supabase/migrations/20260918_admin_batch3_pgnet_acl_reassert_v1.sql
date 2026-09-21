-- ADMIN Batch 3: record pg_net least-privilege reassertion attempt after extension ACL drift.
-- Scope: privilege hardening only. No business data or application behavior changes.
--
-- IMPORTANT PLATFORM CONSTRAINT:
-- pg_net objects are owned by Supabase-managed role supabase_admin. Project role postgres
-- cannot SET ROLE supabase_admin, so REVOKE statements issued by project migrations may
-- be best-effort/no-op for ACL entries granted by supabase_admin. This migration is kept
-- in source because it is present in production migration history. Effective external
-- exposure must be assessed at the Data API exposed-schema boundary and by Security Advisor.
--
-- Internal Rohmat pg_net callers are SECURITY DEFINER functions owned by postgres.

revoke all on schema net from public;
revoke all on schema net from anon;
revoke all on schema net from authenticated;

revoke all on all functions in schema net from public;
revoke all on all functions in schema net from anon;
revoke all on all functions in schema net from authenticated;

revoke all on all tables in schema net from public;
revoke all on all tables in schema net from anon;
revoke all on all tables in schema net from authenticated;

revoke all on all sequences in schema net from public;
revoke all on all sequences in schema net from anon;
revoke all on all sequences in schema net from authenticated;

grant usage on schema net to postgres, supabase_functions_admin, service_role;
grant execute on all functions in schema net to postgres, supabase_functions_admin, service_role;
