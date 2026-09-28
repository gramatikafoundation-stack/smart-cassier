create or replace function provision_tenant(
  p_platform_key text,p_expected_key text,p_tenant_slug text,p_tenant_name text,p_outlet_code text,p_outlet_name text,
  p_owner_email text,p_owner_name text,p_owner_password text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid; v_outlet uuid; v_user uuid;
begin
  if p_platform_key is null or p_expected_key is null or p_platform_key<>p_expected_key then raise exception 'invalid platform key'; end if;
  insert into tenants(slug,name) values(lower(trim(p_tenant_slug)),trim(p_tenant_name)) returning id into v_tenant;
  insert into outlets(tenant_id,code,name) values(v_tenant,upper(trim(p_outlet_code)),trim(p_outlet_name)) returning id into v_outlet;
  insert into app_users(tenant_id,outlet_id,email,display_name,password_hash,role)
  values(v_tenant,v_outlet,lower(trim(p_owner_email)),trim(p_owner_name),crypt(p_owner_password,gen_salt('bf',12)),'OWNER')
  returning id into v_user;
  insert into settings(tenant_id,outlet_id,payload) values(v_tenant,v_outlet,'{}'::jsonb);
  insert into activity_logs(tenant_id,outlet_id,actor_user_id,action,entity_type,entity_id,details)
  values(v_tenant,v_outlet,v_user,'TENANT_PROVISION','TENANT',v_tenant::text,jsonb_build_object('slug',lower(trim(p_tenant_slug))));
  return jsonb_build_object('tenant_id',v_tenant,'outlet_id',v_outlet,'user_id',v_user);
end $$;
revoke all on function provision_tenant(text,text,text,text,text,text,text,text,text) from public;
grant execute on function provision_tenant(text,text,text,text,text,text,text,text,text) to smart_cashier_app;
