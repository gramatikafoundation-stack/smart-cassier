import fs from 'node:fs';
import assert from 'node:assert/strict';

const printer=fs.readFileSync(new URL('../printer-runtime.js',import.meta.url),'utf8');
const render=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const runtime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
const root=fs.readFileSync(new URL('../../../vercel.json',import.meta.url),'utf8');
const adminVercel=fs.readFileSync(new URL('../vercel.json',import.meta.url),'utf8');

for(const token of [
  'navigator.usb.requestDevice',
  'navigator.serial.requestPort',
  'navigator.usb.getDevices',
  'navigator.serial.getPorts',
  'transferOut',
  'getWriter',
  'Hubungkan Printer',
  'PENGATURAN',
  'Printer Thermal',
  'USB Langsung — ESC/POS',
  'USB/Serial — ESC/POS',
  'Printer Sistem / Driver Windows',
  'data-settings-printer',
  'Tidak ada pairing, test print, atau pencetakan otomatis',
  'sdb-smart-cashier-printer-v1',
  '@page{size:80mm auto;margin:0}'
]) assert.ok(printer.includes(token), 'printer runtime missing '+token);

assert.ok(printer.includes('0x1d,0x56,0x42,0x00'), 'ESC/POS cut command missing');
assert.ok(printer.includes("document.addEventListener('click'"), 'receipt print interception missing');
assert.ok(render.includes('sdb-smart-cashier-thermal-printer-v1'), 'printer loader missing from admin shell');
assert.ok(render.includes("usb=(self), serial=(self)"), 'admin USB/Serial permissions policy missing');
assert.ok(runtime.includes('window.__SDB_LAST_CASHIER_RECEIPT__=r'), 'cashier receipt handoff missing');
assert.ok(root.includes('"/admin/runtime/printer.js"'), 'root printer runtime route missing');
assert.ok(root.includes('"destination": "/apps/admin/printer-runtime.js"'), 'root printer asset destination missing');
assert.ok(root.includes('usb=(), serial=()'), 'KDS/device-deny policy missing');
assert.ok(adminVercel.includes('usb=(self), serial=(self)'), 'standalone admin permission policy missing');
assert.doesNotMatch(printer,/setInterval\([^)]*print|onload\s*=\s*\(\)\s*=>\s*directPrint/i,'direct printer must not auto-print');
console.log('SMART_CASHIER_THERMAL_PRINTER_READINESS_GATE_PASS=1');
