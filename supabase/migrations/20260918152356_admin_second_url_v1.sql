-- Allow the selected recovery Admin deployment URL while retaining the original canonical Admin URL.
alter table public.site_settings
  drop constraint if exists site_settings_locked_admin_url_chk;

alter table public.site_settings
  add constraint site_settings_locked_admin_url_chk
  check (admin_url in (
    'https://studio-pengelola-rohmat.vercel.app',
    'https://studio-pengelola-rohmat-4cqepd0ew-gramatikafoundation-3204.vercel.app'
  ));

update public.site_settings
set admin_url='https://studio-pengelola-rohmat-4cqepd0ew-gramatikafoundation-3204.vercel.app',
    updated_at=now()
where id=1;
