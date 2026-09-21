-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905074357  Name: initialize_existing_admin_passwords
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

insert into private.admin_passwords(email, password_hash)
select au.email, '$2a$06$00000000000000000000000000000000000000000000000000000'
from public.admin_users au
where au.is_active
on conflict (email) do nothing;
