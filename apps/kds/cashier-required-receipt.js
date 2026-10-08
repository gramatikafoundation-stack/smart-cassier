(()=>{'use strict';
if(window.__rohmatKdsCashierRequiredReceiptV4)return;
window.__rohmatKdsCashierRequiredReceiptV4=1;

const nativeFetch=window.fetch.bind(window);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const rp=n=>new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(Number(n)||0);
const fd=v=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',day:'2-digit',month:'long',year:'numeric'}).format(new Date(v||Date.now()));
const ft=v=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(v||Date.now())).replace('.',':')+' WIB';
const table=r=>r?.service_mode==='dine-in'?String(r?.table_number||'—'):'Take Away';
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
  const service=r?.service_mode==='dine-in'?'Makan di Tempat':'Bawa Pulang';
  const payment=String(r?.payment_method||r?.payment?.method||'').trim();
  return {items,subtotal,charge,tax,total,service,payment,chargeLabel,taxLabel};
}

function receiptRows(r){
  const d=receiptData(r);
  return '<section class="receiptUnifiedV4">'+
    '<div class="receiptCodeV4"><span>Kode Transaksi</span><strong>'+esc(r?.payment_code||r?.public_order_code||'—')+'</strong></div>'+
    '<div class="receiptMetaV4">'+
      '<div><span>Nama Pemesan</span><strong>'+esc(r?.customer_name||'—')+'</strong></div>'+
      '<div><span>Layanan</span><strong>'+esc(d.service)+'</strong></div>'+
      '<div><span>Nomor Meja</span><strong>'+esc(r?.service_mode==='dine-in'?String(r?.table_number||'—'):'—')+'</strong></div>'+
      (d.payment?'<div><span>Metode Pembayaran</span><strong>'+esc(d.payment.toUpperCase())+'</strong></div>':'')+
      '<div><span>Tanggal Pemesanan</span><strong>'+esc(fd(r?.created_at))+'</strong></div>'+
      '<div><span>Waktu Pemesanan</span><strong>'+esc(ft(r?.created_at))+'</strong></div>'+
    '</div>'+
    '<div class="receiptItemsV4"><div class="receiptSectionV4">Rincian Pesanan</div>'+
      d.items.map(i=>'<div class="receiptItemV4"><div><strong>'+esc(i.name)+'</strong><span>'+Number(i.quantity||0)+' × '+rp(i.price)+'</span></div><b>'+rp((Number(i.quantity)||0)*(Number(i.price)||0))+'</b></div>').join('')+
    '</div>'+
    '<div class="receiptTotalsV4">'+
      '<div><span>Subtotal</span><b>'+rp(d.subtotal)+'</b></div>'+
      (d.charge>0?'<div><span>'+esc(d.chargeLabel)+'</span><b>'+rp(d.charge)+'</b></div>':'')+
      (d.tax>0?'<div><span>'+esc(d.taxLabel)+'</span><b>'+rp(d.tax)+'</b></div>':'')+
      '<div class="receiptGrandV4"><span>Total Pembayaran</span><strong>'+rp(d.total)+'</strong></div>'+
    '</div>'+
  '</section>';
}

function printReceipt(r){
  const w=open('','_blank','width=640,height=820');
  if(!w)return;
  const d=receiptData(r);
  const rows=receiptRows(r);
  w.document.write('<!doctype html><html lang="id"><head><meta charset="utf-8"><title>Struk '+esc(r?.payment_code||r?.public_order_code||'')+'</title><style>'+
  '*{box-sizing:border-box}body{margin:0;padding:28px;background:#f5f7f6;color:#17211d;font:14px/1.45 Arial,sans-serif}.sheet{max-width:720px;margin:auto;background:#fff;border:1px solid #e1e7e3;border-radius:20px;padding:26px}.head{display:flex;justify-content:space-between;gap:18px;padding-bottom:18px;border-bottom:1px solid #e4e9e6}.head h2{margin:0;font-size:24px}.head p{margin:5px 0 0;color:#748079}.receiptCodeV4{text-align:right;background:#f3f6f4;border:1px solid #e0e6e2;border-radius:12px;padding:10px 12px}.receiptCodeV4 span,.receiptCodeV4 strong{display:block}.receiptCodeV4 span{font-size:10px;text-transform:uppercase;letter-spacing:.1em;color:#75817c}.receiptMetaV4{display:grid;grid-template-columns:1fr 1fr;gap:0 24px;padding:14px 0}.receiptMetaV4>div{display:flex;justify-content:space-between;gap:14px;padding:8px 0;border-bottom:1px solid #eef1ef}.receiptMetaV4 span{color:#68756f}.receiptItemsV4{margin-top:14px;border:1px solid #e2e8e4;border-radius:13px;overflow:hidden}.receiptSectionV4{background:#f4f7f5;padding:9px 12px;font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.08em}.receiptItemV4{display:flex;justify-content:space-between;gap:16px;padding:10px 12px;border-top:1px solid #edf1ee}.receiptItemV4 strong,.receiptItemV4 span{display:block}.receiptItemV4 span{color:#7b8782;font-size:12px}.receiptTotalsV4{width:min(100%,340px);margin:14px 0 0 auto}.receiptTotalsV4>div{display:flex;justify-content:space-between;padding:7px 0}.receiptGrandV4{border-top:1px solid #dfe6e2;margin-top:3px;padding-top:12px!important;font-size:16px}.receiptGrandV4 strong{font-size:19px;color:#173f33}.receiptCodeV4 strong,.receiptMetaV4 strong,.receiptItemV4 strong{overflow-wrap:anywhere;word-break:break-word;min-width:0}.receiptItemV4>div{min-width:0;flex:1}.receiptItemV4>b{white-space:nowrap;flex:none}@page{size:80mm auto;margin:0}@media print{html,body{width:80mm;max-width:80mm;margin:0;padding:0}.sheet{width:80mm;max-width:80mm;margin:0;border:0;border-radius:0;box-shadow:none;padding:5mm}.head{display:block}.receiptCodeV4{text-align:left;margin-top:8px}.receiptMetaV4{grid-template-columns:1fr}.receiptMetaV4>div{align-items:flex-start}.receiptItemsV4,.receiptTotalsV4{max-width:100%;overflow:hidden}}</style></head><body><main class="sheet"><div class="head"><div><h2>Struk Pembayaran &amp; Pemesanan</h2><p>Dokumen transaksi</p></div><div class="receiptCodeV4"><span>Kode Transaksi</span><strong>'+esc(r?.payment_code||r?.public_order_code||'—')+'</strong></div></div>'+rows.replace(/^<section class="receiptUnifiedV4"><div class="receiptCodeV4">[\s\S]*?<\/div>/,'<section class="receiptUnifiedV4">')+'</main><script>onload=()=>print()<\/script></body></html>');
  w.document.close();
}

function showReceipt(r){
  if(!r)return;
  document.getElementById('cashReceiptModal')?.remove();
  const modal=document.createElement('div');
  modal.id='cashReceiptModal';
  modal.className='modal';
  modal.innerHTML='<div class="modalbox receiptModalV4"><div class="receiptHeaderV4"><div><h2>Struk Pembayaran & Pemesanan</h2><p>Dokumen transaksi</p></div><button type="button" class="btn" data-cash-receipt-close>Tutup</button></div>'+receiptRows(r)+'<div class="receiptActionsV4"><button type="button" class="btn green" data-cash-receipt-print>Cetak Struk</button></div></div>';
  document.body.appendChild(modal);
  modal.querySelector('[data-cash-receipt-close]')?.addEventListener('click',()=>modal.remove());
  modal.querySelector('[data-cash-receipt-print]')?.addEventListener('click',()=>printReceipt(r));
}

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