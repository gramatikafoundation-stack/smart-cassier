-- Batch 4 KDS: realtime invalidation foundation.
-- Data payloads remain behind the existing cookie-bound KDS BFF; Realtime carries invalidation only.

create table if not exists private.kds_realtime_channels (
  tenant_id uuid primary key references private.platform_tenants(id) on delete cascade,
  topic text not null unique check (topic ~ '^kds:[a-f0-9]{32}$'),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  rotated_at timestamptz not null default now()
);

revoke all on table private.kds_realtime_channels from public, anon, authenticated;

insert into private.kds_realtime_channels(tenant_id,topic,enabled)
select 'd8bb901c-7399-485b-8743-b319fde148ac'::uuid,
       'kds:'||replace(gen_random_uuid()::text,'-',''),
       true
where exists (
  select 1 from private.platform_tenants
  where id='d8bb901c-7399-485b-8743-b319fde148ac'::uuid
)
on conflict (tenant_id) do nothing;

create or replace function private.kds_realtime_broadcast()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_tenant uuid;
  v_topic text;
  v_kind text;
begin
  v_tenant := case when tg_op='DELETE' then old.tenant_id else new.tenant_id end;
  if v_tenant is null then
    return case when tg_op='DELETE' then old else new end;
  end if;

  select c.topic into v_topic
  from private.kds_realtime_channels c
  where c.tenant_id=v_tenant and c.enabled;

  if v_topic is not null then
    v_kind := case when tg_table_name='menu_items' then 'menu' else 'orders' end;
    perform realtime.send(
      jsonb_build_object(
        'kind',v_kind,
        'operation',lower(tg_op),
        'at',clock_timestamp()
      ),
      'kds_change',
      v_topic,
      false
    );
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$$;

revoke all on function private.kds_realtime_broadcast() from public, anon, authenticated;

drop trigger if exists trg_kds_realtime_orders on public.orders;
create trigger trg_kds_realtime_orders
after insert or update or delete on public.orders
for each row execute function private.kds_realtime_broadcast();

drop trigger if exists trg_kds_realtime_menu_items on public.menu_items;
create trigger trg_kds_realtime_menu_items
after insert or update or delete on public.menu_items
for each row execute function private.kds_realtime_broadcast();

create or replace function public.kds_realtime_ticket_tenant(p_tenant_id uuid,p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email extensions.citext;
  v_topic text;
begin
  v_email:=private.tenant_admin_email_from_token(p_tenant_id,p_token);
  if v_email is null then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;

  select c.topic into v_topic
  from private.kds_realtime_channels c
  where c.tenant_id=p_tenant_id and c.enabled;

  if v_topic is null then
    return jsonb_build_object('ok',false,'error','realtime_unavailable');
  end if;

  return jsonb_build_object(
    'ok',true,
    'tenant_id',p_tenant_id,
    'topic',v_topic,
    'event','kds_change'
  );
end
$$;

revoke all on function public.kds_realtime_ticket_tenant(uuid,text) from public, anon, authenticated;
grant execute on function public.kds_realtime_ticket_tenant(uuid,text) to service_role;
