-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911061354  Name: harden_kds_direct_rpc_compat_wrappers
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_password_login(p_email text,p_password text)
returns jsonb
language plpgsql
set search_path=''
as $$
declare
  h jsonb := '{}'::jsonb;
  o text := '';
  r text := coalesce(current_setting('request.jwt.claim.role',true),'');
begin
  if r='anon' then
    begin h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then h:='{}'::jsonb; end;
    o:=coalesce(h->>'origin','');
    if o not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then
      return jsonb_build_object('ok',false,'error','origin_not_allowed');
    end if;
  end if;
  return internal_rpc.admin_password_login(p_email,p_password);
end $$;

create or replace function public.admin_password_logout(p_token text)
returns boolean
language plpgsql
set search_path=''
as $$
declare h jsonb:='{}'::jsonb; o text:=''; r text:=coalesce(current_setting('request.jwt.claim.role',true),''); begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then return true; end if;
  if r='anon' then
    begin h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then h:='{}'::jsonb; end;
    o:=coalesce(h->>'origin','');
    if o not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then return true; end if;
  end if;
  return internal_rpc.admin_password_logout(p_token);
end $$;

create or replace function public.admin_password_session_info(p_token text)
returns jsonb
language plpgsql
set search_path=''
as $$
declare h jsonb:='{}'::jsonb; o text:=''; r text:=coalesce(current_setting('request.jwt.claim.role',true),''); begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then return jsonb_build_object('ok',false); end if;
  if r='anon' then
    begin h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then h:='{}'::jsonb; end;
    o:=coalesce(h->>'origin','');
    if o not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then return jsonb_build_object('ok',false,'error','origin_not_allowed'); end if;
  end if;
  return internal_rpc.admin_password_session_info(p_token);
end $$;

create or replace function public.kds_snapshot(p_token text)
returns jsonb
language plpgsql
set search_path=''
as $$
declare h jsonb:='{}'::jsonb; o text:=''; r text:=coalesce(current_setting('request.jwt.claim.role',true),''); begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if r='anon' then
    begin h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then h:='{}'::jsonb; end;
    o:=coalesce(h->>'origin','');
    if o not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then return jsonb_build_object('ok',false,'error','origin_not_allowed'); end if;
  end if;
  return internal_rpc.kds_snapshot(p_token);
end $$;

create or replace function public.kds_update_order(p_token text,p_id uuid,p_action text)
returns jsonb
language plpgsql
set search_path=''
as $$
declare h jsonb:='{}'::jsonb; o text:=''; r text:=coalesce(current_setting('request.jwt.claim.role',true),''); begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_action not in ('verify_start','verify_payment','reject_payment','start','finish','ready','complete','reopen','print') then return jsonb_build_object('ok',false,'error','invalid_action'); end if;
  if r='anon' then
    begin h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then h:='{}'::jsonb; end;
    o:=coalesce(h->>'origin','');
    if o not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then return jsonb_build_object('ok',false,'error','origin_not_allowed'); end if;
  end if;
  return internal_rpc.kds_update_order(p_token,p_id,p_action);
end $$;

create or replace function public.kds_set_availability(p_token text,p_id text,p_available boolean,p_note text default '')
returns jsonb
language plpgsql
set search_path=''
as $$
declare h jsonb:='{}'::jsonb; o text:=''; r text:=coalesce(current_setting('request.jwt.claim.role',true),''); begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_id is null or length(p_id)>120 then return jsonb_build_object('ok',false,'error','invalid_menu'); end if;
  if r='anon' then
    begin h:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb); exception when others then h:='{}'::jsonb; end;
    o:=coalesce(h->>'origin','');
    if o not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then return jsonb_build_object('ok',false,'error','origin_not_allowed'); end if;
  end if;
  return internal_rpc.kds_set_availability(p_token,p_id,p_available,left(coalesce(p_note,''),160));
end $$;

grant execute on function public.admin_password_login(text,text) to anon,service_role;
grant execute on function public.admin_password_logout(text) to anon,service_role;
grant execute on function public.admin_password_session_info(text) to anon,service_role;
grant execute on function public.kds_snapshot(text) to anon,service_role;
grant execute on function public.kds_update_order(text,uuid,text) to anon,service_role;
grant execute on function public.kds_set_availability(text,text,boolean,text) to anon,service_role;
revoke execute on all functions in schema internal_rpc from authenticated;
revoke usage on schema internal_rpc from authenticated;
