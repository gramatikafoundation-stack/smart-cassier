import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-visual-editor-v1/index.ts',import.meta.url),'utf8');
const runtime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
const secure=fs.readFileSync(new URL('../../../supabase/functions/rohmat-secure-api-v1/index.ts',import.meta.url),'utf8');

assert.match(runtime,/rohmat-admin-visual-editor-v1\?tenant=.*&v=29/,'Admin runtime must pin visual editor v29');
for(const marker of ['rohmat-admin-settings-theme-v29','Transaksi dan Pembayaran','PENGATURAN','transaction_payment','Aktifkan Pajak','Aktifkan Charge','Bahasa Utama','Mandarin (Sederhana)','ar-SA','catalogCache','rohmatThemeSync']) assert.ok(src.includes(marker),'missing settings/theme marker: '+marker);
assert.match(src,/settingsObserverV29/,'PENGATURAN must survive Admin shell rerenders');
for(const rpc of ['admin_console_snapshot','admin_console_update_settings','admin_theme_profile_catalog']) assert.ok(src.includes("rpc('"+rpc+"'"),'missing canonical browser RPC: '+rpc);
for(const forbidden of ['admin_console_snapshot_tenant','admin_console_update_settings_tenant','admin_theme_profile_catalog_tenant']) assert.ok(!src.includes("rpc('"+forbidden+"'"),'browser must never call tenant-suffixed RPC directly: '+forbidden);
for(const mapping of ['admin_console_snapshot:"admin_console_snapshot_tenant"','admin_console_update_settings:"admin_console_update_settings_tenant"','admin_theme_profile_catalog:"admin_theme_profile_catalog_tenant"']) assert.ok(secure.includes(mapping),'secure API tenant mapping missing: '+mapping);
for(const key of ['transaction_settings','language_settings','rohmatAdminThemeLiveV29']) assert.ok(src.includes(key),'missing durable settings/theme key: '+key);
assert.match(src,/v29-secure-canonical-rpc/,'secure canonical RPC runtime marker missing');
assert.ok(src.includes("__SDB_SUPABASE_ORIGIN__"),'runtime must use deployment Supabase origin placeholder');
assert.ok(src.includes("__SDB_SUPABASE_PUBLISHABLE_KEY__"),'runtime must use deployment publishable key placeholder');
assert.ok(src.includes("trim().toUpperCase()==='PENGATURAN'"),'settings navigation must dedupe by visible label');
assert.ok(src.includes("PUBLIC_THEME_SYNC='sdb-theme-sync-v1'"),'Admin must emit the cross-tab Public theme sync signal');
assert.ok(src.includes('setTimeout(signalPublicTheme,760)'),'Admin theme apply must notify Public immediately after persistence revalidation');
assert.match(src,/setTimeout\(\(\)=>syncTheme\(true\),220\)/,'theme must revalidate promptly after apply');
assert.match(src,/setTimeout\(\(\)=>syncTheme\(true\),700\)/,'theme must confirm persisted state without long delay');
console.log('ADMIN_SETTINGS_THEME_GATE_PASS=1');
