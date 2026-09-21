-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912103900  Name: kds_session_fingerprint_binding_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table private.admin_sessions add column if not exists client_fingerprint_hash text;
alter table private.admin_sessions add column if not exists session_scope text not null default 'legacy';

do $$ begin
  if not exists(select 1 from pg_constraint where conname='admin_sessions_scope_check') then
    alter table private.admin_sessions add constraint admin_sessions_scope_check check (session_scope in ('legacy','admin','kds'));
  end if;
  if not exists(select 1 from pg_constraint where conname='admin_sessions_fingerprint_shape') then
    alter table private.admin_sessions add constraint admin_sessions_fingerprint_shape check (client_fingerprint_hash is null or client_fingerprint_hash ~ '^[a-f0-9]{64}$');
  end if;
end $$;

create or replace function private.request_fingerprint_hash()
returns text
language plpgsql
stable
set search_path=''
as $function$
declare h jsonb:='{}'::jsonb; v_ip text:='unknown'; v_ua text:='unknown';
begin
  begin h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then h:='{}'::jsonb; end;
  v_ip:=left(trim(split_part(coalesce(h->>'cf-connecting-ip',h->>'x-real-ip',h->>'x-forwarded-for','unknown'),',',1)),80);
  v_ua:=left(coalesce(h->>'user-agent','unknown'),240);
  return encode(extensions.digest(v_ip||'|'||v_ua,'sha256'),'hex');
end
$function$;
revoke all on function private.request_fingerprint_hash() from public, anon, authenticated;

create or replace function private.admin_email_from_token(p_token text)
returns extensions.citext
language sql
stable security definer
set search_path=''
as $function$
  select au.email
  from private.admin_sessions s
  join public.admin_users au on au.email=s.email
  where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at>now()
    and au.is_active
    and (
      s.session_scope <> 'kds'
      or s.client_fingerprint_hash is null
      or coalesce(current_setting('request.jwt.claim.role',true),'') <> 'anon'
      or s.client_fingerprint_hash = private.request_fingerprint_hash()
    )
  limit 1
$function$;
revoke all on function private.admin_email_from_token(text) from public, anon, authenticated;

create or replace function internal_rpc.admin_password_session_info(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_email extensions.citext; v_role text; v_name text; v_claim_role text:=coalesce(current_setting('request.jwt.claim.role',true),'');
begin
  select au.email,au.role,au.display_name into v_email,v_role,v_name
  from private.admin_sessions s join public.admin_users au on au.email=s.email
  where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at>now() and au.is_active
    and (s.session_scope<>'kds' or s.client_fingerprint_hash is null or v_claim_role<>'anon' or s.client_fingerprint_hash=private.request_fingerprint_hash())
  limit 1;
  if v_email is null then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'email',v_email::text,'display_name',coalesce(v_name,''),'role',v_role);
end
$function$;

create or replace function public.admin_password_session_info_bound(p_token text,p_fingerprint_hash text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_email extensions.citext; v_role text; v_name text;
begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' or p_fingerprint_hash is null or p_fingerprint_hash !~ '^[a-f0-9]{64}$' then return jsonb_build_object('ok',false); end if;
  select au.email,au.role,au.display_name into v_email,v_role,v_name
  from private.admin_sessions s join public.admin_users au on au.email=s.email
  where s.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    and s.expires_at>now() and au.is_active
    and (s.session_scope<>'kds' or s.client_fingerprint_hash is null or s.client_fingerprint_hash=p_fingerprint_hash)
  limit 1;
  if v_email is null then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'email',v_email::text,'display_name',coalesce(v_name,''),'role',v_role);
end
$function$;
revoke all on function public.admin_password_session_info_bound(text,text) from public, anon, authenticated;
grant execute on function public.admin_password_session_info_bound(text,text) to service_role;

create or replace function internal_rpc.admin_password_login(p_email text,p_password text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_email extensions.citext; v_role text; v_name text; v_hash text; v_token text; v_key text; v_rl jsonb; v_exp timestamptz;
  v_headers jsonb:='{}'::jsonb; v_origin text:=''; v_ip text:='unknown'; v_claim_role text:=coalesce(current_setting('request.jwt.claim.role',true),''); v_ip_key text; v_ip_rl jsonb;
  v_ttl interval:=interval '8 hours'; v_scope text:='admin'; v_fingerprint text:=null;
begin
  if p_email is null or p_password is null or length(p_password)>256 then return jsonb_build_object('ok',false,'error','invalid_credentials'); end if;
  begin v_headers:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then v_headers:='{}'::jsonb; end;
  if v_claim_role='anon' then
    v_origin:=coalesce(v_headers->>'origin','');
    if v_origin not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app','http://127.0.0.1:54321') then return jsonb_build_object('ok',false,'error','origin_not_allowed'); end if;
    if v_origin in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then v_ttl:=interval '4 hours'; v_scope:='kds'; v_fingerprint:=private.request_fingerprint_hash(); end if;
    v_ip:=split_part(coalesce(v_headers->>'cf-connecting-ip',v_headers->>'x-real-ip',v_headers->>'x-forwarded-for','unknown'),',',1);
    v_ip_key:=encode(extensions.digest(left(trim(v_ip),80)||'|'||lower(trim(p_email)),'sha256'),'hex');
    v_ip_rl:=public.security_consume_rate_limit('kds-legacy-login-ip',v_ip_key,6,900,900);
    if coalesce((v_ip_rl->>'allowed')::boolean,false) is not true then return jsonb_build_object('ok',false,'error','rate_limited','retry_after',coalesce((v_ip_rl->>'retry_after')::int,900)); end if;
  end if;
  v_key:=encode(extensions.digest(lower(trim(p_email)),'sha256'),'hex');
  v_rl:=public.security_consume_rate_limit('direct-login',v_key,6,900,900);
  if coalesce((v_rl->>'allowed')::boolean,false) is not true then return jsonb_build_object('ok',false,'error','rate_limited','retry_after',coalesce((v_rl->>'retry_after')::int,900)); end if;
  select au.email,au.role,au.display_name,ap.password_hash into v_email,v_role,v_name,v_hash from public.admin_users au join private.admin_passwords ap on ap.email=au.email where au.email=lower(trim(p_email))::extensions.citext and au.is_active limit 1;
  if v_hash is null or extensions.crypt(p_password,v_hash)<>v_hash then return jsonb_build_object('ok',false,'error','invalid_credentials'); end if;
  delete from public.security_rate_limits where bucket='direct-login' and key_hash=v_key;
  if v_claim_role='anon' and v_ip_key is not null then delete from public.security_rate_limits where bucket='kds-legacy-login-ip' and key_hash=v_ip_key; end if;
  delete from private.admin_sessions where expires_at<=now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex'); v_exp:=now()+v_ttl;
  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash) values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp,v_scope,v_fingerprint);
  delete from private.admin_sessions s where s.email=v_email and s.token_hash not in (select s2.token_hash from private.admin_sessions s2 where s2.email=v_email order by s2.expires_at desc limit 3);
  return jsonb_build_object('ok',true,'token',v_token,'email',v_email::text,'display_name',coalesce(v_name,''),'role',v_role,'expires_at',v_exp);
end
$function$;
