(()=>{'use strict';
if(window.__rohmatKdsCashierRequiredReceiptV4)return;
window.__rohmatKdsCashierRequiredReceiptV4=1;

const nativeFetch=window.fetch.bind(window);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const currentLocale=()=>String(window.__SDB_I18N__?.locale?.()||window.__SDB_TENANT_CONFIG?.locale||'id-ID');
const currentTimezone=()=>String(window.__SDB_TENANT_CONFIG?.timezone||'Asia/Jakarta');
const tr=(key,fallback)=>String(window.__SDB_I18N__?.t?.(key)||fallback||key);
const rp=n=>new Intl.NumberFormat(currentLocale(),{style:'currency',currency:window.__SDB_TENANT_CONFIG?.currency||'IDR',maximumFractionDigits:0}).format(Number(n)||0);
const fd=v=>new Intl.DateTimeFormat(currentLocale(),{timeZone:currentTimezone(),day:'2-digit',month:'long',year:'numeric'}).format(new Date(v||Date.now()));
const ft=v=>new Intl.DateTimeFormat(currentLocale(),{timeZone:currentTimezone(),hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(v||Date.now())).replace('.',':')+(currentTimezone()==='Asia/Jakarta'?' WIB':'');
const table=r=>r?.service_mode==='dine-in'?String(r?.table_number||'—'):'Take Away';
function printerPaper(){try{const x=JSON.parse(localStorage.getItem('sdb-smart-order-printer-v3')||'{}');return x.paper==='58mm'?'58mm':'80mm'}catch{return'80mm'}}
const moneyFromText=v=>Number(String(v||'').replace(/[^0-9]/g,''))||0;

function receiptData(r){
  const items=Array.isArray(r?.items)?r.items:[];
  const itemSubtotal=items.reduce((sum,i)=>sum+(Number(i?.quantity)||0)*(Number(i?.price)||0),0);
  const subtotal=Math.max(0,Number(r?.subtotal_amount??r?.subtotal??itemSubtotal)||itemSubtotal);
  const total=Math.max(0,Number(r?.total_amount??r?.grand_total??subtotal)||0);
  const hasCharge=r?.charge_amount!=null||r?.charge!=null;
  const hasTax=r?.tax_amount!=null||r?.tax!=null;
  const charge=Math.max(0,Number(r?.charge_amount??r?.charge??0)||0);
  let tax=Math.max(0,Number(r?.tax_amount??r?.tax??0)||0);
  if(!hasTax)tax=Math.max(0,total-subtotal-(hasCharge?charge:0));
  const pricing=r?.transaction_pricing&&typeof r.transaction_pricing==='object'?r.transaction_pricing:{};
  const chargeCfg=pricing.charge&&typeof pricing.charge==='object'?pricing.charge:{};
  const taxCfg=pricing.tax&&typeof pricing.tax==='object'?pricing.tax:{};
  const chargeLabel=chargeCfg.mode==='percent'&&Number(chargeCfg.value)>0?String(chargeCfg.label||'Charge')+' '+Number(chargeCfg.value)+'%':String(chargeCfg.label||'Charge');
  const taxLabel=taxCfg.mode==='percent'&&Number(taxCfg.value)>0?String(taxCfg.label||'Pajak')+' '+Number(taxCfg.value)+'%':String(taxCfg.label||'Pajak');
  const service=r?.service_mode==='dine-in'?tr('service.dine','Makan di Tempat'):tr('service.takeaway','Bawa Pulang');
  const paymentRaw=String(r?.payment_method||r?.payment?.method||'').trim();
  const payment=paymentRaw==='cash'?tr('payment.cash','Tunai'):paymentRaw==='qris_cashier'||paymentRaw==='qris'?'QRIS':paymentRaw||'—';
  const paymentStatus=String(r?.payment_status||'').toLowerCase();
  const status=paymentStatus==='verified'||paymentStatus==='paid'?tr('payment.paid','LUNAS'):paymentStatus?paymentStatus.toUpperCase():'—';
  const cashier=String(r?.verified_by_email||r?.cashier_actor||(r?.order_source==='public'?'Sistem Publik':'—'));
  const cashReceived=r?.cash_received!=null?Math.max(0,Number(r.cash_received)||0):r?.paid_amount!=null?Math.max(0,Number(r.paid_amount)||0):null;
  const change=r?.change_amount!=null?Math.max(0,Number(r.change_amount)||0):null;
  const paymentAt=r?.verified_at||r?.payment_submitted_at||null;
  return {items,subtotal,charge,tax,total,service,payment,paymentRaw,status,cashier,cashReceived,change,paymentAt,chargeLabel,taxLabel};
}

function receiptRows(r){
  const d=receiptData(r),code=r?.payment_code||r?.public_order_code||'—',dine=r?.service_mode==='dine-in';
  return '<section class="receiptUnifiedV5">'+
    '<header class="receiptHeroV5"><div class="receiptEyV5">'+esc(tr('receipt.proofOrder','BUKTI PEMBAYARAN & PEMESANAN'))+'</div><h2>'+esc(tr('receipt.transaction','STRUK TRANSAKSI'))+'</h2><strong>SMART ORDER</strong></header>'+
    '<div class="receiptMetaV5">'+
      '<div><span>'+esc(tr('receipt.status','Status Pembayaran'))+'</span><strong>'+esc(d.status)+'</strong></div>'+
      '<div><span>'+esc(tr('receipt.code','Kode Transaksi'))+'</span><strong>'+esc(code)+'</strong></div>'+
      '<div><span>'+esc(tr('receipt.customer','Nama Pemesan'))+'</span><strong>'+esc(r?.customer_name||'—')+'</strong></div>'+
      '<div><span>'+esc(tr('receipt.service','Layanan'))+'</span><strong>'+esc(d.service)+'</strong></div>'+
      (dine?'<div><span>'+esc(tr('receipt.table','Nomor Meja'))+'</span><strong>'+esc(String(r?.table_number||'—'))+'</strong></div>':'')+
      '<div><span>'+esc(tr('receipt.orderDate','Tanggal Pemesanan'))+'</span><strong>'+esc(fd(r?.created_at))+'</strong></div>'+
      '<div><span>'+esc(tr('receipt.orderTime','Waktu Pemesanan'))+'</span><strong>'+esc(ft(r?.created_at))+'</strong></div>'+
      '<div><span>'+esc(tr('receipt.method','Metode Pembayaran'))+'</span><strong>'+esc(d.payment)+'</strong></div>'+
      (d.paymentAt?'<div><span>'+esc(tr('receipt.paymentTime','Waktu Pembayaran'))+'</span><strong>'+esc(ft(d.paymentAt))+'</strong></div>':'')+
      '<div><span>'+esc(tr('receipt.cashier','Petugas Kasir'))+'</span><strong>'+esc(d.cashier)+'</strong></div>'+
    '</div>'+
    '<div class="receiptItemsV5"><div class="receiptSectionV5">'+esc(tr('receipt.items','Rincian Pesanan'))+'</div>'+
      d.items.map(i=>'<div class="receiptItemV5"><div><strong>'+esc(i.name)+'</strong><span>'+Number(i.quantity||0)+' × '+rp(i.price)+'</span></div><b>'+rp((Number(i.quantity)||0)*(Number(i.price)||0))+'</b></div>').join('')+
    '</div>'+
    '<div class="receiptTotalsV5">'+
      '<div><span>'+esc(tr('receipt.subtotal','Subtotal'))+'</span><b>'+rp(d.subtotal)+'</b></div>'+
      (d.charge>0?'<div><span>'+esc(d.chargeLabel)+'</span><b>'+rp(d.charge)+'</b></div>':'')+
      (d.tax>0?'<div><span>'+esc(d.taxLabel)+'</span><b>'+rp(d.tax)+'</b></div>':'')+
      '<div class="receiptGrandV5"><span>'+esc(tr('receipt.total','Total Pembayaran').toUpperCase())+'</span><strong>'+rp(d.total)+'</strong></div>'+
      (d.cashReceived!=null?'<div><span>'+esc(tr('receipt.received','Nominal Diterima'))+'</span><b>'+rp(d.cashReceived)+'</b></div>':'')+
      (d.change!=null?'<div><span>'+esc(tr('receipt.change','Kembalian'))+'</span><b>'+rp(d.change)+'</b></div>':'')+
    '</div>'+
    '<footer class="receiptFootV5"><strong>'+esc(tr('receipt.thanks','Terima kasih atas kunjungan Anda.'))+'</strong><span>'+esc(tr('receipt.keep','Simpan struk ini sebagai bukti transaksi.'))+'</span></footer>'+
  '</section>';
}

function reservePrintWindow(){
  return open('','_blank','width=520,height=780');
}

function printReceipt(r,options={}){
  if(!r)throw Error('Data struk tidak tersedia.');
  const w=options.window||reservePrintWindow();
  if(!w)throw Error('Popup cetak diblokir browser.');
  const paper=printerPaper(),rows=receiptRows(r),lang=currentLocale().split('-')[0]||'id';
  const code=r?.payment_code||r?.public_order_code||'';
  const css='*{box-sizing:border-box}html,body{margin:0;padding:0;background:#fff;color:#000}body{font:12px/1.38 ui-monospace,SFMono-Regular,Consolas,"Liberation Mono",monospace}.sheet{width:'+paper+';max-width:'+paper+';margin:0 auto;padding:4mm;overflow:hidden}.receiptHeroV5{text-align:center;padding-bottom:8px;border-bottom:1px dashed #000}.receiptHeroV5 .receiptEyV5{font-size:10px;font-weight:800;letter-spacing:.04em}.receiptHeroV5 h2{font-size:17px;margin:5px 0 2px}.receiptHeroV5>strong{display:block;font-size:13px}.receiptMetaV5{padding:7px 0}.receiptMetaV5>div,.receiptTotalsV5>div{display:flex;justify-content:space-between;gap:8px;padding:3px 0}.receiptMetaV5 span,.receiptTotalsV5 span{min-width:0}.receiptMetaV5 strong,.receiptTotalsV5 b,.receiptTotalsV5 strong{text-align:right;overflow-wrap:anywhere;word-break:break-word}.receiptItemsV5{border-top:1px dashed #000;border-bottom:1px dashed #000;padding:5px 0}.receiptSectionV5{font-weight:900;margin-bottom:4px}.receiptItemV5{display:flex;justify-content:space-between;gap:8px;padding:4px 0}.receiptItemV5>div{min-width:0;flex:1}.receiptItemV5 strong,.receiptItemV5 span{display:block;overflow-wrap:anywhere}.receiptItemV5 span{font-size:11px}.receiptItemV5>b{white-space:nowrap;flex:none}.receiptTotalsV5{padding:6px 0}.receiptGrandV5{font-size:14px;font-weight:900;border-top:1px dashed #000;margin-top:4px;padding-top:6px!important}.receiptGrandV5 strong{font-size:15px}.receiptFootV5{border-top:1px dashed #000;text-align:center;padding-top:7px}.receiptFootV5 strong,.receiptFootV5 span{display:block}.receiptFootV5 span{margin-top:3px;font-size:10px}@page{size:'+paper+' auto;margin:0}@media print{html,body,.sheet{width:'+paper+'!important;max-width:'+paper+'!important}.sheet{padding:3.5mm!important}}';
  w.document.open();
  w.document.write('<!doctype html><html lang="'+esc(lang)+'"><head><meta charset="utf-8"><title>Struk '+esc(code)+'</title><style>'+css+'</style></head><body><main class="sheet">'+rows+'</main><script>onload=()=>{setTimeout(()=>{focus();print()},60)}<\\/script></body></html>');
  w.document.close();
  return w;
}

function showReceipt(r){
  if(!r)return;
  document.getElementById('cashReceiptModal')?.remove();
  const modal=document.createElement('div');
  modal.id='cashReceiptModal';
  modal.className='modal';
  modal.innerHTML='<div class="modalbox receiptModalV5"><div class="receiptHeaderV5"><div><div class="ey">BUKTI TRANSAKSI</div><h2>Struk Transaksi</h2></div><button type="button" class="btn" data-cash-receipt-close>Tutup</button></div>'+receiptRows(r)+'<div class="receiptActionsV5"><button type="button" class="btn green" data-cash-receipt-print>Cetak Struk</button></div></div>';
  document.body.appendChild(modal);
  modal.querySelector('[data-cash-receipt-close]')?.addEventListener('click',()=>modal.remove());
  modal.querySelector('[data-cash-receipt-print]')?.addEventListener('click',()=>{try{printReceipt(r)}catch(error){alert(error?.message||'Struk gagal dicetak.')}});
}

window.__SDB_UNIFIED_RECEIPT__={version:'v5-transaction-proof',receiptData,receiptRows,reservePrintWindow,printReceipt,showReceipt};

function gateState(){
  const root=document.getElementById('cashierRoot');
  const input=document.getElementById('cashName');
  const button=document.getElementById('cashPayNow');
  if(input){input.required=true;input.setAttribute('aria-required','true');input.placeholder='Wajib diisi';}
  if(!root||!button)return null;

  const hasItems=!!root.querySelector('[data-cash-minus]');
  const nameOk=!!input?.value.trim();
  const mode=root.querySelector('[data-cash-mode].on')?.dataset.cashMode||'';
  const tableValue=Number(document.getElementById('cashTable')?.value||0);
  const tableOk=mode==='take-away'||(mode==='dine-in'&&tableValue>=1&&tableValue<=20);
  const pay=root.querySelector('[data-cash-pay].on')?.dataset.cashPay||'';
  const total=moneyFromText(root.querySelector('.cashTotal b')?.textContent);
  const cashReceived=Number(document.getElementById('cashMoney')?.value||0);
  const cashOk=pay==='cash'&&Number.isFinite(cashReceived)&&total>0&&cashReceived>=total;
  const qrisOk=pay==='qris_cashier'&&!!document.getElementById('cashQrisOk')?.checked;
  const paymentOk=cashOk||qrisOk;
  const submitting=button.dataset.cashGateSubmitting==='1'||/Memproses/i.test(button.textContent||'');
  const valid=hasItems&&nameOk&&tableOk&&paymentOk&&!submitting;

  let reason='';
  if(!hasItems)reason='Pilih minimal satu menu.';
  else if(!nameOk)reason='Nama Pemesan wajib diisi.';
  else if(!tableOk)reason='Pilih nomor meja.';
  else if(pay==='cash'&&!cashOk)reason='Uang diterima harus minimal sebesar total pesanan.';
  else if(pay==='qris_cashier'&&!qrisOk)reason='Konfirmasi pembayaran QRIS terlebih dahulu.';
  else if(!paymentOk)reason='Lengkapi metode pembayaran.';
  else if(submitting)reason='Transaksi sedang diproses.';

  button.disabled=!valid;
  button.classList.toggle('cashPayLocked',!valid);
  button.classList.toggle('primary',valid);
  button.setAttribute('aria-disabled',String(!valid));
  button.dataset.cashGateReason=reason;
  button.title=reason;
  return {valid,reason,button};
}

let queued=false;
function scheduleGate(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;gateState();});}

document.addEventListener('rohmat:kds-cashier-rendered',scheduleGate);
document.addEventListener('rohmat:kds-cart-updated',scheduleGate);
document.addEventListener('input',e=>{if(['cashName','cashMoney','cashNote'].includes(e.target?.id))scheduleGate();});
document.addEventListener('change',e=>{if(['cashTable','cashQrisOk'].includes(e.target?.id))scheduleGate();});
document.addEventListener('click',e=>{
  const paymentButton=e.target.closest?.('#cashPayNow');
  if(paymentButton){
    const state=gateState();
    if(!state?.valid){e.preventDefault();e.stopImmediatePropagation();return;}
    paymentButton.dataset.cashGateSubmitting='1';
    paymentButton.disabled=true;
    paymentButton.classList.add('cashPayLocked');
    paymentButton.classList.remove('primary');
    return;
  }
  if(e.target.closest?.('[data-cash-add],[data-cash-plus],[data-cash-minus],[data-cash-mode],[data-cash-pay]'))setTimeout(scheduleGate,0);
},true);

window.fetch=async function(input,init){
  let body=null;
  try{if(init?.body)body=JSON.parse(String(init.body));}catch{}
  const isCreate=body?.action==='cashier'&&body?.payload?.action==='create_order';
  try{
    const response=await nativeFetch(input,init);
    if(isCreate){
      try{if(response.ok){const data=await response.clone().json();if(data?.ok&&data?.receipt)queueMicrotask(()=>showReceipt(data.receipt));}}catch{}
      const button=document.getElementById('cashPayNow');
      if(button)delete button.dataset.cashGateSubmitting;
      setTimeout(scheduleGate,0);
    }
    return response;
  }catch(error){
    if(isCreate){const button=document.getElementById('cashPayNow');if(button)delete button.dataset.cashGateSubmitting;setTimeout(scheduleGate,0);}
    throw error;
  }
};

scheduleGate();
})();