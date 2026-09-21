-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912094800  Name: fix_custom_password_repeat_regex_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.admin_password_is_strong(p text)
returns boolean
language sql
immutable
set search_path=''
as $fn$
select p is not null
 and length(p) between 12 and 128
 and p ~ '[A-Z]'
 and p ~ '[a-z]'
 and p ~ '[0-9]'
 and p ~ '[^A-Za-z0-9]'
 and lower(p) !~ '(password|passw0rd|qwerty|123456|123456789|admin123|administrator|superadmin|letmein|welcome|welcome123|iloveyou|asdfgh|nasiuduk|rohmat)'
 and p !~ E'(.)\\1\\1\\1';
$fn$;
revoke all on function private.admin_password_is_strong(text) from public,anon,authenticated;
