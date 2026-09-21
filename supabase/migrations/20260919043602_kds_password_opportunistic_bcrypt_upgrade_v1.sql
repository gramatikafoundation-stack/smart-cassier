create or replace function public.kds_bff_login_bound(
  p_email text,
  p_password text,
  p_fingerprint_hash text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_role text;
  v_name text;
  v_hash text;
  v_token text;
  v_exp timestamptz;
begin
  if p_email is null or p_password is null or length(p_password)>256 then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;
  if p_fingerprint_hash is null or p_fingerprint_hash !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false,'error','invalid_fingerprint');
  end if;

  select au.email,au.role,au.display_name,ap.password_hash
    into v_email,v_role,v_name,v_hash
  from public.admin_users au
  join private.admin_passwords ap on ap.email=au.email
  where au.email=lower(trim(p_email))::extensions.citext
    and au.is_active
  limit 1;

  if v_hash is null or extensions.crypt(p_password,v_hash)<>v_hash then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;

  if v_hash ~ '^\$2[aby]\$[0-9]{2}\$'
     and split_part(v_hash,'$',3)::int < 12 then
    update private.admin_passwords
       set password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',12)),
           updated_at=now()
     where email=v_email;
  end if;

  delete from private.admin_sessions where expires_at<=now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_exp:=now()+interval '4 hours';

  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash)
  values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp,'kds',p_fingerprint_hash);

  delete from private.admin_sessions s
  where s.email=v_email
    and s.session_scope='kds'
    and s.token_hash not in (
      select s2.token_hash
      from private.admin_sessions s2
      where s2.email=v_email and s2.session_scope='kds'
      order by s2.expires_at desc
      limit 3
    );

  return jsonb_build_object('ok',true,'token',v_token,'email',v_email::text,'display_name',coalesce(v_name,''),'role',v_role,'expires_at',v_exp,'session_scope','kds');
end
$$;

create or replace function internal_rpc.admin_password_login(p_email text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext; v_role text; v_name text; v_hash text; v_token text; v_key text; v_rl jsonb; v_exp timestamptz;
  v_headers jsonb:='{}'::jsonb; v_origin text:=''; v_ip text:='unknown'; v_claim_role text:=coalesce(current_setting('request.jwt.claim.role',true),''); v_ip_key text; v_ip_rl jsonb;
  v_ttl interval:=interval '8 hours'; v_scope text:='admin'; v_fingerprint text:=null;
begin
  if p_email is null or p_password is null or length(p_password)>256 then return jsonb_build_object('ok',false,'error','invalid_credentials'); end if;
  begin v_headers:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then v_headers:='{}'::jsonb; end;
  if v_claim_role='anon' then
    v_origin:=coalesce(v_headers->>'origin','');
    if v_origin not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app','https://yybhpmjuywjxqurrrrxl.supabase.co') then return jsonb_build_object('ok',false,'error','origin_not_allowed'); end if;
    if v_origin in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then
      v_ttl:=interval '4 hours';
      v_scope:='kds';
      v_fingerprint:=private.request_device_fingerprint_hash();
    end if;
    v_ip:=split_part(coalesce(v_headers->>'cf-connecting-ip',v_headers->>'x-real-ip',v_headers->>'x-forwarded-for','unknown'),',',1);
    v_ip_key:=encode(extensions.digest(left(trim(v_ip),80)||'|'||lower(trim(p_email)),'sha256'),'hex');
    v_ip_rl:=public.security_consume_rate_limit('kds-legacy-login-ip',v_ip_key,6,900,900);
    if coalesce((v_ip_rl->>'allowed')::boolean,false) is not true then return jsonb_build_object('ok',false,'error','rate_limited','retry_after',coalesce((v_ip_rl->>'retry_after')::int,900)); end if;
  end if;
  v_key:=encode(extensions.digest(lower(trim(p_email)),'sha256'),'hex');
  v_rl:=public.security_consume_rate_limit('direct-login',v_key,6,900,900);
  if coalesce((v_rl->>'allowed')::boolean,false) is not true then return jsonb_build_object('ok',false,'error','rate_limited','retry_after',coalesce((v_rl->>'retry_after')::int,900)); end if;
  select au.email,au.role,au.display_name,ap.password_hash into v_email,v_role,v_name,v_hash
  from public.admin_users au join private.admin_passwords ap on ap.email=au.email
  where au.email=lower(trim(p_email))::extensions.citext and au.is_active limit 1;
  if v_hash is null or extensions.crypt(p_password,v_hash)<>v_hash then return jsonb_build_object('ok',false,'error','invalid_credentials'); end if;

  if v_hash ~ '^\$2[aby]\$[0-9]{2}\$'
     and split_part(v_hash,'$',3)::int < 12 then
    update private.admin_passwords
       set password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',12)),
           updated_at=now()
     where email=v_email;
  end if;

  delete from public.security_rate_limits where bucket='direct-login' and key_hash=v_key;
  if v_claim_role='anon' and v_ip_key is not null then delete from public.security_rate_limits where bucket='kds-legacy-login-ip' and key_hash=v_ip_key; end if;
  delete from private.admin_sessions where expires_at<=now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex'); v_exp:=now()+v_ttl;
  insert into private.admin_sessions(token_hash,email,expires_at,session_scope,client_fingerprint_hash)
  values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp,v_scope,v_fingerprint);
  delete from private.admin_sessions s
  where s.email=v_email
    and s.session_scope=v_scope
    and s.token_hash not in (
      select s2.token_hash from private.admin_sessions s2
      where s2.email=v_email and s2.session_scope=v_scope
      order by s2.expires_at desc
      limit 3
    );
  return jsonb_build_object('ok',true,'token',v_token,'email',v_email::text,'display_name',coalesce(v_name,''),'role',v_role,'expires_at',v_exp);
end
$$;
