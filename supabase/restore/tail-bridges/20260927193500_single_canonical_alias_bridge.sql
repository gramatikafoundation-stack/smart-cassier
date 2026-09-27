-- DR-only reconstruction of the B1 alias cleanup that existed in live production.
-- Preserve legacy rows as disabled rollback evidence; enforce exactly one enabled canonical alias.

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
