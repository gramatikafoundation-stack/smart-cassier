(()=>{'use strict';
if(window.__rohmatKdsCashierRequiredReceiptV3)return;
window.__rohmatKdsCashierRequiredReceiptV3=1;

const nativeFetch=window.fetch.bind(window);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const rp=n=>new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(Number(n)||0);
const fd=v=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',day:'2-digit',month:'long',year:'numeric'}).format(new Date(v||Date.now()));
const ft=v=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(v||Date.now())).replace('.',':')+' WIB';
const table=r=>r?.service_mode==='dine-in'?String(r?.table_number||'—'):'Take Away';
const moneyFromText=v=>Number(String(v||'').replace(/[^0-9]/g,''))||0;

function receiptRows(r){
  const items=Array.isArray(r?.items)?r.items:[];
  return '<div class="cashLine"><b>KODE PEMBAYARAN</b><strong>'+esc(r?.payment_code||'—')+'</strong></div>'+
    '<div class="cashLine"><b>Nama Pemesan</b><strong>'+esc(r?.customer_name||'—')+'</strong></div>'+
    '<div class="cashLine"><b>Meja</b><strong>'+esc(table(r))+'</strong></div>'+
    '<div class="cashLine"><b>Tanggal Pesanan</b><strong>'+esc(fd(r?.created_at))+'</strong></div>'+
    '<div class="cashLine"><b>Waktu Pesanan</b><strong>'+esc(ft(r?.created_at))+'</strong></div>'+
    '<div class="cashLine"><div><b>Menu, Jumlah, dan Harga Pesanan</b></div><div>'+items.map(i=>'<div class="cashLine"><span>'+esc(i.name)+'</span><strong>'+Number(i.quantity||0)+' × '+rp(i.price)+'</strong></div>').join('')+'</div></div>'+
    '<div class="cashTotal"><span>Total Pesanan</span><b>'+rp(r?.total_amount)+'</b></div>';
}

function printReceipt(r){
  const w=open('','_blank','width=560,height=760');
  if(!w)return;
  const items=Array.isArray(r?.items)?r.items:[];
  w.document.write('<!doctype html><meta charset="utf-8"><title>Struk '+esc(r?.payment_code||'')+'</title><style>body{font:14px Arial,sans-serif;padding:24px;color:#1f332c}h2{margin:0 0 18px}.row{display:grid;grid-template-columns:190px 1fr;gap:12px;padding:9px 0;border-bottom:1px solid #ddd}.items div{display:flex;justify-content:space-between;gap:12px;padding:3px 0}@media print{button{display:none}}</style><h2>Struk Pembayaran & Pemesanan</h2><div class="row"><b>KODE PEMBAYARAN</b><strong>'+esc(r?.payment_code||'—')+'</strong></div><div class="row"><b>Nama Pemesan</b><strong>'+esc(r?.customer_name||'—')+'</strong></div><div class="row"><b>Meja</b><strong>'+esc(table(r))+'</strong></div><div class="row"><b>Tanggal Pesanan</b><strong>'+esc(fd(r?.created_at))+'</strong></div><div class="row"><b>Waktu Pesanan</b><strong>'+esc(ft(r?.created_at))+'</strong></div><div class="row"><b>Menu, Jumlah, dan Harga Pesanan</b><div class="items">'+items.map(i=>'<div><span>'+esc(i.name)+'</span><strong>'+Number(i.quantity||0)+' × '+rp(i.price)+'</strong></div>').join('')+'</div></div><div class="row"><b>Total Pesanan</b><strong>'+rp(r?.total_amount)+'</strong></div><script>onload=()=>print()<\/script>');
  w.document.close();
}

function showReceipt(r){
  if(!r)return;
  document.getElementById('cashReceiptModal')?.remove();
  const modal=document.createElement('div');
  modal.id='cashReceiptModal';
  modal.className='modal';
  modal.innerHTML='<div class="modalbox"><div class="mh"><div><small>RINGKASAN PESANAN</small><h2>Struk Pembayaran & Pemesanan</h2></div><button type="button" class="btn" data-cash-receipt-close>Tutup</button></div>'+receiptRows(r)+'<div class="row"><button type="button" class="btn green" data-cash-receipt-print>Cetak Struk</button></div></div>';
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

const root=document.getElementById('cashierRoot');
if(root)new MutationObserver(scheduleGate).observe(root,{childList:true,subtree:true});
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