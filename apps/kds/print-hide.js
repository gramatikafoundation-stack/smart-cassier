(()=>{'use strict';

function completedOrder(id){
  return (snap.orders||[]).find(x=>String(x.id)===String(id)&&x.order_status==='completed');
}

function removeCompletedFromKds(id){
  snap.orders=(snap.orders||[]).filter(x=>String(x.id)!==String(id));
  try{lastSig=''}catch{}
  renderOrders();
}

function addDismissButtons(){
  document.querySelectorAll('.ticket').forEach(ticket=>{
    const print=ticket.querySelector('[data-print]');
    if(!print)return;
    const id=print.dataset.print;
    if(!completedOrder(id))return;
    const row=ticket.querySelector('.row');
    if(!row||row.querySelector('[data-kds-dismiss]'))return;
    const button=document.createElement('button');
    button.type='button';
    button.className='btn';
    button.dataset.kdsDismiss=id;
    button.textContent='Hilangkan';
    button.title='Hilangkan dari KDS tanpa menghapus riwayat transaksi';
    row.appendChild(button);
  });
}

const lanes=document.getElementById('lanes');
if(lanes){
  new MutationObserver(addDismissButtons).observe(lanes,{childList:true,subtree:true});
  queueMicrotask(addDismissButtons);
}

document.addEventListener('click',async event=>{
  const dismiss=event.target.closest?.('[data-kds-dismiss]');
  if(dismiss){
    event.preventDefault();
    event.stopImmediatePropagation();
    const id=dismiss.dataset.kdsDismiss;
    if(!completedOrder(id))return;
    dismiss.disabled=true;
    try{
      await rpc('kds_update_order',{p_id:id,p_action:'dismiss'});
      removeCompletedFromKds(id);
      toast('Pesanan dihilangkan dari KDS. Riwayat tetap tersimpan.');
    }catch(error){
      dismiss.disabled=false;
      toast(error?.message||'Pesanan gagal dihilangkan.');
    }
    return;
  }

  const button=event.target.closest?.('[data-print]');
  if(!button)return;

  event.preventDefault();
  event.stopImmediatePropagation();

  const id=button.dataset.print;
  const order=(snap.orders||[]).find(x=>String(x.id)===String(id));
  if(!order)return;

  const win=open('','_blank','width=420,height=700');
  if(!win){
    toast('Popup cetak diblokir browser.');
    return;
  }

  const its=Array.isArray(order.items)?order.items:[];
  const tenantName=String(window.__SDB_TENANT_CONFIG?.businessName||'Business').trim()||'Business';
  win.document.write('<!doctype html><style>@page{size:80mm auto;margin:4mm}body{font:13px monospace}h2{text-align:center}.x{border-top:1px dashed;margin:8px 0}</style><h2>'+esc(tenantName.toUpperCase())+'<br>KITCHEN TICKET</h2><div class=x></div><b>#'+esc(order.public_order_code)+'</b><br>'+esc(where(order))+'<div class=x></div>'+its.map(i=>'<p><b>'+Number(i.quantity)+'×</b> '+esc(i.name)+' — '+rp(Number(i.subtotal??(Number(i.price||0)*Number(i.quantity||0))))+'</p>').join('')+'<div class=x></div><b>'+esc(payLabel(order))+' · '+rp(order.total_amount)+'</b><script>onload=()=>print()<\/script>');
  win.document.close();

  button.disabled=true;
  try{
    await rpc('kds_update_order',{p_id:id,p_action:'print'});
    if(order.order_status==='completed'){
      removeCompletedFromKds(id);
      toast('Pesanan dicetak dan dihilangkan dari KDS. Riwayat tetap tersimpan.');
    }
  }catch(error){
    toast(error?.message||'Status cetak gagal disimpan.');
  }finally{
    if(button.isConnected)button.disabled=false;
  }
},true);
})();
