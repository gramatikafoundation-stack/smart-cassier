-- ADMIN Batch 1: pg_net least-privilege hardening
-- Internal cron/private functions execute as postgres; frontend roles do not require direct net access.

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
