import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-visual-editor-v1/index.ts',import.meta.url),'utf8');
const runtime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');

assert.match(runtime,/rohmat-admin-visual-editor-v1\?tenant=.*&v=26/,'Admin runtime must pin visual editor v26');
for(const marker of ['rohmat-admin-settings-theme-v26','Transaksi dan Pembayaran','PENGATURAN','transaction_payment','Aktifkan Pajak','Aktifkan Charge','Bahasa Utama','Mandarin (Sederhana)','ar-SA','catalogCache','rohmatThemeSync']) assert.ok(src.includes(marker),'missing settings/theme marker: '+marker);
assert.match(src,/settingsObserverV26/,'PENGATURAN must survive Admin shell rerenders');
for(const rpc of ['admin_console_snapshot_tenant','admin_console_update_settings_tenant','admin_theme_profile_catalog_tenant']) assert.ok(src.includes(rpc),'missing tenant RPC: '+rpc);
for(const key of ['transaction_settings','language_settings','rohmatAdminThemeLiveV26']) assert.ok(src.includes(key),'missing durable settings/theme key: '+key);
assert.match(src,/v26-tenant-settings-theme-sync/,'theme synchronization runtime version missing');
assert.match(src,/setTimeout\(\(\)=>syncTheme\(true\),220\)/,'theme must revalidate promptly after apply');
assert.match(src,/setTimeout\(\(\)=>syncTheme\(true\),700\)/,'theme must confirm persisted state without long delay');
console.log('ADMIN_SETTINGS_THEME_GATE_PASS=1');
