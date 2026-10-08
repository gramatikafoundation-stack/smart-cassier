import fs from 'node:fs';
import assert from 'node:assert/strict';

const printer=fs.readFileSync(new URL('../printer-runtime.js',import.meta.url),'utf8');
const render=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const runtime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
const root=fs.readFileSync(new URL('../../../vercel.json',import.meta.url),'utf8');
const adminVercel=fs.readFileSync(new URL('../vercel.json',import.meta.url),'utf8');
const publicRender=fs.readFileSync(new URL('../../public/api/render.js',import.meta.url),'utf8');

const fiveRoutes=[
  "id:'system',title:'Sistem / Android Print Service'",
  "id:'usb',title:'USB OTG — ESC/POS'",
  "id:'ble',title:'Bluetooth LE — ESC/POS'",
  "id:'serial',title:'USB / Serial — ESC/POS'",
  "id:'app-bridge',title:'Android ESC/POS App Bridge'"
];
for(const token of fiveRoutes)assert.ok(printer.includes(token),'missing required printer route '+token);
assert.equal((printer.match(/meta:'JALUR [1-5]/g)||[]).length,5,'printer settings must expose exactly five numbered routes');

for(const token of [
  'Printer Thermal','Test Print','Jadikan Default','Putuskan','Hubungkan',
  'Instal aplikasi ESC/POS/vendor printer','navigator.share','navigator.bluetooth.requestDevice',
  'navigator.serial.requestPort','navigator.usb.requestDevice',
  'navigator.bluetooth.getDevices','navigator.serial.getPorts','navigator.usb.getDevices',
  'transferOut','getWriter','writeValueWithoutResponse',
  'sdb-smart-order-printer-v3','sdb-smart-cashier-printer-v2',
  '58mm','80mm','TEST-PRINT','SMART ORDER'
]) assert.ok(printer.includes(token), 'printer runtime missing '+token);

assert.ok(printer.includes('0x1d,0x56,0x42,0x00'),'ESC/POS cut command missing');
assert.ok(printer.includes("b.dataset.sdbPrinterSettings='1'"),'PENGATURAN > Printer Thermal navigation injection missing');
assert.ok(printer.includes("document.addEventListener('click',interceptReceiptPrint,true)"),'receipt print interception missing');
assert.ok(render.includes('sdb-smart-cashier-thermal-printer-v1'),'printer loader missing from admin shell');
assert.ok(render.includes("usb=(self), serial=(self), bluetooth=(self), web-share=(self)"),'admin printer permissions policy missing');
assert.ok(runtime.includes('window.__SDB_LAST_CASHIER_RECEIPT__=r'),'receipt handoff contract changed');
assert.ok(root.includes('"/admin/runtime/printer.js"'),'root printer runtime route missing');
assert.ok(root.includes('"destination": "/apps/admin/printer-runtime.js"'),'printer asset destination missing');
assert.ok(root.includes('usb=(), serial=(), bluetooth=()'),'non-admin device-deny policy missing');
assert.ok(adminVercel.includes('usb=(self), serial=(self), bluetooth=(self), web-share=(self)'),'standalone admin printer permission policy missing');
assert.ok(publicRender.includes('usb=(), serial=(), bluetooth=()'),'public device deny policy missing');

assert.match(printer,/requestDevice\(\{filters:\[\{classCode:7\}\]\}\)/,'WebUSB must request printer class, not an empty device filter');
assert.doesNotMatch(printer,/requestDevice\(\{filters:\[\]\}\)/,'WebUSB must not use an empty device filter');
assert.doesNotMatch(printer,/setInterval\([^)]*print|onload\s*=\s*\(\)\s*=>\s*directPrint/i,'direct printer must never auto-print');
assert.match(printer,/Kegagalan printer tidak memengaruhi pembayaran, penyimpanan order, atau status pesanan/,'printer failure isolation message missing');
assert.match(printer,/Bluetooth LE berbeda dari Bluetooth Classic\/SPP/,'Bluetooth compatibility warning missing');
assert.match(printer,/function testReceipt\(\)/,'local synthetic Test Print fixture missing');
assert.match(printer,/async function testPrint\(id\)/,'Test Print action missing');
assert.match(printer,/function setDefault\(id\)/,'explicit default-route action missing');
assert.match(printer,/async function print\(r\)[\s\S]*system-fallback/,'safe system fallback missing');

console.log('SMART_ORDER_THERMAL_PRINTER_FIVE_ROUTE_GATE_PASS=1');
console.log('SMART_ORDER_PRINTER_TUTORIAL_ACTION_GATE_PASS=1');
console.log('SMART_ORDER_PRINTER_FAILURE_ISOLATION_GATE_PASS=1');
