-- Production state prerequisite that existed outside the tracked migration ledger.
-- The subsequent tracked route-lock migration enforces these canonical values,
-- but no earlier tracked migration sets public_url/admin_url to the locked forms.
-- Capture the observed production state explicitly for isolated DR replay.

update public.site_settings
set public_url='https://rohmat-pesan-bayar-publik.vercel.app/',
    admin_url='https://studio-pengelola-rohmat.vercel.app',
    kds_url='https://rohmat-kds-printer.vercel.app'
where id=1;
