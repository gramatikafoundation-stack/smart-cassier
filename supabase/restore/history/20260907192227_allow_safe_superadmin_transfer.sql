-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260907192227  Name: allow_safe_superadmin_transfer
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create or replace function public.transfer_superadmin(p_new_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_email text;
  target_email text := lower(trim(coalesce(p_new_email,'')));
begin
  select lower(email) into current_email from auth.users where id = auth.uid();
  if current_email is null then raise exception 'Sesi tidak valid.'; end if;
  if not exists (
    select 1 from public.admin_users
    where lower(email::text)=current_email and role='superadmin' and is_active=true
  ) then raise exception 'Hanya superadmin aktif yang dapat mengalihkan otoritas.'; end if;
  if target_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Email superadmin baru tidak valid.'; end if;
  if not exists (select 1 from auth.users where lower(email)=target_email) then
    raise exception 'Akun login untuk email tujuan belum tersedia. Buat akun login terlebih dahulu.';
  end if;
  insert into public.admin_users(email,display_name,role,is_active,is_protected,created_by)
  values(target_email,split_part(target_email,'@',1),'superadmin',true,true,auth.uid())
  on conflict (email) do update set role='superadmin',is_active=true,is_protected=true;
  if target_email <> current_email then
    update public.admin_users set role='admin',is_protected=false where lower(email::text)=current_email;
  end if;
  return jsonb_build_object('ok',true,'previous_superadmin',current_email,'new_superadmin',target_email);
end;
$$;
revoke all on function public.transfer_superadmin(text) from public;
grant execute on function public.transfer_superadmin(text) to authenticated;
