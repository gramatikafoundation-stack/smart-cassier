import fs from 'node:fs';
import assert from 'node:assert/strict';

const kds=fs.readFileSync(new URL('../cashier-required-receipt.js',import.meta.url),'utf8');
const css=fs.readFileSync(new URL('../styles.css',import.meta.url),'utf8');
const pub=fs.readFileSync(new URL('../../../supabase/functions/rohmat-public-element-runtime-v64/index.ts',import.meta.url),'utf8');

assert.doesNotMatch(kds,/KITCHEN TICKET|RINGKASAN PESANAN/i,'legacy KDS ticket/summary label must not return');
for(const label of ['receipt.proofOrder','receipt.transaction','SMART ORDER','receipt.status','receipt.code','receipt.items','receipt.subtotal','receipt.total','receipt.thanks']) assert.ok(kds.includes(label),'KDS receipt i18n/structure missing: '+label);
for(const token of ["'58mm'","'80mm'","@page{size:'+paper+' auto;margin:0}",'overflow-wrap:anywhere']) assert.ok(kds.includes(token),'KDS thermal contract missing: '+token);
for(const token of ['receiptModalV5','receiptMetaV5','receiptItemsV5','receiptTotalsV5','receiptGrandV5']) assert.ok(css.includes(token),'KDS receipt V5 CSS missing: '+token);
assert.match(pub,/rohmat-unified-receipt-v(?:4|5-pricing)/,'Public receipt runtime marker missing');
for(const label of ['Struk Pembayaran & Pemesanan','Rincian Pesanan','Subtotal','Pajak','Total Pembayaran']) assert.ok(pub.includes(label),'Public receipt runtime missing: '+label);
assert.ok(pub.includes('window.__rohmatCreateStyleV27?window.__rohmatCreateStyleV27()'),'Public receipt style must remain CSP nonce-safe');
console.log('UNIFIED_RECEIPT_SMART_ORDER_GATE_PASS=1');
