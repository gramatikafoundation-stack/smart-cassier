(() => {
  const style = document.createElement('style');
  style.textContent = `
    #cashierRoot .cashTop > div:first-child{display:none!important}
    #cashierRoot .cashTop{justify-content:flex-end!important;margin-bottom:8px!important}
    #cashierRoot .cashItem{position:relative}
    #cashierRoot .cashItemQty{
      position:absolute;top:14px;right:14px;z-index:4;
      min-width:30px;height:30px;padding:0 8px;border-radius:999px;
      display:grid;place-items:center;background:#264b3e;color:#fff;
      border:2px solid #fff;font-weight:950;font-size:13px;
      box-shadow:0 2px 8px rgba(0,0,0,.18)
    }
    #cashierRoot .cashItemQty[hidden]{display:none!important}
  `;
  document.head.appendChild(style);

  function syncMenuQuantities(){
    document.querySelectorAll('#cashierRoot [data-cash-add]').forEach(btn => {
      const id = String(btn.dataset.cashAdd || '');
      const qty = Math.max(0, Number(cart?.[id] || 0));
      const item = btn.closest('.cashItem');
      if (!item) return;

      let badge = item.querySelector('.cashItemQty');
      if (!badge) {
        badge = document.createElement('span');
        badge.className = 'cashItemQty';
        badge.setAttribute('aria-live','polite');
        item.appendChild(badge);
      }
      badge.textContent = String(qty);
      badge.hidden = qty < 1;

      btn.textContent = qty > 0 ? `+ Tambah · ${qty}` : '+ Tambah';
      btn.setAttribute('aria-label', qty > 0 ? `Tambah lagi, jumlah saat ini ${qty}` : 'Tambah menu');
    });
  }

  function tidyCashierHeader(){
    const top = document.querySelector('#cashierRoot .cashTop');
    if (!top) return;
    const intro = top.querySelector(':scope > div:first-child');
    if (intro) intro.hidden = true;
  }

  const baseCashRender = cashRender;
  cashRender = function(){
    baseCashRender();
    tidyCashierHeader();
    syncMenuQuantities();
  };

  const baseCashBind = cashBind;
  cashBind = function(){
    baseCashBind();
    tidyCashierHeader();
    syncMenuQuantities();
  };

  const baseCashRerender = cashRerender;
  cashRerender = function(fn){
    baseCashRerender(fn);
    queueMicrotask(() => {
      tidyCashierHeader();
      syncMenuQuantities();
    });
  };

  const observer = new MutationObserver(() => {
    tidyCashierHeader();
    syncMenuQuantities();
  });
  const root = document.getElementById('cashierRoot');
  if (root) observer.observe(root,{childList:true,subtree:true});

  queueMicrotask(() => {
    tidyCashierHeader();
    syncMenuQuantities();
  });
})();
