import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-visual-editor-v1/index.ts',import.meta.url),'utf8');
const runtime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');

assert.match(runtime,/rohmat-admin-visual-editor-v1\?tenant=.*&v=26/,'Admin runtime must pin visual editor v25');
for(const marker of ['rohmat-admin-settings-theme-v26','Transaksi dan Pembayaran','PENGATURAN','transaction_payment','Aktifkan Pajak','Aktifkan Charge','Bahasa Utama','Mandarin (Sederhana)','ar-SA','catalogCache','rohmatThemeSync']) assert.ok(src.includes(marker),'missing settings/theme marker: '+marker);
assert.match(src,/settingsObserverV26/,'PENGATURAN must survive Admin shell rerenders');
assert.match(src,/admin_console_update_settings/,'settings must persist through secured tenant RPC');
assert.match(src,/v26-tenant-settings-theme-sync/,'theme synchronization runtime version missing');
assert.match(src,/setTimeout\(\(\)=>syncTheme\(true\),220\)/,'theme must revalidate promptly after apply');
console.log('ADMIN_SETTINGS_THEME_GATE_PASS=1');
