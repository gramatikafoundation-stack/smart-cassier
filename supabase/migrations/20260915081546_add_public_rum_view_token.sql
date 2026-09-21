alter table public.public_rum_samples add column if not exists view_token uuid;
update public.public_rum_samples set view_token = gen_random_uuid() where view_token is null;
alter table public.public_rum_samples alter column view_token set not null;
create unique index if not exists public_rum_samples_view_metric_uidx on public.public_rum_samples(view_token, metric);