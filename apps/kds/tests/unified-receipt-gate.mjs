import assert from 'node:assert/strict';
import fs from 'node:fs';

const kds=fs.readFileSync(new URL('../cashier-required-receipt.js',import.meta.url),'utf8');
const css=fs.readFileSync(new URL('../styles.css',import.meta.url),'utf8');
const pub=fs.readFileSync(new URL('../../../supabase/functions/rohmat-public-element-runtime-v64/index.ts',import.meta.url),'utf8');

assert.doesNotMatch(kds,/RINGKASAN PESANAN/i,'label lama tidak boleh kembali pada struk KDS');
for(const label of ['Struk Pembayaran & Pemesanan','Kode Transaksi','Rincian Pesanan','Subtotal','Pajak','Total Pembayaran']) assert.ok(kds.includes(label),'KDS receipt missing: '+label);
for(const token of ['receiptModalV4','receiptMetaV4','receiptItemsV4','receiptTotalsV4']) assert.ok(css.includes(token),'KDS receipt CSS missing: '+token);
for(const label of ['rohmat-unified-receipt-v4','Struk Pembayaran & Pemesanan','Rincian Pesanan','Subtotal','Pajak','Total Pembayaran']) assert.ok(pub.includes(label),'Public receipt runtime missing: '+label);
assert.ok(pub.includes('window.__rohmatCreateStyleV27?window.__rohmatCreateStyleV27()'),'Public receipt style must remain CSP nonce-safe');
console.log('UNIFIED_RECEIPT_SMART_ORDER_GATE_PASS=1');
