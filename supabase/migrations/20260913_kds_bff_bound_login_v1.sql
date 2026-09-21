create or replace function public.kds_bff_login_bound(p_email text, p_password text, p_fingerprint_hash text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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
$function$;

revoke all on function public.kds_bff_login_bound(text,text,text) from public, anon, authenticated;
grant execute on function public.kds_bff_login_bound(text,text,text) to service_role;
