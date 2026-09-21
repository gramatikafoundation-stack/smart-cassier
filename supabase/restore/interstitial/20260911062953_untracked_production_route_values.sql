-- DR-only reconstruction of production route values that existed before the tracked
-- production_route_lock_v1 migration. Without these values, the later CHECK
-- constraints correctly fail closed during isolated restore.

update public.site_settings
set public_url = 'https://rohmat-pesan-bayar-publik.vercel.app/',
    admin_url = 'https://studio-pengelola-rohmat.vercel.app',
    kds_url = 'https://rohmat-kds-printer.vercel.app'
where id = 1;
