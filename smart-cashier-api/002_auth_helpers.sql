create or replace function resolve_session(p_token_hash text)
returns table(session_id uuid,user_id uuid,tenant_id uuid,outlet_id uuid,role smart_cashier_role,display_name text,email text,expires_at timestamptz)
language sql security definer set search_path=public as $$
  select s.id,u.id,u.tenant_id,u.outlet_id,u.role,u.display_name,u.email,s.expires_at
  from sessions s join app_users u on u.id=s.user_id
  where s.token_hash=p_token_hash and s.expires_at>now() and u.status='ACTIVE'
  limit 1
$$;
revoke all on function resolve_session(text) from public;
grant execute on function resolve_session(text) to smart_cashier_app;

create or replace function revoke_session(p_token_hash text)
returns void language sql security definer set search_path=public as $$
  delete from sessions where token_hash=p_token_hash
$$;
revoke all on function revoke_session(text) from public;
grant execute on function revoke_session(text) to smart_cashier_app;

create or replace function create_session(
  p_user_id uuid,p_tenant_id uuid,p_outlet_id uuid,p_token_hash text,p_expires_at timestamptz
) returns uuid language sql security definer set search_path=public as $$
  insert into sessions(user_id,tenant_id,outlet_id,token_hash,expires_at)
  values(p_user_id,p_tenant_id,p_outlet_id,p_token_hash,p_expires_at)
  returning id
$$;
revoke all on function create_session(uuid,uuid,uuid,text,timestamptz) from public;
grant execute on function create_session(uuid,uuid,uuid,text,timestamptz) to smart_cashier_app;
