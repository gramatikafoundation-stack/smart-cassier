import fs from 'node:fs';
import assert from 'node:assert/strict';
const read=p=>fs.readFileSync(new URL(p,import.meta.url),'utf8');

const pub=read('../apps/public/api/render.js');
const localeApi=read('../apps/public/api/locale.js');
const gateway=read('../supabase/functions/create-order/index.ts');
const core=read('../supabase/functions/create-order-v6/index.ts');
const kds=read('../apps/kds/app.js');
const kdsHtml=read('../apps/kds/index.html');
const receipt=read('../apps/kds/cashier-required-receipt.js');
const legacyPrintShim=read('../apps/kds/print-hide.js');
const i18n=read('../apps/shared/i18n-runtime.js');
const adminRuntime=read('../apps/admin/api/runtime.js');
const adminRender=read('../supabase/functions/rohmat-admin-render/index.ts');
const visualEditor=read('../supabase/functions/rohmat-admin-visual-editor-v1/index.ts');
const writer=read('../supabase/functions/rohmat-sheet-writer-data-v1/index.ts');
const localeMigration=read('../supabase/migrations/20261010061500_sheet_language_reconcile_v1.sql');
const tenantExample=read('../prototype/tenant.example.json');

assert.ok(pub.includes('grid-template-columns:repeat(4,minmax(0,1fr))'));
console.log('PUBLIC_MENU_FOUR_COLUMN_GATE=PASS');
assert.ok(pub.includes('object-fit:contain'));
assert.ok(pub.includes('object-position:center'));
console.log('PUBLIC_MENU_IMAGE_CONTAIN_GATE=PASS');
assert.ok(pub.includes('grid-template-rows:minmax(0,78fr) minmax(0,22fr)'));
assert.ok(pub.includes('text-align:center'));
console.log('PUBLIC_MENU_CARD_PROPORTION_GATE=PASS');

for(const token of ['master_prototype_runtime_context','p_origin:tenantId?null:origin','if(req.method==="OPTIONS")','Access-Control-Allow-Headers','x-sdb-client-order-id','function internalKey()','const INTERNAL_KEY=internalKey()','apikey:INTERNAL_KEY','Authorization:"Bearer "+INTERNAL_KEY'])
  assert.ok(gateway.includes(token),'gateway contract missing '+token);
for(const token of ['clientOrderId','X-Request-ID','rohmat:order-commit-success','Pesanan sedang disimpan','async function prepareOrder','if(!PIPE?.use)','currentInput=prepared.input','currentInit=prepared.init'])
  assert.ok(pub.includes(token),'public commit contract missing '+token);
for(const token of ['payment_verification_started','payment_verification_success','order_commit_started','order_commit_success','order_commit_failed','sheet_sync_enqueued'])
  assert.ok(core.includes(token),'structured order event missing '+token);
console.log('PUBLIC_PAYMENT_COMMIT_GATE=PASS');

assert.ok(!pub.includes("status.textContent='Pembayaran berhasil'"),'false success marker found');
assert.ok(pub.includes('rohmat:order-commit-success'));
console.log('PUBLIC_PAYMENT_NO_FALSE_SUCCESS_GATE=PASS');

for(const token of ['sb.from("orders").insert','tenant_id:ctx.tenant_id','client_order_id:client','payment_status:"submitted"','order_status:"payment_review"'])
  assert.ok(core.includes(token),'canonical persistence missing '+token);
console.log('PUBLIC_DATABASE_PERSISTENCE_GATE=PASS');
assert.ok(core.includes('sb.from("sheet_sync_outbox")'));
assert.ok(localeMigration.includes('sheet_sync_outbox'));
assert.ok(localeMigration.includes("'RECONCILE'"));
console.log('PUBLIC_SHEET_SYNC_ENQUEUE_GATE=PASS');

assert.ok(!kds.includes('data-print='));
assert.ok(!kdsHtml.includes('print-hide.js'));
assert.ok(!kds.includes('function printOne('));
assert.ok(!legacyPrintShim.includes('KITCHEN TICKET'));
assert.ok(!legacyPrintShim.includes('[data-print]')||legacyPrintShim.includes("querySelectorAll('[data-print]').forEach(el=>el.remove())"));
console.log('KDS_NO_PRINT_BUTTON_GATE=PASS');
for(const token of ["action==='complete'","await run(id,action)","committed=true","printReceipt(order","handoverPrintLocks"])
  assert.ok(kds.includes(token),'handover auto-print missing '+token);
console.log('KDS_HANDOVER_AUTO_PRINT_GATE=PASS');
for(const token of ['data-kds-live-mirror="v1"',"src=login?'/kds/login':'/kds'","frame.contentDocument","[data-tab=\"'+target+'\"]"])
  assert.ok(adminRender.includes(token),'admin KDS live mirror contract missing '+token);
assert.ok(!adminRender.includes('KDS dan Admin membaca source of truth pesanan yang sama.'));
console.log('ADMIN_KDS_LIVE_VISUAL_PARITY_GATE=PASS');
for(const src of [adminRender,visualEditor]){
  assert.ok(src.includes("data.settingsMain='1'"),'stable settings identity missing');
  assert.ok(src.includes('data.settingsMainV29'), 'cross-runtime settings identity missing');
  assert.ok(!src.includes("trim().toUpperCase()==='PENGATURAN'"),'translated text must not own settings identity');
}
console.log('ADMIN_SETTINGS_I18N_DEDUP_GATE=PASS');

const locales=['id-ID','en-US','ms-MY','ar-SA','zh-CN','zh-TW','ja-JP','ko-KR','hi-IN','th-TH','vi-VN','fr-FR','de-DE','es-ES','pt-BR','tr-TR','ru-RU','nl-NL'];
for(const l of locales)assert.ok(i18n.includes("'"+l+"'"),'locale missing '+l);
for(const key of ['nav.public','nav.admin','nav.database','action.save','payment.send','receipt.total'])
  assert.ok(i18n.includes("'"+key+"'"),'i18n key missing '+key);
assert.ok(i18n.includes('missing'));
assert.ok(i18n.includes("fetch('/api/locale'"));
assert.ok(adminRender.includes('/runtime/i18n.js?v=20261010-global-v2'));
assert.ok(kdsHtml.includes('/runtime/i18n.js?v=20261010-global-v2'));
assert.ok(pub.includes('/runtime/i18n.js?v=20261010-global-v2'));
console.log('GLOBAL_I18N_COVERAGE_GATE=PASS');
assert.ok(adminRuntime.includes("mb?.dataset?.main"));
assert.ok(adminRuntime.includes("sb?.dataset?.sub"));
assert.ok(adminRender.includes("mb?.dataset?.main||(mb?.dataset?.settingsMain?'settings':'')"));
assert.ok(!adminRender.includes("sb?.dataset?.settingsSub||sb?.textContent||''"));
console.log('I18N_ROUTE_ID_STABILITY_GATE=PASS');
assert.ok(i18n.includes("current==='ar-SA'?'rtl':'ltr'"));
assert.ok(adminRender.includes("['ar-SA','Arab','rtl']"));
console.log('I18N_RTL_GATE=PASS');

for(const t of ['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN'])assert.ok(tenantExample.includes(t),'technical sheet contract missing '+t);
for(const token of ['tenant_site_settings_public_v1','language_settings','sheetLocale','service(o.service_mode,locale)','pay(o.payment_method,locale)','stage(o,locale)'])
  assert.ok(writer.includes(token),'sheet locale writer missing '+token);
assert.ok(localeMigration.includes('language_changed'));
assert.ok(localeMigration.includes('after update of settings'));
assert.ok(localeApi.includes("url.searchParams.get('format')==='csv'"));
assert.ok(localeApi.includes("'text/csv; charset=utf-8'"));
assert.ok(localeApi.includes("'text/html; charset=utf-8'"));
assert.ok(localeApi.includes('<span id="locale">'));
console.log('SHEET_I18N_NO_WRITER_REGRESSION_GATE=PASS');

for(const token of ['receipt.proofOrder','receipt.transaction','SMART ORDER','receipt.status','receipt.code','receipt.customer','receipt.items','receipt.total','receipt.thanks'])
  assert.ok(receipt.includes(token),'receipt i18n/section contract missing '+token);
for(const token of ['58mm','80mm','payment_status','public_order_code','customer_name','service_mode','table_number','cashier_actor','cash_received','change_amount'])
  assert.ok(receipt.includes(token),'receipt dynamic field missing '+token);
assert.ok(!receipt.includes('Fariz'));
console.log('UNIFIED_TRANSACTION_RECEIPT_GATE=PASS');
