import http from 'node:http';
import { chromium } from 'playwright';


// Self-contained fail-closed tenant fixture for local/CI gates.
process.env.MASTER_PROTOTYPE_STRICT ||= '1';
process.env.SDB_TENANT_ID ||= 'd8bb901c-7399-485b-8743-b319fde148ac';
process.env.SUPABASE_URL ||= 'https://xrepmvbccalzhlcznrff.supabase.co';
process.env.PUBLIC_LKG_PATH ||= '/storage/v1/object/public/merchant-static/public-lkg-v1.html';
process.env.BUSINESS_NAME ||= 'Master Prototype Test Merchant';
process.env.PUBLIC_ORIGIN ||= 'https://master-prototype-test.invalid';
process.env.TENANT_LOCALE ||= 'id-ID';
const { default: renderHandler } = await import('../api/render-seo-brand.js');
const { default: runtimeHandler } = await import('../lib/runtime-lifecycle.js');
const PORT=4182,ORIGIN=`http://127.0.0.1:${PORT}`;
const RUM='https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-public-element-runtime-v64';
const fail=m=>{throw new Error(m)},sleep=ms=>new Promise(r=>setTimeout(r,ms));

function server(){return http.createServer((req,res)=>{const path=(req.url||'').split('?')[0],fn=path==='/runtime-lifecycle.js'?runtimeHandler:renderHandler;Promise.resolve(fn(req,res)).catch(e=>{console.error('LOCAL_HANDLER_ERROR',e);if(!res.headersSent)res.statusCode=500;if(!res.writableEnded)res.end('handler error')})})}

const probe=()=>{
  const RealMO=window.MutationObserver,rows=new Map();let seq=0;
  const targetName=t=>t===document?'document':t===document.body?'body':`${t?.tagName||'node'}#${t?.id||''}.${String(t?.className||'').trim().replace(/\s+/g,'.').slice(0,120)}`;
  class MO{constructor(cb){this.id=++seq;this.real=new RealMO(cb);rows.set(this.id,{active:false,disconnects:0,target:''})}observe(...a){const r=rows.get(this.id);r.active=true;r.target=targetName(a[0]);return this.real.observe(...a)}disconnect(){const r=rows.get(this.id);r.active=false;r.disconnects++;return this.real.disconnect()}takeRecords(){return this.real.takeRecords()}}
  window.MutationObserver=MO;
  const st=window.setTimeout.bind(window),ct=window.clearTimeout.bind(window),timers=new Map();
  window.setTimeout=(fn,ms=0,...args)=>{let id=0;const w=typeof fn==='function'?()=>{timers.delete(id);return fn(...args)}:fn;id=st(w,ms);timers.set(id,Number(ms)||0);return id};window.clearTimeout=id=>{timers.delete(id);return ct(id)};
  const si=window.setInterval.bind(window),ci=window.clearInterval.bind(window),intervals=new Set();window.setInterval=(fn,ms=0,...a)=>{const id=si(fn,ms,...a);intervals.add(id);return id};window.clearInterval=id=>{intervals.delete(id);return ci(id)};
  window.__checkoutLifecycle=()=>{const all=[...rows.values()];return{created:all.length,active:all.filter(x=>x.active).length,disconnects:all.reduce((n,x)=>n+x.disconnects,0),ownedLive:all.length-all.reduce((n,x)=>n+x.disconnects,0),activeTargets:all.filter(x=>x.active).map(x=>x.target),intervals:intervals.size,longTimers:[...timers.values()].filter(x=>x>=1000).length,pendingTimers:timers.size}}
};

async function snap(page,label){const s=await page.evaluate(()=>window.__checkoutLifecycle());console.log('CHECKOUT_LIFECYCLE',label,JSON.stringify(s));return s}

async function main(){
  const srv=server();await new Promise((ok,no)=>{srv.once('error',no);srv.listen(PORT,'127.0.0.1',ok)});const browser=await chromium.launch({headless:true});
  try{const ctx=await browser.newContext({viewport:{width:1280,height:900},locale:'id-ID'});await ctx.addInitScript(probe);const page=await ctx.newPage(),errors=[],writes=[];
    page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push('console:'+m.text())});page.on('request',r=>{if(r.method()==='POST'&&!r.url().startsWith(RUM))writes.push(r.url())});
    await page.route(url=>url.toString().startsWith(RUM),async route=>route.request().method()==='POST'?route.fulfill({status:204,headers:{'access-control-allow-origin':ORIGIN}}):route.continue());
    const response=await page.goto(ORIGIN,{waitUntil:'domcontentloaded',timeout:30000});if(!response||response.status()!==200)fail('http_'+response?.status());await page.waitForFunction(()=>document.documentElement.dataset.rohmatLifecycleRuntime==='v65',null,{timeout:10000});await sleep(500);
    const base=await snap(page,'home');if(base.intervals)fail('home_interval');
    await page.evaluate(()=>{const x=document.querySelector('input[name="mode"][value="take-away"]')||document.querySelector('input[value="take-away"]');x.checked=true;x.dispatchEvent(new Event('change',{bubbles:true}))});await page.locator('#next').click();await page.waitForSelector('.grid [data-id][data-a="+"]',{timeout:10000});await page.locator('.grid [data-id][data-a="+"]').first().click();await page.waitForSelector('#confirm:not(.hidden)',{timeout:5000});await page.locator('#confirm').click();await page.waitForSelector('#name',{timeout:5000});await page.locator('#name').fill('LIFECYCLE TEST');await sleep(900);await page.locator('#pay').click();await page.waitForSelector('#proof',{timeout:7000});await sleep(150);
    const checkout=await snap(page,'checkout');if(checkout.intervals)fail('checkout_interval');if(checkout.active>base.active+3)fail(`checkout_observer_growth_${checkout.active}_${base.active}`);
    await page.locator('#backm').click();await page.waitForSelector('.grid [data-id][data-a="+"]',{timeout:10000});await sleep(160);const menu=await snap(page,'menu-after-checkout');if(menu.intervals)fail('menu_interval');if(menu.active>base.active+1)fail(`checkout_observer_not_released_${menu.active}_${base.active}`);if(menu.ownedLive>base.active+1)fail(`owned_observer_not_released_${menu.ownedLive}_${base.active}`);
    await page.locator('#back').click();await page.waitForSelector('#next',{timeout:10000});await sleep(120);
    let previousRestore=null;for(let i=1;i<=2;i++){await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true})));await sleep(80);const hidden=await snap(page,`pagehide-${i}`);if(hidden.intervals)fail(`pagehide_${i}_interval`);if(hidden.longTimers>base.longTimers)fail(`pagehide_${i}_timer_growth`);await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true})));await sleep(250);const restored=await snap(page,`pageshow-${i}`);if(restored.intervals)fail(`pageshow_${i}_interval`);if(previousRestore&&restored.active>previousRestore.active)fail(`restore_observer_growth_${restored.active}_${previousRestore.active}`);if(previousRestore&&restored.longTimers>previousRestore.longTimers+1)fail(`restore_timer_growth_${restored.longTimers}_${previousRestore.longTimers}`);previousRestore=restored}
    if(writes.length)fail('unexpected_writes:'+writes.join('|'));if(errors.length)fail('browser_errors:'+errors.join('|'));
    console.log(JSON.stringify({ok:true,base,checkout,menuAfterCheckout:menu,finalRestore:previousRestore,browserErrors:errors.length,unexpectedWrites:writes.length},null,2));console.log('PUBLIC_LIFECYCLE_CHECKOUT_GATE_PASS=1');await ctx.close();
  }finally{await browser.close();await new Promise(r=>srv.close(r))}
}
main().catch(e=>{console.error(e);process.exit(1)});
