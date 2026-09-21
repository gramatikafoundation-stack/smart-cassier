(() => {
  const style = document.createElement('style');
  style.textContent = 'button,.tab,.cashBtn,.sw{touch-action:manipulation}.cashItem[hidden]{display:none!important}.cashItem,.stock{contain:layout paint style}';
  document.head.appendChild(style);

  let fastOrderSig = '';
  let fastMenuSig = '';
  const stockPending = new Set();
  const baseCashBind = cashBind;

  function orderSignature(d){
    return JSON.stringify((d?.orders||[]).map(o=>[o.id,o.order_status,o.payment_status,o.updated_at,o.preparing_at,o.ready_at,o.completed_at]));
  }
  function menuSignature(d){
    return JSON.stringify((d?.menu||[]).map(m=>[m.id,m.is_available]));
  }

  refresh = async function(manual=false){
    if(syncBusy)return;
    syncBusy=true;
    const b=$('refresh');
    if(manual){b.disabled=true;b.textContent='↻ Memperbarui…'}
    try{
      const d=await rpc('kds_snapshot');
      const nextOrderSig=orderSignature(d),nextMenuSig=menuSignature(d);
      snap=d;
      if(nextOrderSig!==fastOrderSig){fastOrderSig=nextOrderSig;renderOrders()}
      if(nextMenuSig!==fastMenuSig){fastMenuSig=nextMenuSig;renderStock()}
      $('sync').textContent='● Live · '+new Date().toLocaleTimeString('id-ID',{hour:'2-digit',minute:'2-digit',second:'2-digit'});
    }catch(error){
      $('sync').textContent='● Gangguan';
      if(manual)toast(error.message||'Gagal memperbarui');
    }finally{
      syncBusy=false;
      if(manual){b.disabled=false;b.textContent='↻ Perbarui'}
    }
  };

  function annotateCashMenu(){
    if(!cashSnap)return;
    const map=new Map((cashSnap.menu||[]).map(m=>[String(m.id),m]));
    document.querySelectorAll('#cashierRoot .cashMenu [data-cash-add]').forEach(btn=>{
      const item=btn.closest('.cashItem'),m=map.get(String(btn.dataset.cashAdd));
      if(item&&m)item.dataset.cashCategory=String(m.category||'');
    });
  }

  function setCategoryButtonState(){
    document.querySelectorAll('#cashierRoot [data-cash-cat]').forEach(b=>b.classList.toggle('on',b.dataset.cashCat===cashCat));
  }

  function filterCashCategoryFast(){
    if(!cashSnap)return false;
    const items=[...document.querySelectorAll('#cashierRoot .cashMenu .cashItem')];
    if(!items.length||items.length<(cashSnap.menu||[]).length)return false;
    for(const item of items)item.hidden=cashCat!=='Semua'&&item.dataset.cashCategory!==cashCat;
    setCategoryButtonState();
    return true;
  }

  function bindCartFast(){
    document.querySelectorAll('#cashCartPanel [data-cash-plus]').forEach(b=>b.onclick=()=>cashRerender(()=>cart[b.dataset.cashPlus]=(cart[b.dataset.cashPlus]||0)+1));
    document.querySelectorAll('#cashCartPanel [data-cash-minus]').forEach(b=>b.onclick=()=>cashRerender(()=>{const id=b.dataset.cashMinus,n=(cart[id]||0)-1;if(n>0)cart[id]=n;else delete cart[id]}));
    document.querySelectorAll('#cashCartPanel [data-cash-mode]').forEach(b=>b.onclick=()=>cashRerender(()=>{cashMode=b.dataset.cashMode;if(cashMode==='take-away')cashDraft.table=''}));
    document.querySelectorAll('#cashCartPanel [data-cash-pay]').forEach(b=>b.onclick=()=>cashRerender(()=>{cashPay=b.dataset.cashPay;if(cashPay==='cash')cashDraft.qrisOk=false}));
    $('cashName')?.addEventListener('input',e=>cashDraft.name=e.target.value);
    $('cashTable')?.addEventListener('change',e=>cashDraft.table=e.target.value);
    $('cashNote')?.addEventListener('input',e=>cashDraft.note=e.target.value);
    $('cashQrisOk')?.addEventListener('change',e=>cashDraft.qrisOk=e.target.checked);
    $('cashMoney')?.addEventListener('input',e=>{cashDraft.cash=e.target.value;if($('cashChange'))$('cashChange').textContent=rp(Math.max(0,Number(cashDraft.cash||0)-cashTotal()))});
    $('cashPayNow')?.addEventListener('click',cashCreate);
  }

  function cashCartHtml(){
    const sel=cashSelected(),qris=!!(cashSnap?.settings?.qris_enabled&&cashSnap?.settings?.qris_image_url);
    return (sel.length?sel.map(x=>'<div class="cashLine"><div><b>'+esc(x.m.name)+'</b><div class="muted">'+rp(x.m.price)+' × '+x.q+'</div></div><div class="cashQty"><button class="cashBtn" data-cash-minus="'+esc(x.m.id)+'">−</button><b>'+x.q+'</b><button class="cashBtn" data-cash-plus="'+esc(x.m.id)+'">+</button></div></div>').join(''):'<div class="cashEmpty">Belum ada menu dipilih.</div>')+
      '<div class="cashField"><label>Nama Pemesan</label><input id="cashName" value="'+esc(cashDraft.name)+'"></div><div class="cashTwo"><button class="cashBtn '+(cashMode==='dine-in'?'on':'')+'" data-cash-mode="dine-in">Dine In</button><button class="cashBtn '+(cashMode==='take-away'?'on':'')+'" data-cash-mode="take-away">Take Away</button></div>'+
      (cashMode==='dine-in'?'<div class="cashField"><label>Nomor Meja</label><select id="cashTable"><option value="">Pilih meja</option>'+Array.from({length:20},(_,i)=>'<option value="'+(i+1)+'" '+(String(i+1)===String(cashDraft.table)?'selected':'')+'>Meja '+String(i+1).padStart(2,'0')+'</option>').join('')+'</select></div>':'')+
      '<div class="cashField"><label>Keterangan</label><textarea id="cashNote" rows="2">'+esc(cashDraft.note)+'</textarea></div><div class="cashTwo"><button class="cashBtn '+(cashPay==='cash'?'on':'')+'" data-cash-pay="cash">Cash</button><button class="cashBtn '+(cashPay==='qris_cashier'?'on':'')+'" data-cash-pay="qris_cashier">QRIS</button></div>'+
      (cashPay==='cash'?'<div class="cashField"><label>Uang diterima</label><input id="cashMoney" type="number" min="0" step="1000" value="'+esc(cashDraft.cash)+'"><div class="muted">Kembalian: <b id="cashChange">'+rp(Math.max(0,Number(cashDraft.cash||0)-cashTotal()))+'</b></div></div>':(qris?'<div class="cashQris"><img src="'+esc(cashSnap.settings.qris_image_url)+'" alt="QRIS"><label><input id="cashQrisOk" type="checkbox" '+(cashDraft.qrisOk?'checked':'')+'> Pembayaran QRIS sudah diterima kasir.</label></div>':'<div class="cashBad">QRIS belum tersedia.</div>'))+
      '<div class="cashTotal"><span>Total</span><b>'+rp(cashTotal())+'</b></div><button id="cashPayNow" class="cashBtn primary" style="width:100%" '+(!sel.length||(cashPay==='qris_cashier'&&!qris)?'disabled':'')+'>Bayar & Kirim ke Dapur</button><div id="cashMsg"></div>';
  }

  function ensureCartPanelId(){
    const aside=document.querySelector('#cashierRoot .cashLayout > aside.cashPanel');
    if(aside&&!aside.id)aside.id='cashCartPanel';
    return aside;
  }

  function renderCashCartFast(){
    cashRemember();
    const aside=ensureCartPanelId();
    if(!aside){cashRender();annotateCashMenu();ensureCartPanelId();return}
    aside.innerHTML=cashCartHtml();
    bindCartFast();
  }

  cashBind = function(){
    baseCashBind();
    annotateCashMenu();
    ensureCartPanelId();
  };

  cashRerender = function(fn){
    cashRemember();
    const beforeCat=cashCat;
    if(fn)fn();
    if(cashCat!==beforeCat){
      if(!filterCashCategoryFast()){
        const target=cashCat;
        cashCat='Semua';
        cashRender();
        cashCat=target;
        annotateCashMenu();
        filterCashCategoryFast();
      }
      return;
    }
    renderCashCartFast();
  };

  function updateCashAvailabilityDom(id,on){
    const b=document.querySelector('#cashierRoot [data-cash-add="'+CSS.escape(String(id))+'"]');
    if(!b)return;
    b.disabled=!on;
    b.closest('.cashItem')?.classList.toggle('off',!on);
  }

  stock = async function(id,on){
    id=String(id);
    if(stockPending.has(id))return;
    stockPending.add(id);
    const sm=(snap.menu||[]).find(x=>String(x.id)===id);
    const cm=(cashSnap?.menu||[]).find(x=>String(x.id)===id);
    const prevSnap=sm?.is_available,prevCash=cm?.is_available;
    if(sm)sm.is_available=on;
    if(cm)cm.is_available=on;
    fastMenuSig=menuSignature(snap);
    if(cashSnap)cashSig=cashSignature(cashSnap);
    renderStock();
    updateCashAvailabilityDom(id,on);
    try{
      await rpc('kds_set_availability',{p_id:id,p_available:on,p_note:on?'':'Habis'});
      toast(on?'Menu kembali tersedia':'Menu ditandai habis');
      void refresh(false);
      if(cashSnap)void cashLoad(false);
    }catch(error){
      if(sm)sm.is_available=prevSnap;
      if(cm)cm.is_available=prevCash;
      fastMenuSig=menuSignature(snap);
      if(cashSnap)cashSig=cashSignature(cashSnap);
      renderStock();
      updateCashAvailabilityDom(id,!!(prevCash??prevSnap));
      throw error;
    }finally{
      stockPending.delete(id);
    }
  };

  // Warm both data sources immediately so tab switching does not wait for a serial request chain.
  queueMicrotask(()=>{
    try{void refresh(false)}catch{}
    try{void cashLoad(false)}catch{}
  });
})();
