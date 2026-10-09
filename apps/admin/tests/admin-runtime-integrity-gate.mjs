import fs from 'node:fs';
import assert from 'node:assert/strict';

const render=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const language=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-visual-editor-v1/index.ts',import.meta.url),'utf8');
const database=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-database-ui-v1/index.ts',import.meta.url),'utf8');

for(const token of [
  'dynamic-menu-categories-v1',
  '+ Tambah Kategori',
  'menu_categories',
  '“Semua” adalah filter bawaan',
  'Pilih kategori atau tambahkan kategori baru terlebih dahulu.'
]) assert.ok(render.includes(token),'dynamic category contract missing: '+token);

for(const token of [
  'function langUi(code)',
  "dataset.sdbLanguageApplied='1'",
  'renderLanguage(view,j.settings',
  "document.documentElement.dir=x.dir==='rtl'?'rtl':'ltr'",
  "language_settings={default:bx[0]"
]) assert.ok(language.includes(token),'language runtime contract missing: '+token);

for(const token of [
  'Sheet sinkron tervalidasi',
  'Number(h.dead||0)',
  'h.writer_configured===true',
  'consistent===targets',
  'lastEvent',
  'lastCheck',
  'Sheet perlu verifikasi event terbaru'
]) assert.ok(database.includes(token),'sheet health evidence contract missing: '+token);

console.log('SMART_ORDER_DYNAMIC_CATEGORY_GATE_PASS=1');
console.log('SMART_ORDER_LANGUAGE_RUNTIME_GATE_PASS=1');
console.log('SMART_ORDER_SHEET_SYNC_EVIDENCE_GATE_PASS=1');
