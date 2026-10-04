-- SMART ORDER Admin settings: transaction payment and language
-- Applied to tenant-aware runtime config on 2026-10-04.
create or replace function public.admin_console_update_settings_tenant(
  p_tenant_id uuid,
  p_token text,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_email extensions.citext;
  v_patch jsonb:='{}'::jsonb;
  v_settings jsonb;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_patch is null or jsonb_typeof(p_patch)<>'object' then
    return jsonb_build_object('ok',false,'error','invalid_patch');
  end if;

  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
    into v_patch
  from jsonb_each(p_patch)
  where key=any(array[
    'business_name','welcome_text','motto','hero_image_url','photo_position','content_position',
    'content_width','element_order','theme_preset','color_outer','color_panel','color_primary',
    'color_accent','color_text','color_muted','typography','merchant_name','payment_instructions',
    'qris_image_url','qris_enabled','admin_design','kds_design','design_system',
    'require_table_qr_signature','google_sheet_url',
    'transaction_payment','language','transaction_settings','language_settings'
  ]);

  update private.tenant_runtime_config c
  set business_name=case when v_patch?'business_name'
        then left(coalesce(v_patch->>'business_name',''),120) else c.business_name end,
      merchant_name=case when v_patch?'merchant_name'
        then left(coalesce(v_patch->>'merchant_name',''),120) else c.merchant_name end,
      qris_asset=case when v_patch?'qris_image_url'
        then nullif(left(coalesce(v_patch->>'qris_image_url',''),1000),'') else c.qris_asset end,
      require_table_qr_signature=case when v_patch?'require_table_qr_signature'
        then coalesce((v_patch->>'require_table_qr_signature')::boolean,false)
        else c.require_table_qr_signature end,
      settings=coalesce(c.settings,'{}'::jsonb)||v_patch,
      updated_at=now()
  where c.tenant_id=p_tenant_id and c.enabled;

  if not found then return jsonb_build_object('ok',false,'error','tenant_unavailable'); end if;
  perform private.sync_tenant_public_settings_projection(p_tenant_id);
  v_settings:=private.tenant_settings_json(p_tenant_id);
  return jsonb_build_object('ok',true,'tenant_id',p_tenant_id,'settings',v_settings);
exception when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end
$function$;
