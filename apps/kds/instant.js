(()=>{'use strict';
const style=document.createElement('style');style.id='rohmatInstantUiV3';style.textContent=`
button,.tab,.cashBtn,.sw{touch-action:manipulation}
.cashItem[hidden]{display:none!important}.cashItem,.stock{contain:layout paint style}
#cashierRoot .cashTop>div:first-child{display:none!important}
#cashierRoot .cashTop{justify-content:flex-end!important;margin-bottom:8px!important}
.cashCardControl{display:grid;width:100%;gap:6px}
.cashCardControl.single{grid-template-columns:1fr}
.cashCardControl.stepper{grid-template-columns:42px 1fr 42px;align-items:center}
.cashCardControl .cashBtn{width:100%;min-height:38px}
.cashCardQty{display:grid;place-items:center;min-height:38px;border:1px solid var(--c-line);border-radius:10px;background:#f7f5ef;font-weight:950;font-size:15px}
.sw[data-pending='1']{opacity:.72}
`;document.head.appendChild(style);

const pendingAvailability=new Map();
let orderSigFast='',menuSigFast='',cashLoadedAt=0;

function orderSig(d){return JSON.stringify((d?.orders||[]).map(o=>[o.id,o.order_status,o.payment_status,o.updated_at,o.preparing_at,o.ready_at,o.completed_at]))}
function menuSig(d){return JSON.stringify((d?.menu||[]).map(m=>[m.id,m.name,m.category,m.price,m.is_available,m.image_url]))}
function overlayPending(menu){
  const now=Date.now();
  for(const [id,p] of [...pendingAvailability]){
    const m=(menu||[]).find(x=>String(x.id)===id);
    if(!m)continue;
    if(m.is_available===p.desired && now-p.started>40){pendingAvailability.delete(id);continue}
    m.is_available=p.desired;
  }
}
function syncPendingButtons(){
  document.querySelectorAll('[data-stock]').forEach(b=>b.dataset.pending=pendingAvailability.has(String(b.dataset.stock))?'1':'0');
}

refresh=async function(manual=false){
  if(syncBusy)return;syncBusy=true;const b=$('refresh');
  if(manual){b.disabled=true;b.textContent='↻ Memperbarui…'}
  try{
    const d=await rpc('kds_snapshot');
    overlayPending(d.menu||[]);
    const os=orderSig(d),ms=menuSig(d);
    snap=d;
    if(os!==orderSigFast){orderSigFast=os;renderOrders()}
    if(ms!==menuSigFast){menuSigFast=ms;renderStock();syncPendingButtons()}
    $('sync').textContent='● Live · '+new Date().toLocaleTimeString('id-ID',{hour:'2-digit',minute:'2-digit',second:'2-digit'});
  }catch(error){$('sync').textContent='● Gangguan';if(manual)toast(error.message||'Gagal memperbarui')}
  finally{syncBusy=false;if(manual){b.disabled=false;b.textContent='↻ Perbarui'}}
};

function findMenu(id,source){return (source||[]).find(x=>String(x.id)===String(id))}
function updateCashAvailabilityDom(id,on){
  const item=document.querySelector('#cashierRoot .cashItem[data-menu-id="'+CSS.escape(String(id))+'"]');
  if(!item)return;item.classList.toggle('off',!on);const plus=item.querySelector('[data-fast-plus],[data-fast-add]');if(plus)plus.disabled=!on;
}
stock=async function(id,on){
  id=String(id);if(pendingAvailability.has(id))return;
  const sm=findMenu(id,snap.menu),cm=findMenu(id,cashSnap?.menu),prevSnap=sm?.is_available,prevCash=cm?.is_available;
  pendingAvailability.set(id,{desired:on,started:Date.now(),prevSnap,prevCash});
  if(sm)sm.is_available=on;if(cm)cm.is_available=on;
  menuSigFast=menuSig(snap);renderStock();syncPendingButtons();updateCashAvailabilityDom(id,on);
  try{
    await rpc('kds_set_availability',{p_id:id,p_available:on,p_note:on?'':'Habis'});
    toast(on?'Menu kembali tersedia':'Menu ditandai habis');
    setTimeout(()=>void refresh(false),60);
    if(cashSnap)setTimeout(()=>void cashLoad(false),90);
  }catch(error){
    pendingAvailability.delete(id);
    if(sm)sm.is_available=prevSnap;if(cm)cm.is_available=prevCash;
    menuSigFast='';renderStock();syncPendingButtons();updateCashAvailabilityDom(id,!!(prevCash??prevSnap));
    throw error;
  }
};

function ensureCashRootBinding(){
  const root=$('cashierRoot');if(!root||root.dataset.instantBound==='1')return;root.dataset.instantBound='1';
  root.addEventListener('click',e=>{
    const reload=e.target.closest('#cashReload');if(reload){e.preventDefault();void cashLoad(true);return}
    const catBtn=e.target.closest('[data-cash-cat]');if(catBtn){e.preventDefault();cashCat=catBtn.dataset.cashCat;filterCashCategory();return}
    const add=e.target.closest('[data-fast-add]');if(add){e.preventDefault();const id=add.dataset.fastAdd;cart[id]=(cart[id]||0)+1;updateMenuControl(id);renderCashCartFast();return}
    const plus=e.target.closest('[data-fast-plus]');if(plus){e.preventDefault();const id=plus.dataset.fastPlus;cart[id]=(cart[id]||0)+1;updateMenuControl(id);renderCashCartFast();return}
    const minus=e.target.closest('[data-fast-minus]');if(minus){e.preventDefault();const id=minus.dataset.fastMinus,n=(cart[id]||0)-1;if(n>0)cart[id]=n;else delete cart[id];updateMenuControl(id);renderCashCartFast();return}
    const cplus=e.target.closest('[data-cash-plus]');if(cplus){e.preventDefault();const id=cplus.dataset.cashPlus;cart[id]=(cart[id]||0)+1;updateMenuControl(id);renderCashCartFast();return}
    const cminus=e.target.closest('[data-cash-minus]');if(cminus){e.preventDefault();const id=cminus.dataset.cashMinus,n=(cart[id]||0)-1;if(n>0)cart[id]=n;else delete cart[id];updateMenuControl(id);renderCashCartFast();return}
    const modeBtn=e.target.closest('[data-cash-mode]');if(modeBtn){e.preventDefault();cashRemember();cashMode=modeBtn.dataset.cashMode;if(cashMode==='take-away')cashDraft.table='';renderCashCartFast();return}
    const payBtn=e.target.closest('[data-cash-pay]');if(payBtn){e.preventDefault();cashRemember();cashPay=payBtn.dataset.cashPay;if(cashPay==='cash')cashDraft.qrisOk=false;renderCashCartFast();return}
    if(e.target.closest('#cashPayNow')){e.preventDefault();void cashCreate()}
  });
  root.addEventListener('input',e=>{
    if(e.target.id==='cashName')cashDraft.name=e.target.value;
    else if(e.target.id==='cashNote')cashDraft.note=e.target.value;
    else if(e.target.id==='cashMoney'){cashDraft.cash=e.target.value;const c=$('cashChange');if(c)c.textContent=rp(Math.max(0,Number(cashDraft.cash||0)-cashTotal()))}
  });
  root.addEventListener('change',e=>{
    if(e.target.id==='cashTable')cashDraft.table=e.target.value;
    else if(e.target.id==='cashQrisOk')cashDraft.qrisOk=e.target.checked;
  });
}

function cashControlHtml(id){
  const qty=Math.max(0,Number(cart[String(id)]||0)),m=findMenu(id,cashSnap?.menu),disabled=m?.is_available===false?' disabled':'';
  if(qty<1)return '<div class="cashCardControl single" data-fast-control="'+esc(id)+'"><button class="cashBtn primary" data-fast-add="'+esc(id)+'"'+disabled+'>+ Tambah</button></div>';
  return '<div class="cashCardControl stepper" data-fast-control="'+esc(id)+'"><button class="cashBtn" data-fast-minus="'+esc(id)+'" aria-label="Kurangi">−</button><div class="cashCardQty" aria-live="polite">'+qty+'</div><button class="cashBtn primary" data-fast-plus="'+esc(id)+'" aria-label="Tambah"'+disabled+'>+</button></div>';
}
function enhanceCashMenu(){
  if(!cashSnap)return;const map=new Map((cashSnap.menu||[]).map(m=>[String(m.id),m]));
  document.querySelectorAll('#cashierRoot .cashMenu .cashItem').forEach(item=>{
    const old=item.querySelector('[data-cash-add]');let id=old?.dataset.cashAdd||item.dataset.menuId||'';if(!id)return;id=String(id);item.dataset.menuId=id;const m=map.get(id);if(m)item.dataset.cashCategory=String(m.category||'');
    const current=item.querySelector('[data-fast-control]');if(current)current.outerHTML=cashControlHtml(id);else if(old)old.outerHTML=cashControlHtml(id);
  });
}
function updateMenuControl(id){
  const item=document.querySelector('#cashierRoot .cashItem[data-menu-id="'+CSS.escape(String(id))+'"]');if(!item)return;const c=item.querySelector('[data-fast-control]');if(c)c.outerHTML=cashControlHtml(id);
}
function filterCashCategory(){
  document.querySelectorAll('#cashierRoot [data-cash-cat]').forEach(b=>b.classList.toggle('on',b.dataset.cashCat===cashCat));
  document.querySelectorAll('#cashierRoot .cashMenu .cashItem').forEach(item=>{item.hidden=cashCat!=='Semua'&&item.dataset.cashCategory!==cashCat});
}
function cartHtml(){
  const sel=cashSelected(),qris=!!(cashSnap?.settings?.qris_enabled&&cashSnap?.settings?.qris_image_url);
  return (sel.length?sel.map(x=>'<div class="cashLine"><div><b>'+esc(x.m.name)+'</b><div class="muted">'+rp(x.m.price)+' × '+x.q+'</div></div><div class="cashQty"><button class="cashBtn" data-cash-minus="'+esc(x.m.id)+'">−</button><b>'+x.q+'</b><button class="cashBtn" data-cash-plus="'+esc(x.m.id)+'">+</button></div></div>').join(''):'<div class="cashEmpty">Belum ada menu dipilih.</div>')+
  '<div class="cashField"><label>Nama Pemesan</label><input id="cashName" value="'+esc(cashDraft.name)+'"></div><div class="cashTwo"><button class="cashBtn '+(cashMode==='dine-in'?'on':'')+'" data-cash-mode="dine-in">Dine In</button><button class="cashBtn '+(cashMode==='take-away'?'on':'')+'" data-cash-mode="take-away">Take Away</button></div>'+
  (cashMode==='dine-in'?'<div class="cashField"><label>Nomor Meja</label><select id="cashTable"><option value="">Pilih meja</option>'+Array.from({length:20},(_,i)=>'<option value="'+(i+1)+'" '+(String(i+1)===String(cashDraft.table)?'selected':'')+'>Meja '+String(i+1).padStart(2,'0')+'</option>').join('')+'</select></div>':'')+
  '<div class="cashField"><label>Keterangan</label><textarea id="cashNote" rows="2">'+esc(cashDraft.note)+'</textarea></div><div class="cashTwo"><button class="cashBtn '+(cashPay==='cash'?'on':'')+'" data-cash-pay="cash">Cash</button><button class="cashBtn '+(cashPay==='qris_cashier'?'on':'')+'" data-cash-pay="qris_cashier">QRIS</button></div>'+
  (cashPay==='cash'?'<div class="cashField"><label>Uang diterima</label><input id="cashMoney" type="number" min="0" step="1000" value="'+esc(cashDraft.cash)+'"><div class="muted">Kembalian: <b id="cashChange">'+rp(Math.max(0,Number(cashDraft.cash||0)-cashTotal()))+'</b></div></div>':(qris?'<div class="cashQris"><img src="'+esc(cashSnap.settings.qris_image_url)+'" alt="QRIS"><label><input id="cashQrisOk" type="checkbox" '+(cashDraft.qrisOk?'checked':'')+'> Pembayaran QRIS sudah diterima kasir.</label></div>':'<div class="cashBad">QRIS belum tersedia.</div>'))+
  '<div class="cashTotal"><span>Total</span><b>'+rp(cashTotal())+'</b></div><button id="cashPayNow" class="cashBtn primary" style="width:100%" '+(!sel.length||(cashPay==='qris_cashier'&&!qris)?'disabled':'')+'>Bayar & Kirim ke Dapur</button><div id="cashMsg"></div>';
}
function renderCashCartFast(){cashRemember();const aside=document.querySelector('#cashierRoot .cashLayout>aside.cashPanel');if(!aside)return;aside.innerHTML=cartHtml()}

const nativeCashRender=cashRender;
cashBind=function(){ensureCashRootBinding()};
cashRender=function(){
  const wanted=cashCat;cashCat='Semua';nativeCashRender();cashCat=wanted;
  ensureCashRootBinding();enhanceCashMenu();filterCashCategory();
};
cashRerender=function(fn){cashRemember();const before=cashCat;fn?.();if(cashCat!==before){filterCashCategory();return}enhanceCashMenu();renderCashCartFast()};

cashLoad=async function(manual=false){
  if(cashBusy)return;if(!manual&&cashSnap&&Date.now()-cashLoadedAt<5000)return;cashBusy=true;
  if(!cashSnap)$('cashierRoot').innerHTML='<div class="cashEmpty">Memuat Smart Cashier…</div>';
  try{
    const next=await cashier({action:'snapshot'});overlayPending(next.menu||[]);const nextSig=cashSignature(next),changed=nextSig!==cashSig;
    cashSnap=next;cashLoadedAt=Date.now();if(changed||manual||!$('cashierRoot').dataset.ready){cashSig=nextSig;cashRender();$('cashierRoot').dataset.ready='1'}
  }catch(error){if(!cashSnap)$('cashierRoot').innerHTML='<div class="cashBad"><b>Smart Cashier gagal dimuat.</b><br>'+esc(error.message||error)+'</div>';if(manual)toast(error.message)}
  finally{cashBusy=false}
};

// Warm Smart Cashier in parallel with the normal boot sequence.
setTimeout(()=>{try{void cashLoad(false)}catch{}},0);
})();