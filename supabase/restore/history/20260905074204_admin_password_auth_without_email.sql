-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260905074204  Name: admin_password_auth_without_email
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.admin_passwords (
  email extensions.citext primary key references public.admin_users(email) on delete cascade,
  password_hash text not null,
  updated_at timestamptz not null default now()
);

create table if not exists private.admin_sessions (
  token_hash text primary key,
  email extensions.citext not null references public.admin_users(email) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists admin_sessions_email_idx on private.admin_sessions(email);
create index if not exists admin_sessions_expires_idx on private.admin_sessions(expires_at);

insert into private.admin_passwords(email, password_hash)
values ('restore-superadmin@example.invalid', '$2a$06$00000000000000000000000000000000000000000000000000000')
on conflict (email) do update
set password_hash = excluded.password_hash,
    updated_at = now();

create or replace function private.admin_session_email_from_header()
returns extensions.citext
language sql
stable
security definer
set search_path = ''
as $$
  select s.email
  from private.admin_sessions s
  where s.token_hash = encode(
      extensions.digest(
        coalesce((coalesce(current_setting('request.headers', true), '{}')::jsonb ->> 'x-admin-session'), ''),
        'sha256'
      ),
      'hex'
    )
    and s.expires_at > now()
  limit 1;
$$;

create or replace function private.is_admin_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_users au
    where au.email = private.admin_session_email_from_header()
      and au.is_active
  );
$$;

create or replace function private.is_superadmin_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_users au
    where au.email = private.admin_session_email_from_header()
      and au.is_active
      and au.role = 'superadmin'
  );
$$;

create or replace function public.admin_password_login(p_email text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_role text;
  v_name text;
  v_hash text;
  v_token text;
begin
  if p_email is null or p_password is null or length(p_password) > 256 then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  select au.email, au.role, au.display_name, ap.password_hash
    into v_email, v_role, v_name, v_hash
  from public.admin_users au
  join private.admin_passwords ap on ap.email = au.email
  where au.email = lower(trim(p_email))::extensions.citext
    and au.is_active
  limit 1;

  if v_hash is null or extensions.crypt(p_password, v_hash) <> v_hash then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  delete from private.admin_sessions where expires_at <= now();
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into private.admin_sessions(token_hash, email, expires_at)
  values (encode(extensions.digest(v_token, 'sha256'), 'hex'), v_email, now() + interval '12 hours');

  return jsonb_build_object(
    'ok', true,
    'token', v_token,
    'email', v_email::text,
    'display_name', coalesce(v_name, ''),
    'role', v_role,
    'expires_at', (now() + interval '12 hours')
  );
end;
$$;

create or replace function public.admin_password_session_info(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_role text;
  v_name text;
begin
  select au.email, au.role, au.display_name
    into v_email, v_role, v_name
  from private.admin_sessions s
  join public.admin_users au on au.email = s.email
  where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and s.expires_at > now()
    and au.is_active
  limit 1;

  if v_email is null then
    return jsonb_build_object('ok', false);
  end if;

  return jsonb_build_object('ok', true, 'email', v_email::text, 'display_name', coalesce(v_name,''), 'role', v_role);
end;
$$;

create or replace function public.admin_password_logout(p_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.admin_sessions
  where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  return true;
end;
$$;

create or replace function public.admin_password_change(p_token text, p_current_password text, p_new_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email extensions.citext;
  v_hash text;
begin
  if p_new_password is null or length(p_new_password) < 12 or length(p_new_password) > 256 then
    return jsonb_build_object('ok', false, 'error', 'new_password_invalid');
  end if;

  select s.email into v_email
  from private.admin_sessions s
  join public.admin_users au on au.email = s.email and au.is_active
  where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and s.expires_at > now()
  limit 1;

  if v_email is null then
    return jsonb_build_object('ok', false, 'error', 'session_invalid');
  end if;

  select password_hash into v_hash from private.admin_passwords where email = v_email;
  if v_hash is null or extensions.crypt(coalesce(p_current_password,''), v_hash) <> v_hash then
    return jsonb_build_object('ok', false, 'error', 'current_password_invalid');
  end if;

  update private.admin_passwords
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)), updated_at = now()
  where email = v_email;

  delete from private.admin_sessions
  where email = v_email
    and token_hash <> encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_password_set_for_admin(p_token text, p_email text, p_new_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor extensions.citext;
  v_target extensions.citext;
begin
  if p_new_password is null or length(p_new_password) < 12 or length(p_new_password) > 256 then
    return jsonb_build_object('ok', false, 'error', 'new_password_invalid');
  end if;

  select au.email into v_actor
  from private.admin_sessions s
  join public.admin_users au on au.email = s.email
  where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and s.expires_at > now()
    and au.is_active
    and au.role = 'superadmin'
  limit 1;

  if v_actor is null then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select email into v_target
  from public.admin_users
  where email = lower(trim(p_email))::extensions.citext and is_active
  limit 1;

  if v_target is null then
    return jsonb_build_object('ok', false, 'error', 'admin_not_found');
  end if;

  insert into private.admin_passwords(email, password_hash, updated_at)
  values (v_target, extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)), now())
  on conflict (email) do update
  set password_hash = excluded.password_hash, updated_at = now();

  delete from private.admin_sessions where email = v_target;
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.admin_password_login(text,text) to anon, authenticated;
grant execute on function public.admin_password_session_info(text) to anon, authenticated;
grant execute on function public.admin_password_logout(text) to anon, authenticated;
grant execute on function public.admin_password_change(text,text,text) to anon, authenticated;
grant execute on function public.admin_password_set_for_admin(text,text,text) to anon, authenticated;

-- Session-token RLS policies for the password-only admin UI.
drop policy if exists "Password admins read team" on public.admin_users;
create policy "Password admins read team" on public.admin_users for select to anon using ((select private.is_admin_session()));
drop policy if exists "Password superadmins add team" on public.admin_users;
create policy "Password superadmins add team" on public.admin_users for insert to anon with check ((select private.is_superadmin_session()));
drop policy if exists "Password superadmins update team" on public.admin_users;
create policy "Password superadmins update team" on public.admin_users for update to anon using ((select private.is_superadmin_session())) with check ((select private.is_superadmin_session()));
drop policy if exists "Password superadmins delete team" on public.admin_users;
create policy "Password superadmins delete team" on public.admin_users for delete to anon using ((select private.is_superadmin_session()) and not is_protected);

drop policy if exists "Password admins read all menu" on public.menu_items;
create policy "Password admins read all menu" on public.menu_items for select to anon using ((select private.is_admin_session()));
drop policy if exists "Password admins insert menu" on public.menu_items;
create policy "Password admins insert menu" on public.menu_items for insert to anon with check ((select private.is_admin_session()));
drop policy if exists "Password admins update menu" on public.menu_items;
create policy "Password admins update menu" on public.menu_items for update to anon using ((select private.is_admin_session())) with check ((select private.is_admin_session()));
drop policy if exists "Password admins delete menu" on public.menu_items;
create policy "Password admins delete menu" on public.menu_items for delete to anon using ((select private.is_admin_session()));

drop policy if exists "Password admins update site settings" on public.site_settings;
create policy "Password admins update site settings" on public.site_settings for update to anon using ((select private.is_admin_session())) with check ((select private.is_admin_session()));

drop policy if exists "Password admins read orders" on public.orders;
create policy "Password admins read orders" on public.orders for select to anon using ((select private.is_admin_session()));
drop policy if exists "Password admins insert orders" on public.orders;
create policy "Password admins insert orders" on public.orders for insert to anon with check ((select private.is_admin_session()));
drop policy if exists "Password admins update orders" on public.orders;
create policy "Password admins update orders" on public.orders for update to anon using ((select private.is_admin_session())) with check ((select private.is_admin_session()));

drop policy if exists "Password admins read order events" on public.order_events;
create policy "Password admins read order events" on public.order_events for select to anon using ((select private.is_admin_session()));
drop policy if exists "Password admins create order events" on public.order_events;
create policy "Password admins create order events" on public.order_events for insert to anon with check ((select private.is_admin_session()));
