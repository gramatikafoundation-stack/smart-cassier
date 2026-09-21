-- ADMIN Batch 3: repair cashier runtime snapshot syntax and align release registry.
-- Scope: one-character JavaScript syntax repair + release metadata only.
-- Root cause: the captured v15 cashier snapshot had one missing closing brace
-- in the window.fetch receipt wrapper: "}}catch{}" instead of "}}}catch{}".

insert into public.runtime_asset_backups(name,content,updated_at)
select 'public:admin-cashier-v15-captured-pre-b3-syntaxfix-20260918',content,now()
from public.runtime_asset_backups
where name='public:admin-cashier-v15-captured'
on conflict(name) do nothing;

update public.runtime_asset_backups
set content=replace(
      content,
      '}}catch{}return response};document.addEventListener',
      '}}}catch{}return response};document.addEventListener'
    ),
    updated_at=now()
where name='public:admin-cashier-v15-captured'
  and (length(content)-length(replace(content,'}}catch{}return response};document.addEventListener','')))
      / length('}}catch{}return response};document.addEventListener') = 1;

update private.release_component_registry
set expected_version='v33',
    expected_sha256='616a51a45ba384d3150b15aa6c3dbfdde1ec1aecdae94afaed1a925a0d4d1c1b',
    deployment_ref='edge-version:v33',
    rollback_ref='edge-version:v32',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Batch 3 final browser qualification: fixed missing closing brace in captured cashier receipt wrapper. Chromium desktop/mobile pageErrors returned to zero; v32 retained as immediate rollback.'
where component_key='admin_cashier_loader';

update private.production_change_control
set baseline_version='v33',
    baseline_sha256='616a51a45ba384d3150b15aa6c3dbfdde1ec1aecdae94afaed1a925a0d4d1c1b',
    updated_at=now()
where component='admin-cashier-loader';
