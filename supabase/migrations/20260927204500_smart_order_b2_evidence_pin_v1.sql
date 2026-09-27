-- SMART ORDER B2.4 evidence pin and explicit default-deny policy
begin;

do $$
begin
  if not exists(
    select 1 from pg_policies
    where schemaname='private'
      and tablename='kds_realtime_channels'
      and policyname='kds_realtime_channels_explicit_client_deny_b2'
  ) then
    create policy kds_realtime_channels_explicit_client_deny_b2
      on private.kds_realtime_channels
      for all
      to authenticated
      using (false)
      with check (false);
  end if;
end $$;

update private.platform_prototypes
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'freeze_state','candidate_b2',
      'b2_gate','passed',
      'b2_cutover_state','passed',
      'b2_health_contract','smart-order-master-runtime-security-v2',
      'b2_health_ok',true,
      'b2_runtime_source_sha','abc56e5fa3db530ae55feb84fd3cac6f9e41c9de',
      'b2_vercel_deployment','dpl_5YZjx6BkNkanxaf1djcACaXQiTm1',
      'b2_verified_at',now(),
      'b2_edge_artifacts',jsonb_build_object(
        'secure_api',jsonb_build_object(
          'version','v6',
          'sha256','8ac9fb58b974bebb1ddeb9fd7ee4f4a12c85ed1eeb5c4f052b75880cefa9983c',
          'rollback','v5'
        ),
        'admin_media_upload',jsonb_build_object(
          'version','v3',
          'sha256','537c05722bda48791e4a39aabd34a92df2692ef93207b8372f2dc80986b5183f',
          'rollback','v2'
        ),
        'admin_order_history',jsonb_build_object(
          'version','v3',
          'sha256','e06762359fb344751915575afc3c71b3381c82f66366de147ec7cb60d0f7043a',
          'rollback','v2'
        )
      ),
      'b2_residual_advisory',jsonb_build_object(
        'supabase_auth_leaked_password_protection','disabled_external_platform_setting',
        'application_admin_auth','custom_bcrypt_cost_12_plus_rate_limit_plus_fingerprint_binding',
        'blocking',false
      )
    ),
    updated_at=now()
where prototype_key='smart-order-sdb-platform-v1'
  and status='draft';

commit;
