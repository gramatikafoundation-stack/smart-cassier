import { chromium } from 'playwright';

const BASE=String(process.env.BATCH5_BASE_URL||'https://smart-cassier.vercel.app').replace(/\/$/,'');
const BRAND=String(process.env.BATCH5_BUSINESS_NAME||'Rohmat Nasi Uduk');
const launch=process.env.PLAYWRIGHT_EXECUTABLE_PATH
  ? {headless:true,executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}
  : {headless:true};
const browser=await chromium.launch(launch);
const cases=[
  ['mobile',{width:390,height:844}],
  ['tablet',{width:768,height:1024}],
  ['desktop',{width:1365,height:900}]
];
const surfaces=[
  {name:'public',path:'/',ready:'h1.brand',interactive:true},
  {name:'admin',path:'/admin',ready:'body'},
  {name:'kds-login',path:'/kds/login',ready:'#loginForm'}
];
const rows=[];

try{
  for(const [viewportName,viewport] of cases){
    for(const s of surfaces){
      const ctx=await browser.newContext({viewport,locale:'id-ID'});
      const page=await ctx.newPage();
      const errors=[],bad=[];
      page.on('pageerror',e=>errors.push(String(e)));
      page.on('console',m=>{if(m.type()==='error')errors.push('console:'+m.text())});
      page.on('response',r=>{
        if(r.status()>=400&&!/favicon\.ico/.test(r.url())) bad.push({status:r.status(),url:r.url()});
      });
      const started=Date.now();
      const resp=await page.goto(BASE+s.path,{waitUntil:'domcontentloaded',timeout:30000});
      await page.waitForSelector(s.ready,{timeout:15000});
      await page.waitForFunction(expected=>document.title.includes(expected),BRAND,{timeout:5000});
      const brandSettleMs=Date.now()-started;

      if(s.interactive){
        const take=page.locator('input[value="take-away"]');
        if(await take.count()) await take.check({force:true});
        await page.locator('#next').click();
        await page.waitForSelector('.grid',{timeout:10000});
        await page.waitForFunction(expected=>document.title.includes(expected),BRAND,{timeout:3000});
      }

      const state=await page.evaluate(()=>({
        width:innerWidth,
        scrollWidth:document.documentElement.scrollWidth,
        bodyVisible:getComputedStyle(document.body).display!=='none'&&getComputedStyle(document.body).visibility!=='hidden',
        title:document.title,
        targets:[...document.querySelectorAll('button,input,select,[role="button"]')]
          .filter(e=>e.offsetParent!==null&&getComputedStyle(e).pointerEvents!=='none')
          .slice(0,100)
          .map(e=>{const r=e.getBoundingClientRect();return{tag:e.tagName,id:e.id||'',w:Math.round(r.width),h:Math.round(r.height)}})
      }));
      const tiny=state.targets.filter(x=>x.w>0&&x.h>0&&(x.w<44||x.h<44));
      rows.push({
        viewport:viewportName,surface:s.name,status:resp?.status(),brandSettleMs,title:state.title,
        overflow:state.scrollWidth-state.width,pageErrors:errors,badResponses:bad,tinyTargets:tiny
      });
      await ctx.close();
    }
  }

  const failures=rows.filter(r=>
    r.status!==200||r.overflow>2||r.pageErrors.length||r.badResponses.length||
    r.tinyTargets.length||r.brandSettleMs>5000||!r.title.includes(BRAND)
  );
  console.log(JSON.stringify({ok:failures.length===0,base:BASE,brand:BRAND,rows,failures},null,2));
  if(failures.length) process.exit(1);
  console.log('BATCH5_CROSS_SURFACE_BROWSER_GATE_PASS=1');
}finally{
  await browser.close();
}
