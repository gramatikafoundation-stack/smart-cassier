import http from 'node:http';
import { chromium } from 'playwright';

process.env.MASTER_PROTOTYPE_STRICT ||= '1';
process.env.SDB_TENANT_ID ||= 'd8bb901c-7399-485b-8743-b319fde148ac';
process.env.SUPABASE_URL ||= 'https://xrepmvbccalzhlcznrff.supabase.co';
process.env.PUBLIC_LKG_PATH ||= '/storage/v1/object/public/merchant-static/public-lkg-v1.html';
process.env.BUSINESS_NAME ||= 'Rohmat Nasi Uduk';
process.env.PUBLIC_ORIGIN ||= 'https://smart-cassier.vercel.app';
process.env.TENANT_LOCALE ||= 'id-ID';
const { default: handler } = await import('../api/render-seo-brand.js');
const { default: runtimeLifecycleHandler } = await import('../lib/runtime-lifecycle.js');

const PORT=4192,ORIGIN=`http://127.0.0.1:${PORT}`;
const RUM='https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-public-element-runtime-v64';
const fail=m=>{throw new Error(m)},sleep=ms=>new Promise(r=>setTimeout(r,ms));
function server(){return http.createServer((req,res)=>{const path=(req.url||'').split('?')[0],fn=path==='/runtime-lifecycle.js'?runtimeLifecycleHandler:handler;Promise.resolve(fn(req,res)).catch(e=>{console.error(e);if(!res.headersSent)res.statusCode=500;if(!res.writableEnded)res.end('handler error')})})}
const pct=(a,p)=>{if(!a.length)return 0;const s=[...a].sort((x,y)=>x-y);return s[Math.max(0,Math.ceil(p*s.length)-1)]};
async function a11y(page,stage){const check=stage=>{const main=document.querySelector('#app main');if(!main||main.id!=='main-content')return false;if(stage==='home')return !!document.querySelector('h1.brand[tabindex="-1"]');if(stage==='menu')return !!(main.getAttribute('aria-labelledby')&&document.querySelector('.grid .card[aria-labelledby]')&&document.querySelector('#confirm[aria-label]'));if(stage==='dialog')return !!(document.querySelector('#dlg[aria-labelledby]')&&document.querySelector('#name[required][aria-required="true"]'));if(stage==='checkout'){const proof=document.querySelector('#proof'),desc=proof?.getAttribute('aria-describedby');return !!(main.getAttribute('aria-labelledby')&&document.querySelector('.payroom[aria-labelledby]')&&desc&&document.getElementById(desc))}return true};try{await page.waitForFunction(check,stage,{timeout:800,polling:25})}catch{const snap=await page.evaluate(stage=>({stage,mainId:document.querySelector('#app main')?.id||'',mainLabel:document.querySelector('#app main')?.getAttribute('aria-labelledby')||'',payLabel:document.querySelector('.payroom')?.getAttribute('aria-labelledby')||'',proofDesc:document.querySelector('#proof')?.getAttribute('aria-describedby')||'',dialogLabel:document.querySelector('#dlg')?.getAttribute('aria-labelledby')||'',nameRequired:document.querySelector('#name')?.getAttribute('aria-required')||''}),stage);fail('a11y_afterpaint_'+stage+':'+JSON.stringify(snap))}}

async function run(browser,label,viewport,cpuRate){
  const ctx=await browser.newContext({viewport,locale:'id-ID'}),page=await ctx.newPage(),errors=[],writes=[];
  const cdp=await ctx.newCDPSession(page);if(cpuRate>1)await cdp.send('Emulation.setCPUThrottlingRate',{rate:cpuRate});
  await page.addInitScript(()=>{window.__evt=[];window.__lt=[];try{new PerformanceObserver(l=>{for(const e of l.getEntries())if(e.interactionId)window.__evt.push({id:e.interactionId,d:e.duration,name:e.name,target:e.target?.id||String(e.target?.className||e.target?.tagName||''),step:window.__step||'unknown'})}).observe({type:'event',buffered:true,durationThreshold:16})}catch{}try{new PerformanceObserver(l=>{for(const e of l.getEntries())window.__lt.push(e.duration)}).observe({type:'longtask',buffered:true})}catch{}});
  page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push('console:'+m.text())});
  await page.route(url=>url.toString().startsWith(RUM),async route=>{if(route.request().method()==='POST'){writes.push('rum');return route.fulfill({status:204,headers:{'access-control-allow-origin':ORIGIN}})}return route.continue()});
  const r=await page.goto(ORIGIN,{waitUntil:'domcontentloaded',timeout:30000});if(!r||r.status()!==200)fail(label+'_http_'+r?.status());
  await page.locator('#next').waitFor({timeout:15000});await sleep(1200);await a11y(page,'home');await page.evaluate(()=>{window.__evt=[];window.__lt=[]});
  await page.evaluate(()=>window.__step='mode');await page.locator('.opt').filter({hasText:'TAKE AWAY'}).click();
  await page.evaluate(()=>window.__step='next');const tNext=Date.now();await page.locator('#next').click();await page.locator('.grid').waitFor({timeout:10000});const nextMs=Date.now()-tNext;await a11y(page,'menu');
  for(const name of ['Nasi','Minuman','Semua']){const b=page.locator('.cat').filter({hasText:name});if(await b.count()){await page.evaluate(n=>window.__step='cat:'+n,name);await b.first().click()}}
  const add=page.locator('.grid [data-id][data-a="+"]').first();await add.waitFor({timeout:10000});await page.evaluate(()=>window.__step='add');await add.click();
  await page.evaluate(()=>window.__step='confirm');await page.locator('#confirm').click();await page.locator('#name').waitFor({timeout:5000});await a11y(page,'dialog');await page.locator('#name').fill('PERF TEST');
  await page.evaluate(()=>window.__step='pay');const tPay=Date.now();await page.locator('#pay').click();await page.locator('.checkout').waitFor({timeout:10000});const payMs=Date.now()-tPay;await a11y(page,'checkout');
  await page.evaluate(()=>window.__step='backm');const tBack=Date.now();await page.locator('#backm').click();await page.locator('.grid').waitFor({timeout:10000});const backMs=Date.now()-tBack;await a11y(page,'menu');
  await page.evaluate(()=>window.__step='back');await page.locator('#back').click();await page.locator('#next').waitFor({timeout:10000});
  await sleep(700);
  const raw=await page.evaluate(()=>({events:window.__evt||[],longtasks:window.__lt||[]}));
  const byId=new Map();for(const e of raw.events){const cur=byId.get(e.id);if(!cur||Number(e.d)>cur.duration)byId.set(e.id,{duration:Number(e.d)||0,target:e.target||'',name:e.name||'',step:e.step||'unknown'})}const interactionDetails=[...byId.values()];const interactions=interactionDetails.map(x=>x.duration);
  const result={label,cpuRate,interactionCount:interactions.length,inpLabP75:pct(interactions,.75),inpLabMax:interactions.length?Math.max(...interactions):0,longTaskMax:raw.longtasks.length?Math.max(...raw.longtasks):0,longTaskCount:raw.longtasks.length,routeMs:{next:nextMs,pay:payMs,back:backMs},browserErrors:errors.length,unexpectedWrites:writes.filter(x=>x!=='rum').length,interactionDetails};console.log('PERF_DEBUG',JSON.stringify(result));
  if(result.interactionCount<6)fail(label+'_interaction_sample_too_small_'+result.interactionCount);
  if(result.inpLabP75>200)fail(label+'_inp_p75_'+result.inpLabP75);
  if(result.inpLabMax>500)fail(label+'_inp_max_'+result.inpLabMax);
  if(result.longTaskMax>250)fail(label+'_longtask_'+result.longTaskMax);
  if(errors.length)fail(label+'_browser_errors_'+errors.join('|'));
  await ctx.close();return result;
}
const srv=server();await new Promise((ok,no)=>{srv.once('error',no);srv.listen(PORT,'127.0.0.1',ok)});const browser=await chromium.launch(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{headless:true,executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{headless:true});
try{const desktop=await run(browser,'desktop',{width:1365,height:900},1),mobile=await run(browser,'mobile-2x-cpu',{width:390,height:844},2);console.log(JSON.stringify({ok:true,target:'INP lab p75 <= 200ms',desktop,mobile},null,2));console.log('PUBLIC_PERFORMANCE_BROWSER_GATE_PASS=1')}finally{await browser.close();await new Promise(r=>srv.close(r))}
