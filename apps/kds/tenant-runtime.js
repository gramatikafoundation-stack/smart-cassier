(()=>{'use strict';
const defaults={tenantId:'',businessName:'Business',locale:'id-ID',currency:'IDR',timezone:'Asia/Jakarta',supabaseUrl:'',publishableKey:''};
const current={...defaults};
window.__SDB_TENANT_CONFIG=current;

function apply(){
  const name=String(current.businessName||defaults.businessName);
  document.querySelectorAll('[data-tenant-business]').forEach(el=>{el.textContent=name});
  if(document.body?.classList.contains('loginPage'))document.title='Masuk KDS — '+name;
  else if(document.body?.classList.contains('kdsPage'))document.title='Kitchen Display System — '+name;
  document.documentElement.lang=String(current.locale||'id-ID').split('-')[0]||'id';
  document.dispatchEvent(new CustomEvent('sdb:tenant-config',{detail:{...current}}));
}
async function readConfig(){
  try{
    const r=await fetch('/api/kds/config',{cache:'no-store',credentials:'same-origin'});
    if(!r.ok)return;
    const n=await r.json();
    for(const k of Object.keys(defaults))if(n?.[k]!=null&&String(n[k]).trim())current[k]=n[k];
  }catch{}
}
async function readBrand(){
  try{
    const r=await fetch('/api/kds',{method:'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'brand'})});
    if(!r.ok)return;
    const n=await r.json();
    const brand=String(n?.businessName||'').trim().slice(0,120);
    if(brand)current.businessName=brand;
  }catch{}
}
window.__SDB_TENANT_CONFIG_READY=(async()=>{
  await readConfig();
  await readBrand();
  apply();
  return current;
})();
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();
