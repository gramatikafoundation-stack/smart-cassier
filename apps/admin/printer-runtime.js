(()=>{'use strict';
if(window.__SDB_THERMAL_PRINTER_RUNTIME_V1)return;
window.__SDB_THERMAL_PRINTER_RUNTIME_V1=1;

const STORE='sdb-smart-cashier-printer-v1';
const WIDTH=42;
let active=null;
let restoring=false;

const enc=new TextEncoder();
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ascii=s=>String(s??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^\x20-\x7E]/g,'?');
const rp=n=>'Rp '+Math.max(0,Number(n)||0).toLocaleString('id-ID');
const cfg=()=>{try{return JSON.parse(localStorage.getItem(STORE)||'{}')}catch{return {}}};
const save=v=>localStorage.setItem(STORE,JSON.stringify(v||{}));
const clear=()=>localStorage.removeItem(STORE);

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
  if(left.length+right.length+1<=width)return left+' '.repeat(width-left.length-right.length)+right;
  const lines=splitWords(left,Math.max(16,width-right.length-1));
  const last=lines.pop()||'';
  return [...lines,last+' '.repeat(Math.max(1,width-last.length-right.length))+right];
}
function line(ch='-'){return ch.repeat(WIDTH)}
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
  const out=[];
  out.push('STRUK PEMBAYARAN & PEMESANAN',line('='));
  out.push(...lr('Kode',r?.payment_code||r?.public_order_code||'-'));
  out.push(...lr('Pemesan',r?.customer_name||'-'));
  out.push(...lr('Layanan',r?.service_mode==='dine-in'?'Makan di Tempat':'Bawa Pulang'));
  if(r?.service_mode==='dine-in')out.push(...lr('Meja',String(r?.table_number||'-')));
  if(r?.payment_method)out.push(...lr('Pembayaran',String(r.payment_method).toUpperCase()));
  out.push(...lr('Tanggal',date),...lr('Waktu',time),line());
  out.push('RINCIAN PESANAN');
  for(const i of items){
    out.push(...splitWords(i?.name||'-'));
    out.push(...lr((Number(i?.quantity)||0)+' x '+rp(i?.price),rp((Number(i?.quantity)||0)*(Number(i?.price)||0))));
  }
  out.push(line(),...lr('Subtotal',rp(subtotal)));
  if(charge>0)out.push(...lr(chargeLabel,rp(charge)));
  if(tax>0)out.push(...lr(taxLabel,rp(tax)));
  out.push(line('='),...lr('TOTAL',rp(total)),line('='),'Terima kasih','','');
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
function statusText(){
  const s=cfg();
  if(active?.mode==='usb')return 'Terhubung · USB '+(active.name||'Thermal');
  if(active?.mode==='serial')return 'Terhubung · Serial';
  if(s.mode==='system')return 'Siap · Printer Sistem';
  if(s.mode==='usb'||s.mode==='serial')return 'Tersimpan · sambungkan perangkat';
  return 'Belum terhubung';
}
function style(){
  if(document.getElementById('sdbThermalPrinterCssV1'))return;
  const s=document.createElement('style');s.id='sdbThermalPrinterCssV1';
  s.textContent='#sdbThermalPrinterPanel{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;margin:0 0 12px;padding:11px 12px;border:1px solid #dce5e1;border-radius:12px;background:#f8fbf9;color:#1d2924}#sdbThermalPrinterPanel .sdbPrinterInfo{display:grid;gap:2px}#sdbThermalPrinterPanel small{color:#728079}#sdbThermalPrinterPanel .sdbPrinterActions{display:flex;gap:7px;flex-wrap:wrap}#sdbPrinterModal{position:fixed;inset:0;z-index:100000;background:rgba(6,14,16,.66);display:grid;place-items:center;padding:18px}#sdbPrinterModal .box{width:min(560px,100%);background:#fff;border-radius:18px;padding:20px;color:#17211d;box-shadow:0 30px 90px rgba(0,0,0,.28)}#sdbPrinterModal .grid{display:grid;gap:9px;margin-top:15px}#sdbPrinterModal button{min-height:43px;border:1px solid #dbe4df;border-radius:11px;background:#fff;color:#1d2924;font-weight:800;padding:10px 12px;text-align:left}#sdbPrinterModal button.primary{background:#173f33;color:#fff;border-color:#173f33}#sdbPrinterModal p{color:#68756f;line-height:1.5}.sdbPrinterStatusCard{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin-bottom:14px}.sdbPrinterStatusCard p{margin:5px 0 0;color:var(--muted,#718078)}.sdbPrinterPathGrid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-bottom:14px}.sdbPrinterPath{display:flex;flex-direction:column;gap:12px;min-height:310px}.sdbPrinterPath.active{border-color:var(--accent,#00bfae)!important;box-shadow:0 0 0 2px color-mix(in srgb,var(--accent,#00bfae) 18%,transparent)!important}.sdbPrinterPathTop{display:flex;align-items:flex-start;justify-content:space-between;gap:10px}.sdbPrinterPathTop h3{margin:6px 0 0}.sdbPrinterPathNo{font-size:10px;font-weight:900;letter-spacing:.12em;color:var(--accent,#00bfae)}.sdbPrinterPath>p{margin:0;color:var(--muted,#718078);line-height:1.55}.sdbPrinterPath>.notice{margin-top:auto}.sdbPrinterPath>.btn{width:100%}.sdbPrinterSafety p{color:var(--muted,#718078);line-height:1.55}@media(max-width:980px){.sdbPrinterPathGrid{grid-template-columns:1fr}.sdbPrinterStatusCard{grid-template-columns:1fr}}';
  document.head.appendChild(s);
}
function updatePanel(){
  const p=document.getElementById('sdbThermalPrinterPanel');
  if(p){
    const st=p.querySelector('[data-printer-status]');if(st)st.textContent=statusText();
    const d=p.querySelector('[data-printer-disconnect]');if(d)d.hidden=!(active||cfg().mode);
  }
  updateSettingsUi();
}
function panel(){
  style();
  const root=document.getElementById('rohmatCashierSafe');if(!root||document.getElementById('sdbThermalPrinterPanel'))return;
  const p=document.createElement('div');p.id='sdbThermalPrinterPanel';
  p.innerHTML='<div class="sdbPrinterInfo"><b>Printer Thermal</b><small data-printer-status>'+esc(statusText())+'</small></div><div class="sdbPrinterActions"><button type="button" class="rc6Btn" data-printer-connect>Buka Pengaturan Printer</button><button type="button" class="rc6Btn" data-printer-disconnect hidden>Putuskan</button></div>';
  root.prepend(p);
  p.querySelector('[data-printer-connect]').addEventListener('click',openPrinterSettings);
  p.querySelector('[data-printer-disconnect]').addEventListener('click',disconnect);
  updatePanel();
}

function modeName(mode){
  return mode==='usb'?'USB Langsung (ESC/POS)':mode==='serial'?'USB/Serial (ESC/POS)':mode==='system'?'Printer Sistem / Driver Windows':'Belum dipilih';
}
function updateSettingsUi(){
  const root=document.getElementById('sdbPrinterSettingsV1');if(!root)return;
  const s=cfg(),mode=active?.mode||s.mode||'';
  const status=root.querySelector('[data-settings-printer-status]');
  if(status)status.textContent=statusText();
  const modeEl=root.querySelector('[data-settings-printer-mode]');if(modeEl)modeEl.textContent=modeName(mode);
  root.querySelectorAll('[data-printer-path]').forEach(card=>{
    const m=card.dataset.printerPath;
    card.classList.toggle('active',m===mode);
    const badge=card.querySelector('[data-path-state]');
    if(badge)badge.textContent=m===mode?(active?.mode===m?'Terhubung':'Dipilih'):'Siap dipilih';
  });
  const d=root.querySelector('[data-settings-printer-disconnect]');
  if(d)d.hidden=!(active||s.mode);
}
async function choosePath(mode,button){
  const label=button?.textContent||'Hubungkan';
  if(button){button.disabled=true;button.textContent='Menghubungkan…'}
  try{
    if(mode==='usb')await connectUsb();
    else if(mode==='serial')await connectSerial();
    else if(mode==='system'){await closeActive();save({mode:'system',paper:'80mm'});active=null}
    updatePanel();updateSettingsUi();
  }catch(err){
    alert('Printer belum terhubung: '+String(err?.message||err));
  }finally{
    if(button){button.disabled=false;button.textContent=label}
  }
}
function renderPrinterSettings(){
  style();
  const nav=document.querySelector('.subnav'),view=document.getElementById('view'),title=document.querySelector('.topbar h2');
  if(!nav||!view)return;
  if(title)title.textContent='PENGATURAN';
  nav.querySelectorAll('button').forEach(b=>b.classList.toggle('on',b.dataset.settingsPrinter==='1'));
  const usb=!!navigator.usb,serial=!!navigator.serial,s=cfg();
  view.innerHTML='<div id="sdbPrinterSettingsV1">'+
    '<div class="sectionHead"><div><div class="ey">PENGATURAN</div><h1>Printer Thermal</h1><p>Hubungkan printer thermal untuk SMART CASHIER. Pilih satu jalur sesuai tipe perangkat; pengaturan tersimpan hanya pada browser/perangkat kasir ini.</p></div></div>'+
    '<section class="card sdbPrinterStatusCard"><div><span class="statusDot"></span><b>Status Printer</b><p data-settings-printer-status>'+esc(statusText())+'</p></div><div><b>Mode Aktif</b><p data-settings-printer-mode>'+esc(modeName(active?.mode||s.mode))+'</p></div></section>'+
    '<div class="sdbPrinterPathGrid">'+
      '<section class="card sdbPrinterPath" data-printer-path="usb"><div class="sdbPrinterPathTop"><div><span class="sdbPrinterPathNo">01</span><h3>USB Langsung — ESC/POS</h3></div><span class="pill" data-path-state>Siap dipilih</span></div><p>Untuk printer thermal USB yang dapat diakses langsung oleh Chrome/Edge melalui WebUSB. SMART CASHIER mengirim data ESC/POS langsung ke endpoint printer.</p><div class="notice">'+(usb?'WebUSB tersedia pada browser ini.':'WebUSB tidak tersedia pada browser ini; gunakan Chrome/Edge desktop atau Printer Sistem.')+'</div><button type="button" class="btn primary" data-settings-connect="usb" '+(usb?'':'disabled')+'>Hubungkan USB Langsung</button></section>'+
      '<section class="card sdbPrinterPath" data-printer-path="serial"><div class="sdbPrinterPathTop"><div><span class="sdbPrinterPathNo">02</span><h3>USB/Serial — ESC/POS</h3></div><span class="pill" data-path-state>Siap dipilih</span></div><p>Untuk printer yang muncul sebagai port serial/virtual COM. Browser meminta Anda memilih port, lalu SMART CASHIER mengirim ESC/POS melalui Web Serial.</p><div class="notice">'+(serial?'Web Serial tersedia pada browser ini.':'Web Serial tidak tersedia pada browser ini; gunakan Chrome/Edge desktop atau Printer Sistem.')+'</div><button type="button" class="btn primary" data-settings-connect="serial" '+(serial?'':'disabled')+'>Hubungkan USB/Serial</button></section>'+
      '<section class="card sdbPrinterPath" data-printer-path="system"><div class="sdbPrinterPathTop"><div><span class="sdbPrinterPathNo">03</span><h3>Printer Sistem / Driver Windows</h3></div><span class="pill" data-path-state>Siap dipilih</span></div><p>Fallback universal. SMART CASHIER membuat struk 80 mm dan menyerahkan pencetakan ke dialog printer Chrome/Windows. Cocok untuk printer yang memakai driver pabrikan.</p><div class="notice">Tidak memerlukan akses USB/Serial dari browser. Printer harus sudah terinstal di Windows.</div><button type="button" class="btn primary" data-settings-connect="system">Gunakan Printer Sistem</button></section>'+
    '</div>'+
    '<section class="card sdbPrinterSafety"><h3>Keamanan & Perilaku</h3><p>Tidak ada pairing, test print, atau pencetakan otomatis tanpa tindakan pengguna. Izin perangkat disimpan oleh browser; transaksi tetap berjalan walaupun printer tidak tersedia.</p><button type="button" class="btn soft" data-settings-printer-disconnect '+((active||s.mode)?'':'hidden')+'>Putuskan / Lupakan Printer</button></section>'+
  '</div>';
  view.querySelectorAll('[data-settings-connect]').forEach(b=>b.addEventListener('click',()=>choosePath(b.dataset.settingsConnect,b)));
  view.querySelector('[data-settings-printer-disconnect]')?.addEventListener('click',async()=>{await disconnect();renderPrinterSettings()});
  updateSettingsUi();
}
function openPrinterSettings(){
  const settings=document.querySelector('.mainNav [data-settings-main="1"]');
  if(settings&&!settings.classList.contains('on'))settings.click();
  setTimeout(()=>{patchSettingsNav();renderPrinterSettings()},40);
}
function patchSettingsNav(){
  const nav=document.querySelector('.mainNav'),sub=document.querySelector('.subnav');
  if(!nav||!sub)return;
  const settings=nav.querySelector('[data-settings-main="1"]');
  const activeSettings=!!settings?.classList.contains('on')||String(document.querySelector('.topbar h2')?.textContent||'').trim().toUpperCase()==='PENGATURAN';
  if(!activeSettings)return;
  let b=sub.querySelector('[data-settings-printer="1"]');
  if(!b){
    b=document.createElement('button');b.type='button';b.dataset.settingsPrinter='1';b.textContent='Printer Thermal';
    b.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();renderPrinterSettings()});
    sub.appendChild(b);
  }
}
function openConnect(){
  document.getElementById('sdbPrinterModal')?.remove();
  const m=document.createElement('div');m.id='sdbPrinterModal';
  const usb=!!navigator.usb,serial=!!navigator.serial;
  m.innerHTML='<div class="box"><h2 style="margin:0">Hubungkan Printer Thermal</h2><p>Pilih jalur sesuai printer. Pairing hanya dilakukan setelah Anda memilih perangkat dari dialog browser.</p><div class="grid">'+
    (usb?'<button type="button" class="primary" data-mode="usb">USB Langsung (ESC/POS)</button>':'')+
    (serial?'<button type="button" class="primary" data-mode="serial">USB/Serial (ESC/POS)</button>':'')+
    '<button type="button" data-mode="system">Printer Sistem / Driver Windows</button><button type="button" data-mode="cancel">Batal</button></div><p style="font-size:12px;margin-bottom:0">Jika direct USB/Serial tidak didukung model printer, pilih Printer Sistem. Tidak ada cetak uji otomatis.</p></div>';
  document.body.appendChild(m);
  m.addEventListener('click',async e=>{
    const b=e.target.closest('[data-mode]');if(!b)return;
    const mode=b.dataset.mode;
    if(mode==='cancel'){m.remove();return}
    b.disabled=true;
    try{
      if(mode==='usb')await connectUsb();
      else if(mode==='serial')await connectSerial();
      else {await closeActive();save({mode:'system',paper:'80mm'});active=null}
      m.remove();updatePanel();
    }catch(err){
      b.disabled=false;
      alert('Printer belum terhubung: '+String(err?.message||err));
    }
  });
}
async function connectUsb(){
  if(!navigator.usb)throw Error('WebUSB tidak tersedia di browser ini.');
  const device=await navigator.usb.requestDevice({filters:[{classCode:0x07},{classCode:0xff}]});
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
  if(!choice){await device.close();throw Error('Endpoint cetak USB tidak ditemukan. Gunakan Printer Sistem.')}
  await device.claimInterface(choice.interfaceNumber);
  if(choice.alternateSetting)await device.selectAlternateInterface(choice.interfaceNumber,choice.alternateSetting);
  await closeActive();
  active={mode:'usb',device,...choice,name:device.productName||'Thermal'};
  save({mode:'usb',paper:'80mm',vendorId:device.vendorId,productId:device.productId,name:device.productName||''});
}
async function connectSerial(){
  if(!navigator.serial)throw Error('Web Serial tidak tersedia di browser ini.');
  const port=await navigator.serial.requestPort();
  const baudRate=9600;
  await port.open({baudRate});
  const info=port.getInfo?.()||{};
  await closeActive();
  active={mode:'serial',port,baudRate};
  save({mode:'serial',paper:'80mm',baudRate,usbVendorId:info.usbVendorId||null,usbProductId:info.usbProductId||null});
}
async function closeActive(){
  const a=active;active=null;
  if(!a)return;
  try{
    if(a.mode==='usb'){
      try{await a.device.releaseInterface(a.interfaceNumber)}catch{}
      try{await a.device.close()}catch{}
    }else if(a.mode==='serial'){
      try{await a.port.close()}catch{}
    }
  }catch{}
}
async function disconnect(){await closeActive();clear();updatePanel()}
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
        if(choice){await d.claimInterface(choice.interfaceNumber);if(choice.alternateSetting)await d.selectAlternateInterface(choice.interfaceNumber,choice.alternateSetting);active={mode:'usb',device:d,...choice,name:d.productName||s.name||'Thermal'}}
      }
    }else if(s.mode==='serial'&&navigator.serial){
      const ports=await navigator.serial.getPorts(),p=ports.find(x=>{const i=x.getInfo?.()||{};return (!s.usbVendorId||i.usbVendorId===s.usbVendorId)&&(!s.usbProductId||i.usbProductId===s.usbProductId)})||ports[0];
      if(p){await p.open({baudRate:Number(s.baudRate)||9600});active={mode:'serial',port:p,baudRate:Number(s.baudRate)||9600}}
    }
  }catch{}finally{restoring=false;updatePanel()}
}
async function directPrint(r){
  const bytes=escpos(r);
  if(active?.mode==='usb'){const x=await active.device.transferOut(active.endpointNumber,bytes);if(x.status!=='ok')throw Error('Transfer USB gagal.');return}
  if(active?.mode==='serial'){
    const w=active.port.writable?.getWriter();if(!w)throw Error('Port serial tidak siap.');
    try{await w.write(bytes)}finally{w.releaseLock()}
    return;
  }
  throw Error('Printer direct belum terhubung.');
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
  if((s.mode==='usb'||s.mode==='serial')&&!active)await restore();
  if(active){
    try{await directPrint(r);return}catch(err){
      alert('Koneksi printer direct terputus. SMART CASHIER akan membuka Printer Sistem.');
      await closeActive();updatePanel();systemPrint(r);return;
    }
  }
  systemPrint(r);
}
document.addEventListener('click',e=>{
  const b=e.target.closest?.('[data-rc6-receipt-print]');if(!b)return;
  const r=window.__SDB_LAST_CASHIER_RECEIPT__;if(!r)return;
  e.preventDefault();e.stopPropagation();e.stopImmediatePropagation();
  print(r).catch(err=>alert('Gagal mencetak: '+String(err?.message||err)));
},true);
if(navigator.usb){
  navigator.usb.addEventListener('disconnect',e=>{if(active?.mode==='usb'&&active.device===e.device){active=null;updatePanel()}});
  navigator.usb.addEventListener('connect',()=>restore());
}
const boot=()=>{panel();patchSettingsNav();restore();new MutationObserver(()=>{panel();patchSettingsNav()}).observe(document.documentElement,{childList:true,subtree:true})};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.__SDB_THERMAL_PRINTER__={connect:openConnect,settings:openPrinterSettings,disconnect,status:statusText,print,restore,version:'v1'};
})();