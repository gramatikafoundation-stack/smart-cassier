import fs from 'node:fs';
import assert from 'node:assert/strict';

const render=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-render/index.ts',import.meta.url),'utf8');
const dbui=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-database-ui-v1/index.ts',import.meta.url),'utf8');
const printer=fs.readFileSync(new URL('../printer-runtime.js',import.meta.url),'utf8');

for(const token of [
  'menu_categories',
  '+ Tambah Kategori',
  'function menuCategories',
  'async function addMenuCategory',
  "category:''",
  'Pilih atau tambahkan kategori terlebih dahulu.'
]) assert.ok(render.includes(token),'dynamic category contract missing: '+token);
assert.ok(!render.includes("['Nasi','Lauk','Minuman','Jus Buah'].map"),'hardcoded built-in menu categories must be removed');

for(const token of [
  'function normalizeLanguage',
  'function languageCopy',
  "document.documentElement.dataset.adminLanguage=x.code",
  'renderLanguage(view)',
  "['id-ID','Indonesia','ltr']",
  "['en-US','Inggris','ltr']",
  "['ar-SA','Arab','rtl']",
  "language:{code:x.code,name:x.name,dir:x.dir}",
  "rohmat:language-updated"
]) assert.ok(render.includes(token),'language runtime contract missing: '+token);
assert.match(render,/const LANGS=\[[\s\S]*?\['nl-NL','Belanda','ltr'\]/,'canonical locale language catalog missing');

for(const token of [
  'navigator.userAgentData?.platform',
  "if(id==='app-bridge')return isAndroid()",
  "typeof navigator.share==='function'",
  'android.intent.action.SEND',
  "return 'android-intent'",
  "label=mode==='web-share'?'Web Share':mode==='android-intent'?'Android Intent'"
]) assert.ok(printer.includes(token),'Android app bridge runtime contract missing: '+token);

for(const token of [
  'freshCheck',
  'Date.now()-lastCheck.getTime()<=120000',
  'Sheet tervalidasi backend',
  'last_synced_at',
  'last_checked_at',
  'pemeriksaan backend kedaluwarsa',
  'queue===0',
  'consistent===targets'
]) assert.ok(dbui.includes(token),'sheet health evidence contract missing: '+token);

console.log('ADMIN_DYNAMIC_CATEGORY_GATE_PASS=1');
console.log('ADMIN_LANGUAGE_RUNTIME_GATE_PASS=1');
console.log('ADMIN_ANDROID_APP_BRIDGE_GATE_PASS=1');
console.log('ADMIN_SHEET_HEALTH_EVIDENCE_GATE_PASS=1');
