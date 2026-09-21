-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260904024821  Name: add_private_payment_proof_bucket
-- Production-specific credentials, operator identities, and project endpoint were neutralized.


insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'rohmat-payment-proofs',
  'rohmat-payment-proofs',
  false,
  3145728,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Admins read payment proof objects"
on storage.objects for select
to authenticated
using (bucket_id = 'rohmat-payment-proofs' and (select private.is_admin()));

