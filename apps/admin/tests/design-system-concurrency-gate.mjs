import assert from 'node:assert/strict';
import fs from 'node:fs';

const admin=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-render/index.ts',import.meta.url),'utf8');
const migration=fs.readFileSync(new URL('../../../supabase/migrations/20261005030000_design_system_optimistic_concurrency_v1.sql',import.meta.url),'utf8');
const preserve=fs.readFileSync(new URL('../../../supabase/migrations/20261006070000_design_system_preserve_missing_scopes_v1.sql',import.meta.url),'utf8');

assert.ok(admin.includes('expectedPublishedVersionId'),'Admin full publish must carry expected published version');
assert.ok(migration.includes('for update'),'Design System publish must lock tenant state');
assert.ok(migration.includes('design_system_expected_version_required'),'Published writes must require an expected version');
assert.ok(migration.includes('design_system_conflict'),'Stale writes must return a conflict');
assert.ok(migration.includes("p_payload-'expectedPublishedVersionId'"),'Expected version must not persist into published payload');
assert.ok(migration.includes("'expectedPublishedVersionId'"),'Server-side scoped publishes must inherit the current version');

assert.ok(preserve.includes("v_payload:=coalesce(v_state->'published','{}'::jsonb) || v_payload"),
  'Partial published writes must preserve omitted top-level Design System scopes');
assert.ok(preserve.includes("if p_kind='published' then"),
  'Preservation must apply to normal publish writes');
assert.ok(preserve.includes("Rollback must remain an exact restore"),
  'Rollback semantics must remain exact and documented');
assert.ok(preserve.includes('system-repair-preserve-scopes-v1'),
  'Known lost General/element overrides must have a surgical recovery step');

console.log('DESIGN_SYSTEM_CONCURRENCY_GATE_PASS=1');
