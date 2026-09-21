create or replace function internal_rpc.kds_set_availability(p_token text, p_id text, p_available boolean, p_note text default ''::text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_email extensions.citext;
  v_row public.menu_items%rowtype;
  v_next boolean;
begin
  v_email := private.admin_email_from_token(p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  select * into v_row
  from public.menu_items
  where id=p_id
  for update;

  if v_row.id is null then
    return jsonb_build_object('ok',false,'error','menu_not_found');
  end if;

  v_next := not coalesce(v_row.is_available,false);

  update public.menu_items
  set is_available=v_next,
      availability_note=case when v_next then '' else 'Habis' end,
      availability_updated_at=now(),
      updated_at=now(),
      updated_by=null
  where id=p_id
  returning * into v_row;

  return jsonb_build_object(
    'ok',true,
    'menu',to_jsonb(v_row),
    'toggle_applied',true,
    'effective_available',v_row.is_available
  );
end;
$function$;
