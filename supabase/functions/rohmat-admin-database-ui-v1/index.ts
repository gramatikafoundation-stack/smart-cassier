import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
const U=Deno.env.get('SUPABASE_URL')||'';
const S=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const JS=String.raw`(()=>{'use strict';
if(window.__rohmatDbRealtimeV13)return;window.__rohmatDbRealtimeV13=1;
const API='__SUPABASE_URL__/functions/v1/rohmat-admin-order-history-v1';
const TENANT='__SDB_TENANT_ID__',SHEET='__SPREADSHEET_URL__';
let rows=[],busy=false,lastSig='',lastLoad=0,sheetHealth=null,total=0;
const LOCALE='__TENANT_LOCALE__',CURRENCY='__TENANT_CURRENCY__',TIMEZONE='__TENANT_TIMEZONE__';const tx=s=>String(s||'').replace(/\s+/g,' ').trim(),esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),rp=n=>new Intl.NumberFormat(LOCALE,{style:'currency',currency:CURRENCY,maximumFractionDigits:0}).format(Number(n)||0);
const source=s=>s==='cashier_admin'?'Smart Cashier Admin':s==='cashier_kds'?'Smart Cashier KDS':s==='public'?'Situs Publik / Barcode':(s||'—');
const service=s=>s==='dine-in'?'Dine In':s==='take-away'?'Take Away':(s||'—');
const pay=s=>s==='cash'?'Cash':s==='qris_cashier'?'QRIS Kasir':s==='qris'?'QRIS':(s||'—');
const ord=s=>({confirmed:'Pesanan Baru',preparing:'Sedang Diproses',ready:'Siap',completed:'Pesanan Selesai',payment_review:'Menunggu Verifikasi'}[s]||s||'—');
function isDb(){return tx(document.querySelector('.mainNav button.on')?.textContent).toUpperCase()==='DATABASE'}function isHistory(){return isDb()&&tx(document.querySelector('.subnav button.on')?.textContent)==='Riwayat'}
function token(){let v=localStorage.getItem('rohmat-admin-session-v4')||sessionStorage.getItem('rohmat-admin-session-v4')||'';if(v&&v[0]==='{'){try{const j=JSON.parse(v);v=j.token||j.access_token||''}catch{}}return String(v||'')}
function dt(v,t){if(!v)return'—';try{return t==='d'?new Date(v).toLocaleDateString(LOCALE,{timeZone:TIMEZONE,day:'2-digit',month:'2-digit',year:'numeric'}):new Date(v).toLocaleTimeString(LOCALE,{timeZone:TIMEZONE,hour:'2-digit',minute:'2-digit',second:'2-digit'})+' WIB'}catch{return'—'}}
function items(o){return(Array.isArray(o?.items)?o.items:[]).map(i=>({name:String(i?.name??i?.menu_name??'Menu'),qty:Math.max(1,Number(i?.quantity??i?.qty??1)||1),price:Math.max(0,Number(i?.price??i?.unit_price??0)||0)}))}
function openSheet(){const w=window.open(SHEET,'_blank','noopener,noreferrer');if(!w)location.href=SHEET}
function css(){if(document.getElementById('rohmatDbRtCss13'))return;const s=document.createElement('style');s.id='rohmatDbRtCss13';s.textContent='#rohmatDbSafe9{display:block!important;width:100%}.rd13h{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin:4px 0 12px}.rd13status{display:flex;gap:7px;align-items:center;flex-wrap:wrap}.rd13chip{font-size:11px;font-weight:850;padding:6px 9px;border:1px solid var(--line);border-radius:999px;background:var(--panel2)}.rd13ok{color:#2f6f56}.rd13wait{color:#9a6a22}.rd13wrap{overflow:auto;border:1px solid var(--line);border-radius:15px;background:var(--panel);max-height:calc(100vh - 250px)}.rd13tbl{width:100%;min-width:1900px;border-collapse:collapse}.rd13tbl th,.rd13tbl td{padding:9px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top;font-size:11px}.rd13tbl th{background:var(--panel2);position:sticky;top:0;z-index:2;white-space:nowrap}.rd13items{display:grid;gap:2px;min-width:190px}.rd13total{font-weight:900;white-space:nowrap}.rd13empty,.rd13err{padding:24px;text-align:center}.rd13err{color:#9a4238;background:#fff0ed;border-radius:12px}.rd13btn{display:inline-flex;border:0;border-radius:10px;padding:9px 12px;background:var(--primary);color:#fff;text-decoration:none;font-weight:850;cursor:pointer}';document.head.appendChild(s)}
function root(){const v=document.getElementById('view');if(!v)return null;let r=document.getElementById('rohmatDbSafe9');if(!r){r=document.createElement('section');r.id='rohmatDbSafe9'}if(r.parentElement!==v||v.children.length!==1||v.firstElementChild!==r)v.replaceChildren(r);return r}
function nav(){const n=document.querySelector('.subnav');if(!n)return;n.removeAttribute('data-rd13')}
function syncText(){const h=sheetHealth||{};if(h.enabled===false)return'<span class="rd13chip rd13wait">Sheet: tidak tersedia</span>';const pending=Number(h.pending||0)+Number(h.processing||0)+Number(h.failed||0),last=h.last_synced_at?new Date(h.last_synced_at).toLocaleTimeString(LOCALE,{timeZone:TIMEZONE,hour:'2-digit',minute:'2-digit',second:'2-digit'}):'—';return'<span class="rd13chip '+(pending?'rd13wait':'rd13ok')+'">Sheet '+(pending?'menunggu '+pending:'sinkron')+' · '+last+'</span>'}
function render(){if(!isHistory())return;css();const r=root();if(!r)return;const body=rows.length?rows.map(o=>{const a=items(o),it=a.length?'<div class="rd13items">'+a.map(i=>'<span><b>'+i.qty+'×</b> '+esc(i.name)+' · '+rp(i.price)+'</span>').join('')+'</div>':'—';return'<tr><td><b>'+esc(o.public_order_code||'—')+'</b></td><td>'+dt(o.created_at,'d')+'</td><td>'+dt(o.created_at,'t')+'</td><td>'+esc(source(o.order_source))+'</td><td>'+esc(service(o.service_mode))+'</td><td>'+esc(o.service_mode==='dine-in'?(o.table_number||'—'):'—')+'</td><td>'+esc(o.customer_name||'—')+'</td><td>'+esc(o.customer_whatsapp||'—')+'</td><td>'+it+'</td><td>'+Number(o.item_count||0)+'</td><td class="rd13total">'+rp(o.total_amount||0)+'</td><td>'+esc(pay(o.payment_method))+'</td><td>'+esc(o.payment_status||'—')+'</td><td>'+esc(ord(o.order_status))+'</td><td>'+dt(o.payment_submitted_at||o.verified_at||o.kitchen_sent_at||o.created_at,'t')+'</td><td>'+dt(o.preparing_at||o.ready_at,'t')+'</td><td>'+dt(o.completed_at,'t')+'</td><td>'+esc(o.customer_note||'—')+'</td><td>'+esc(o.cashier_actor||'—')+'</td></tr>'}).join(''):'<tr><td colspan="19" class="rd13empty">Belum ada riwayat pesanan.</td></tr>';r.innerHTML='<div class="rd13h"><div class="rd13status"><span class="rd13chip rd13ok">Database live · '+total+' transaksi</span>'+syncText()+'</div><button class="rd13btn" type="button" id="rd13OpenSheet">Spreadsheet ↗</button></div><div class="rd13wrap"><table class="rd13tbl"><thead><tr><th>Kode Pesanan</th><th>Tanggal</th><th>Waktu</th><th>Sumber</th><th>Layanan</th><th>Meja</th><th>Pemesan</th><th>No. WA</th><th>Menu, Jumlah & Harga</th><th>Item</th><th>Total</th><th>Metode Bayar</th><th>Status Bayar</th><th>Status Pesanan</th><th>Pesanan Baru</th><th>Diproses</th><th>Selesai</th><th>Catatan</th><th>Petugas Kasir</th></tr></thead><tbody>'+body+'</tbody></table></div>';document.getElementById('rd13OpenSheet')?.addEventListener('click',openSheet)}
async function load(force=false){if(!isHistory()||busy||document.hidden)return;if(!force&&Date.now()-lastLoad<900)return;const t=token();if(!t){const r=root();if(r)r.innerHTML='<div class="rd13err">Sesi Admin tidak ditemukan. Silakan login kembali.</div>';return}busy=true;lastLoad=Date.now();try{const res=await fetch(API+'?t='+Date.now(),{method:'POST',cache:'no-store',headers:{'content-type':'application/json','x-admin-session':t,'x-sdb-tenant-id':TENANT},body:JSON.stringify({limit:1000,offset:0})});const j=await res.json().catch(()=>({}));if(!res.ok||!j.ok)throw Error(j.error||'Riwayat gagal dimuat');const next=Array.isArray(j.rows)?j.rows:[],sig=JSON.stringify(next.map(x=>[x.id,x.updated_at,x.order_status,x.payment_status,x.total_amount,x.items]));sheetHealth=j.sheet_sync||null;total=Number(j.total||next.length);if(force||sig!==lastSig){rows=next;lastSig=sig;render()}else{const st=document.querySelector('.rd13status');if(st)st.innerHTML='<span class="rd13chip rd13ok">Database live · '+total+' transaksi</span>'+syncText()}}catch(e){const r=root();if(r)r.innerHTML='<div class="rd13err"><b>Riwayat Pesanan gagal dimuat.</b><br>'+esc(e.message||e)+'</div>'}finally{busy=false}}
function activate(){nav();if(!isHistory()){document.getElementById('rohmatDbSafe9')?.remove();return}render();load(true)}
document.addEventListener('click',e=>{if(e.target.closest('.mainNav button,.subnav button'))setTimeout(activate,50)},true);document.addEventListener('rohmat:navigation',()=>setTimeout(activate,40));document.addEventListener('rohmat:cashier-order-created',()=>setTimeout(()=>load(true),50));document.addEventListener('visibilitychange',()=>{if(!document.hidden)setTimeout(()=>load(true),50)});window.addEventListener('focus',()=>setTimeout(()=>load(true),50));window.addEventListener('pageshow',()=>setTimeout(activate,80));setInterval(()=>{if(!document.hidden&&isHistory())load(false)},5000);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(activate,100),{once:true});else setTimeout(activate,100);
})();`;
Deno.serve(async(req:Request)=>{
  if(req.method!=='GET'&&req.method!=='HEAD')return new Response('Method Not Allowed',{status:405});
  if(!U||!S)return new Response('/* platform configuration incomplete */',{status:503,headers:{'content-type':'application/javascript; charset=utf-8','cache-control':'no-store'}});
  const u=new URL(req.url),tenantId=String(u.searchParams.get('tenant')||req.headers.get('x-sdb-tenant-id')||'').trim();
  if(!UUID_RE.test(tenantId))return new Response('/* tenant required */',{status:400,headers:{'content-type':'application/javascript; charset=utf-8','cache-control':'no-store'}});
  const sb=createClient(U,S,{auth:{persistSession:false,autoRefreshToken:false}});
  const [ctx,cfg]=await Promise.all([
    sb.rpc('master_prototype_tenant_context',{p_tenant_id:tenantId}),
    sb.rpc('tenant_sheet_sync_config',{p_tenant_id:tenantId})
  ]);
  if(ctx.error||!ctx.data?.ok||ctx.data?.enabled===false||cfg.error||!cfg.data?.ok){
    return new Response('/* tenant unavailable */',{status:404,headers:{'content-type':'application/javascript; charset=utf-8','cache-control':'no-store'}});
  }
  const targets=Array.isArray(cfg.data.targets)?cfg.data.targets:[];
  const target=targets.find((x:any)=>x.enabled!==false)||targets[0]||null;
  const sheet=target?.spreadsheet_id?'https://docs.google.com/spreadsheets/d/'+target.spreadsheet_id+'/edit':'';
  const body=JS
    .replaceAll('__SUPABASE_URL__',U.replace(/\/$/,''))
    .replaceAll('__SDB_TENANT_ID__',tenantId)
    .replaceAll('__SPREADSHEET_URL__',sheet)
    .replaceAll('__TENANT_LOCALE__',String(ctx.data.locale||'id-ID'))
    .replaceAll('__TENANT_CURRENCY__',String(ctx.data.currency||'IDR'))
    .replaceAll('__TENANT_TIMEZONE__',String(ctx.data.timezone||'Asia/Jakarta'));
  return new Response(req.method==='HEAD'?null:body,{status:200,headers:{
    'content-type':'application/javascript; charset=utf-8',
    'cache-control':'no-cache, max-age=0, must-revalidate',
    'etag':'"rohmat-admin-dbui-master-prototype-v1-'+tenantId.slice(0,8)+'"',
    'access-control-allow-origin':'*',
    'cross-origin-resource-policy':'cross-origin',
    'x-content-type-options':'nosniff',
    'vary':'X-SDB-Tenant-ID',
    'x-sdb-tenant-id':tenantId,
    'x-rohmat-admin-db-ui':'master-prototype-v1'
  }});
});