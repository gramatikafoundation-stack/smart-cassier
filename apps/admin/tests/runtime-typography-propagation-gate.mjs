import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-render/index.ts',import.meta.url),'utf8');

assert.ok(src.includes("cache:'no-store'"),'Admin bootstrap must avoid stale Design System cache');
assert.ok(src.includes("window.__rohmatAdminBootstrap=(force=false)"),'Admin bootstrap must support forced refresh');
assert.ok(src.includes("load(force=false)"),'Admin Design System loader must support forced refresh');
assert.ok(src.includes("load(true)"),'Admin Design System must force reload after settings changes');
assert.ok(src.includes("rohmatAdminDesign='v44'"),'Admin runtime v44 marker missing');
for(const key of ['--ds-font','--ds-base-size','--ds-login-brand-font','--ds-login-brand-size','--ds-login-brand-align','--ds-login-brand-weight']){
  assert.ok(src.includes(key),'missing typography token '+key);
}
assert.ok(src.includes("'important'"),'Admin typography tokens must be able to win stale CSS cascade');
console.log('ADMIN_RUNTIME_TYPOGRAPHY_PROPAGATION_GATE_PASS=1');
