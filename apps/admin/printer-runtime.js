(()=>{'use strict';
if(window.__SDB_THERMAL_PRINTER_RUNTIME_V2)return;
window.__SDB_THERMAL_PRINTER_RUNTIME_V2=1;

const STORE='sdb-smart-cashier-printer-v2';
const WIDTH=42;
const BLE_SERVICES=[
  '0000ffe0-0000-1000-8000-00805f9b34fb',
  '0000ff00-0000-1000-8000-00805f9b34fb',
  '0000ae30-0000-1000-8000-00805f9b34fb',
  '000018f0-0000-1000-8000-00805f9b34fb',
  'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
  '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  '49535343-fe7d-4ae5-8fa9-9fafd205e455'
];
let active=null;
let restoring=false;
const enc=new TextEncoder();
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ascii=s=>String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^\x20-\x7E]/g,'?');
const rp=n=>'Rp '+Math.max(0,Number(n)||0).toLocaleString('id-ID');
const cfg=()=>{try{return JSON.parse(localStorage.getItem(STORE)||'{}')}catch{return {}}};
const save=v=>localStorage.setItem(STORE,JSON.stringify(v||{}));
const clear=()=>localStorage.removeItem(STORE);
const isAndroid=()=>/Android/i.test(navigator.userAgent||'');
const isMobile=()=>/Android|Mobile|Tablet/i.test(navigator.userAgent||'');

function splitWords(text,width=WIDTH){
  const words=ascii(text).trim().split(/\s+/).filter(Boolean),out=[];let line='';
  for(const w0 of words){
    let w=w0;
    while(w.length>width){if(line){out.push(line);line=''}out.push(w.slice(0,width));w=w.slice(width)}
    const next=line?line+' '+w:w;
    if(next.length>width){if(line)out.push(line);line=w}else line=next;
  }
  if(line)out.push(line);
  return out.length?out:[''];
}
function lr(left,right,width=WIDTH){
  left=ascii(left);right=ascii(right);
  if(left.length+right.length+1<=width)return [left+' '.repeat(width-left.length-right.length)+right];
  const lines=splitWords(left,Math.max(16,width-right.length-1));
  const last=lines.pop()||'';
  return [...lines,last+' '.repeat(Math.max(1,width-last.length-right.length))+right];
}
function rule(ch='-'){return ch.repeat(WIDTH)}
function receiptText(r){
  const items=Array.isArray(r?.items)?r.items:[];
  const subtotal=Math.max(0,Number(r?.subtotal_amount??r?.subtotal)||items.reduce((s,i)=>s+(Number(i.quantity)||0)*(Number(i.price)||0),0));
  const charge=Math.max(0,Number(r?.charge_amount??r?.charge)||0);
  const tax=Math.max(0,Number(r?.tax_amount??r?.tax)||0);
  const total=Math.max(0,Number(r?.total_amount??r?.grand_total)||(subtotal+charge+tax));
  const pc=r?.transaction_pricing&&typeof r.transaction_pricing==='object'?r.transaction_pricing:{};
  const cc=pc.charge||{},tc=pc.tax||{};
  const chargeLabel=cc.mode==='percent'&&Number(cc.value)>0?String(cc.label||'Charge')+' '+Number(cc.value)+'%':String(cc.label||'Charge');
  const taxLabel=tc.mode==='percent'&&Number(tc.value)>0?String(tc.label||'Pajak')+' '+Number(tc.value)+'%':String(tc.label||'Pajak');
  const when=new Date(r?.created_at||Date.now());
  const date=new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',day:'2-digit',month:'2-digit',year:'numeric'}).format(when);
  const time=new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',hour:'2-digit',minute:'2-digit',hour12:false}).format(when).replace('.',':')+' WIB';
  const out=['STRUK PEMBAYARAN & PEMESANAN',rule('=')];
  out.push(...lr('Kode',r?.payment_code||r?.public_order_code||'-'));
  out.push(...lr('Pemesan',r?.customer_name||'-'));
  out.push(...lr('Layanan',r?.service_mode==='dine-in'?'Makan di Tempat':'Bawa Pulang'));
  if(r?.service_mode==='dine-in')out.push(...lr('Meja',String(r?.table_number||'-')));
  if(r?.payment_method)out.push(...lr('Pembayaran',String(r.payment_method).toUpperCase()));
  out.push(...lr('Tanggal',date),...lr('Waktu',time),rule(),'RINCIAN PESANAN');
  for(const i of items){
    out.push(...splitWords(i?.name||'-'));
    out.push(...lr((Number(i?.quantity)||0)+' x '+rp(i?.price),rp((Number(i?.quantity)||0)*(Number(i?.price)||0))));
  }
  out.push(rule(),...lr('Subtotal',rp(subtotal)));
  if(charge>0)out.push(...lr(chargeLabel,rp(charge)));
  if(tax>0)out.push(...lr(taxLabel,rp(tax)));
  out.push(rule('='),...lr('TOTAL',rp(total)),rule('='),'Terima kasih','','');
  return out.flat().join('\n');
}
function escpos(r){
  const body=enc.encode(receiptText(r));
  const init=Uint8Array.from([0x1b,0x40,0x1b,0x61,0x00]);
  const feedcut=Uint8Array.from([0x0a,0x0a,0x0a,0x1d,0x56,0x42,0x00]);
  const out=new Uint8Array(init.length+body.length+feedcut.length);
  out.set(init,0);out.set(body,init.length);out.set(feedcut,init.length+body.length);
  return out;
}
function modeLabel(mode){
  return ({
    'bt-classic':'Bluetooth Classic / SPP',
    'ble':'Bluetooth Low Energy (BLE)',
    'usb':'USB / USB OTG',
    'serial':'Serial / COM',
    'share':'Aplikasi Printer Android',
    'system':'Printer Sistem'
  })[mode]||'Belum dipilih';
}
function statusText(){
  const s=cfg();
  if(active)return 'Terhubung · '+modeLabel(active.route||active.mode)+(active.name?' · '+active.name:'');
  if(s.mode)return 'Tersimpan · '+modeLabel(s.mode);
  return 'Belum terhubung';
}
function capability(){
  return {
    android:isAndroid(),
    mobile:isMobile(),
    usb:!!navigator.usb,
    serial:!!navigator.serial,
    bluetooth:!!navigator.bluetooth,
    share:typeof navigator.share==='function',
    system:true
  };
}
function style(){
  if(document.getElementById('sdbThermalPrinterCssV2'))return;
  const s=document.createElement('style');s.id='sdbThermalPrinterCssV2';
  s.textContent='.sdbPrinterHero{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;flex-wrap:wrap}.sdbPrinterStatus{padding:8px 11px;border-radius:999px;background:#eef5f2;border:1px solid #d8e4de;font-size:12px;font-weight:800}.sdbPrinterGrid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-top:14px}.sdbPrinterCard{border:1px solid var(--line,#dfe5e1);border-radius:14px;background:var(--panel,#fff);padding:15px;display:grid;gap:9px}.sdbPrinterCard h3{margin:0;font-size:15px}.sdbPrinterCard p{margin:0;color:var(--muted,#6d7b75);font-size:12px;line-height:1.5}.sdbPrinterCard .meta{font-size:10px;font-weight:850;letter-spacing:.06em;text-transform:uppercase;color:#688078}.sdbPrinterActions{display:flex;gap:8px;flex-wrap:wrap;margin-top:4px}.sdbPrinterActions button{min-height:39px}.sdbPrinterWarn{margin-top:14px;padding:11px 12px;border-radius:12px;background:#fff8e9;border:1px solid #efe0b9;color:#6d5826;font-size:12px;line-height:1.5}.sdbPrinterSupport{display:flex;gap:7px;flex-wrap:wrap;margin-top:10px}.sdbPrinterSupport span{padding:5px 8px;border-radius:999px;background:#f1f4f3;font-size:10px;font-weight:800}.sdbPrinterSupport .yes{background:#e8f7f0;color:#176548}.sdbPrinterSupport .no{background:#f8eeee;color:#8b3d3d}@media(max-width:760px){.sdbPrinterGrid{grid-template-columns:1fr}}';
  document.head.appendChild(s);
}
function supportBadge(name,ok){return '<span class="'+(ok?'yes':'no')+'">'+esc(name)+' · '+(ok?'tersedia':'tidak tersedia')+'</span>'}
function settingsHtml(){
  const c=capability(),s=cfg();
  const card=(meta,title,desc,mode,available,button='Hubungkan')=>'<article class="sdbPrinterCard"><div class="meta">'+esc(meta)+'</div><h3>'+esc(title)+'</h3><p>'+esc(desc)+'</p><div class="sdbPrinterActions"><button type="button" class="btn '+(available?'primary':'soft')+'" data-sdb-printer-mode="'+esc(mode)+'" '+(available?'':'disabled')+'>'+esc(button)+'</button></div></article>';
  return '<div class="sectionHead"><div><div class="ey">PENGATURAN</div><h1>Printer Thermal</h1><p>Hubungkan printer pembayaran SMART CASHIER. Tidak ada pairing atau cetak uji otomatis; akses perangkat hanya berjalan setelah tindakan pengguna.</p></div><span class="sdbPrinterStatus" data-sdb-printer-status>'+esc(statusText())+'</span></div>'+
    '<section class="card"><div class="sdbPrinterHero"><div><h3 style="margin:0">Perangkat ini</h3><p style="margin:4px 0 0;color:var(--muted)">SMART CASHIER mendeteksi kemampuan browser secara lokal.</p></div><div class="sdbPrinterActions"><button type="button" class="btn soft" data-sdb-printer-disconnect '+(s.mode?'':'disabled')+'>Putuskan / Lupakan</button></div></div><div class="sdbPrinterSupport">'+
    supportBadge('Android',c.android)+supportBadge('Web Bluetooth BLE',c.bluetooth)+supportBadge('WebUSB / OTG',c.usb)+supportBadge('Bagikan ke aplikasi printer',c.share)+supportBadge('Android/System Print',true)+supportBadge('Web Serial (desktop)',c.serial&&!c.android)+'</div></section>'+
    '<div class="sdbPrinterGrid">'+
    card('ANDROID / TABLET · DIREK','Bluetooth Low Energy (BLE)','Untuk printer BLE/GATT yang menyediakan karakteristik tulis ESC/POS. Runtime mencoba service BLE/UART printer thermal yang umum; pairing hanya dimulai setelah pengguna memilih perangkat.','ble',c.android&&c.bluetooth)+
    card('ANDROID / TABLET · KABEL','USB OTG / WebUSB','Untuk printer USB yang dihubungkan lewat adaptor OTG dan dapat diakses Chrome Android melalui WebUSB. Android tetap menampilkan izin perangkat sebelum koneksi dibuka.','usb',c.android&&c.usb)+
    card('ANDROID / TABLET · APLIKASI','Bagikan ke Aplikasi Printer Android','Untuk printer Bluetooth Classic/SPP atau model vendor yang memakai aplikasi pendamping. Saat mencetak, SMART CASHIER membuka lembar Bagikan Android agar pengguna memilih aplikasi printer yang sudah terpasang.','share',c.android&&c.share,'Gunakan Jalur Ini')+
    card('ANDROID / TABLET · UNIVERSAL','Android System Print · Wi-Fi / Print Service','Untuk printer yang sudah ditambahkan ke Android melalui Wi-Fi, layanan cetak sistem, atau PrintService/vendor plugin. SMART CASHIER menyiapkan struk 80 mm lalu menyerahkannya ke dialog cetak Android.','system',true,'Gunakan Jalur Ini')+
    card('DESKTOP / CHROMEBOOK · DIREK','USB ESC/POS','Koneksi langsung ke endpoint USB printer ESC/POS pada browser Chromium yang mendukung WebUSB.','usb',!c.android&&c.usb)+
    card('DESKTOP / CHROMEBOOK · DIREK','Bluetooth Classic / SPP atau Serial / COM','Untuk Chrome desktop yang mengekspos Bluetooth Classic RFCOMM/SPP atau port serial melalui Web Serial.','serial',!c.android&&c.serial)+
    card('DESKTOP · UNIVERSAL','Printer Sistem / Driver Windows','Menghasilkan struk 80 mm dan menyerahkan job ke dialog printer Windows/browser.','system',true,'Gunakan Jalur Ini')+
    '</div><div class="sdbPrinterWarn"><b>Catatan kompatibilitas.</b> Pada Android, SMART CASHIER memprioritaskan BLE, USB OTG/WebUSB, Bagikan ke Aplikasi Printer, lalu Android System Print sebagai fallback universal. Bluetooth Classic/SPP tidak diklaim sebagai koneksi langsung browser Android; untuk printer Classic gunakan aplikasi printer/PrintService vendor. Semua direct-print memakai ESC/POS hanya pada perangkat yang kompatibel dan otomatis kembali ke System Print bila koneksi direct gagal.</div>';
}
function updateSettingsStatus(){
  const st=document.querySelector('[data-sdb-printer-status]');if(st)st.textContent=statusText();
  const d=document.querySelector('[data-sdb-printer-disconnect]');if(d)d.disabled=!cfg().mode;
}
function renderSettings(){
  style();
  const view=document.getElementById('view');if(!view)return;
  const sub=document.querySelector('.subnav');
  if(sub)sub.querySelectorAll('button').forEach(b=>b.classList.toggle('on',b.dataset.sdbPrinterSettings==='1'));
  view.innerHTML=settingsHtml();
  view.querySelectorAll('[data-sdb-printer-mode]').forEach(b=>b.addEventListener('click',()=>choose(b.dataset.sdbPrinterMode,b)));
  view.querySelector('[data-sdb-printer-disconnect]')?.addEventListener('click',async()=>{await disconnect();renderSettings()});
}
function ensureSettingsNav(){
  const nav=document.querySelector('.mainNav'),sub=document.querySelector('.subnav');
  if(!nav||!sub)return;
  const settings=[...nav.querySelectorAll('button')].find(b=>b.dataset.settingsMain==='1'||(b.textContent||'').trim().toUpperCase()==='PENGATURAN');
  if(!settings?.classList.contains('on'))return;
  if(sub.querySelector('[data-sdb-printer-settings="1"]'))return;
  const b=document.createElement('button');b.type='button';b.dataset.sdbPrinterSettings='1';b.textContent='Printer Thermal';
  b.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();renderSettings()});
  sub.appendChild(b);
}
async function choose(mode,button){
  if(button)button.disabled=true;
  try{
    if(mode==='bt-classic')await connectSerial('bt-classic');
    else if(mode==='ble')await connectBle();
    else if(mode==='usb')await connectUsb();
    else if(mode==='serial')await connectSerial('serial');
    else if(mode==='share'){await closeActive();active=null;save({mode:'share',paper:'80mm'});}
    else {await closeActive();active=null;save({mode:'system',paper:'80mm'});}
    updateSettingsStatus();
  }catch(err){
    alert('Printer belum terhubung: '+String(err?.message||err));
  }finally{if(button&&button.isConnected)button.disabled=false}
}
async function connectUsb(){
  if(!navigator.usb)throw Error('WebUSB tidak tersedia di browser ini.');
  const device=await navigator.usb.requestDevice({filters:[]});
  await device.open();
  if(!device.configuration)await device.selectConfiguration(device.configurations?.[0]?.configurationValue||1);
  let choice=null;
  for(const intf of device.configuration?.interfaces||[]){
    for(const alt of intf.alternates||[]){
      const out=alt.endpoints?.find(e=>e.direction==='out');
      if(out){choice={interfaceNumber:intf.interfaceNumber,alternateSetting:alt.alternateSetting,endpointNumber:out.endpointNumber};break}
    }
    if(choice)break;
  }
  if(!choice){await device.close();throw Error('Endpoint OUT USB tidak ditemukan. Gunakan Printer Sistem/PrintService.')}
  await device.claimInterface(choice.interfaceNumber);
  if(choice.alternateSetting)await device.selectAlternateInterface(choice.interfaceNumber,choice.alternateSetting);
  await closeActive();
  active={mode:'usb',route:'usb',device,...choice,name:device.productName||'Thermal USB'};
  save({mode:'usb',paper:'80mm',vendorId:device.vendorId,productId:device.productId,name:device.productName||''});
}
async function connectSerial(route='serial'){
  if(!navigator.serial)throw Error('Web Serial tidak tersedia di browser ini.');
  const options=route==='bt-classic'?{}:{};
  const port=await navigator.serial.requestPort(options);
  await port.open({baudRate:9600});
  const info=port.getInfo?.()||{};
  await closeActive();
  active={mode:'serial',route,port,baudRate:9600,name:route==='bt-classic'?'Bluetooth SPP':'Serial'};
  save({mode:route,paper:'80mm',baudRate:9600,usbVendorId:info.usbVendorId||null,usbProductId:info.usbProductId||null});
}
async function writableBleCharacteristic(device){
  const server=await device.gatt.connect();
  for(const uuid of BLE_SERVICES){
    try{
      const service=await server.getPrimaryService(uuid);
      const chars=await service.getCharacteristics();
      const ch=chars.find(x=>x.properties?.writeWithoutResponse)||chars.find(x=>x.properties?.write);
      if(ch)return {server,serviceUuid:uuid,characteristic:ch};
    }catch{}
  }
  try{
    const services=await server.getPrimaryServices();
    for(const service of services){
      const chars=await service.getCharacteristics();
      const ch=chars.find(x=>x.properties?.writeWithoutResponse)||chars.find(x=>x.properties?.write);
      if(ch)return {server,serviceUuid:service.uuid,characteristic:ch};
    }
  }catch{}
  try{server.disconnect()}catch{}
  throw Error('Karakteristik BLE tulis yang kompatibel tidak ditemukan. Gunakan USB OTG atau Android System Print/PrintService.');
}
async function connectBle(){
  if(!navigator.bluetooth)throw Error('Web Bluetooth tidak tersedia di browser ini.');
  const device=await navigator.bluetooth.requestDevice({acceptAllDevices:true,optionalServices:BLE_SERVICES});
  const found=await writableBleCharacteristic(device);
  await closeActive();
  active={mode:'ble',route:'ble',device,...found,name:device.name||'Thermal BLE'};
  device.addEventListener('gattserverdisconnected',()=>{if(active?.device===device){active=null;updateSettingsStatus()}});
  save({mode:'ble',paper:'80mm',deviceId:device.id,name:device.name||'',serviceUuid:found.serviceUuid,characteristicUuid:found.characteristic.uuid});
}
async function closeActive(){
  const a=active;active=null;if(!a)return;
  try{
    if(a.mode==='usb'){try{await a.device.releaseInterface(a.interfaceNumber)}catch{}try{await a.device.close()}catch{}}
    else if(a.mode==='serial'){try{await a.port.close()}catch{}}
    else if(a.mode==='ble'){try{a.device.gatt?.disconnect()}catch{}}
  }catch{}
}
async function disconnect(){await closeActive();clear();updateSettingsStatus()}
async function restore(){
  if(restoring||active)return;restoring=true;
  try{
    const s=cfg();
    if(s.mode==='usb'&&navigator.usb){
      const devices=await navigator.usb.getDevices();
      const d=devices.find(x=>(!s.vendorId||x.vendorId===s.vendorId)&&(!s.productId||x.productId===s.productId));
      if(d){
        await d.open();if(!d.configuration)await d.selectConfiguration(d.configurations?.[0]?.configurationValue||1);
        let choice=null;for(const intf of d.configuration?.interfaces||[]){for(const alt of intf.alternates||[]){const out=alt.endpoints?.find(e=>e.direction==='out');if(out){choice={interfaceNumber:intf.interfaceNumber,alternateSetting:alt.alternateSetting,endpointNumber:out.endpointNumber};break}}if(choice)break}
        if(choice){await d.claimInterface(choice.interfaceNumber);if(choice.alternateSetting)await d.selectAlternateInterface(choice.interfaceNumber,choice.alternateSetting);active={mode:'usb',route:'usb',device:d,...choice,name:d.productName||s.name||'Thermal USB'}}
      }
    }else if((s.mode==='serial'||s.mode==='bt-classic')&&navigator.serial){
      const ports=await navigator.serial.getPorts(),p=ports.find(x=>{const i=x.getInfo?.()||{};return (!s.usbVendorId||i.usbVendorId===s.usbVendorId)&&(!s.usbProductId||i.usbProductId===s.usbProductId)})||ports[0];
      if(p){await p.open({baudRate:Number(s.baudRate)||9600});active={mode:'serial',route:s.mode,port:p,baudRate:Number(s.baudRate)||9600,name:s.mode==='bt-classic'?'Bluetooth SPP':'Serial'}}
    }else if(s.mode==='ble'&&navigator.bluetooth){
      const devices=await navigator.bluetooth.getDevices();
      const d=devices.find(x=>x.id===s.deviceId)||devices[0];
      if(d){
        const server=await d.gatt.connect();
        const service=await server.getPrimaryService(s.serviceUuid);
        const characteristic=await service.getCharacteristic(s.characteristicUuid);
        active={mode:'ble',route:'ble',device:d,server,serviceUuid:s.serviceUuid,characteristic,name:d.name||s.name||'Thermal BLE'};
      }
    }
  }catch{}finally{restoring=false;updateSettingsStatus()}
}
async function bleWrite(ch,bytes){
  const size=120;
  for(let i=0;i<bytes.length;i+=size){
    const chunk=bytes.slice(i,i+size);
    if(ch.properties?.writeWithoutResponse&&ch.writeValueWithoutResponse)await ch.writeValueWithoutResponse(chunk);
    else if(ch.writeValueWithResponse)await ch.writeValueWithResponse(chunk);
    else await ch.writeValue(chunk);
  }
}
async function directPrint(r){
  const bytes=escpos(r);
  if(active?.mode==='usb'){const x=await active.device.transferOut(active.endpointNumber,bytes);if(x.status!=='ok')throw Error('Transfer USB gagal.');return}
  if(active?.mode==='serial'){
    const w=active.port.writable?.getWriter();if(!w)throw Error('Port serial tidak siap.');
    try{await w.write(bytes)}finally{w.releaseLock()}return;
  }
  if(active?.mode==='ble'){await bleWrite(active.characteristic,bytes);return}
  throw Error('Printer direct belum terhubung.');
}
async function sharePrint(r){
  if(typeof navigator.share!=='function')throw Error('Fitur Bagikan Android tidak tersedia di browser ini.');
  const payload={title:'Struk SMART CASHIER',text:receiptText(r)};
  return navigator.share(payload);
}
function systemPrint(r){
  const w=open('','_blank','width=480,height=760');if(!w)return;
  const lines=receiptText(r).split('\n').map(x=>esc(x)).join('<br>');
  w.document.write('<!doctype html><html><head><meta charset="utf-8"><title>Struk</title><style>@page{size:80mm auto;margin:0}*{box-sizing:border-box}html,body{width:80mm;max-width:80mm;margin:0;padding:0}body{font:12px/1.38 ui-monospace,SFMono-Regular,Consolas,monospace;color:#000}.paper{width:80mm;max-width:80mm;padding:4mm;overflow:hidden;overflow-wrap:anywhere;word-break:break-word}</style></head><body><main class="paper">'+lines+'</main><script>onload=()=>print()<\/script></body></html>');
  w.document.close();
}
async function print(r){
  if(!r)return;
  const s=cfg();
  if(s.mode==='share'){
    try{await sharePrint(r);return 'shared'}catch(err){
      if(String(err?.name||'')==='AbortError')return 'cancelled';
      alert('Aplikasi printer tidak dapat dibuka. SMART CASHIER akan membuka Printer Sistem.');
      systemPrint(r);return 'system-fallback';
    }
  }
  if(['usb','serial','bt-classic','ble'].includes(s.mode)&&!active)await restore();
  if(active){
    try{await directPrint(r);return}catch(err){
      alert('Koneksi printer direct tidak siap. SMART CASHIER akan membuka Printer Sistem.');
      await closeActive();updateSettingsStatus();systemPrint(r);return;
    }
  }
  systemPrint(r);
}
function interceptReceiptPrint(e){
  const b=e.target.closest?.('[data-rc6-receipt-print]');if(!b)return;
  const r=window.__SDB_LAST_CASHIER_RECEIPT__;if(!r)return;
  e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
  print(r).catch(err=>alert('Gagal mencetak: '+String(err?.message||err)));
}
function boot(){
  style();ensureSettingsNav();restore();
  document.addEventListener('click',interceptReceiptPrint,true);
  new MutationObserver(()=>ensureSettingsNav()).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
  document.addEventListener('rohmat:navigation',()=>setTimeout(ensureSettingsNav,0));
}
if(navigator.usb){
  navigator.usb.addEventListener('disconnect',e=>{if(active?.mode==='usb'&&active.device===e.device){active=null;updateSettingsStatus()}});
  navigator.usb.addEventListener('connect',()=>restore());
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.__SDB_THERMAL_PRINTER__={connectMode:choose,disconnect,status:statusText,capability,print,restore,renderSettings,version:'v2-android-ready'};
})();