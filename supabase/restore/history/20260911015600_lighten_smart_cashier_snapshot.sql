-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911015600  Name: lighten_smart_cashier_snapshot
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.smart_cashier_snapshot(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext;
  v_settings jsonb;
  v_menu jsonb;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  select jsonb_build_object(
    'business_name',s.business_name,
    'merchant_name',s.merchant_name,
    'qris_enabled',s.qris_enabled,
    'qris_image_url',s.qris_image_url,
    'updated_at',s.updated_at
  )
  into v_settings
  from public.site_settings s
  where s.id=1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,
    'name',m.name,
    'category',m.category,
    'price',m.price,
    'image_url',m.image_url,
    'is_available',m.is_available,
    'is_visible',m.is_visible,
    'display_order',m.display_order,
    'updated_at',m.updated_at
  ) order by m.display_order,m.name),'[]'::jsonb)
  into v_menu
  from public.menu_items m
  where m.is_visible;

  return jsonb_build_object(
    'ok',true,
    'actor',v_email::text,
    'settings',coalesce(v_settings,'{}'::jsonb),
    'menu',v_menu,
    'generated_at',now()
  );
end;
$function$;
