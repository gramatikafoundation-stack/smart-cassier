-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909172450  Name: allow_database_registry_rpc
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.admin_design_system_registry(p_token text,p_site text,p_page text) returns jsonb language plpgsql security definer set search_path=public as $$
declare em extensions.citext; rows jsonb;
begin
 em:=private.admin_email_from_token(p_token); if em is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
 if p_site not in ('public','admin','kds','database') then return jsonb_build_object('ok',false,'error','site_invalid'); end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.element_id,'label',r.label,'sort',r.sort_order) order by r.sort_order,r.label),'[]'::jsonb) into rows from public.design_element_registry r where r.site=p_site and r.page=p_page;
 return jsonb_build_object('ok',true,'elements',rows);
end $$;
revoke all on function public.admin_design_system_registry(text,text,text) from public,anon,authenticated;
grant execute on function public.admin_design_system_registry(text,text,text) to service_role;
