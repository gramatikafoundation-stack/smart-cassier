-- Integration maintenance: Admin global design writer + deterministic Smart Cashier.
-- Scope: runtime-asset normalization and release metadata only.
-- Application source changes are stored separately in Admin/KDS source files.

insert into public.runtime_asset_backups(name,content,updated_at)
select 'public:admin-cashier-v15-captured-pre-integration-normalize-20260918',content,now()
from public.runtime_asset_backups
where name='public:admin-cashier-v15-captured'
on conflict(name) do nothing;

-- Idempotent repair: only normalize the known four-brace drift to the validated three-brace form.
update public.runtime_asset_backups
set content=replace(
      content,
      '}}}}catch{}return response};document.addEventListener',
      '}}}catch{}return response};document.addEventListener'
    ),
    updated_at=case
      when strpos(content,'}}}}catch{}return response};document.addEventListener')>0 then now()
      else updated_at
    end
where name='public:admin-cashier-v15-captured'
  and strpos(content,'}}}}catch{}return response};document.addEventListener')>0;

update private.release_component_registry
set expected_version='v69',
    expected_sha256='77d18927db6f20823aecbaaff281ee3ef486bb940e64c29976788cc95412d7bd',
    deployment_ref='edge-version:v69',
    rollback_ref='edge-version:v68',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Integration maintenance: General and Theme publish through canonical versioned design_system; Admin consumes canonical global typography/theme; Smart Cashier has explicit route contract.'
where component_key='admin_renderer';

update private.production_change_control
set baseline_version='v69',
    baseline_sha256='77d18927db6f20823aecbaaff281ee3ef486bb940e64c29976788cc95412d7bd',
    updated_at=now()
where component='admin-renderer';

update private.release_component_registry
set expected_version='v35',
    expected_sha256='07021c64534499a17a5132635235e435f1965610d35a04c3960e6fa2358f9040',
    deployment_ref='edge-version:v35',
    rollback_ref='edge-version:v33',
    last_verified_at=now(),
    notes=coalesce(notes,'') ||
      case when coalesce(notes,'')='' then '' else ' ' end ||
      'Integration maintenance: deterministic Smart Cashier open contract. v34 excluded from rollback because it memoized a drifted malformed snapshot; v33 remains safe rollback.'
where component_key='admin_cashier_loader';

update private.production_change_control
set baseline_version='v35',
    baseline_sha256='07021c64534499a17a5132635235e435f1965610d35a04c3960e6fa2358f9040',
    updated_at=now()
where component='admin-cashier-loader';
