-- SMART ORDER v1.0.1 hotfix: one-time tenant-bound admin password recovery.
-- Password plaintext never needs to pass through operator tooling.

create table if not exists private.admin_password_recovery_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references private.platform_tenants(id) on delete cascade,
  email extensions.citext not null,
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  created_by text not null default 'admin-recovery'
);

alter table private.admin_password_recovery_tokens enable row level security;
revoke all on table private.admin_password_recovery_tokens from public,anon,authenticated;

create index if not exists admin_password_recovery_tokens_active_idx
  on private.admin_password_recovery_tokens(tenant_id,email,expires_at)
  where used_at is null;

create or replace function public.admin_password_recovery_once(
  p_token text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_rec private.admin_password_recovery_tokens%rowtype;
  v_target extensions.citext;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false,'error','recovery_invalid_or_expired');
  end if;

  if not private.admin_password_is_strong(p_new_password) then
    return jsonb_build_object('ok',false,'error','new_password_weak');
  end if;

  select *
  into v_rec
  from private.admin_password_recovery_tokens
  where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    and used_at is null
    and expires_at>now()
  order by created_at desc
  limit 1
  for update;

  if v_rec.id is null then
    return jsonb_build_object('ok',false,'error','recovery_invalid_or_expired');
  end if;

  select au.email
  into v_target
  from private.tenant_memberships tm
  join public.admin_users au on lower(au.email::text)=lower(tm.email)
  where tm.tenant_id=v_rec.tenant_id
    and lower(tm.email)=lower(v_rec.email::text)
    and tm.is_active
    and tm.role='superadmin'
    and au.is_active
  limit 1;

  if v_target is null then
    update private.admin_password_recovery_tokens
    set used_at=now()
    where id=v_rec.id;
    return jsonb_build_object('ok',false,'error','recovery_target_unavailable');
  end if;

  insert into private.admin_passwords(email,password_hash,updated_at)
  values(
    v_target,
    extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),
    now()
  )
  on conflict(email) do update
  set password_hash=excluded.password_hash,
      updated_at=excluded.updated_at;

  delete from private.admin_sessions
  where lower(email::text)=lower(v_target::text);

  delete from public.security_rate_limits
  where bucket='login:'||v_rec.tenant_id::text;

  update private.admin_password_recovery_tokens
  set used_at=now()
  where id=v_rec.id;

  return jsonb_build_object(
    'ok',true,
    'tenant_id',v_rec.tenant_id,
    'email',lower(v_target::text),
    'sessions_revoked',true,
    'rate_limit_cleared',true
  );
end
$$;

revoke all on function public.admin_password_recovery_once(text,text) from public,anon,authenticated;
grant execute on function public.admin_password_recovery_once(text,text) to service_role;
