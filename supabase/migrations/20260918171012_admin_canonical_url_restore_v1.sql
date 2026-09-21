-- Restore the short canonical Admin URL after repairing the Vercel alias.
-- The long deployment URL remains an allowlisted recovery fallback only.

update public.site_settings
set admin_url='https://studio-pengelola-rohmat.vercel.app',
    updated_at=now()
where id=1;
