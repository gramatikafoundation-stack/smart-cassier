(()=>{'use strict';
if(window.__SDB_THERMAL_PRINTER_RUNTIME_V3)return;
window.__SDB_THERMAL_PRINTER_RUNTIME_V3=1;

const STORE='sdb-smart-order-printer-v3';
const LEGACY_STORE='sdb-smart-cashier-printer-v2';
const WIDTHS={'58mm':32,'80mm':42};
const BLE_SERVICES=[
  '0000ffe0-0000-1000-8000-00805f9b34fb',
  '0000ff00-0000-1000-8000-00805f9b34fb',
  '0000ae30-0000-1000-8000-00805f9b34fb',
  '000018f0-0000-1000-8000-00805f9b34fb',
  'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
  '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  '49535343-fe7d-4ae5-8fa9-9fafd205e455'
];
const ROUTES=[
  {id:'system',title:'Sistem / Android Print Service',meta:'JALUR 1 · SISTEM',desc:'Menggunakan dialog cetak sistem, Android Print Service, Mopria, atau layanan printer vendor. Ini adalah fallback universal tanpa akses ESC/POS langsung dari browser.'},
  {id:'usb',title:'USB OTG — ESC/POS',meta:'JALUR 2 · KABEL',desc:'Mengirim ESC/POS langsung melalui WebUSB ke printer USB yang kompatibel. Pada Android gunakan adaptor OTG dan Chrome/Chromium yang menyediakan WebUSB.'},
  {id:'ble',title:'Bluetooth LE — ESC/POS',meta:'JALUR 3 · NIRKABEL',desc:'Mengirim ESC/POS langsung melalui Bluetooth Low Energy (BLE/GATT). Jalur ini tidak sama dengan Bluetooth Classic/SPP.'},
  {id:'serial',title:'USB / Serial — ESC/POS',meta:'JALUR 4 · SERIAL',desc:'Mengirim ESC/POS melalui Web Serial/virtual COM pada browser dan perangkat yang mendukung Web Serial.'},
  {id:'app-bridge',title:'Android ESC/POS App Bridge',meta:'JALUR 5 · APLIKASI',desc:'Menyerahkan teks struk ke lembar Bagikan Android agar Anda memilih aplikasi ESC/POS/vendor yang sudah terhubung ke printer.'}
];
let active=null,restoring=false,connecting=null;
const errors={};
const enc=new TextEncoder();
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ascii=s=>String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^\x20-\x7E]/g,'?');
const rp=n=>'Rp '+Math.max(0,Number(n)||0).toLocaleString('id-ID');
const isAndroid=()=>{const ua=String(navigator.userAgent||''),platform=String(navigator.platform||''),uaPlatform=String(navigator.userAgentData?.platform||'');return /Android/i.test(ua)||/Android/i.test(uaPlatform)||(/Linux/i.test(platform)&&Number(navigator.maxTouchPoints||0)>1&&/Mobile/i.test(ua))};
const appBridgeMode=()=>!isAndroid()?'unsupported':typeof navigator.share==='function'?'web-share':'android-intent';

function readRaw(key){try{return JSON.parse(localStorage.getItem(key)||'{}')}catch{return {}}}
function normalizeLegacy(v){
  if(!v||typeof v!=='object')return {};
  let mode=v.defaultMode||v.mode||'';
  if(mode==='share')mode='app-bridge';
  if(mode==='bt-classic')mode='serial';
  if(mode==='android-system'||mode==='wifi-system')mode='system';
  return {...v,defaultMode:mode||undefined,paper:v.paper==='58mm'?'58mm':'80mm'};
}
function cfg(){
  const current=readRaw(STORE);
  if(Object.keys(current).length)return normalizeLegacy(current);
  const legacy=readRaw(LEGACY_STORE);
  if(Object.keys(legacy).length){
    const migrated=normalizeLegacy(legacy);
    try{localStorage.setItem(STORE,JSON.stringify(migrated))}catch{}
    return migrated;
  }
  return {paper:'80mm'};
}
function save(patch){const next={...cfg(),...patch};localStorage.setItem(STORE,JSON.stringify(next));return next}
function width(){return WIDTHS[cfg().paper]||42}

function splitWords(text,w=width()){
  const words=ascii(text).trim().split(/\s+/).filter(Boolean),out=[];let line='';
  for(const original of words){
    let word=original;
    while(word.length>w){if(line){out.push(line);line=''}out.push(word.slice(0,w));word=word.slice(w)}
    const next=line?line+' '+word:word;
    if(next.length>w){if(line)out.push(line);line=word}else line=next;
  }
  if(line)out.push(line);
  return out.length?out:[''];
}
function lr(left,right,w=width()){
  left=ascii(left);right=ascii(right);
  if(left.length+right.length+1<=w)return [left+' '.repeat(w-left.length-right.length)+right];
  const lines=splitWords(left,Math.max(14,w-right.length-1)),last=lines.pop()||'';
  return [...lines,last+' '.repeat(Math.max(1,w-last.length-right.length))+right];
}
function rule(ch='-'){return ch.repeat(width())}
function receiptText(r){
  const items=Array.isArray(r?.items)?r.items:[];
  const subtotal=Math.max(0,Number(r?.subtotal_amount??r?.subtotal)||items.reduce((s,i)=>s+(Number(i.quantity)||0)*(Number(i.price)||0),0));
  const charge=Math.max(0,Number(r?.charge_amount??r?.charge)||0);
  const tax=Math.max(0,Number(r?.tax_amount??r?.tax)||0);
  const total=Math.max(0,Number(r?.total_amount??r?.grand_total)||(subtotal+charge+tax));
  const pc=r?.transaction_pricing&&typeof r.transaction_pricing==='object'?r.transaction_pricing:{},cc=pc.charge||{},tc=pc.tax||{};
  const chargeLabel=cc.mode==='percent'&&Number(cc.value)>0?String(cc.label||'Charge')+' '+Number(cc.value)+'%':String(cc.label||'Charge');
  const taxLabel=tc.mode==='percent'&&Number(tc.value)>0?String(tc.label||'Pajak')+' '+Number(tc.value)+'%':String(tc.label||'Pajak');
  const when=new Date(r?.created_at||Date.now());
  const date=new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',day:'2-digit',month:'2-digit',year:'numeric'}).format(when);
  const time=new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',hour:'2-digit',minute:'2-digit',hour12:false}).format(when).replace('.',':')+' WIB';
  const out=['STRUK PEMBAYARAN & PEMESANAN',rule('=')];
  out.push(...lr('Kode',r?.payment_code||r?.public_order_code||'-'),...lr('Pemesan',r?.customer_name||'-'));
  out.push(...lr('Layanan',r?.service_mode==='dine-in'?'Makan di Tempat':'Bawa Pulang'));
  if(r?.service_mode==='dine-in')out.push(...lr('Meja',String(r?.table_number||'-')));
  if(r?.payment_method)out.push(...lr('Pembayaran',String(r.payment_method).toUpperCase()));
  out.push(...lr('Tanggal',date),...lr('Waktu',time),rule(),'RINCIAN PESANAN');
  for(const i of items){out.push(...splitWords(i?.name||'-'),...lr((Number(i?.quantity)||0)+' x '+rp(i?.price),rp((Number(i?.quantity)||0)*(Number(i?.price)||0))))}
  out.push(rule(),...lr('Subtotal',rp(subtotal)));
  if(charge>0)out.push(...lr(chargeLabel,rp(charge)));
  if(tax>0)out.push(...lr(taxLabel,rp(tax)));
  out.push(rule('='),...lr('TOTAL',rp(total)),rule('='),'Terima kasih','','');
  return out.join('\n');
}
function testReceipt(){
  return {payment_code:'TEST-PRINT',customer_name:'Pengujian Printer',service_mode:'take-away',payment_method:'TEST',created_at:new Date().toISOString(),items:[{name:'Tes Cetak SMART ORDER',quantity:1,price:1000}],subtotal_amount:1000,total_amount:1000};
}
function escpos(r){
  const body=enc.encode(receiptText(r)),init=Uint8Array.from([0x1b,0x40,0x1b,0x61,0x00]),cut=Uint8Array.from([0x0a,0x0a,0x0a,0x1d,0x56,0x42,0x00]);
  const out=new Uint8Array(init.length+body.length+cut.length);out.set(init);out.set(body,init.length);out.set(cut,init.length+body.length);return out;
}
function routeTitle(id){return ROUTES.find(x=>x.id===id)?.title||'Belum dipilih'}
function capability(id){
  if(id==='usb')return !!navigator.usb;
  if(id==='ble')return !!navigator.bluetooth;
  if(id==='serial')return !!navigator.serial;
  if(id==='app-bridge')return isAndroid();
  return true;
}
function state(id){
  if(!capability(id))return 'Tidak Didukung pada Perangkat Ini';
  if(connecting===id)return 'Menghubungkan';
  if(errors[id])return 'Error · '+errors[id];
  if(id==='app-bridge'){const mode=appBridgeMode(),label=mode==='web-share'?'Web Share':mode==='android-intent'?'Android Intent':'Tidak Didukung';return cfg().defaultMode===id?'Siap · '+label+' · Default':'Tersedia · '+label}
  if(id==='system')return cfg().defaultMode===id?'Siap · Default':'Tersedia';
  if(active?.route===id)return 'Terhubung'+(active.name?' · '+active.name:'')+(cfg().defaultMode===id?' · Default':'');
  return 'Belum Terhubung'+(cfg().defaultMode===id?' · Default':'');
}
function tutorial(id){
  const t={
    system:['Pastikan printer sudah ditambahkan ke Android/Windows melalui Print Service atau driver vendor.','Nyalakan printer dan pastikan perangkat kasir dapat melihat printer.','Tekan “Jadikan Default” bila jalur ini ingin digunakan saat mencetak struk.','Tekan “Test Print”, lalu pilih printer pada dialog cetak sistem.','Jika printer tidak muncul, periksa Print Service/driver, Wi-Fi/Bluetooth/USB, lalu coba kembali.'],
    usb:['Sambungkan printer ke HP/tablet menggunakan adaptor USB OTG dan nyalakan printer.','Gunakan Chrome/Chromium yang mendukung WebUSB; izinkan akses perangkat saat diminta.','Tekan “Hubungkan”, lalu pilih printer USB dari daftar perangkat.','Setelah status Terhubung, tekan “Test Print” dan kemudian “Jadikan Default”.','Jika tidak terdeteksi, cabut-pasang OTG, cek daya/kabel, dan pastikan printer mendukung USB printer class/WebUSB.'],
    ble:['Aktifkan Bluetooth dan nyalakan printer BLE/ESC-POS.','Pastikan printer menggunakan Bluetooth Low Energy, bukan hanya Bluetooth Classic/SPP.','Tekan “Hubungkan”, pilih printer, lalu izinkan pairing browser.','Setelah Terhubung, tekan “Test Print” lalu “Jadikan Default”.','Jika karakteristik tulis tidak ditemukan, gunakan USB OTG atau Android ESC/POS App Bridge.'],
    serial:['Hubungkan printer/adapter yang menyediakan port Serial/virtual COM dan nyalakan printer.','Gunakan browser desktop/Chromebook yang mendukung Web Serial dan izinkan akses port.','Tekan “Hubungkan”, pilih port printer, lalu tunggu status Terhubung.','Tekan “Test Print” dan “Jadikan Default” bila hasil cetak benar.','Jika gagal, cek port, driver, baud rate printer, lalu putuskan dan hubungkan kembali.'],
    'app-bridge':['Instal aplikasi ESC/POS/vendor printer di Android dan hubungkan printer di aplikasi tersebut terlebih dahulu.','Pastikan aplikasi printer dapat mencetak dari perangkat Android.','Tekan “Jadikan Default” untuk memakai jalur App Bridge.','Tekan “Test Print”; pada lembar Bagikan Android pilih aplikasi ESC/POS/vendor printer.','Jika aplikasi tidak muncul, periksa instalasi/izin aplikasi dan koneksi printer di aplikasi vendor.']
  };
  return t[id]||[];
}
function ensureStyle(){
  if(document.getElementById('sdbThermalPrinterCssV3'))return;
  const s=document.createElement('style');s.id='sdbThermalPrinterCssV3';
  s.textContent='.sdbPrinterHero{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;flex-wrap:wrap}.sdbPrinterStatus{padding:7px 10px;border-radius:999px;background:#eef5f2;border:1px solid #d8e4de;font-size:11px;font-weight:800}.sdbPrinterGrid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-top:14px}.sdbPrinterCard{border:1px solid var(--line,#dfe5e1);border-radius:14px;background:var(--panel,#fff);padding:15px;display:grid;gap:9px}.sdbPrinterCard h3{margin:0;font-size:15px}.sdbPrinterCard p,.sdbPrinterCard li{color:var(--muted,#6d7b75);font-size:12px;line-height:1.5}.sdbPrinterCard p{margin:0}.sdbPrinterCard ol{margin:2px 0 0;padding-left:19px}.sdbPrinterCard .meta{font-size:10px;font-weight:850;letter-spacing:.06em;text-transform:uppercase;color:#688078}.sdbPrinterActions{display:flex;gap:7px;flex-wrap:wrap;margin-top:4px}.sdbPrinterActions button{min-height:38px}.sdbPrinterDefault{outline:2px solid color-mix(in srgb,var(--primary,#173f33) 25%,transparent)}.sdbPrinterUnsupported{opacity:.58}.sdbPrinterPaper{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.sdbPrinterPaper select{min-height:36px}.sdbPrinterWarn{margin-top:14px;padding:11px 12px;border-radius:12px;background:#fff8e9;border:1px solid #efe0b9;color:#6d5826;font-size:12px;line-height:1.5}@media(max-width:760px){.sdbPrinterGrid{grid-template-columns:1fr}}';
  document.head.appendChild(s);
}
function routeCard(r){
  const ok=capability(r.id),direct=['usb','ble','serial'].includes(r.id),isDefault=cfg().defaultMode===r.id;
  const steps=tutorial(r.id).map(x=>'<li>'+esc(x)+'</li>').join('');
  return '<article class="sdbPrinterCard '+(!ok?'sdbPrinterUnsupported ':'')+(isDefault?'sdbPrinterDefault':'')+'"><div class="meta">'+esc(r.meta)+'</div><h3>'+esc(r.title)+'</h3><p>'+esc(r.desc)+'</p><span class="sdbPrinterStatus" data-sdb-route-status="'+esc(r.id)+'">'+esc(state(r.id))+'</span><ol>'+steps+'</ol><div class="sdbPrinterActions">'+
    (direct?'<button type="button" class="btn soft" data-sdb-connect="'+r.id+'" '+(!ok?'disabled':'')+'>Hubungkan</button><button type="button" class="btn soft" data-sdb-disconnect="'+r.id+'" '+(!(active?.route===r.id)?'disabled':'')+'>Putuskan</button>':'')+
    '<button type="button" class="btn soft" data-sdb-test="'+r.id+'" '+(!ok?'disabled':'')+'>Test Print</button>'+
    '<button type="button" class="btn '+(isDefault?'primary':'soft')+'" data-sdb-default="'+r.id+'" '+(!ok?'disabled':'')+'>'+(isDefault?'Default Aktif':'Jadikan Default')+'</button></div></article>';
}
function settingsHtml(){
  const c=cfg();
  return '<div class="sectionHead"><div><div class="ey">PENGATURAN</div><h1>Printer Thermal</h1><p>Pilih satu dari lima jalur printer SMART ORDER. Koneksi perangkat dan Test Print hanya berjalan setelah tindakan pengguna.</p></div><span class="sdbPrinterStatus">Default · '+esc(routeTitle(c.defaultMode||'system'))+'</span></div>'+
    '<section class="card sdbPrinterHero"><div><h3 style="margin:0">Konfigurasi Printer</h3><p style="margin:4px 0 0;color:var(--muted)">Kegagalan printer tidak memengaruhi pembayaran, penyimpanan order, atau status pesanan.</p></div><label class="sdbPrinterPaper">Lebar kertas <select data-sdb-paper><option value="80mm" '+(c.paper!=='58mm'?'selected':'')+'>80 mm</option><option value="58mm" '+(c.paper==='58mm'?'selected':'')+'>58 mm</option></select></label></section>'+
    '<div class="sdbPrinterGrid">'+ROUTES.map(routeCard).join('')+'</div>'+
    '<div class="sdbPrinterWarn"><b>Kompatibilitas:</b> Bluetooth LE berbeda dari Bluetooth Classic/SPP. Untuk printer Android yang hanya mendukung Classic/SPP, gunakan Android ESC/POS App Bridge atau Print Service/vendor. WebUSB/WebSerial/Web Bluetooth bergantung pada dukungan browser dan perangkat.</div>';
}
function refresh(){
  document.querySelectorAll('[data-sdb-route-status]').forEach(n=>n.textContent=state(n.dataset.sdbRouteStatus));
}
function renderSettings(){
  ensureStyle();const view=document.getElementById('view');if(!view)return;
  const sub=document.querySelector('.subnav');if(sub)sub.querySelectorAll('button').forEach(b=>b.classList.toggle('on',b.dataset.sdbPrinterSettings==='1'));
  view.innerHTML=settingsHtml();
  view.querySelector('[data-sdb-paper]')?.addEventListener('change',e=>{save({paper:e.target.value==='58mm'?'58mm':'80mm'});renderSettings()});
  view.querySelectorAll('[data-sdb-connect]').forEach(b=>b.addEventListener('click',()=>connect(b.dataset.sdbConnect)));
  view.querySelectorAll('[data-sdb-disconnect]').forEach(b=>b.addEventListener('click',()=>disconnect(b.dataset.sdbDisconnect)));
  view.querySelectorAll('[data-sdb-test]').forEach(b=>b.addEventListener('click',()=>testPrint(b.dataset.sdbTest)));
  view.querySelectorAll('[data-sdb-default]').forEach(b=>b.addEventListener('click',()=>setDefault(b.dataset.sdbDefault)));
}
function ensureSettingsNav(){
  const nav=document.querySelector('.mainNav'),sub=document.querySelector('.subnav');if(!nav||!sub)return;
  const settings=[...nav.querySelectorAll('button')].find(b=>b.dataset.settingsMain==='1'||(b.textContent||'').trim().toUpperCase()==='PENGATURAN');
  if(!settings?.classList.contains('on')||sub.querySelector('[data-sdb-printer-settings="1"]'))return;
  const b=document.createElement('button');b.type='button';b.dataset.sdbPrinterSettings='1';b.textContent='Printer Thermal';
  b.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();renderSettings()});sub.appendChild(b);
}
async function connect(id){
  if(!capability(id))return;
  connecting=id;delete errors[id];refresh();
  try{
    if(id==='usb')await connectUsb();
    else if(id==='ble')await connectBle();
    else if(id==='serial')await connectSerial();
  }catch(err){errors[id]=String(err?.message||err);alert('Printer belum terhubung: '+errors[id])}
  finally{connecting=null;refresh();renderSettings()}
}
async function connectUsb(){
  if(!navigator.usb)throw Error('WebUSB tidak tersedia di browser ini.');
  const device=await navigator.usb.requestDevice({filters:[{classCode:7}]});await device.open();
  if(!device.configuration)await device.selectConfiguration(device.configurations?.[0]?.configurationValue||1);
  let choice=null;
  for(const intf of device.configuration?.interfaces||[]){for(const alt of intf.alternates||[]){const out=alt.endpoints?.find(e=>e.direction==='out');if(out){choice={interfaceNumber:intf.interfaceNumber,alternateSetting:alt.alternateSetting,endpointNumber:out.endpointNumber};break}}if(choice)break}
  if(!choice){await device.close();throw Error('Endpoint OUT USB tidak ditemukan. Gunakan Print Service/App Bridge.')}
  await device.claimInterface(choice.interfaceNumber);if(choice.alternateSetting)await device.selectAlternateInterface(choice.interfaceNumber,choice.alternateSetting);
  await closeActive();active={mode:'usb',route:'usb',device,...choice,name:device.productName||'Thermal USB'};
  save({usb:{vendorId:device.vendorId,productId:device.productId,name:device.productName||''}});
}
async function writableBleCharacteristic(device){
  const server=await device.gatt.connect();
  for(const uuid of BLE_SERVICES){try{const service=await server.getPrimaryService(uuid),chars=await service.getCharacteristics(),ch=chars.find(x=>x.properties?.writeWithoutResponse)||chars.find(x=>x.properties?.write);if(ch)return {server,serviceUuid:uuid,characteristic:ch}}catch{}}
  try{server.disconnect()}catch{};throw Error('Karakteristik BLE tulis ESC/POS tidak ditemukan. Gunakan USB OTG/App Bridge.');
}
async function connectBle(){
  if(!navigator.bluetooth)throw Error('Web Bluetooth tidak tersedia di browser ini.');
  const device=await navigator.bluetooth.requestDevice({acceptAllDevices:true,optionalServices:BLE_SERVICES}),found=await writableBleCharacteristic(device);
  await closeActive();active={mode:'ble',route:'ble',device,...found,name:device.name||'Thermal BLE'};
  device.addEventListener('gattserverdisconnected',()=>{if(active?.device===device){active=null;refresh()}});
  save({ble:{deviceId:device.id,name:device.name||'',serviceUuid:found.serviceUuid,characteristicUuid:found.characteristic.uuid}});
}
async function connectSerial(){
  if(!navigator.serial)throw Error('Web Serial tidak tersedia di browser ini.');
  const port=await navigator.serial.requestPort(),baudRate=9600;await port.open({baudRate});const info=port.getInfo?.()||{};
  await closeActive();active={mode:'serial',route:'serial',port,baudRate,name:'Serial Thermal'};
  save({serial:{baudRate,usbVendorId:info.usbVendorId||null,usbProductId:info.usbProductId||null}});
}
async function closeActive(){
  const a=active;active=null;if(!a)return;
  try{if(a.mode==='usb'){try{await a.device.releaseInterface(a.interfaceNumber)}catch{}try{await a.device.close()}catch{}}else if(a.mode==='serial'){try{await a.port.close()}catch{}}else if(a.mode==='ble'){try{a.device.gatt?.disconnect()}catch{}}}catch{}
}
async function disconnect(id){
  if(active?.route===id)await closeActive();
  const c=cfg();if(id==='usb')delete c.usb;if(id==='ble')delete c.ble;if(id==='serial')delete c.serial;localStorage.setItem(STORE,JSON.stringify(c));delete errors[id];renderSettings();
}
function setDefault(id){if(!capability(id))return;save({defaultMode:id});renderSettings()}
async function restore(id=cfg().defaultMode){
  if(restoring||active||!['usb','ble','serial'].includes(id))return;restoring=true;
  try{
    const c=cfg();
    if(id==='usb'&&navigator.usb&&c.usb){const devices=await navigator.usb.getDevices(),d=devices.find(x=>(!c.usb.vendorId||x.vendorId===c.usb.vendorId)&&(!c.usb.productId||x.productId===c.usb.productId));if(d){await d.open();if(!d.configuration)await d.selectConfiguration(d.configurations?.[0]?.configurationValue||1);let ch=null;for(const intf of d.configuration?.interfaces||[]){for(const alt of intf.alternates||[]){const out=alt.endpoints?.find(e=>e.direction==='out');if(out){ch={interfaceNumber:intf.interfaceNumber,alternateSetting:alt.alternateSetting,endpointNumber:out.endpointNumber};break}}if(ch)break}if(ch){await d.claimInterface(ch.interfaceNumber);if(ch.alternateSetting)await d.selectAlternateInterface(ch.interfaceNumber,ch.alternateSetting);active={mode:'usb',route:'usb',device:d,...ch,name:d.productName||c.usb.name||'Thermal USB'}}}}
    else if(id==='serial'&&navigator.serial&&c.serial){const ports=await navigator.serial.getPorts(),p=ports.find(x=>{const i=x.getInfo?.()||{};return (!c.serial.usbVendorId||i.usbVendorId===c.serial.usbVendorId)&&(!c.serial.usbProductId||i.usbProductId===c.serial.usbProductId)})||ports[0];if(p){await p.open({baudRate:Number(c.serial.baudRate)||9600});active={mode:'serial',route:'serial',port:p,baudRate:Number(c.serial.baudRate)||9600,name:'Serial Thermal'}}}
    else if(id==='ble'&&navigator.bluetooth?.getDevices&&c.ble){const devices=await navigator.bluetooth.getDevices(),d=devices.find(x=>x.id===c.ble.deviceId);if(d){const server=await d.gatt.connect(),service=await server.getPrimaryService(c.ble.serviceUuid),characteristic=await service.getCharacteristic(c.ble.characteristicUuid);active={mode:'ble',route:'ble',device:d,server,serviceUuid:c.ble.serviceUuid,characteristic,name:d.name||c.ble.name||'Thermal BLE'}}}
  }catch(err){errors[id]=String(err?.message||err)}finally{restoring=false;refresh()}
}
async function bleWrite(ch,bytes){for(let i=0;i<bytes.length;i+=120){const chunk=bytes.slice(i,i+120);if(ch.properties?.writeWithoutResponse&&ch.writeValueWithoutResponse)await ch.writeValueWithoutResponse(chunk);else if(ch.writeValueWithResponse)await ch.writeValueWithResponse(chunk);else await ch.writeValue(chunk)}}
async function directPrint(r){
  const bytes=escpos(r);
  if(active?.mode==='usb'){const x=await active.device.transferOut(active.endpointNumber,bytes);if(x.status!=='ok')throw Error('Transfer USB gagal.');return}
  if(active?.mode==='serial'){const w=active.port.writable?.getWriter();if(!w)throw Error('Port serial tidak siap.');try{await w.write(bytes)}finally{w.releaseLock()}return}
  if(active?.mode==='ble'){await bleWrite(active.characteristic,bytes);return}
  throw Error('Printer direct belum terhubung.');
}
async function appBridgePrint(r){
  if(!isAndroid())throw Error('Android App Bridge hanya tersedia pada perangkat Android.');
  const title='Struk SMART ORDER',text=receiptText(r);
  if(typeof navigator.share==='function')return navigator.share({title,text});
  const intent='intent:#Intent;action=android.intent.action.SEND;type=text/plain;S.android.intent.extra.SUBJECT='+encodeURIComponent(title)+';S.android.intent.extra.TEXT='+encodeURIComponent(text)+';end';
  location.href=intent;
  return 'android-intent';
}
function systemPrint(r){
  const old=document.getElementById('sdbPrinterFrameV3');if(old)old.remove();
  const frame=document.createElement('iframe');frame.id='sdbPrinterFrameV3';frame.setAttribute('aria-hidden','true');frame.style.cssText='position:fixed;width:1px;height:1px;right:0;bottom:0;border:0;opacity:.001;pointer-events:none';document.body.appendChild(frame);
  const doc=frame.contentDocument,lines=receiptText(r).split('\n').map(x=>esc(x)).join('<br>'),paper=cfg().paper==='58mm'?'58mm':'80mm';
  doc.open();doc.write('<!doctype html><html><head><meta charset="utf-8"><title>Struk SMART ORDER</title><style>@page{size:'+paper+' auto;margin:0}*{box-sizing:border-box}html,body{width:'+paper+';max-width:'+paper+';margin:0;padding:0}body{font:12px/1.38 ui-monospace,SFMono-Regular,Consolas,monospace;color:#000}.paper{width:'+paper+';max-width:'+paper+';padding:4mm;overflow:hidden;overflow-wrap:anywhere;word-break:break-word}</style></head><body><main class="paper">'+lines+'</main></body></html>');doc.close();
  setTimeout(()=>{try{frame.contentWindow.focus();frame.contentWindow.print()}catch{alert('Dialog cetak tidak dapat dibuka. Gunakan menu Print/Cetak pada browser.')}setTimeout(()=>frame.remove(),1500)},80);
}
async function printWithRoute(r,id){
  if(id==='system'){systemPrint(r);return 'system'}
  if(id==='app-bridge'){try{await appBridgePrint(r);return 'app-bridge'}catch(err){if(String(err?.name||'')==='AbortError')return 'cancelled';throw err}}
  if(!active||active.route!==id)await restore(id);
  if(!active||active.route!==id)throw Error('Hubungkan printer '+routeTitle(id)+' terlebih dahulu.');
  await directPrint(r);return id;
}
async function testPrint(id){try{await printWithRoute(testReceipt(),id)}catch(err){errors[id]=String(err?.message||err);refresh();alert('Test Print gagal: '+errors[id])}}
async function print(r){
  if(!r)return;const id=cfg().defaultMode||'system';
  try{return await printWithRoute(r,id)}
  catch(err){errors[id]=String(err?.message||err);await closeActive();refresh();alert('Jalur printer default tidak siap. SMART ORDER akan membuka Printer Sistem.');systemPrint(r);return 'system-fallback'}
}
function interceptReceiptPrint(e){
  const b=e.target.closest?.('[data-rc6-receipt-print]');if(!b)return;const r=window.__SDB_LAST_CASHIER_RECEIPT__;if(!r)return;
  e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();print(r).catch(err=>alert('Gagal mencetak: '+String(err?.message||err)));
}
function boot(){
  ensureStyle();ensureSettingsNav();restore();
  document.addEventListener('click',interceptReceiptPrint,true);
  new MutationObserver(()=>ensureSettingsNav()).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
  document.addEventListener('rohmat:navigation',()=>setTimeout(ensureSettingsNav,0));
}
if(navigator.usb){
  navigator.usb.addEventListener('disconnect',e=>{if(active?.mode==='usb'&&active.device===e.device){active=null;refresh()}});
  navigator.usb.addEventListener('connect',()=>restore('usb'));
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.__SDB_THERMAL_PRINTER__={connect,disconnect,status:state,capability,print,testPrint,setDefault,restore,renderSettings,version:'v3-smart-order-five-route'};
})();