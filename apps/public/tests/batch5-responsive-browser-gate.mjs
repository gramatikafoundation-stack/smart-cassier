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
const PORT=4195,ORIGIN=`http://127.0.0.1:${PORT}`;
const RUNTIME='https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-public-element-runtime-v64';
const cases=[
  ['mobile',{width:390,height:844}],
  ['tablet',{width:768,height:1024}],
  ['desktop',{width:1365,height:900}]
];
const fail=m=>{throw new Error(m)};

function server(){
  return http.createServer((req,res)=>{
    const path=(req.url||'').split('?')[0];
    const fn=path==='/runtime-lifecycle.js'?runtimeHandler:renderHandler;
    Promise.resolve(fn(req,res)).catch(e=>{
      console.error(e);
      if(!res.headersSent)res.statusCode=500;
      if(!res.writableEnded)res.end('handler error');
    });
  });
}

async function probe(browser,label,viewport){
  const ctx=await browser.newContext({viewport,locale:'id-ID'});
  const page=await ctx.newPage(),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('console',m=>{if(m.type()==='error')errors.push('console:'+m.text())});
  await page.route(url=>url.toString().startsWith(RUNTIME),async route=>
    route.request().method()==='POST'
      ?route.fulfill({status:204,headers:{'access-control-allow-origin':ORIGIN}})
      :route.continue()
  );
  const r=await page.goto(ORIGIN,{waitUntil:'domcontentloaded',timeout:30000});
  if(!r||r.status()!==200)fail(label+'_http_'+r?.status());
  await page.locator('#next').waitFor({timeout:15000});
  const home=await page.evaluate(()=>({
    innerWidth:window.innerWidth,
    scrollWidth:document.documentElement.scrollWidth,
    next:(()=>{const b=document.querySelector('#next')?.getBoundingClientRect();return b?{w:b.width,h:b.height}:null})(),
    viewport:document.querySelector('meta[name="viewport"]')?.content||''
  }));
  if(home.scrollWidth>home.innerWidth+2)fail(label+'_home_horizontal_overflow_'+JSON.stringify(home));
  if(!home.next||home.next.w<44||home.next.h<44)fail(label+'_primary_touch_target_'+JSON.stringify(home.next));
  if(!/width=device-width/i.test(home.viewport))fail(label+'_viewport_meta');

  await page.evaluate(()=>{
    const x=document.querySelector('input[name="mode"][value="take-away"]');
    if(!x)throw new Error('takeaway_missing');
    x.checked=true;x.dispatchEvent(new Event('change',{bubbles:true}));
  });
  await page.locator('#next').click();
  await page.waitForSelector('.grid .card',{timeout:10000});
  const menu=await page.evaluate(()=>({
    innerWidth:window.innerWidth,
    scrollWidth:document.documentElement.scrollWidth,
    cards:document.querySelectorAll('.grid .card').length,
    first:(()=>{const b=document.querySelector('.grid .card')?.getBoundingClientRect();return b?{left:b.left,right:b.right,w:b.width}:null})()
  }));
  if(menu.scrollWidth>menu.innerWidth+2)fail(label+'_menu_horizontal_overflow_'+JSON.stringify(menu));
  if(menu.cards<1||!menu.first||menu.first.left<0||menu.first.right>menu.innerWidth+2)fail(label+'_menu_layout_'+JSON.stringify(menu));
  if(errors.length)fail(label+'_browser_errors_'+errors.join('|'));
  await ctx.close();
  return {label,viewport,home,menu,browserErrors:errors.length};
}

const srv=server();
await new Promise((ok,no)=>{srv.once('error',no);srv.listen(PORT,'127.0.0.1',ok)});
const browser=await chromium.launch({headless:true});
try{
  const results=[];
  for(const [label,viewport] of cases)results.push(await probe(browser,label,viewport));
  console.log(JSON.stringify({ok:true,results},null,2));
  console.log('BATCH5_RESPONSIVE_BROWSER_GATE_PASS=1');
}finally{
  await browser.close();
  await new Promise(r=>srv.close(r));
}
