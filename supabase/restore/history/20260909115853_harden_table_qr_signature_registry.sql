-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909115853  Name: harden_table_qr_signature_registry
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.table_qr_signatures (
  table_number smallint primary key check (table_number between 1 and 20),
  signature_hash text not null check (signature_hash ~ '^[a-f0-9]{64}$'),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into private.table_qr_signatures(table_number,signature_hash) values
(1,'b2ed48002b231e17cc8345014387acc39b669acba763341155310c96f6c01cb2'),
(2,'aec6deef595ebbfcd01123a35a2a599bb924efc7c8ded1156cec70dae18dcb0d'),
(3,'17649e3b5fc3657bbe5e85b25944d01aedba6935729d53f039c5822016324f2b'),
(4,'4bc40849bccddd3eb6c1daea9617b8cde6b3bc2359f781be10a393780a0d1dca'),
(5,'f887f2148006a5c7d7a45e54b939ad21fce827d582adf506cbde27db30ee72df'),
(6,'afb6a049dbbb100b2a7e1e8bad5a18e996b7951f6e2b30e45ecadb07994e9d1b'),
(7,'dad8dbedc50bd1d363196d267ab515add3aa1aa0ec8a76c60bfc8a75bc8af573'),
(8,'02758222ac68b3d86408a516a634a2d23b7561aa66687e6c329d7e68b534a228'),
(9,'099dfab08d8541623d9e1e2290da15078ab372c53065b506b585a06fef493b67'),
(10,'96bfa70fbe8d3979df24036f1ae180c03c3d6b62bd33b74fe6617659985af395'),
(11,'f2d7a50f91552cc1abcf3b3c0880d5bb3e571d1479c8575fec81107b5edbff16'),
(12,'dac03b3366f8afc44eae365c322d7067a743be10a44f9b4b0e71005754d82256'),
(13,'39ca54d6390f914d853b85808e90eddd8b4664423d553f3347d75b68a88681bf'),
(14,'9b3c6161a5b5bd341c12611f25719f7bd7f66062ab382d4e0a252822938983fa'),
(15,'0389010225d6d4191bd710c999ceb3ff9bba226941b7c395c8e46227f09bd3b4'),
(16,'fe4a3d4197435ac50b350eea63cd12b6fec1eaca06acdfb34942c27c87c494b0'),
(17,'032737ee1f09929a8657af85f5018a30416cc3dfde812cde3b5a526c15d55861'),
(18,'fe3f659d7fd3a88d6bfb6dbcd1773fb2a58b85a2da0e46894fc105eec60aed3b'),
(19,'4ea802faffb6c766b042d33ff534afd379a5cdaad69eb9a44398956f8213a32d'),
(20,'d58ba041dd61b052770d11f1da026de6e865fb28e8f585d9a60b14516b4a4cc9')
on conflict(table_number) do update set signature_hash=excluded.signature_hash,is_active=true,updated_at=now();

create or replace function public.verify_table_qr_signature(p_table integer,p_signature text)
returns boolean
language sql
security definer
set search_path=''
as $$
  select exists(
    select 1 from private.table_qr_signatures q
    where q.table_number=p_table
      and q.is_active
      and q.signature_hash=encode(extensions.digest(coalesce(p_signature,''),'sha256'),'hex')
      and coalesce(p_signature,'') ~ '^[a-f0-9]{32}$'
  );
$$;
revoke all on function public.verify_table_qr_signature(integer,text) from public,anon,authenticated;
grant execute on function public.verify_table_qr_signature(integer,text) to service_role;
