import assert from 'node:assert/strict';
import fs from 'node:fs';

const api=fs.readFileSync(new URL('../api/kds.js',import.meta.url),'utf8');
const config=fs.readFileSync(new URL('../api/config.js',import.meta.url),'utf8');
const tenant=fs.readFileSync(new URL('../tenant-runtime.js',import.meta.url),'utf8');
const design=fs.readFileSync(new URL('../design-runtime.js',import.meta.url),'utf8');
const css=fs.readFileSync(new URL('../styles.css',import.meta.url),'utf8');

assert.ok(api.includes("process.env.SUPABASE_URL || process.env.SUPABASE_ORIGIN"),'KDS proxy must derive canonical project origin from trusted env');
assert.ok(api.includes("expectedPath = '/functions/v1/rohmat-kds-api'"),'KDS proxy must pin canonical Edge Function path');
assert.ok(config.includes('process.env.BUSINESS_NAME'),'KDS config must source business name from deployment configuration');
assert.ok(tenant.includes("body:JSON.stringify({action:'brand'})"),'KDS tenant runtime must retrieve tenant brand/design through BFF');
assert.ok(tenant.includes("current.kdsDesign=n.kdsDesign"),'KDS tenant runtime must retain Design System payload');
for(const marker of ['p.theme','p.general','p.sites?.kds','p.pages?.kds?.[page()]']) assert.ok(design.includes(marker),'KDS resolver hierarchy missing: '+marker);
for(const token of ['--kds-font','--kds-head-font','--kds-size','--kds-line-height','--kds-primary','--kds-accent']) assert.ok(design.includes(token),'KDS design runtime token missing: '+token);
assert.ok(css.includes('font-family:var(--kds-font)!important'),'KDS surface must consume canonical font token');
assert.ok(css.includes('font-size:var(--kds-size)!important'),'KDS surface must consume canonical base-size token');
assert.ok(!api.includes("hostname !== 'yybhpmjuywjxqurrrrxl.supabase.co'"),'legacy KDS project pin must never return');

console.log('KDS_DESIGN_SYSTEM_GATE_PASS=1');
