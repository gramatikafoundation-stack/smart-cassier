import fs from 'node:fs';
import assert from 'node:assert/strict';
const read=p=>fs.readFileSync(new URL(p,import.meta.url),'utf8');

const pub=read('../apps/public/api/render.js');
const gateway=read('../supabase/functions/create-order/index.ts');
const core=read('../supabase/functions/create-order-v6/index.ts');
const kds=read('../apps/kds/app.js');
const kdsHtml=read('../apps/kds/index.html');
const receipt=read('../apps/kds/cashier-required-receipt.js');
const i18n=read('../apps/shared/i18n-runtime.js');
const adminRuntime=read('../apps/admin/api/runtime.js');
const adminRender=read('../supabase/functions/rohmat-admin-render/index.ts');
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

for(const token of ['master_prototype_runtime_context','p_origin:tenantId?null:origin','if(req.method==="OPTIONS")','Access-Control-Allow-Headers','function internalKey()','const INTERNAL_KEY=internalKey()','apikey:INTERNAL_KEY','Authorization:"Bearer "+INTERNAL_KEY'])
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
console.log('KDS_NO_PRINT_BUTTON_GATE=PASS');
for(const token of ["action==='complete'","await run(id,action)","committed=true","printReceipt(order","handoverPrintLocks"])
  assert.ok(kds.includes(token),'handover auto-print missing '+token);
console.log('KDS_HANDOVER_AUTO_PRINT_GATE=PASS');

const locales=['id-ID','en-US','ms-MY','ar-SA','zh-CN','zh-TW','ja-JP','ko-KR','hi-IN','th-TH','vi-VN','fr-FR','de-DE','es-ES','pt-BR','tr-TR','ru-RU','nl-NL'];
for(const l of locales)assert.ok(i18n.includes("'"+l+"'"),'locale missing '+l);
for(const key of ['nav.public','nav.admin','nav.database','action.save','payment.send','receipt.total'])
  assert.ok(i18n.includes("'"+key+"'"),'i18n key missing '+key);
assert.ok(i18n.includes('missing'));
console.log('GLOBAL_I18N_COVERAGE_GATE=PASS');
assert.ok(adminRuntime.includes("mb?.dataset?.main"));
assert.ok(adminRuntime.includes("sb?.dataset?.sub"));
assert.ok(adminRender.includes("mb?.dataset?.main||(mb?.dataset?.settingsMain?'settings':'')"));
console.log('I18N_ROUTE_ID_STABILITY_GATE=PASS');
assert.ok(i18n.includes("current==='ar-SA'?'rtl':'ltr'"));
assert.ok(adminRender.includes("['ar-SA','Arab','rtl']"));
console.log('I18N_RTL_GATE=PASS');

for(const t of ['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN'])assert.ok(tenantExample.includes(t),'technical sheet contract missing '+t);
for(const token of ['tenant_site_settings_public_v1','language_settings','sheetLocale','service(o.service_mode,locale)','pay(o.payment_method,locale)','stage(o,locale)'])
  assert.ok(writer.includes(token),'sheet locale writer missing '+token);
assert.ok(localeMigration.includes('language_changed'));
assert.ok(localeMigration.includes('after update of settings'));
console.log('SHEET_I18N_NO_WRITER_REGRESSION_GATE=PASS');

for(const token of ['BUKTI PEMBAYARAN &amp; PEMESANAN','STRUK TRANSAKSI','SMART ORDER','Status Pembayaran','Kode Transaksi','Nama Pemesan','Rincian Pesanan','TOTAL PEMBAYARAN','Terima kasih'])
  assert.ok(receipt.includes(token),'receipt section missing '+token);
for(const token of ['58mm','80mm','payment_status','public_order_code','customer_name','service_mode','table_number','cashier_actor','cash_received','change_amount'])
  assert.ok(receipt.includes(token),'receipt dynamic field missing '+token);
assert.ok(!receipt.includes('Fariz'));
console.log('UNIFIED_TRANSACTION_RECEIPT_GATE=PASS');
