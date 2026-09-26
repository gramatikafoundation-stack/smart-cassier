import fs from 'node:fs';
import { chromium } from 'playwright';

const ROOT=new URL('../../../',import.meta.url).pathname.replace(/^\/(?:[A-Za-z]:)/,m=>m.slice(1));
const TS=fs.readFileSync(ROOT+'supabase/functions/rohmat-public-element-runtime-v64/index.ts','utf8');
const MIG=fs.readFileSync(ROOT+'supabase/migrations/20260917184346_extend_public_rum_performance_metrics_b2.sql','utf8');
const ENDPOINT='https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-public-element-runtime-v64';
const fail=m=>{throw new Error(m)};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const match=TS.match(/const RUM_V3=String\.raw`([\s\S]*?)`;\r?\n\r?\nfunction stripProof/);
if(!match)fail('rum_v3_block_missing');
const rumScript=match[1].replaceAll('__SDB_RUM_ENDPOINT__',ENDPOINT);
for(const marker of ['rum-v3-20260918-b2','RUNTIME=\'v57\'','LONGTASK','OCRMS','OCRFAIL','performance-observer-v1','ocr-runtime-v1','rowStage','rowViewport','v3-stage-aware'])if(!TS.includes(marker))fail('source_marker_missing:'+marker);
for(const metric of ['LONGTASK','OCRMS','OCRFAIL'])if(!MIG.includes("'"+metric+"'"))fail('migration_metric_missing:'+metric);

const metricMap=p=>Object.fromEntries((p.metrics||[]).map(x=>[x.metric,x]));
const browser=await chromium.launch({headless:true});
try{
  const page=await browser.newPage({viewport:{width:1280,height:900}}),payloads=[];
  await page.route(ENDPOINT,async route=>{if(route.request().method()==='POST'){try{payloads.push(JSON.parse(route.request().postData()||'{}'))}catch{}return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}})}return route.fulfill({status:200,body:''})});
  await page.setContent('<main class="hero"><section class="welcome"><input id="pii" value="SECRET-08123456789"><button id="homeBtn">Home</button></section></main>');
  await page.evaluate(()=>{try{Object.defineProperty(navigator,'sendBeacon',{value:undefined,configurable:true})}catch{}window.__wv={};window.webVitals={onCLS:f=>window.__wv.CLS=f,onFCP:f=>window.__wv.FCP=f,onINP:f=>window.__wv.INP=f,onLCP:f=>window.__wv.LCP=f,onTTFB:f=>window.__wv.TTFB=f}});
  await page.addScriptTag({content:rumScript});
  await page.waitForFunction(()=>document.documentElement.dataset.rohmatRum==='v3-stage-aware');
  await page.evaluate(()=>{window.__wv.TTFB({name:'TTFB',value:120,entries:[]});window.__wv.FCP({name:'FCP',value:360,entries:[]});window.__wv.LCP({name:'LCP',value:520,entries:[]});window.__wv.CLS({name:'CLS',value:.02,entries:[]})});
  await page.evaluate(()=>{document.body.innerHTML='<div class="grid"><button id="menuBtn">Tambah</button></div>';window.__wv.INP({name:'INP',value:128,entries:[{target:document.getElementById('menuBtn')}]})});
  await page.evaluate(()=>new Promise(resolve=>setTimeout(()=>{const end=performance.now()+110;while(performance.now()<end){Math.sqrt(144)}resolve()},0)));
  await sleep(220);
  await page.evaluate(()=>{document.body.innerHTML='<div class="checkout"><input id="name" value="SECRET NAME"><div id="proof">SECRET PROOF OCR TEXT</div></div>';document.dispatchEvent(new CustomEvent('rohmat:ocr-metric',{detail:{duration:2380,status:'success'}}))});
  await sleep(250);
  await page.evaluate(()=>window.dispatchEvent(new Event('error')));
  await sleep(250);
  await page.evaluate(()=>document.dispatchEvent(new CustomEvent('rohmat:ocr-metric',{detail:{duration:4700,status:'timeout'}})));
  await sleep(350);
  if(!payloads.length)fail('no_rum_payload');
  const last=payloads.at(-1),metrics=metricMap(last);
  for(const k of ['VIEW','TTFB','FCP','LCP','CLS','INP','LONGTASK','OCRMS','OCRFAIL','JSERR'])if(!metrics[k])fail('metric_missing:'+k+':'+JSON.stringify(last));
  for(const k of ['TTFB','FCP','LCP','VIEW'])if(metrics[k].stage!=='home')fail(k+'_stage_'+metrics[k].stage);
  if(metrics.INP.stage!=='menu')fail('inp_stage_'+metrics.INP.stage);
  if(metrics.OCRMS.stage!=='checkout'||metrics.OCRFAIL.stage!=='checkout')fail('ocr_stage_invalid');
  if(!['home','menu','checkout','success'].includes(metrics.LONGTASK.stage)||metrics.LONGTASK.source!=='performance-observer-v1')fail('longtask_attribution_'+JSON.stringify(metrics.LONGTASK));
  if(metrics.OCRMS.value<4600||metrics.OCRFAIL.value!==1)fail('ocr_failure_metrics_invalid');
  if(last.release!=='rum-v3-20260918-b2'||last.runtime!=='v57')fail('release_runtime_invalid');
  const raw=JSON.stringify(payloads);
  for(const secret of ['SECRET-08123456789','SECRET NAME','SECRET PROOF OCR TEXT'])if(raw.includes(secret))fail('pii_leak:'+secret);
  for(const x of Object.values(metrics)){if(!['mobile','tablet','desktop'].includes(x.viewportClass))fail('viewport_invalid:'+JSON.stringify(x));if(!x.source)fail('source_missing:'+JSON.stringify(x))}
  console.log(JSON.stringify({ok:true,payload_count:payloads.length,release:last.release,runtime:last.runtime,metrics:Object.fromEntries(Object.entries(metrics).map(([k,v])=>[k,{value:v.value,stage:v.stage,source:v.source,viewportClass:v.viewportClass}])),pii_leak:false},null,2));
  console.log('PUBLIC_RUM_V3_GATE_PASS=1');
}finally{await browser.close()}
