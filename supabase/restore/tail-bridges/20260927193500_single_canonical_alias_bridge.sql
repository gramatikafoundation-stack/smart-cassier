-- DR-only reconstruction of the B1 alias cleanup that existed in live production.
-- Preserve legacy rows as disabled rollback evidence; enforce exactly one enabled canonical alias.

-- Fresh/sanitized DR history may not contain the later SMART ORDER alias rows at all.
-- Recreate the two live identity rows idempotently before normalizing their roles.
insert into private.tenant_origin_aliases(
  tenant_id,app_kind,origin,enabled,alias_kind,metadata,created_at,updated_at
)
values
(
  'd8bb901c-7399-485b-8743-b319fde148ac','public',
  'https://smart-order-sdb.vercel.app',true,'canonical',
  jsonb_build_object(
    'architecture','single_domain_four_surface_v1',
    'unified_routes',jsonb_build_array('/','/admin','/kds','/database')
  ),now(),now()
),
(
  'd8bb901c-7399-485b-8743-b319fde148ac','public',
  'https://smart-cassier.vercel.app',true,'custom',
  jsonb_build_object(
    'status','legacy_redirect',
    'canonical',false,
    'redirect_to','https://smart-order-sdb.vercel.app',
    'unified_routes',jsonb_build_array('/','/admin','/kds')
  ),now(),now()
)
on conflict(origin) do update
set tenant_id=excluded.tenant_id,
    app_kind=excluded.app_kind,
    enabled=excluded.enabled,
    alias_kind=excluded.alias_kind,
    metadata=coalesce(private.tenant_origin_aliases.metadata,'{}'::jsonb)||excluded.metadata,
    updated_at=now();

update private.tenant_origin_aliases
set enabled=false,
    alias_kind=case when alias_kind='preview' then 'preview' else 'custom' end,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('status','legacy_disabled_b1_recovery'),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and origin not in (
    'https://smart-order-sdb.vercel.app',
    'https://smart-cassier.vercel.app'
  );

update private.tenant_origin_aliases
set app_kind='public',alias_kind='canonical',enabled=true,updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and origin='https://smart-order-sdb.vercel.app';

update private.tenant_origin_aliases
set app_kind='public',alias_kind='custom',enabled=true,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'status','legacy_redirect','canonical',false,
      'redirect_to','https://smart-order-sdb.vercel.app'
    ),
    updated_at=now()
where tenant_id='d8bb901c-7399-485b-8743-b319fde148ac'
  and origin='https://smart-cassier.vercel.app';
