import fs from 'node:fs';
import assert from 'node:assert/strict';

const printer=fs.readFileSync(new URL('../printer-runtime.js',import.meta.url),'utf8');
const render=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const runtime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
const root=fs.readFileSync(new URL('../../../vercel.json',import.meta.url),'utf8');
const adminVercel=fs.readFileSync(new URL('../vercel.json',import.meta.url),'utf8');
const publicRender=fs.readFileSync(new URL('../../public/api/render.js',import.meta.url),'utf8');

for(const token of [
  'Printer Thermal',
  'Bluetooth Low Energy (BLE)',
  'USB OTG / WebUSB',
  'Bagikan ke Aplikasi Printer Android',
  'Android System Print · Wi-Fi / Print Service',
  'Web Serial (desktop)',
  'navigator.share',
  'USB ESC/POS',
  'Bluetooth Classic / SPP atau Serial / COM',
  'Printer Sistem / Driver Windows',
  'navigator.bluetooth.requestDevice',
  'navigator.serial.requestPort',
  'navigator.usb.requestDevice',
  'navigator.bluetooth.getDevices',
  'navigator.serial.getPorts',
  'navigator.usb.getDevices',
  'transferOut',
  'getWriter',
  'writeValueWithoutResponse',
  'Tidak ada pairing atau cetak uji otomatis',
  'sdb-smart-cashier-printer-v2',
  '@page{size:80mm auto;margin:0}'
]) assert.ok(printer.includes(token), 'printer runtime missing '+token);

assert.ok(printer.includes('0x1d,0x56,0x42,0x00'), 'ESC/POS cut command missing');
assert.ok(printer.includes("b.dataset.sdbPrinterSettings='1'"), 'PENGATURAN > Printer Thermal navigation injection missing');
assert.ok(printer.includes("document.addEventListener('click',interceptReceiptPrint,true)"), 'receipt print interception missing');
assert.ok(render.includes('sdb-smart-cashier-thermal-printer-v1'), 'printer loader missing from admin shell');
assert.ok(render.includes("usb=(self), serial=(self), bluetooth=(self), web-share=(self)"), 'admin device/share permissions policy missing');
assert.ok(runtime.includes('window.__SDB_LAST_CASHIER_RECEIPT__=r'), 'cashier receipt handoff missing');
assert.ok(root.includes('"/admin/runtime/printer.js"'), 'root printer runtime route missing');
assert.ok(root.includes('"destination": "/apps/admin/printer-runtime.js"'), 'root printer static asset destination missing');
assert.ok(root.includes('usb=(), serial=(), bluetooth=()'), 'non-admin device-deny policy missing');
assert.ok(adminVercel.includes('usb=(self), serial=(self), bluetooth=(self), web-share=(self)'), 'standalone admin device/share permission policy missing');
assert.ok(publicRender.includes('usb=(), serial=(), bluetooth=()'), 'public device deny policy missing');
assert.ok(printer.includes("if(s.mode==='share')"),'Android share printer route missing');
assert.match(printer,/Bluetooth Classic\/SPP tidak diklaim sebagai koneksi langsung browser Android/,'must not overclaim Android Bluetooth Classic direct support');
assert.doesNotMatch(printer,/ANDROID \/ TABLET[^\n]*Bluetooth Classic \/ SPP · Web Serial RFCOMM/,'must not advertise Bluetooth Classic direct route on Android');
assert.doesNotMatch(printer,/setInterval\([^)]*print|onload\s*=\s*\(\)\s*=>\s*directPrint/i,'direct printer must not auto-print');
console.log('SMART_CASHIER_THERMAL_PRINTER_READINESS_GATE_PASS=1');
console.log('SMART_CASHIER_PRINTER_SETTINGS_UI_GATE_PASS=1');
console.log('SMART_CASHIER_ANDROID_PRINTER_PATHS_GATE_PASS=1');
