(()=>{'use strict';
if(window.__SDB_THERMAL_PRINTER_RUNTIME_V2)return;
window.__SDB_THERMAL_PRINTER_RUNTIME_V2=1;

const STORE='sdb-smart-cashier-printer-v2';
const WIDTH=42;
const BLE_SERVICES=[
  '0000ffe0-0000-1000-8000-00805f9b34fb',
  '0000ff00-0000-1000-8000-00805f9b34fb',
  '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  '49535343-fe7d-4ae5-8fa9-9fafd205e455'
];
let active=null;
let restoring=false;

const enc=new TextEncoder();
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ascii=s=>String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^\x20-\x7E]/g,'?');
const rp=n=>'Rp '+Math.max(0,Number(n)||0).toLocaleString('id-ID');
const readCfg=()=>{try{return JSON.parse(localStorage.getItem(STORE)||'{}')}catch{return {}}};
const saveCfg=v=>localStorage.setItem(STORE,JSON.stringify(v||{}));
const clearCfg=()=>localStorage.removeItem(STORE);

function splitWords(text,width=WIDTH){
  const words=ascii(text).trim().split(/\s+/).filter(Boolean),out=[];let line='';
  for(const original of words){
    let word=original;
    while(word.length>width){if(line){out.push(line);line=''}out.push(word.slice(0,width));word=word.slice(width)}
    const next=line?line+' '+word:word;
    if(next.length>width){if(line)out.push(line);line=word}else line=next;
  }
  if(line)out.push(line);
  return out.length?out:[''];
}
function lr(left,right,width=WIDTH){
  left=ascii(left);right=ascii(right);
  if(left.length+right.length+1<=width)return [left+' '.repeat(width-left.length-right.length)+right];
  const lines=splitWords(left,Math.max(16,width-right.length-1)),last=lines.pop()||'';
  return [...lines,last+' '.repeat(Math.max(1,width-last.length-right.length))+right];
}
const line=(ch='-')=>ch.repeat(WIDTH);

function receiptText(r){
  const items=Array.isArray(r?.items)?r.items:[];
  const subtotal=Math.max(0,Number(r?.subtotal_amount??r?.subtotal)||items.reduce((s,i)=>s+(Number(i.quantity)||0)*(Number(i.price)||0),0));
  const charge=Math.max(0,Number(r?.charge_amount??r?.charge)||0);
  const tax=Math.max(0,Number(r?.tax_amount??r?.tax)||0);
  const total=Math.max(0,Number(r?.total_amount??r?.grand_total)||(subtotal+charge+tax));
  const pricing=r?.transaction_pricing&&typeof r.transaction_pricing==='object'?r.transaction_pricing:{};
  const cc=pricing.charge||{},tc=pricing.tax||{};
  const chargeLabel=cc.mode==='percent'&&Number(cc.value)>0?String(cc.label||'Charge')+' '+Number(cc.value)+'%':String(cc.label||'Charge');
  const taxLabel=tc.mode==='percent'&&Number(tc.value)>0?String(tc.label||'Pajak')+' '+Number(tc.value)+'%':String(tc.label||'Pajak');
  const when=new Date(r?.created_at||Date.now());
  const date=new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',day:'2-digit',month:'2-digit',year:'numeric'}).format(when);
  const time=new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',hour:'2-digit',minute:'2-digit',hour12:false}).format(when).replace('.',':')+' WIB';
  const out=['STRUK PEMBAYARAN & PEMESANAN',line('=')];
  out.push(...lr('Kode',r?.payment_code||r?.public_order_code||'-'));
  out.push(...lr('Pemesan',r?.customer_name||'-'));
  out.push(...lr('Layanan',r?.service_mode==='dine-in'?'Makan di Tempat':'Bawa Pulang'));
  if(r?.service_mode==='dine-in')out.push(...lr('Meja',String(r?.table_number||'-')));
  if(r?.payment_method)out.push(...lr('Pembayaran',String(r.payment_method).toUpperCase()));
  out.push(...lr('Tanggal',date),...lr('Waktu',time),line(),'RINCIAN PESANAN');
  for(const item of items){
    out.push(...splitWords(item?.name||'-'));
    out.push(...lr((Number(item?.quantity)||0)+' x '+rp(item?.price),rp((Number(item?.quantity)||0)*(Number(item?.price)||0))));
  }
  out.push(line(),...lr('Subtotal',rp(subtotal)));
  if(charge>0)out.push(...lr(chargeLabel,rp(charge)));
  if(tax>0)out.push(...lr(taxLabel,rp(tax)));
  out.push(line('='),...lr('TOTAL',rp(total)),line('='),'Terima kasih','','');
  return out.join('\n');
}
function escpos(r){
  const body=enc.encode(receiptText(r));
  const init=Uint8Array.from([0x1b,0x40,0x1b,0x61,0x00]);
  const cut=Uint8Array.from([0x0a,0x0a,0x0a,0x1d,0x56,0x42,0x00]);
  const out=new Uint8Array(init.length+body.length+cut.length);
  out.set(init);out.set(body,init.length);out.set(cut,init.length+body.length);
  return out;
}
function routeName(mode){
  return ({
    ble:'Bluetooth BLE Langsung',
    usb:'USB OTG Langsung',
    'android-system':'Android Print Service',
    'wifi-system':'Wi-Fi / Wi-Fi Direct',
    serial:'USB / Serial Desktop',
    system:'Printer Sistem'
  })[mode]||'Belum dipilih';
}
function platform(){
  const ua=navigator.userAgent||'';
  return {android:/Android/i.test(ua),mobile:/Android|iPhone|iPad|Mobile/i.test(ua)};
}
function status(){
  const c=readCfg();
  if(active?.mode)return 'Terhubung · '+routeName(active.mode)+(active.name?' · '+active.name:'');
  if(c.mode)return 'Siap · '+routeName(c.mode);
  return 'Belum dikonfigurasi';
}
function canDirect(mode){
  if(mode==='ble')return !!navigator.bluetooth;
  if(mode==='usb')return !!navigator.usb;
  if(mode==='serial')return !!navigator.serial;
  return true;
}
function ensureStyle(){
  if(document.getElementById('sdbPrinterSettingsCssV2'))return;
  const s=document.createElement('style');s.id='sdbPrinterSettingsCssV2';
  s.textContent='.sdbPrinterGrid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.sdbPrinterCard{border:1px solid var(--line,#dfe6e2);border-radius:14px;background:var(--panel,#fff);padding:15px;display:grid;gap:9px}.sdbPrinterCard h3{margin:0;font-size:15px}.sdbPrinterCard p{margin:0;color:var(--muted,#6f7d77);font-size:12px;line-height:1.5}.sdbPrinterCard .meta{display:flex;gap:6px;flex-wrap:wrap}.sdbPrinterChip{display:inline-flex;padding:4px 7px;border-radius:999px;background:color-mix(in srgb,var(--primary,#173f33) 8%,transparent);font-size:10px;font-weight:800}.sdbPrinterActions{display:flex;gap:7px;flex-wrap:wrap;margin-top:4px}.sdbPrinterStatus{margin-bottom:12px;display:flex;justify-content:space-between;gap:12px;align-items:center;flex-wrap:wrap}.sdbPrinterNote{margin-top:12px}.sdbPrinterUnsupported{opacity:.56}.sdbPrinterUnsupported button{cursor:not-allowed}@media(max-width:760px){.sdbPrinterGrid{grid-template-columns:1fr}}';
  document.head.appendChild(s);
}
function settingsHeader(){
  const c=readCfg(),p=platform();
  return '<div class="sectionHead"><div><div class="ey">PENGATURAN</div><h1>Printer Thermal</h1><p>Siapkan printer untuk SMART CASHIER. Pairing perangkat selalu membutuhkan tindakan pengguna dan tidak pernah mencetak otomatis.</p></div></div>'+
    '<section class="card sdbPrinterStatus"><div><b>Status Printer</b><div class="muted" data-sdb-printer-status>'+esc(status())+'</div></div><div class="sdbPrinterActions"><button type="button" class="btn soft" data-sdb-printer-disconnect '+(!c.mode?'disabled':'')+'>Lupakan Printer</button></div></section>'+
    '<div class="notice">'+(p.android?'Perangkat Android terdeteksi. Jalur mobile ditampilkan sebagai rekomendasi utama.':'Gunakan jalur sesuai jenis printer dan perangkat kasir.')+'</div>';
}
function card(mode,title,desc,chips,button){
  const supported=canDirect(mode),activeMode=readCfg().mode===mode;
  return '<section class="sdbPrinterCard '+(!supported?'sdbPrinterUnsupported':'')+'"><h3>'+esc(title)+(activeMode?' · Aktif':'')+'</h3><p>'+esc(desc)+'</p><div class="meta">'+chips.map(x=>'<span class="sdbPrinterChip">'+esc(x)+'</span>').join('')+'</div><div class="sdbPrinterActions"><button type="button" class="btn '+(activeMode?'primary':'soft')+'" data-sdb-printer-route="'+mode+'" '+(!supported?'disabled':'')+'>'+esc(!supported?'Tidak didukung browser':button)+'</button></div></section>';
}
function renderSettings(){
  ensureStyle();
  const view=document.getElementById('view');if(!view)return;
  const sub=document.querySelector('.subnav');if(sub)sub.querySelectorAll('button').forEach(b=>b.classList.toggle('on',b.dataset.sdbPrinterSub==='1'));
  view.innerHTML=settingsHeader()+
    '<h3 style="margin:16px 0 9px">Direkomendasikan untuk Android / Tablet / HP</h3><div class="sdbPrinterGrid">'+
    card('ble','Bluetooth BLE Langsung','Untuk printer thermal BLE yang menyediakan GATT characteristic tulis. SMART CASHIER mengirim ESC/POS langsung setelah Anda memilih perangkat.',['Android','BLE','ESC/POS'],'Hubungkan Bluetooth BLE')+
    card('usb','USB OTG Langsung','Untuk printer USB class yang kompatibel melalui kabel OTG. Browser akan meminta Anda memilih perangkat USB.',['Android','USB OTG','ESC/POS'],'Hubungkan USB OTG')+
    card('android-system','Android Print Service','Fallback paling aman untuk Android. Gunakan Default Print Service atau print service aplikasi vendor printer; struk dikirim sebagai halaman 80 mm.',['Android','Bluetooth/Wi-Fi/USB via service','80 mm'],'Gunakan Android Print Service')+
    card('wifi-system','Wi-Fi / Wi-Fi Direct','Untuk printer yang tersedia melalui Android Default Print Service, Mopria, atau layanan vendor pada jaringan/Wi-Fi Direct.',['Android','Wi-Fi','Wi-Fi Direct'],'Gunakan Wi-Fi / Wi-Fi Direct')+
    '</div><h3 style="margin:18px 0 9px">Desktop / Lanjutan</h3><div class="sdbPrinterGrid">'+
    card('serial','USB / Serial Desktop','Untuk printer yang mengekspos port serial/virtual COM dan browser desktop yang mendukung Web Serial.',['Desktop','Serial','ESC/POS'],'Hubungkan Serial')+
    card('system','Printer Sistem','Fallback standar melalui dialog print browser dan driver sistem operasi.',['Windows/macOS/Linux','Driver sistem','80 mm'],'Gunakan Printer Sistem')+
    '</div><section class="card sdbPrinterNote"><b>Catatan kompatibilitas</b><p class="muted">Bluetooth BLE berbeda dari Bluetooth Classic. Printer Bluetooth Classic yang tidak menyediakan BLE harus digunakan melalui Android Print Service/aplikasi vendor. Tidak ada test print otomatis; cetak baru terjadi saat pengguna menekan Cetak Struk.</p></section>';
  view.querySelectorAll('[data-sdb-printer-route]').forEach(b=>b.addEventListener('click',()=>chooseRoute(b.dataset.sdbPrinterRoute,b)));
  view.querySelector('[data-sdb-printer-disconnect]')?.addEventListener('click',async()=>{await disconnect(true);renderSettings()});
}
function ensureSettingsTab(){
  const main=document.querySelector('[data-settings-main="1"]');
  const sub=document.querySelector('.subnav');
  if(!main||!sub||!main.classList.contains('on'))return;
  if(sub.querySelector('[data-sdb-printer-sub="1"]'))return;
  const b=document.createElement('button');b.type='button';b.dataset.sdbPrinterSub='1';b.textContent='Printer Thermal';
  b.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();renderSettings()});
  sub.appendChild(b);
}
async function chooseRoute(mode,button){
  const label=button?.textContent||'';if(button){button.disabled=true;button.textContent='Menghubungkan…'}
  try{
    if(mode==='ble')await connectBle();
    else if(mode==='usb')await connectUsb();
    else if(mode==='serial')await connectSerial();
    else{await closeActive();saveCfg({mode,paper:'80mm'});active=null}
    renderSettings();
  }catch(err){
    alert('Printer belum terhubung: '+String(err?.message||err));
    if(button){button.disabled=false;button.textContent=label}
  }
}
async function connectBle(){
  if(!navigator.bluetooth)throw Error('Web Bluetooth tidak tersedia di browser ini.');
  const device=await navigator.bluetooth.requestDevice({acceptAllDevices:true,optionalServices:BLE_SERVICES});
  const server=await device.gatt.connect();
  let chosen=null;
  for(const uuid of BLE_SERVICES){
    try{
      const service=await server.getPrimaryService(uuid);
      const chars=await service.getCharacteristics();
      const characteristic=chars.find(c=>c.properties?.writeWithoutResponse||c.properties?.write);
      if(characteristic){chosen={serviceUuid:service.uuid,characteristic};break}
    }catch{}
  }
  if(!chosen){try{device.gatt.disconnect()}catch{};throw Error('Characteristic BLE untuk cetak tidak ditemukan. Gunakan Android Print Service.')}
  await closeActive();
  active={mode:'ble',device,server,characteristic:chosen.characteristic,serviceUuid:chosen.serviceUuid,name:device.name||'BLE Thermal'};
  device.addEventListener('gattserverdisconnected',()=>{if(active?.device===device){active=null;refreshSettingsStatus()}});
  saveCfg({mode:'ble',paper:'80mm',deviceId:device.id,name:device.name||'',serviceUuid:chosen.serviceUuid,characteristicUuid:chosen.characteristic.uuid});
}
async function connectUsb(){
  if(!navigator.usb)throw Error('WebUSB tidak tersedia di browser ini.');
  const device=await navigator.usb.requestDevice({filters:[{classCode:7}]});
  await device.open();
  if(!device.configuration)await device.selectConfiguration(device.configurations?.[0]?.configurationValue||1);
  let choice=null;
  for(const intf of device.configuration?.interfaces||[]){
    for(const alt of intf.alternates||[]){
      const endpoint=alt.endpoints?.find(e=>e.direction==='out');
      if(endpoint){choice={interfaceNumber:intf.interfaceNumber,alternateSetting:alt.alternateSetting,endpointNumber:endpoint.endpointNumber};break}
    }
    if(choice)break;
  }
  if(!choice){await device.close();throw Error('Endpoint cetak USB tidak ditemukan. Gunakan Android Print Service.')}
  await device.claimInterface(choice.interfaceNumber);
  if(choice.alternateSetting)await device.selectAlternateInterface(choice.interfaceNumber,choice.alternateSetting);
  await closeActive();
  active={mode:'usb',device,...choice,name:device.productName||'USB Thermal'};
  saveCfg({mode:'usb',paper:'80mm',vendorId:device.vendorId,productId:device.productId,name:device.productName||''});
}
async function connectSerial(){
  if(!navigator.serial)throw Error('Web Serial tidak tersedia di browser ini.');
  const port=await navigator.serial.requestPort();
  const baudRate=9600;
  await port.open({baudRate});
  const info=port.getInfo?.()||{};
  await closeActive();
  active={mode:'serial',port,baudRate,name:'Serial Thermal'};
  saveCfg({mode:'serial',paper:'80mm',baudRate,usbVendorId:info.usbVendorId||null,usbProductId:info.usbProductId||null});
}
async function closeActive(){
  const a=active;active=null;if(!a)return;
  try{
    if(a.mode==='ble'){try{a.device?.gatt?.disconnect()}catch{}}
    else if(a.mode==='usb'){try{await a.device.releaseInterface(a.interfaceNumber)}catch{}try{await a.device.close()}catch{}}
    else if(a.mode==='serial'){try{await a.port.close()}catch{}}
  }catch{}
}
async function disconnect(forget=false){
  const a=active;
  await closeActive();
  if(forget&&a?.mode==='ble'&&a.device?.forget){try{await a.device.forget()}catch{}}
  clearCfg();refreshSettingsStatus();
}
async function restore(){
  if(restoring||active)return;restoring=true;
  try{
    const c=readCfg();
    if(c.mode==='ble'&&navigator.bluetooth?.getDevices){
      const devices=await navigator.bluetooth.getDevices(),device=devices.find(d=>d.id===c.deviceId)||devices.find(d=>d.name===c.name);
      if(device){
        const server=await device.gatt.connect(),service=await server.getPrimaryService(c.serviceUuid),characteristic=await service.getCharacteristic(c.characteristicUuid);
        active={mode:'ble',device,server,characteristic,serviceUuid:c.serviceUuid,name:device.name||c.name||'BLE Thermal'};
        device.addEventListener('gattserverdisconnected',()=>{if(active?.device===device){active=null;refreshSettingsStatus()}});
      }
    }else if(c.mode==='usb'&&navigator.usb){
      const devices=await navigator.usb.getDevices(),device=devices.find(d=>(!c.vendorId||d.vendorId===c.vendorId)&&(!c.productId||d.productId===c.productId));
      if(device){
        await device.open();if(!device.configuration)await device.selectConfiguration(device.configurations?.[0]?.configurationValue||1);
        let choice=null;for(const intf of device.configuration?.interfaces||[]){for(const alt of intf.alternates||[]){const endpoint=alt.endpoints?.find(e=>e.direction==='out');if(endpoint){choice={interfaceNumber:intf.interfaceNumber,alternateSetting:alt.alternateSetting,endpointNumber:endpoint.endpointNumber};break}}if(choice)break}
        if(choice){await device.claimInterface(choice.interfaceNumber);if(choice.alternateSetting)await device.selectAlternateInterface(choice.interfaceNumber,choice.alternateSetting);active={mode:'usb',device,...choice,name:device.productName||c.name||'USB Thermal'}}
      }
    }else if(c.mode==='serial'&&navigator.serial){
      const ports=await navigator.serial.getPorts(),port=ports.find(p=>{const i=p.getInfo?.()||{};return (!c.usbVendorId||i.usbVendorId===c.usbVendorId)&&(!c.usbProductId||i.usbProductId===c.usbProductId)})||ports[0];
      if(port){await port.open({baudRate:Number(c.baudRate)||9600});active={mode:'serial',port,baudRate:Number(c.baudRate)||9600,name:'Serial Thermal'}}
    }
  }catch{}finally{restoring=false;refreshSettingsStatus()}
}
async function writeBle(bytes){
  const ch=active?.characteristic;if(!ch)throw Error('Printer BLE tidak siap.');
  const size=180;
  for(let i=0;i<bytes.length;i+=size){
    const chunk=bytes.slice(i,i+size);
    if(ch.properties?.writeWithoutResponse&&ch.writeValueWithoutResponse)await ch.writeValueWithoutResponse(chunk);
    else if(ch.writeValue)await ch.writeValue(chunk);
    else throw Error('Characteristic BLE tidak dapat ditulis.');
  }
}
async function directPrint(r){
  const bytes=escpos(r);
  if(active?.mode==='ble'){await writeBle(bytes);return}
  if(active?.mode==='usb'){const result=await active.device.transferOut(active.endpointNumber,bytes);if(result.status!=='ok')throw Error('Transfer USB gagal.');return}
  if(active?.mode==='serial'){
    const writer=active.port.writable?.getWriter();if(!writer)throw Error('Port serial tidak siap.');
    try{await writer.write(bytes)}finally{writer.releaseLock()}
    return;
  }
  throw Error('Printer direct belum terhubung.');
}
function systemPrint(r){
  const old=document.getElementById('sdbPrinterFrameV2');if(old)old.remove();
  const frame=document.createElement('iframe');frame.id='sdbPrinterFrameV2';frame.setAttribute('aria-hidden','true');frame.style.cssText='position:fixed;width:1px;height:1px;right:0;bottom:0;border:0;opacity:.001;pointer-events:none';
  document.body.appendChild(frame);
  const doc=frame.contentDocument,lines=receiptText(r).split('\n').map(x=>esc(x)).join('<br>');
  doc.open();doc.write('<!doctype html><html><head><meta charset="utf-8"><title>Struk</title><style>@page{size:80mm auto;margin:0}*{box-sizing:border-box}html,body{width:80mm;max-width:80mm;margin:0;padding:0}body{font:12px/1.38 ui-monospace,SFMono-Regular,Consolas,monospace;color:#000}.paper{width:80mm;max-width:80mm;padding:4mm;overflow:hidden;overflow-wrap:anywhere;word-break:break-word}</style></head><body><main class="paper">'+lines+'</main></body></html>');doc.close();
  setTimeout(()=>{try{frame.contentWindow.focus();frame.contentWindow.print()}catch(err){alert('Dialog cetak tidak dapat dibuka. Gunakan menu Print/Cetak pada browser.')}setTimeout(()=>frame.remove(),1500)},80);
}
async function print(r){
  if(!r)return;
  const c=readCfg();
  if(['android-system','wifi-system','system'].includes(c.mode)||!c.mode){systemPrint(r);return}
  if(!active)await restore();
  if(active){
    try{await directPrint(r);return}catch{
      alert('Koneksi direct printer terputus. SMART CASHIER akan memakai Printer Sistem.');
      await closeActive();systemPrint(r);return;
    }
  }
  systemPrint(r);
}
function refreshSettingsStatus(){
  const n=document.querySelector('[data-sdb-printer-status]');if(n)n.textContent=status();
}
document.addEventListener('click',e=>{
  const b=e.target.closest?.('[data-rc6-receipt-print]');if(!b)return;
  const r=window.__SDB_LAST_CASHIER_RECEIPT__;if(!r)return;
  e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
  print(r).catch(err=>alert('Gagal mencetak: '+String(err?.message||err)));
},true);
if(navigator.usb){
  navigator.usb.addEventListener('disconnect',e=>{if(active?.mode==='usb'&&active.device===e.device){active=null;refreshSettingsStatus()}});
  navigator.usb.addEventListener('connect',()=>restore());
}
const boot=()=>{
  ensureStyle();ensureSettingsTab();restore();
  new MutationObserver(()=>ensureSettingsTab()).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.__SDB_THERMAL_PRINTER__={renderSettings,disconnect,status,print,restore,version:'v2-mobile'};
})();