import http from 'node:http';
import { chromium } from 'playwright';

process.env.MASTER_PROTOTYPE_STRICT ||= '1';
process.env.SDB_TENANT_ID ||= 'd8bb901c-7399-485b-8743-b319fde148ac';
process.env.SUPABASE_URL ||= 'https://xrepmvbccalzhlcznrff.supabase.co';
process.env.PUBLIC_LKG_PATH ||= '/storage/v1/object/public/merchant-static/public-lkg-v1.html';
process.env.BUSINESS_NAME ||= 'Rohmat Nasi Uduk';
process.env.PUBLIC_ORIGIN ||= 'https://smart-cassier.vercel.app';
process.env.TENANT_LOCALE ||= 'id-ID';
const { default: renderHandler } = await import('../api/render-seo-brand.js');
const { default: runtimeHandler } = await import('../lib/runtime-lifecycle.js');
const PORT=4192, ORIGIN=`http://127.0.0.1:${PORT}`;
const RUNTIME='https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-public-element-runtime-v64';
const fail=m=>{throw new Error(m)};

function server(){
  return http.createServer((req,res)=>{
    const path=(req.url||'').split('?')[0];
    const fn=path==='/runtime-lifecycle.js'?runtimeHandler:renderHandler;
    Promise.resolve(fn(req,res)).catch(e=>{
      console.error('LOCAL_HANDLER_ERROR',e);
      if(!res.headersSent)res.statusCode=500;
      if(!res.writableEnded)res.end('handler error');
    });
  });
}

async function main(){
  const srv=server();
  await new Promise((ok,no)=>{srv.once('error',no);srv.listen(PORT,'127.0.0.1',ok)});
  const browser=await chromium.launch({headless:true});
  try{
    const ctx=await browser.newContext({viewport:{width:1366,height:900},locale:'id-ID'});
    const page=await ctx.newPage();
    const errors=[],failed=[],assetResponses=new Map();
    page.on('pageerror',e=>errors.push(String(e)));
    page.on('console',m=>{if(m.type()==='error')errors.push('console:'+m.text())});
    page.on('requestfailed',r=>failed.push(r.url()));
    page.on('response',async r=>{
      const u=r.url();
      if(u.includes('/storage/v1/object/public/rohmat-assets/')) assetResponses.set(u,{status:r.status(),cache:(await r.allHeaders())['cache-control']||''});
    });
    await page.route(url=>url.toString().startsWith(RUNTIME),async route=>route.request().method()==='POST'
      ?route.fulfill({status:204,headers:{'access-control-allow-origin':ORIGIN}})
      :route.continue());

    const response=await page.goto(ORIGIN,{waitUntil:'domcontentloaded',timeout:30000});
    if(!response||response.status()!==200)fail('http_'+response?.status());
    await page.waitForSelector('.hero .photo img',{timeout:10000});
    const radio=await page.evaluate(()=>({
      fieldset:!!document.querySelector('fieldset.opts'),
      legend:(document.querySelector('fieldset.opts legend')?.textContent||'').trim(),
      count:document.querySelectorAll('input[name="mode"][type="radio"]').length,
      checked:document.querySelectorAll('input[name="mode"][type="radio"]:checked').length
    }));
    if(!radio.fieldset||radio.legend!=='Pilih jenis layanan'||radio.count!==2||radio.checked!==1)fail('radio_a11y_contract_'+JSON.stringify(radio));

    await page.waitForFunction(()=>{const x=document.querySelector('.hero .photo img');return x&&x.complete&&x.naturalWidth>0&&x.naturalHeight>0},null,{timeout:15000});
    const hero=await page.evaluate(()=>{const x=document.querySelector('.hero .photo img');return {src:x.currentSrc||x.src,w:x.naturalWidth,h:x.naturalHeight,loading:x.loading,decoding:x.decoding,priority:x.fetchPriority}});
    if(!hero.src.includes('/rohmat-assets/hero/rohmat-nasi-uduk-hero-v1.jpg')||hero.w<1||hero.h<1||hero.loading!=='eager'||hero.priority!=='high')fail('hero_contract_'+JSON.stringify(hero));

    await page.evaluate(()=>{const x=document.querySelector('input[name="mode"][value="take-away"]');x.checked=true;x.dispatchEvent(new Event('change',{bubbles:true}))});
    await page.locator('#next').click();
    const imgs=page.locator('.grid .food img');
    await imgs.first().waitFor({timeout:10000});
    const count=await imgs.count();
    if(count!==36)fail('menu_image_count_'+count);
    for(let i=0;i<count;i++)await imgs.nth(i).scrollIntoViewIfNeeded();
    await page.waitForFunction(()=>{const xs=[...document.querySelectorAll('.grid .food img')];return xs.length===36&&xs.every(x=>x.complete&&x.naturalWidth>0&&x.naturalHeight>0)},null,{timeout:20000});
    const menu=await page.evaluate(()=>{
      const xs=[...document.querySelectorAll('.grid .food img')];
      return xs.map(x=>({src:x.currentSrc||x.src,w:x.naturalWidth,h:x.naturalHeight,loading:x.loading,decoding:x.decoding,fit:getComputedStyle(x).objectFit}));
    });
    const unique=new Set(menu.map(x=>x.src));
    const canonical=menu.filter(x=>x.src.startsWith('https://xrepmvbccalzhlcznrff.supabase.co/storage/v1/object/public/rohmat-assets/menu-cache/')).length;
    const bad=menu.filter(x=>x.w<1||x.h<1||x.decoding!=='async'||x.fit!=='cover');
    if(unique.size!==36||canonical!==36||bad.length)fail('menu_media_contract_'+JSON.stringify({unique:unique.size,canonical,bad:bad.length}));
    await page.waitForTimeout(500);
    const relevant=[...assetResponses.entries()].filter(([u])=>u.includes('/menu-cache/')||u.includes('/hero/'));
    const badCache=relevant.filter(([,v])=>v.status!==200||!v.cache.includes('31536000')||!v.cache.toLowerCase().includes('immutable'));
    if(relevant.length!==37||badCache.length)fail('asset_cache_contract_'+JSON.stringify({responses:relevant.length,badCache}));

    if(errors.length)fail('browser_errors:'+errors.join('|'));
    const badRequests=failed.filter(u=>u.includes('/rohmat-assets/'));
    if(badRequests.length)fail('asset_request_failures:'+badRequests.join('|'));
    console.log(JSON.stringify({ok:true,hero,menuCount:count,uniqueMenuImages:unique.size,canonicalMenuImages:canonical,assetResponses:relevant.length,immutableAssets:relevant.length-badCache.length,radio,browserErrors:errors.length},null,2));
    console.log('PUBLIC_MEDIA_VISUAL_GATE_PASS=1');
    await ctx.close();
  }finally{
    await browser.close();
    await new Promise(r=>srv.close(r));
  }
}
main().catch(e=>{console.error(e);process.exit(1)});
