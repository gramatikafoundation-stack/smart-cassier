-- Golden Master v12: canonical 19-locale contract.
-- Default locale remains id-ID; this only removes list drift across DB/runtime/admin/shared i18n.

do $$
declare
  v_lang jsonb := jsonb_build_object(
    'default','id-ID',
    'available',jsonb_build_array(
      'id-ID','en-US','ms-MY','ar-SA','zh-CN','zh-TW','ja-JP','ko-KR','hi-IN',
      'th-TH','vi-VN','fr-FR','de-DE','es-ES','pt-BR','it-IT','tr-TR','ru-RU','nl-NL'
    )
  );
  v_tenant uuid;
begin
  update public.site_settings
  set language_settings=v_lang,
      updated_at=now()
  where id=1;

  update private.tenant_runtime_config
  set settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{language_settings}',v_lang,true),
      updated_at=now()
  where enabled;

  for v_tenant in
    select tenant_id from private.tenant_runtime_config where enabled
  loop
    perform private.sync_tenant_public_settings_projection(v_tenant);
  end loop;

  perform private.enqueue_sheet_reconciliation();
end $$;

create or replace function private.sync_tenant_public_settings_projection(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare s jsonb; c private.tenant_runtime_config%rowtype;
begin
  select * into c from private.tenant_runtime_config where tenant_id=p_tenant_id and enabled;
  if c.tenant_id is null then raise exception 'tenant_unavailable'; end if;
  s:=private.tenant_settings_json(p_tenant_id);
  insert into public.tenant_site_settings_public_v1(
    tenant_id,business_name,welcome_text,motto,hero_image_url,public_url,
    merchant_name,payment_instructions,qris_image_url,qris_enabled,
    require_table_qr_signature,typography,design_system,transaction_settings,language_settings,updated_at
  ) values(
    p_tenant_id,c.business_name,coalesce(s->>'welcome_text',''),coalesce(s->>'motto',''),nullif(s->>'hero_image_url',''),
    c.public_origin,c.merchant_name,coalesce(s->>'payment_instructions',''),coalesce(c.qris_asset,nullif(s->>'qris_image_url','')),
    coalesce((s->>'qris_enabled')::boolean,false),c.require_table_qr_signature,coalesce(s->'typography','{}'::jsonb),
    coalesce(s->'design_system','{}'::jsonb),
    coalesce(s->'transaction_settings','{"tax":{"enabled":false,"mode":"percent","value":0,"label":"Pajak"},"charge":{"enabled":false,"mode":"percent","value":0,"label":"Charge"}}'::jsonb),
    coalesce(s->'language_settings','{"default":"id-ID","available":["id-ID","en-US","ms-MY","ar-SA","zh-CN","zh-TW","ja-JP","ko-KR","hi-IN","th-TH","vi-VN","fr-FR","de-DE","es-ES","pt-BR","it-IT","tr-TR","ru-RU","nl-NL"]}'::jsonb),
    c.updated_at
  )
  on conflict(tenant_id) do update set
    business_name=excluded.business_name,welcome_text=excluded.welcome_text,motto=excluded.motto,
    hero_image_url=excluded.hero_image_url,public_url=excluded.public_url,merchant_name=excluded.merchant_name,
    payment_instructions=excluded.payment_instructions,qris_image_url=excluded.qris_image_url,qris_enabled=excluded.qris_enabled,
    require_table_qr_signature=excluded.require_table_qr_signature,typography=excluded.typography,design_system=excluded.design_system,
    transaction_settings=excluded.transaction_settings,language_settings=excluded.language_settings,updated_at=excluded.updated_at;
end
$function$;
