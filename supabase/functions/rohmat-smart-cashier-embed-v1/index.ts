import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const SVG=String.raw`<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 1180 1500" preserveAspectRatio="xMinYMin meet">
<rect width="1180" height="1500" fill="#f6f1e7"/>
<foreignObject x="0" y="0" width="1180" height="1500">
<div xmlns="http://www.w3.org/1999/xhtml" id="app" style="min-height:1500px;background:#f6f1e7;color:#24372f;font-family:system-ui,-apple-system,Segoe UI,sans-serif;padding:18px;box-sizing:border-box">
  <style>
    *{box-sizing:border-box}button,input,select,textarea{font:inherit}.top{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:14px}.ey{font-size:12px;font-weight:900;letter-spacing:.12em;color:#7c5039}.top h2{margin:3px 0;font-size:28px}.muted{color:#778179}.btn{border:1px solid #cfc7b9;border-radius:10px;background:#fff;color:#24372f;padding:9px 12px;font-weight:800;cursor:pointer}.btn.on,.btn.primary{background:#2f5d4c;color:#fff;border-color:#2f5d4c}.btn:disabled{opacity:.45;cursor:not-allowed}.layout{display:grid;grid-template-columns:minmax(0,1.45fr) minmax(340px,.7fr);gap:14px}.panel{background:#fff;border:1px solid #d9d1c3;border-radius:16px;padding:13px}.cats{display:flex;gap:7px;overflow:auto;margin-bottom:10px}.cat{white-space:nowrap;border-radius:999px}.menu{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:9px}.item{border:1px solid #ded6ca;border-radius:12px;padding:0;background:#fff;display:grid;gap:0;overflow:hidden}.item.off{opacity:.5}.media{position:relative;width:100%;aspect-ratio:4/3;overflow:hidden;isolation:isolate;background:#eee7da;border-radius:12px 12px 0 0}.media:after{content:"";position:absolute;inset:0;z-index:1;background:linear-gradient(180deg,rgba(255,253,248,.09),rgba(255,253,248,.18));pointer-events:none}.mediaBg{position:absolute;inset:-9px;z-index:0;display:block;width:calc(100% + 18px);height:calc(100% + 18px);max-width:none;max-height:none;object-fit:cover;object-position:center;border-radius:0;filter:blur(10px) saturate(.94) brightness(.92);transform:scale(1.08);opacity:.82;pointer-events:none}.mediaFg{position:relative;z-index:2;display:block;width:100%;height:100%;max-width:100%;max-height:100%;object-fit:contain;object-position:center;padding:3px;margin:0;border:0;border-radius:10px;background:transparent;filter:none;transform:none}.item h4{margin:9px 10px 0;font-size:14px;line-height:1.25}.price{font-weight:900;color:#7c5039;margin:7px 10px 10px}.item>.btn.primary{margin:0 10px 10px;justify-self:end;min-height:38px}.cart{position:sticky;top:8px;align-self:start}.line{display:grid;grid-template-columns:1fr auto;gap:8px;padding:8px 0;border-bottom:1px dashed #ddd3c4}.qty{display:flex;align-items:center;gap:5px}.qty button{width:31px;height:31px;padding:0}.field{display:grid;gap:5px;margin-top:9px}.field label{font-size:12px;font-weight:800;color:#69746c}.field input,.field select,.field textarea{width:100%;min-height:40px;border:1px solid #d0c8bb;border-radius:9px;padding:8px 10px;background:#fff;color:#24372f}.two{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-top:9px}.total{display:flex;justify-content:space-between;font-size:20px;padding:12px 0}.notice{padding:11px;border-radius:10px;margin-top:9px}.ok{background:#e6f2ec;color:#285f49}.bad{background:#fae8e5;color:#91483e}.empty{padding:18px;text-align:center;color:#7b847d;border:1px dashed #d3cbbc;border-radius:10px}.qris{text-align:center;padding:8px;border:1px solid #ddd3c4;border-radius:10px;margin-top:9px}.qris img{max-width:220px;max-height:245px;object-fit:contain}.sync{font-size:12px;color:#2f6f56;font-weight:800}@media(max-width:850px){.layout{grid-template-columns:1fr}.cart{position:static}.menu{grid-template-columns:repeat(2,1fr)}}
  </style>
  <div class="top"><div><div class="ey">__SDB_BUSINESS_UPPER__</div><h2>Smart Cashier</h2><div id="sync" class="sync">Menghubungkan ke KDS…</div></div><button id="reload" class="btn">↻ Perbarui</button></div>
  <div id="root"><div class="empty">Menunggu sesi KDS…</div></div>
</div>
</foreignObject>
<script type="application/ecmascript"><![CDATA[
(function(){'use strict';
const API='__SDB_SUPABASE_ORIGIN__/functions/v1/rohmat-smart-cashier-v1',TENANT='__SDB_TENANT_ID__';
let token='',source='cashier_kds',snap=null,cat='Semua',mode='dine-in',pay='cash',cart={},busy=false;
const draft={name:'',table:'',note:'',cash:'',qrisOk:false};
const root=()=>document.getElementById('root'),sync=()=>document.getElementById('sync');
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const rp=n=>'Rp'+new Intl.NumberFormat('id-ID',{maximumFractionDigits:0}).format(Number(n)||0);
function remember(){const g=id=>document.getElementById(id);if(g('nm'))draft.name=g('nm').value;if(g('tb'))draft.table=g('tb').value;if(g('nt'))draft.note=g('nt').value;if(g('cs'))draft.cash=g('cs').value;if(g('qo'))draft.qrisOk=g('qo').checked}
function selected(){const map=new Map((snap?.menu||[]).map(x=>[String(x.id),x]));return Object.entries(cart).map(([id,q])=>({m:map.get(id),q:Number(q)})).filter(x=>x.m&&x.q>0)}
function total(){return selected().reduce((a,x)=>a+Number(x.m.price||0)*x.q,0)}
async function call(body){if(!token)throw Error('Sesi KDS belum diterima.');const r=await fetch(API+'?t='+Date.now(),{method:'POST',cache:'no-store',headers:{'content-type':'application/json','x-kds-session':token,'x-sdb-tenant-id':TENANT,'cache-control':'no-cache'},body:JSON.stringify(body)});const j=await r.json().catch(()=>({}));if(!r.ok||!j.ok){const map={invalid_session:'Sesi KDS berakhir. Silakan masuk kembali.',invalid_table:'Pilih nomor meja yang benar.',menu_unavailable:'Salah satu menu sedang tidak tersedia.',insufficient_cash:'Uang diterima masih kurang.',empty_cart:'Keranjang masih kosong.'};throw Error(map[j.error]||j.detail||j.error||'Smart Cashier gagal diproses')}return j}
function render(){if(!snap)return;remember();const cats=['Semua',...new Set((snap.menu||[]).map(x=>x.category).filter(Boolean))],list=(snap.menu||[]).filter(x=>cat==='Semua'||x.category===cat),sel=selected(),qris=!!(snap.settings?.qris_enabled&&snap.settings?.qris_image_url);root().innerHTML='<div class="layout"><section class="panel"><div class="cats">'+cats.map(c=>'<button class="btn cat '+(c===cat?'on':'')+'" data-cat="'+esc(c)+'">'+esc(c)+'</button>').join('')+'</div><div class="menu">'+list.map(m=>'<article class="item '+(m.is_available===false?'off':'')+'">'+(m.image_url?'<div class="media"><img class="mediaBg" src="'+esc(m.image_url)+'" alt="" aria-hidden="true"/><img class="mediaFg" src="'+esc(m.image_url)+'" alt="'+esc(m.name)+'"/></div>':'')+'<h4>'+esc(m.name)+'</h4><div class="price">'+rp(m.price)+'</div><button class="btn primary" data-add="'+esc(m.id)+'" '+(m.is_available===false?'disabled':'')+'>+ Tambah</button></article>').join('')+'</div></section><aside class="panel cart"><div class="ey">PESANAN</div><h3 style="margin:3px 0 8px">Keranjang Kasir</h3>'+(sel.length?sel.map(x=>'<div class="line"><div><b>'+esc(x.m.name)+'</b><div class="muted">'+rp(x.m.price)+' × '+x.q+'</div></div><div class="qty"><button class="btn" data-minus="'+esc(x.m.id)+'">−</button><b>'+x.q+'</b><button class="btn" data-plus="'+esc(x.m.id)+'">+</button></div></div>').join(''):'<div class="empty">Belum ada menu dipilih.</div>')+'<div class="field"><label>Nama Pemesan</label><input id="nm" value="'+esc(draft.name)+'" placeholder="Masukkan nama pemesan"/></div><div class="two"><button class="btn '+(mode==='dine-in'?'on':'')+'" data-mode="dine-in">Dine In</button><button class="btn '+(mode==='take-away'?'on':'')+'" data-mode="take-away">Take Away</button></div>'+(mode==='dine-in'?'<div class="field"><label>Nomor Meja</label><select id="tb"><option value="">Pilih meja</option>'+Array.from({length:20},(_,i)=>'<option value="'+(i+1)+'" '+(String(i+1)===String(draft.table)?'selected':'')+'>Meja '+String(i+1).padStart(2,'0')+'</option>').join('')+'</select></div>':'')+'<div class="field"><label>Keterangan</label><textarea id="nt" rows="2">'+esc(draft.note)+'</textarea></div><div class="two"><button class="btn '+(pay==='cash'?'on':'')+'" data-pay="cash">Cash</button><button class="btn '+(pay==='qris_cashier'?'on':'')+'" data-pay="qris_cashier">QRIS</button></div>'+(pay==='cash'?'<div class="field"><label>Uang diterima</label><input id="cs" type="number" min="0" step="1000" value="'+esc(draft.cash)+'"/><div class="muted">Kembalian: <b id="chg">'+rp(Math.max(0,Number(draft.cash||0)-total()))+'</b></div></div>':(qris?'<div class="qris"><img src="'+esc(snap.settings.qris_image_url)+'" alt="QRIS"/><div><label><input id="qo" type="checkbox" '+(draft.qrisOk?'checked':'')+'/> Pembayaran QRIS sudah diterima kasir.</label></div></div>':'<div class="notice bad">QRIS belum tersedia.</div>'))+'<div class="total"><span>Total</span><b>'+rp(total())+'</b></div><button id="paynow" class="btn primary" style="width:100%" '+(!sel.length||(pay==='qris_cashier'&&!qris)?'disabled':'')+'>Bayar &amp; Kirim ke Dapur</button><div id="msg"></div></aside></div>';bind();try{parent.postMessage({type:'rohmat-cashier-height',height:1450},'*')}catch{}}
function rerender(fn){remember();fn();render()}
function bind(){document.querySelectorAll('[data-cat]').forEach(b=>b.onclick=()=>rerender(()=>cat=b.dataset.cat));document.querySelectorAll('[data-add]').forEach(b=>b.onclick=()=>rerender(()=>cart[b.dataset.add]=(cart[b.dataset.add]||0)+1));document.querySelectorAll('[data-plus]').forEach(b=>b.onclick=()=>rerender(()=>cart[b.dataset.plus]=(cart[b.dataset.plus]||0)+1));document.querySelectorAll('[data-minus]').forEach(b=>b.onclick=()=>rerender(()=>{const id=b.dataset.minus,n=(cart[id]||0)-1;if(n>0)cart[id]=n;else delete cart[id]}));document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>rerender(()=>{mode=b.dataset.mode;if(mode==='take-away')draft.table=''}));document.querySelectorAll('[data-pay]').forEach(b=>b.onclick=()=>rerender(()=>{pay=b.dataset.pay;if(pay==='cash')draft.qrisOk=false}));document.getElementById('nm')?.addEventListener('input',e=>draft.name=e.target.value);document.getElementById('tb')?.addEventListener('change',e=>draft.table=e.target.value);document.getElementById('nt')?.addEventListener('input',e=>draft.note=e.target.value);document.getElementById('qo')?.addEventListener('change',e=>draft.qrisOk=e.target.checked);document.getElementById('cs')?.addEventListener('input',e=>{draft.cash=e.target.value;const z=document.getElementById('chg');if(z)z.textContent=rp(Math.max(0,Number(draft.cash||0)-total()))});document.getElementById('paynow')?.addEventListener('click',create)}
async function load(){if(!token||busy)return;busy=true;sync().textContent='● Memperbarui…';try{snap=await call({action:'snapshot',nonce:Date.now()});sync().textContent='● Live · '+new Date().toLocaleTimeString('id-ID');render()}catch(e){sync().textContent='● Gangguan';root().innerHTML='<div class="notice bad"><b>Smart Cashier gagal dimuat.</b><br/>'+esc(e.message||e)+'</div>'}finally{busy=false}}
async function create(){remember();const msg=document.getElementById('msg'),btn=document.getElementById('paynow'),sel=selected(),table=mode==='dine-in'?Number(draft.table||0):null,cash=pay==='cash'?Number(draft.cash||0):null;if(mode==='dine-in'&&!(table>=1&&table<=20)){msg.innerHTML='<div class="notice bad">Pilih nomor meja terlebih dahulu.</div>';return}if(pay==='cash'&&cash<total()){msg.innerHTML='<div class="notice bad">Uang diterima masih kurang.</div>';return}if(pay==='qris_cashier'&&!draft.qrisOk){msg.innerHTML='<div class="notice bad">Konfirmasi pembayaran QRIS terlebih dahulu.</div>';return}btn.disabled=true;btn.textContent='Memproses…';try{const j=await call({action:'create_order',source:source,customerName:draft.name,serviceMode:mode,tableNumber:table,items:sel.map(x=>({menuId:x.m.id,quantity:x.q})),paymentMethod:pay,cashReceived:cash,note:draft.note});cart={};draft.name='';draft.table='';draft.note='';draft.cash='';draft.qrisOk=false;await load();try{parent.postMessage({type:'rohmat-cashier-order-created',order:j.order},'*')}catch{}}catch(e){msg.innerHTML='<div class="notice bad">'+esc(e.message||e)+'</div>';btn.disabled=false;btn.textContent='Bayar & Kirim ke Dapur'}}
window.addEventListener('message',e=>{const d=e.data||{};if(d.type==='rohmat-cashier-init'&&d.token){token=String(d.token);source=String(d.source||'cashier_kds');load()}});
document.getElementById('reload').onclick=load;
try{parent.postMessage({type:'rohmat-cashier-ready'},'*')}catch{}
setTimeout(()=>{if(!token){root().innerHTML='<div class="empty">Menunggu otorisasi dari KDS…</div>';try{parent.postMessage({type:'rohmat-cashier-ready'},'*')}catch{}}},700);
})();
]]></script>
</svg>`;

const SUPABASE_URL=Deno.env.get('SUPABASE_URL')||'';
const SERVICE_ROLE=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type TenantCtx={tenant_id:string;business_name:string;kds_origin:string;enabled?:boolean};
async function tenantContext(req:Request):Promise<TenantCtx>{
  if(!SUPABASE_URL||!SERVICE_ROLE)throw new Error('platform_configuration_incomplete');
  const url=new URL(req.url);
  const tenantId=String(url.searchParams.get('tenant')||req.headers.get('x-sdb-tenant-id')||'').trim();
  if(!UUID_RE.test(tenantId))throw new Error('tenant_required');
  const sb=createClient(SUPABASE_URL,SERVICE_ROLE,{auth:{persistSession:false,autoRefreshToken:false}});
  const r=await sb.rpc('master_prototype_tenant_context',{p_tenant_id:tenantId});
  if(r.error||!r.data?.ok||r.data?.enabled===false)throw new Error('tenant_unavailable');
  return r.data as TenantCtx;
}
function renderedSvg(ctx:TenantCtx){
  const origin=new URL(SUPABASE_URL).origin;
  return SVG
    .replaceAll('__SDB_SUPABASE_ORIGIN__',origin)
    .replaceAll('__SDB_BUSINESS_UPPER__',String(ctx.business_name||'Merchant').toUpperCase())
    .replaceAll('__SDB_TENANT_ID__',ctx.tenant_id);
}
Deno.serve(async(req:Request)=>{
  if(req.method!=="GET"&&req.method!=="HEAD") return new Response("Method Not Allowed",{status:405});
  try{
    const ctx=await tenantContext(req);
    const origin=new URL(SUPABASE_URL).origin;
    const body=renderedSvg(ctx);
    const frames=ctx.kds_origin;
    return new Response(req.method==="HEAD"?null:body,{status:200,headers:{
      "content-type":"image/svg+xml; charset=utf-8",
      "cache-control":"no-store, max-age=0, must-revalidate",
      "pragma":"no-cache",
      "access-control-allow-origin":"*",
      "cross-origin-resource-policy":"cross-origin",
      "content-security-policy":`default-src 'self' https: data: blob:; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src https: data: blob:; connect-src ${origin}; frame-ancestors ${frames}`,
      "x-content-type-options":"nosniff",
      "vary":"X-SDB-Tenant-ID",
      "x-sdb-tenant-id":ctx.tenant_id,
      "x-rohmat-smart-cashier":"svg-master-prototype-v1"
    }});
  }catch{return new Response("tenant_required_or_invalid",{status:400,headers:{"content-type":"text/plain; charset=utf-8","cache-control":"no-store","x-content-type-options":"nosniff"}})}
});