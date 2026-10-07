import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-render/index.ts',import.meta.url),'utf8');

assert.ok(src.includes("cache:'no-store'"),'Admin bootstrap must avoid stale Design System cache');
assert.ok(src.includes("window.__rohmatAdminBootstrap=(force=false)"),'Admin bootstrap must support forced refresh');
assert.ok(src.includes("load(force=false)"),'Admin Design System loader must support forced refresh');
assert.ok(src.includes("load(true)"),'Admin Design System must force reload after settings changes');
assert.ok(src.includes("rohmatAdminDesign='v44'"),'Admin runtime v44 marker missing');
assert.ok(src.includes('admin-design-system-runtime-v41'),'Renderer must keep v41 script id for deployed Vercel core compatibility');
assert.ok(src.includes("out=out.replace('<script id=\"admin-design-system-runtime-v41\">'"),'Tenant bootstrap must inject into the v41 compatibility runtime');
assert.ok(src.includes("window.__rohmatAdminBootstrap()"),'Admin runtime must consume tenant bootstrap rather than global site_settings');
assert.ok(!src.includes("replaceAll('admin-design-system-runtime-v43','admin-design-system-runtime-v44')"),'Compatibility id must not be renamed away');
for(const key of ['--ds-font','--ds-base-size','--ds-login-brand-font','--ds-login-brand-size','--ds-login-brand-align','--ds-login-brand-weight']){
  assert.ok(src.includes(key),'missing typography token '+key);
}
assert.ok(src.includes("'important'"),'Admin typography tokens must be able to win stale CSS cascade');
assert.ok(src.includes("'access-control-allow-headers':'x-sdb-tenant-id, cache-control, pragma'"),'Admin bootstrap CORS must permit browser no-store request headers');
assert.ok(src.includes("'access-control-allow-methods':'GET,OPTIONS'"),'Admin bootstrap preflight must permit GET');
console.log('ADMIN_RUNTIME_TYPOGRAPHY_PROPAGATION_GATE_PASS=1');
