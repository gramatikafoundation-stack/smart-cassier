import fs from 'node:fs';
import assert from 'node:assert/strict';

const printer=fs.readFileSync(new URL('../printer-runtime.js',import.meta.url),'utf8');
const render=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const runtime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
const root=fs.readFileSync(new URL('../../../vercel.json',import.meta.url),'utf8');
const adminVercel=fs.readFileSync(new URL('../vercel.json',import.meta.url),'utf8');
const publicVercel=fs.readFileSync(new URL('../../public/vercel.json',import.meta.url),'utf8');
const kdsVercel=fs.readFileSync(new URL('../../kds/vercel.json',import.meta.url),'utf8');

for(const token of [
  'Printer Thermal',
  'Bluetooth BLE Langsung',
  'USB OTG Langsung',
  'Android Print Service',
  'Wi-Fi / Wi-Fi Direct',
  'USB / Serial Desktop',
  'Printer Sistem',
  'navigator.bluetooth.requestDevice',
  'navigator.bluetooth.getDevices',
  'navigator.usb.requestDevice({filters:[{classCode:7}]})',
  'navigator.usb.getDevices',
  'navigator.serial.requestPort',
  'navigator.serial.getPorts',
  'transferOut',
  'getWriter',
  'writeValueWithoutResponse',
  'Tidak ada test print otomatis',
  'Bluetooth Classic',
  'sdb-smart-cashier-printer-v2',
  '@page{size:80mm auto;margin:0}'
]) assert.ok(printer.includes(token),'printer runtime missing '+token);

for(const uuid of [
  '0000ffe0-0000-1000-8000-00805f9b34fb',
  '0000ff00-0000-1000-8000-00805f9b34fb',
  '6e400001-b5a3-f393-e0a9-e50e24dcca9e'
]) assert.ok(printer.includes(uuid),'BLE service missing '+uuid);

assert.ok(printer.includes('0x1d,0x56,0x42,0x00'),'ESC/POS cut command missing');
assert.ok(printer.includes('data-sdb-printer-sub'),'PENGATURAN printer subnavigation missing');
assert.ok(printer.includes("document.addEventListener('click'"),'receipt print interception missing');
assert.ok(render.includes('sdb-smart-cashier-thermal-printer-v2'),'printer loader missing from admin shell');
assert.ok(render.includes('usb=(self), serial=(self), bluetooth=(self)'),'admin device permissions missing');
assert.ok(runtime.includes('window.__SDB_LAST_CASHIER_RECEIPT__=r'),'cashier receipt handoff missing');
assert.ok(root.includes('"/admin/runtime/printer.js"'),'root printer runtime route missing');
assert.ok(root.includes('"destination": "/apps/admin/printer-runtime.js"'),'printer asset destination missing');
assert.ok(adminVercel.includes('usb=(self), serial=(self), bluetooth=(self)'),'standalone admin permissions missing');
assert.ok(publicVercel.includes('usb=(), serial=(), bluetooth=()'),'public device deny missing');
assert.ok(kdsVercel.includes('usb=(), serial=(), bluetooth=()'),'kds device deny missing');
assert.doesNotMatch(printer,/requestDevice\(\{filters:\[\]\}\)/,'WebUSB must not use empty filters');
assert.doesNotMatch(printer,/setInterval\([^)]*print|onload\s*=\s*\(\)\s*=>\s*directPrint/i,'direct printer must not auto-print');
console.log('SMART_CASHIER_THERMAL_MOBILE_READINESS_GATE_PASS=1');
