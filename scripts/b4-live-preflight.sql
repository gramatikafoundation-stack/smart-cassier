-- B4.1 read-only live preflight before clone foundation is applied.

do $$
declare
  v_status text;
begin
  select status into v_status
  from private.platform_prototypes
  where prototype_key='smart-order-sdb-platform-v1'
    and metadata->>'b3_gate'='passed'
  limit 1;

  if v_status is distinct from 'draft' then raise exception 'b4_candidate_must_be_draft'; end if;
  if not coalesce((private.release_preflight_status()->>'ok')::boolean,false)
    then raise exception 'b4_live_release_preflight_failed'; end if;
  if not coalesce((private.release_engineering_status()->>'ok')::boolean,false)
    then raise exception 'b4_live_release_engineering_failed'; end if;
  if exists(select 1 from private.master_template_snapshots where prototype_key='smart-order-sdb-platform-v1')
    then raise exception 'b4_snapshot_already_exists'; end if;
end $$;

select jsonb_build_object(
  'ok',true,
  'contract','smart-order-b4-clone-foundation-live-preflight-v1',
  'candidate_status',(select status from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1'),
  'b3_gate',(select metadata->>'b3_gate' from private.platform_prototypes where prototype_key='smart-order-sdb-platform-v1'),
  'release_preflight',private.release_preflight_status(),
  'release_engineering',private.release_engineering_status(),
  'snapshot_absent',not exists(select 1 from private.master_template_snapshots where prototype_key='smart-order-sdb-platform-v1')
) b4_live_preflight;
