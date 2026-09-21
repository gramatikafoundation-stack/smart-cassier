-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909114332  Name: strengthen_custom_admin_auth
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function private.admin_password_is_strong(p text) returns boolean language sql immutable set search_path='' as $$
select p is not null and length(p) between 12 and 128
 and p ~ '[A-Z]' and p ~ '[a-z]' and p ~ '[0-9]' and p ~ '[^A-Za-z0-9]'
 and lower(p) !~ '(password|qwerty|123456|admin123|letmein|welcome123)';
$$;

create or replace function public.admin_password_login(p_email text,p_password text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email extensions.citext; v_role text; v_name text; v_hash text; v_token text; v_key text; v_rl jsonb; v_exp timestamptz;
begin
 if p_email is null or p_password is null or length(p_password)>256 then return jsonb_build_object('ok',false,'error','invalid_credentials'); end if;
 v_key:=encode(extensions.digest(lower(trim(p_email)),'sha256'),'hex');
 v_rl:=public.security_consume_rate_limit('direct-login',v_key,6,900,900);
 if coalesce((v_rl->>'allowed')::boolean,false) is not true then return jsonb_build_object('ok',false,'error','rate_limited','retry_after',coalesce((v_rl->>'retry_after')::int,900)); end if;
 select au.email,au.role,au.display_name,ap.password_hash into v_email,v_role,v_name,v_hash from public.admin_users au join private.admin_passwords ap on ap.email=au.email where au.email=lower(trim(p_email))::extensions.citext and au.is_active limit 1;
 if v_hash is null or extensions.crypt(p_password,v_hash)<>v_hash then return jsonb_build_object('ok',false,'error','invalid_credentials'); end if;
 delete from public.security_rate_limits where bucket='direct-login' and key_hash=v_key;
 delete from private.admin_sessions where expires_at<=now();
 v_token:=encode(extensions.gen_random_bytes(32),'hex'); v_exp:=now()+interval '8 hours';
 insert into private.admin_sessions(token_hash,email,expires_at) values(encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_exp);
 delete from private.admin_sessions s where s.email=v_email and s.token_hash not in (select s2.token_hash from private.admin_sessions s2 where s2.email=v_email order by s2.expires_at desc limit 3);
 return jsonb_build_object('ok',true,'token',v_token,'email',v_email::text,'display_name',coalesce(v_name,''),'role',v_role,'expires_at',v_exp);
end $$;

create or replace function public.admin_password_change(p_token text,p_current_password text,p_new_password text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_email extensions.citext; v_hash text;
begin
 if not private.admin_password_is_strong(p_new_password) then return jsonb_build_object('ok',false,'error','new_password_weak'); end if;
 select s.email into v_email from private.admin_sessions s join public.admin_users au on au.email=s.email and au.is_active where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and s.expires_at>now() limit 1;
 if v_email is null then return jsonb_build_object('ok',false,'error','session_invalid'); end if;
 select password_hash into v_hash from private.admin_passwords where email=v_email;
 if v_hash is null or extensions.crypt(coalesce(p_current_password,''),v_hash)<>v_hash then return jsonb_build_object('ok',false,'error','current_password_invalid'); end if;
 update private.admin_passwords set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),updated_at=now() where email=v_email;
 delete from private.admin_sessions where email=v_email and token_hash<>encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.admin_password_set_for_admin(p_token text,p_email text,p_new_password text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor extensions.citext; v_target extensions.citext;
begin
 if not private.admin_password_is_strong(p_new_password) then return jsonb_build_object('ok',false,'error','new_password_weak'); end if;
 select au.email into v_actor from private.admin_sessions s join public.admin_users au on au.email=s.email where s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') and s.expires_at>now() and au.is_active and au.role='superadmin' limit 1;
 if v_actor is null then return jsonb_build_object('ok',false,'error','forbidden'); end if;
 select email into v_target from public.admin_users where email=lower(trim(p_email))::extensions.citext and is_active limit 1;
 if v_target is null then return jsonb_build_object('ok',false,'error','admin_not_found'); end if;
 insert into private.admin_passwords(email,password_hash,updated_at) values(v_target,extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),now()) on conflict(email) do update set password_hash=excluded.password_hash,updated_at=now();
 delete from private.admin_sessions where email=v_target;
 return jsonb_build_object('ok',true);
end $$;
