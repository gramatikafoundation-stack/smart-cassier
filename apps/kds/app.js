const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tenant = () => window.__SDB_TENANT_CONFIG || {businessName:'Business',locale:'id-ID',currency:'IDR',timezone:'Asia/Jakarta'};
const rp = n => new Intl.NumberFormat(tenant().locale||'id-ID',{style:'currency',currency:tenant().currency||'IDR',maximumFractionDigits:0}).format(Number(n)||0);
const fmt = v => v ? new Date(v).toLocaleString(tenant().locale||'id-ID',{timeZone:tenant().timezone||'Asia/Jakarta',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}).replace(',',' ·') : '—';
const today = v => v && new Date(v).toLocaleDateString('en-CA',{timeZone:tenant().timezone||'Asia/Jakarta'}) === new Date().toLocaleDateString('en-CA',{timeZone:tenant().timezone||'Asia/Jakarta'});

let snap={orders:[],menu:[]}, current='orders', syncBusy=false, syncPromise=null, lastSig='', timer=null;
const POLL_FALLBACK_ACTIVE_MS=4000,POLL_FALLBACK_CASHIER_MS=8000,POLL_FALLBACK_IDLE_MS=15000,POLL_FALLBACK_STOCK_MS=20000,POLL_REALTIME_MS=45000,POLL_REALTIME_CASHIER_MS=60000;
let cashSnap=null,cashBusy=false,cashPromise=null,cashSig='',cashCat='Semua',cashMode='dine-in',cashPay='cash',cart={};
const cashDraft={name:'',table:'',note:'',cash:'',qrisOk:false};

async function call(body){
  const response=await fetch('/api/kds',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const data=await response.json().catch(()=>({}));
  if(response.status===401){location.replace('/kds/login');throw new Error('invalid_session')}
  if(!response.ok||data?.ok===false)throw new Error(data?.error||'Permintaan KDS gagal.');
  return data;
}
const rpc=(name,args={})=>call({action:'rpc',rpc:name,args});
const proof=path=>call({action:'proof',path});
const cashier=payload=>call({action:'cashier',payload});

function toast(text){const e=$('toast');e.textContent=text;e.style.display='block';clearTimeout(e._t);e._t=setTimeout(()=>e.style.display='none',2200)}
function payLabel(o){return o.payment_method==='cash'?'CASH':o.payment_method==='qris_cashier'?'QRIS KASIR':'QRIS'}
function where(o){return o.service_mode==='dine-in'?'Meja '+(o.table_number||'—'):'Take Away'}
function items(o){const a=Array.isArray(o.items)?o.items:[];return '<div class="items">'+a.map(i=>'<div class="item"><span><b>'+Number(i.quantity||0)+'×</b> '+esc(i.name)+'</span><strong>'+rp(Number(i.subtotal??(Number(i.price||0)*Number(i.quantity||0))))+'</strong></div>').join('')+'</div>'}
function newTime(o){return o.verified_at||o.payment_submitted_at||o.kitchen_sent_at||o.created_at}
function processTime(o){return o.preparing_at||o.ready_at}
function completeTime(o){return o.completed_at}
function timeline(o){return '<div class="timeline"><span class="on">Pesanan Baru: '+fmt(newTime(o))+'</span><span class="'+(processTime(o)?'on':'')+'">Sedang Diproses: '+fmt(processTime(o))+'</span><span class="'+(completeTime(o)?'on':'')+'">Pesanan Selesai: '+fmt(completeTime(o))+'</span></div>'}

function card(o,stage){
  const review=o.payment_status==='submitted'&&o.order_status==='payment_review';
  let actions='';
  if(stage==='new') actions=review?'<button class="btn green" data-act="verify_start" data-id="'+o.id+'">Verifikasi & Proses</button><button class="btn red" data-act="reject_payment" data-id="'+o.id+'">Tolak</button>':'<button class="btn green" data-act="start" data-id="'+o.id+'">Proses Pesanan</button>';
  else if(stage==='processing') actions='<button class="btn green" data-act="finish" data-id="'+o.id+'">Selesaikan Pesanan</button>';
  const proofBtn=o.payment_proof_url?'<button class="btn" data-proof="'+esc(o.payment_proof_url)+'">Lihat Bukti</button>':'';
  const printBtn=!review?'<button class="btn" data-print="'+o.id+'">Cetak</button>':'';
  return '<article class="ticket '+(review?'review':'')+'"><div class="th"><div><div class="code">#'+esc(o.public_order_code||o.id)+'</div><div class="name">'+esc(o.customer_name||'Pelanggan')+' · '+esc(where(o))+'</div></div><span class="badge">'+(review?'MENUNGGU BAYAR':esc(payLabel(o)))+'</span></div>'+items(o)+(o.customer_note?'<div class="note"><b>Keterangan:</b> '+esc(o.customer_note)+'</div>':'')+'<div class="meta">Total '+rp(o.total_amount||0)+'</div><div class="statusTime"><b>Waktu status:</b> '+fmt(stage==='new'?newTime(o):stage==='processing'?processTime(o):completeTime(o))+'</div>'+timeline(o)+'<div class="row">'+actions+proofBtn+printBtn+'</div></article>';
}
function lane(title,desc,list,stage){return '<section class="lane"><div class="lh"><div><h2>'+title+'</h2><p>'+desc+'</p></div><span class="count">'+list.length+' tiket</span></div><div class="cards">'+(list.length?list.map(o=>card(o,stage)).join(''):'<div class="empty">Belum ada pesanan.</div>')+'</div></section>'}
function classify(){const o=snap.orders||[];return{n:o.filter(x=>(x.payment_status==='submitted'&&x.order_status==='payment_review')||(x.payment_status==='verified'&&x.order_status==='confirmed')),p:o.filter(x=>x.order_status==='preparing'||x.order_status==='ready'),d:o.filter(x=>x.order_status==='completed'&&today(x.completed_at||x.updated_at))}}
function hasActiveOrders(){const {n,p}=classify();return n.length>0||p.length>0}
function pollDelay(){const rt=window.__ROHMAT_KDS_REALTIME__;if(rt?.connected)return current==='cashier'?Math.max(POLL_REALTIME_CASHIER_MS,Number(rt.safetyPollMs||0)):Math.max(POLL_REALTIME_MS,Number(rt.safetyPollMs||0));if(current==='cashier')return POLL_FALLBACK_CASHIER_MS;if(current==='stock')return POLL_FALLBACK_STOCK_MS;return hasActiveOrders()?POLL_FALLBACK_ACTIVE_MS:POLL_FALLBACK_IDLE_MS}
function stopPolling(){if(timer){clearTimeout(timer);timer=null}}
function schedulePolling(delay=pollDelay()){stopPolling();if(document.hidden)return;timer=setTimeout(async()=>{if(document.hidden)return;try{if(current==='cashier')await cashLoad(false);else await refresh(false)}finally{schedulePolling()}},delay)}
async function syncCurrent(manual=false){if(current==='cashier')return cashLoad(manual);return refresh(manual)}
function renderOrders(){const {n,p,d}=classify();$('sNew').textContent=n.length;$('sProc').textContent=p.length;$('sDone').textContent=d.length;$('lanes').innerHTML=lane('Pesanan Baru','Pesanan masuk dan siap ditangani dapur',n,'new')+lane('Sedang Diproses','Semua pesanan yang sedang dikerjakan dapur',p,'processing')+lane('Pesanan Selesai','Pesanan yang selesai hari ini',d,'done')}
function renderStock(){const q=($('search').value||'').toLowerCase(),f=$('filter').value,m=snap.menu||[];$('stockgrid').innerHTML=m.filter(x=>(!q||String(x.name).toLowerCase().includes(q)||String(x.category).toLowerCase().includes(q))&&(f==='all'||(f==='on'&&x.is_available)||(f==='off'&&!x.is_available))).map(x=>'<article class="stock '+(x.is_available?'':'off')+'"><div><b>'+esc(x.name)+'</b><div class="muted">'+esc(x.category)+' · '+rp(x.price)+'</div></div><button class="sw '+(x.is_available?'':'off')+'" data-stock="'+esc(x.id)+'" data-next="'+(x.is_available?'0':'1')+'">'+(x.is_available?'Tersedia':'Habis')+'</button></article>').join('')||'<div class="empty">Menu tidak ditemukan.</div>'}

async function refresh(manual=false,afterBusy=false){
  if(syncPromise){if(!afterBusy)return syncPromise;try{await syncPromise}catch{}}
  syncBusy=true;const b=$('refresh');
  if(manual){b.disabled=true;b.textContent='↻ Memperbarui…'}
  const task=(async()=>{try{
    const d=await rpc('kds_snapshot');
    const sig=JSON.stringify([(d.orders||[]).map(o=>[o.id,o.order_status,o.payment_status,o.updated_at,o.preparing_at,o.ready_at,o.completed_at]),(d.menu||[]).map(m=>[m.id,m.is_available])]);
    snap=d;if(sig!==lastSig){lastSig=sig;renderOrders();renderStock()}
    document.dispatchEvent(new CustomEvent('rohmat:kds-snapshot',{detail:{ok:true,at:Date.now(),surface:'orders'}}));
    if(!window.__ROHMAT_KDS_REALTIME__)$('sync').textContent='● Sinkron · '+new Date().toLocaleTimeString('id-ID',{hour:'2-digit',minute:'2-digit'});
  }catch(error){document.dispatchEvent(new CustomEvent('rohmat:kds-snapshot',{detail:{ok:false,at:Date.now(),surface:'orders'}}));$('sync').dataset.syncState='error';$('sync').textContent='● Gangguan';if(manual)toast(error.message||'Gagal memperbarui')}})();
  syncPromise=task;
  try{return await task}finally{if(syncPromise===task)syncPromise=null;syncBusy=false;if(manual){b.disabled=false;b.textContent='↻ Perbarui'}}
}
async function run(id,command){return rpc('kds_update_order',{p_id:id,p_action:command})}
async function act(id,action){stopPolling();try{if(action==='verify_start')await run(id,'verify_start');else if(action==='finish')await run(id,'finish');else await run(id,action);toast(action==='start'||action==='verify_start'?'Pesanan masuk ke Sedang Diproses':action==='finish'?'Pesanan selesai':'Status diperbarui');await refresh(false,true)}finally{schedulePolling()}}
async function stock(id,on){stopPolling();try{await rpc('kds_set_availability',{p_id:id,p_available:on,p_note:on?'':'Habis'});toast(on?'Menu kembali tersedia':'Menu ditandai habis');await refresh(false,true)}finally{schedulePolling()}}
async function showProof(path){try{const d=await proof(path);$('proofImg').src=d.url;$('proofModal').hidden=false}catch(error){toast(error.message||'Bukti gagal dibuka')}}
function printOne(id){const o=(snap.orders||[]).find(x=>x.id===id);if(!o)return;const w=open('','_blank','width=420,height=700'),its=Array.isArray(o.items)?o.items:[];w.document.write('<!doctype html><style>@page{size:80mm auto;margin:4mm}body{font:13px monospace}h2{text-align:center}.x{border-top:1px dashed;margin:8px 0}</style><h2>'+esc(String(tenant().businessName||'').toUpperCase())+'<br>KITCHEN TICKET</h2><div class=x></div><b>#'+esc(o.public_order_code)+'</b><br>'+esc(where(o))+'<div class=x></div>'+its.map(i=>'<p><b>'+Number(i.quantity)+'×</b> '+esc(i.name)+' — '+rp(Number(i.subtotal??(Number(i.price||0)*Number(i.quantity||0))))+'</p>').join('')+'<div class=x></div><b>'+esc(payLabel(o))+' · '+rp(o.total_amount)+'</b><script>onload=()=>print()<\/script>');w.document.close();rpc('kds_update_order',{p_id:id,p_action:'print'}).catch(()=>{})}

function cashRemember(){if($('cashName'))cashDraft.name=$('cashName').value;if($('cashTable'))cashDraft.table=$('cashTable').value;if($('cashNote'))cashDraft.note=$('cashNote').value;if($('cashMoney'))cashDraft.cash=$('cashMoney').value;if($('cashQrisOk'))cashDraft.qrisOk=$('cashQrisOk').checked}
function cashSelected(){const map=new Map((cashSnap?.menu||[]).map(x=>[String(x.id),x]));return Object.entries(cart).map(([id,q])=>({m:map.get(id),q:Number(q)})).filter(x=>x.m&&x.q>0)}
function cashTotal(){return cashSelected().reduce((a,x)=>a+Number(x.m.price||0)*x.q,0)}
function cashRerender(fn){cashRemember();if(fn)fn();cashRender()}
function cashRender(){
  if(!cashSnap)return;const root=$('cashierRoot'),cats=['Semua',...new Set((cashSnap.menu||[]).map(x=>x.category).filter(Boolean))],list=(cashSnap.menu||[]).filter(x=>cashCat==='Semua'||x.category===cashCat),sel=cashSelected(),qris=!!(cashSnap.settings?.qris_enabled&&cashSnap.settings?.qris_image_url);
  root.innerHTML='<div class="cashTop"><div><div class="cashEy">KDS · SMART CASHIER</div><h2>Smart Cashier</h2><div class="muted">Tampilan dan alur transaksi sama dengan Kasir pada Situs Admin.</div></div><button id="cashReload" class="cashBtn">↻ Perbarui</button></div><div class="cashLayout"><section class="cashPanel"><div class="cashCats">'+cats.map(c=>'<button class="cashBtn '+(cashCat===c?'on':'')+'" data-cash-cat="'+esc(c)+'">'+esc(c)+'</button>').join('')+'</div><div class="cashMenu">'+list.map(m=>'<article class="cashItem '+(m.is_available===false?'off':'')+'">'+(m.image_url?'<img loading="lazy" src="'+esc(m.image_url)+'" alt="'+esc(m.name)+'">':'')+'<b>'+esc(m.name)+'</b><strong>'+rp(m.price)+'</strong><button class="cashBtn primary" data-cash-add="'+esc(m.id)+'" '+(m.is_available===false?'disabled':'')+'>+ Tambah</button></article>').join('')+'</div></section><aside class="cashPanel">'+(sel.length?sel.map(x=>'<div class="cashLine"><div><b>'+esc(x.m.name)+'</b><div class="muted">'+rp(x.m.price)+' × '+x.q+'</div></div><div class="cashQty"><button class="cashBtn" data-cash-minus="'+esc(x.m.id)+'">−</button><b>'+x.q+'</b><button class="cashBtn" data-cash-plus="'+esc(x.m.id)+'">+</button></div></div>').join(''):'<div class="cashEmpty">Belum ada menu dipilih.</div>')+'<div class="cashField"><label>Nama Pemesan</label><input id="cashName" value="'+esc(cashDraft.name)+'"></div><div class="cashTwo"><button class="cashBtn '+(cashMode==='dine-in'?'on':'')+'" data-cash-mode="dine-in">Dine In</button><button class="cashBtn '+(cashMode==='take-away'?'on':'')+'" data-cash-mode="take-away">Take Away</button></div>'+(cashMode==='dine-in'?'<div class="cashField"><label>Nomor Meja</label><select id="cashTable"><option value="">Pilih meja</option>'+Array.from({length:20},(_,i)=>'<option value="'+(i+1)+'" '+(String(i+1)===String(cashDraft.table)?'selected':'')+'>Meja '+String(i+1).padStart(2,'0')+'</option>').join('')+'</select></div>':'')+'<div class="cashField"><label>Keterangan</label><textarea id="cashNote" rows="2">'+esc(cashDraft.note)+'</textarea></div><div class="cashTwo"><button class="cashBtn '+(cashPay==='cash'?'on':'')+'" data-cash-pay="cash">Cash</button><button class="cashBtn '+(cashPay==='qris_cashier'?'on':'')+'" data-cash-pay="qris_cashier">QRIS</button></div>'+(cashPay==='cash'?'<div class="cashField"><label>Uang diterima</label><input id="cashMoney" type="number" min="0" step="1000" value="'+esc(cashDraft.cash)+'"><div class="muted">Kembalian: <b id="cashChange">'+rp(Math.max(0,Number(cashDraft.cash||0)-cashTotal()))+'</b></div></div>':(qris?'<div class="cashQris"><img src="'+esc(cashSnap.settings.qris_image_url)+'" alt="QRIS"><label><input id="cashQrisOk" type="checkbox" '+(cashDraft.qrisOk?'checked':'')+'> Pembayaran QRIS sudah diterima kasir.</label></div>':'<div class="cashBad">QRIS belum tersedia.</div>'))+'<div class="cashTotal"><span>Total</span><b>'+rp(cashTotal())+'</b></div><button id="cashPayNow" class="cashBtn primary" style="width:100%" '+(!sel.length||(cashPay==='qris_cashier'&&!qris)?'disabled':'')+'>Bayar & Kirim ke Dapur</button><div id="cashMsg"></div></aside></div>';
  cashBind();
}
function cashBind(){
  $('cashReload')?.addEventListener('click',()=>cashLoad(true));
  document.querySelectorAll('[data-cash-cat]').forEach(b=>b.onclick=()=>cashRerender(()=>cashCat=b.dataset.cashCat));
  document.querySelectorAll('[data-cash-add]').forEach(b=>b.onclick=()=>cashRerender(()=>cart[b.dataset.cashAdd]=(cart[b.dataset.cashAdd]||0)+1));
  document.querySelectorAll('[data-cash-plus]').forEach(b=>b.onclick=()=>cashRerender(()=>cart[b.dataset.cashPlus]=(cart[b.dataset.cashPlus]||0)+1));
  document.querySelectorAll('[data-cash-minus]').forEach(b=>b.onclick=()=>cashRerender(()=>{const id=b.dataset.cashMinus,n=(cart[id]||0)-1;if(n>0)cart[id]=n;else delete cart[id]}));
  document.querySelectorAll('[data-cash-mode]').forEach(b=>b.onclick=()=>cashRerender(()=>{cashMode=b.dataset.cashMode;if(cashMode==='take-away')cashDraft.table=''}));
  document.querySelectorAll('[data-cash-pay]').forEach(b=>b.onclick=()=>cashRerender(()=>{cashPay=b.dataset.cashPay;if(cashPay==='cash')cashDraft.qrisOk=false}));
  $('cashName')?.addEventListener('input',e=>cashDraft.name=e.target.value);$('cashTable')?.addEventListener('change',e=>cashDraft.table=e.target.value);$('cashNote')?.addEventListener('input',e=>cashDraft.note=e.target.value);$('cashQrisOk')?.addEventListener('change',e=>cashDraft.qrisOk=e.target.checked);$('cashMoney')?.addEventListener('input',e=>{cashDraft.cash=e.target.value;if($('cashChange'))$('cashChange').textContent=rp(Math.max(0,Number(cashDraft.cash||0)-cashTotal()))});$('cashPayNow')?.addEventListener('click',cashCreate);
}
function cashSignature(d){return JSON.stringify([(d?.menu||[]).map(m=>[m.id,m.name,m.category,m.price,m.is_available,m.image_url]),d?.settings?.qris_enabled,d?.settings?.qris_image_url])}
async function cashLoad(manual=false,afterBusy=false){
  if(cashPromise){if(!afterBusy)return cashPromise;try{await cashPromise}catch{}}
  cashBusy=true;
  if(!cashSnap)$('cashierRoot').innerHTML='<div class="cashEmpty">Memuat Smart Cashier…</div>';
  const task=(async()=>{try{
    const next=await cashier({action:'snapshot'}),nextSig=cashSignature(next),changed=nextSig!==cashSig;
    cashSnap=next;
    if(changed||manual||!$('cashierRoot').dataset.ready){cashSig=nextSig;cashRender();$('cashierRoot').dataset.ready='1'}
    document.dispatchEvent(new CustomEvent('rohmat:kds-snapshot',{detail:{ok:true,at:Date.now(),surface:'cashier'}}));
  }catch(error){
    document.dispatchEvent(new CustomEvent('rohmat:kds-snapshot',{detail:{ok:false,at:Date.now(),surface:'cashier'}}));
    if(!cashSnap)$('cashierRoot').innerHTML='<div class="cashBad"><b>Smart Cashier gagal dimuat.</b><br>'+esc(error.message||error)+'</div>';
    if(manual)toast(error.message)
  }})();
  cashPromise=task;
  try{return await task}finally{if(cashPromise===task)cashPromise=null;cashBusy=false}
}
async function cashCreate(){cashRemember();const msg=$('cashMsg'),btn=$('cashPayNow'),sel=cashSelected(),table=cashMode==='dine-in'?Number(cashDraft.table||0):null,cash=cashPay==='cash'?Number(cashDraft.cash||0):null;if(!sel.length)return;if(cashMode==='dine-in'&&!(table>=1&&table<=20)){msg.innerHTML='<div class="cashBad">Pilih nomor meja terlebih dahulu.</div>';return}if(cashPay==='cash'&&cash<cashTotal()){msg.innerHTML='<div class="cashBad">Uang diterima masih kurang.</div>';return}if(cashPay==='qris_cashier'&&!cashDraft.qrisOk){msg.innerHTML='<div class="cashBad">Konfirmasi pembayaran QRIS terlebih dahulu.</div>';return}btn.disabled=true;btn.textContent='Memproses…';try{const j=await cashier({action:'create_order',source:'cashier_kds',customerName:cashDraft.name,serviceMode:cashMode,tableNumber:table,items:sel.map(x=>({menuId:x.m.id,quantity:x.q})),paymentMethod:cashPay,cashReceived:cash,note:cashDraft.note});msg.innerHTML='<div class="cashOk">Pesanan '+esc(j.order?.public_order_code||'')+' berhasil dikirim ke dapur.</div>';cart={};Object.assign(cashDraft,{name:'',table:'',note:'',cash:'',qrisOk:false});cashRender();stopPolling();await Promise.all([cashLoad(false,true),refresh(false,true)]);schedulePolling();toast('Pesanan berhasil dibuat dari Smart Cashier')}catch(error){msg.innerHTML='<div class="cashBad">'+esc(error.message||error)+'</div>';btn.disabled=false;btn.textContent='Bayar & Kirim ke Dapur'}}

function syncTabA11y(){
  document.querySelectorAll('.tab').forEach(x=>{const on=x.dataset.tab===current;x.classList.toggle('on',on);x.setAttribute('aria-selected',on?'true':'false');x.tabIndex=on?0:-1})
}
function switchTab(tab){
  if(current===tab)return;
  current=tab;
  syncTabA11y();
  document.dispatchEvent(new Event('rohmat:kds-page'));
  $('ordersTab').hidden=tab!=='orders';$('cashierTab').hidden=tab!=='cashier';$('stockTab').hidden=tab!=='stock';
  stopPolling();
  syncCurrent(false).catch(()=>{}).finally(()=>schedulePolling());
}
async function logout(){try{await call({action:'logout'})}catch{}location.replace('/kds/login')}

async function boot(){
  try{
    await Promise.all([call({action:'session'}),window.__SDB_TENANT_CONFIG_READY||Promise.resolve()]);
    $('app').hidden=false;syncTabA11y();await refresh(false);
    document.dispatchEvent(new CustomEvent('rohmat:kds-session-ready'));
    schedulePolling();
  }catch{location.replace('/kds/login')}
}

document.addEventListener('click',async e=>{const tab=e.target.closest('[data-tab]');if(tab)return switchTab(tab.dataset.tab);const a=e.target.closest('[data-act]');if(a){a.disabled=true;try{await act(a.dataset.id,a.dataset.act)}catch(error){toast(error.message||'Aksi gagal')}finally{a.disabled=false}return}const pr=e.target.closest('[data-proof]');if(pr)return showProof(pr.dataset.proof);const pi=e.target.closest('[data-print]');if(pi)return printOne(pi.dataset.print);const st=e.target.closest('[data-stock]');if(st){st.disabled=true;try{await stock(st.dataset.stock,st.dataset.next==='1')}catch(error){toast(error.message||'Gagal')}finally{st.disabled=false}}});
document.addEventListener('input',e=>{if(e.target.id==='search')renderStock()});document.addEventListener('change',e=>{if(e.target.id==='filter')renderStock()});
$('refresh').onclick=async()=>{await syncCurrent(true);schedulePolling()};$('logout').onclick=logout;$('closeProof').onclick=()=>{$('proofModal').hidden=true;$('proofImg').src=''};
document.addEventListener('visibilitychange',()=>{if(document.hidden)stopPolling();else syncCurrent(false).catch(()=>{}).finally(()=>schedulePolling())});
window.addEventListener('online',()=>syncCurrent(false).catch(()=>{}).finally(()=>schedulePolling()));
boot();