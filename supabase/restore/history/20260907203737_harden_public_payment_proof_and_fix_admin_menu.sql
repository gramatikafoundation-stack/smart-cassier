-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907203737  Name: harden_public_payment_proof_and_fix_admin_menu
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

alter table public.orders
  add column if not exists payment_proof_sha256 text,
  add column if not exists proof_check_status text not null default 'review',
  add column if not exists proof_merchant_match boolean,
  add column if not exists proof_amount_match boolean,
  add column if not exists proof_date_match boolean,
  add column if not exists proof_time_match boolean,
  add column if not exists proof_amount_detected integer,
  add column if not exists proof_date_detected text,
  add column if not exists proof_time_detected text,
  add column if not exists proof_checked_at timestamptz;

create unique index if not exists orders_payment_proof_sha256_unique
  on public.orders(payment_proof_sha256)
  where payment_proof_sha256 is not null and payment_proof_sha256 <> '';

create or replace function public.admin_console_save_menu(p_token text, p_menu jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email extensions.citext;
  v_id text;
  v_name text;
  v_row public.menu_items%rowtype;
  v_image text;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if p_menu is null or jsonb_typeof(p_menu) <> 'object' then return jsonb_build_object('ok',false,'error','invalid_menu'); end if;

  v_name := left(trim(coalesce(p_menu->>'name','')),120);
  if length(v_name) < 1 then return jsonb_build_object('ok',false,'error','name_required'); end if;
  v_id := left(trim(coalesce(p_menu->>'id','')),160);
  if v_id='' then v_id := 'menu-' || replace(gen_random_uuid()::text,'-',''); end if;
  v_image := left(coalesce(p_menu->>'image_url',''),1000);

  insert into public.menu_items(
    id,name,category,price,description,image_url,is_favorite,is_visible,
    is_available,display_order,updated_by,updated_at
  )
  values(
    v_id,
    v_name,
    case when coalesce(p_menu->>'category','') in ('Nasi','Lauk','Minuman','Jus Buah') then p_menu->>'category' else 'Lauk' end,
    greatest(0,coalesce((p_menu->>'price')::integer,0)),
    left(coalesce(p_menu->>'description',''),600),
    coalesce(v_image,''),
    coalesce((p_menu->>'is_favorite')::boolean,false),
    coalesce((p_menu->>'is_visible')::boolean,true),
    coalesce((p_menu->>'is_available')::boolean,true),
    greatest(0,coalesce((p_menu->>'display_order')::integer,999)),
    null,
    now()
  )
  on conflict (id) do update set
    name=excluded.name,
    category=excluded.category,
    price=excluded.price,
    description=excluded.description,
    image_url=excluded.image_url,
    is_favorite=excluded.is_favorite,
    is_visible=excluded.is_visible,
    is_available=excluded.is_available,
    display_order=excluded.display_order,
    updated_by=null,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object('ok',true,'menu',to_jsonb(v_row));
exception when others then
  return jsonb_build_object('ok',false,'error',sqlerrm);
end;
$$;

create or replace function public.admin_console_update_order(p_token text, p_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email extensions.citext;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  return jsonb_build_object('ok',false,'error','payment_verification_is_kds_responsibility');
end;
$$;

grant execute on function public.admin_console_save_menu(text,jsonb) to anon, authenticated;
grant execute on function public.admin_console_update_order(text,uuid,text) to anon, authenticated;
