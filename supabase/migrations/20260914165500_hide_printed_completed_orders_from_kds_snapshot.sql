create or replace function public.kds_snapshot(p_token text)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  h jsonb := '{}'::jsonb;
  o text := '';
  r text := coalesce(current_setting('request.jwt.claim.role',true),'');
  v_result jsonb;
  v_orders jsonb;
begin
  if p_token is null or p_token !~* '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  if r='anon' then
    begin
      h := coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'::jsonb);
    exception when others then
      h := '{}'::jsonb;
    end;
    o := coalesce(h->>'origin','');
    if o not in ('https://rohmat-kds-printer.vercel.app','https://rohmat-kds-printer-gramatikafoundation-3204.vercel.app') then
      return jsonb_build_object('ok',false,'error','origin_not_allowed');
    end if;
  end if;

  v_result := internal_rpc.kds_snapshot(p_token);
  if coalesce(v_result->>'ok','false') <> 'true' then
    return v_result;
  end if;

  select coalesce(jsonb_agg(item),'[]'::jsonb)
    into v_orders
  from jsonb_array_elements(coalesce(v_result->'orders','[]'::jsonb)) item
  where not (
    coalesce(item->>'order_status','') = 'completed'
    and coalesce(nullif(item->>'kitchen_print_count','')::integer,0) > 0
  );

  return jsonb_set(v_result,'{orders}',v_orders,true);
end
$function$;
