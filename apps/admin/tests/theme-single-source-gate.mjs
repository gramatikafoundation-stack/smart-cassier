import assert from 'node:assert/strict';
import fs from 'node:fs';

const proxy=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
const style=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-style-runtime-v59/index.ts',import.meta.url),'utf8');

assert.ok(proxy.includes('__rohmatAdminGlobalDesignV49'),'proxy must recognize legacy global theme engine');
assert.ok(proxy.includes("out = out.replace(/\\(\\(\\)=>\\{'use strict'"),'proxy must strip legacy theme engine');
assert.ok(style.includes('__rohmatAdminNavDedupeV56'),'style runtime must deduplicate PENGATURAN');
assert.ok(style.includes('__rohmatTenantShellGuardV57'),'tenant shell guard must exist');
assert.ok(style.includes('__rohmatTenantDesignAuthorityV59'),'tenant design authority must exist');
assert.ok(style.includes('__rohmatAdminGlobalDesignV49'),'style runtime must explicitly remove legacy global theme engine');
assert.ok(style.includes('baseline-v47-tenant-design-authority-v59'),'single-source runtime marker missing');
for(const token of ['--ds-font','--ds-base-size','--ds-login-brand-font','--ds-login-brand-size','--ds-login-brand-align','--ds-login-brand-weight']) assert.ok(style.includes(token),'tenant design authority missing '+token);
assert.ok(style.includes("return PRELUDE+out+SHELL_GUARD+NAV_DEDUPE"),'shell guard and nav dedupe must be included in final style runtime');
console.log('ADMIN_THEME_SINGLE_SOURCE_GATE_PASS=1');
