const BASE=String(process.env.BATCH5_BASE_URL||'https://smart-cassier.vercel.app').replace(/\/$/,'');
const key=String(process.env.BATCH5_CACHE_KEY||('gate-'+Date.now()));
const pages=['/','/admin','/kds/login'];
const cacheTargets=[
  {name:'public',path:'/?batch5cache='+key},
  {name:'admin',path:'/admin?batch5cache='+key},
  {name:'kds-login',path:'/kds/login?batch5cache='+key},
  {name:'kds-asset',path:'/kds-assets/v4/styles.css?batch5cache='+key}
];
const pick=h=>Object.fromEntries(
  ['x-vercel-cache','age','cache-control','cdn-cache-control','vercel-cdn-cache-control','content-type','x-robots-tag']
    .map(k=>[k,h.get(k)])
);
const timed=async p=>{
  const t=performance.now();
  const r=await fetch(BASE+p,{redirect:'follow'});
  const b=await r.arrayBuffer();
  return {path:p,status:r.status,ms:Math.round(performance.now()-t),bytes:b.byteLength,headers:pick(r.headers)};
};

const cache=[];
for(const t of cacheTargets) cache.push({name:t.name,cold:await timed(t.path),warm:await timed(t.path)});

const refs=new Set(),pageResults=[];
const baseOrigin=new URL(BASE).origin;
for(const p of pages){
  const r=await fetch(BASE+p);
  const html=await r.text();
  pageResults.push({path:p,status:r.status,bytes:Buffer.byteLength(html)});

  for(const re of [
    /<script\b[^>]*\bsrc=["']([^"']+)["']/gi,
    /<img\b[^>]*\bsrc=["']([^"']+)["']/gi,
    /<a\b[^>]*\bhref=["']([^"']+)["']/gi
  ]){
    for(const m of html.matchAll(re)){
      const raw=(m[1]||'').trim();
      if(!raw||raw.startsWith('#')||/^(?:data:|blob:|mailto:|tel:|javascript:)/i.test(raw)) continue;
      try{
        const u=new URL(raw,BASE);
        if(u.origin===baseOrigin||u.hostname.endsWith('.supabase.co')) refs.add(u.href);
      }catch{}
    }
  }
  for(const m of html.matchAll(/<link\b([^>]*)>/gi)){
    const attrs=m[1]||'';
    const rel=(attrs.match(/\brel=["']([^"']+)["']/i)?.[1]||'').toLowerCase();
    if(/\b(?:preconnect|dns-prefetch)\b/.test(rel)) continue;
    const raw=(attrs.match(/\bhref=["']([^"']+)["']/i)?.[1]||'').trim();
    if(!raw||raw.startsWith('#')||/^(?:data:|blob:)/i.test(raw)) continue;
    try{
      const u=new URL(raw,BASE);
      if(u.origin===baseOrigin||u.hostname.endsWith('.supabase.co')) refs.add(u.href);
    }catch{}
  }
}

const assetResults=[],all=[...refs];
for(let i=0;i<all.length;i+=8){
  const batch=all.slice(i,i+8);
  assetResults.push(...await Promise.all(batch.map(async url=>{
    try{
      const r=await fetch(url,{redirect:'follow'});
      await r.body?.cancel?.();
      return {url,status:r.status,ok:r.ok,cache:r.headers.get('cache-control'),type:r.headers.get('content-type')};
    }catch(e){
      return {url,status:0,ok:false,error:String(e)};
    }
  })));
}
const broken=assetResults.filter(x=>!x.ok);
const by=Object.fromEntries(cache.map(x=>[x.name,x]));
const h=(o,k)=>String(o.headers[k]||'');
const policyOk=
  h(by.public.cold,'cdn-cache-control').includes('s-maxage=300') &&
  h(by.admin.cold,'cache-control').includes('no-store') &&
  h(by.admin.cold,'cdn-cache-control').includes('max-age=60') &&
  h(by['kds-login'].cold,'cache-control').includes('no-store') &&
  /max-age=31536000/.test(h(by['kds-asset'].cold,'cache-control')) &&
  /immutable/.test(h(by['kds-asset'].cold,'cache-control'));
const transitionOk=['public','admin'].every(n=>{
  const c=by[n].cold.headers['x-vercel-cache'],w=by[n].warm.headers['x-vercel-cache'];
  return c==='HIT'||c==='STALE'||w==='HIT'||w==='STALE';
});
const ok=pageResults.every(x=>x.status===200)&&broken.length===0&&policyOk&&transitionOk;
console.log(JSON.stringify({ok,base:BASE,pageResults,cache,scanned:assetResults.length,broken,policyOk,transitionOk},null,2));
if(!ok) process.exit(1);
console.log('BATCH5_HTTP_CACHE_ASSET_GATE_PASS=1');
