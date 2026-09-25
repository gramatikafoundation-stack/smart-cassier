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
const { default: ocrWorkerHandler } = await import('../api/ocr-worker.js');
const { default: runtimeLifecycleHandler } = await import('../lib/runtime-lifecycle.js');

const PORT=4177,ORIGIN=`http://127.0.0.1:${PORT}`;
const RUM='https://xrepmvbccalzhlcznrff.supabase.co/functions/v1/rohmat-public-element-runtime-v64';
const fail=m=>{throw new Error(m)},sleep=ms=>new Promise(r=>setTimeout(r,ms));

function server(){return http.createServer((req,res)=>{const path=(req.url||'').split('?')[0];const fn=path==='/ocr-worker.js'?ocrWorkerHandler:path==='/runtime-lifecycle.js'?runtimeLifecycleHandler:handler;Promise.resolve(fn(req,res)).catch(e=>{console.error('LOCAL_HANDLER_ERROR',e);if(!res.headersSent)res.statusCode=500;if(!res.writableEnded)res.end('handler error')})})}

async function receipt(browser,merchant,amount){
  const p=await browser.newPage({viewport:{width:1000,height:720}}),now=new Date();
  const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Jakarta',day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(now),g=t=>parts.find(x=>x.type===t)?.value||'';
  const date=`${g('day')}/${g('month')}/${g('year')}`,time=`${g('hour')}:${g('minute')}`;
  await p.setContent(`<!doctype html><style>html,body{margin:0;background:#fff;color:#000;font-family:Arial,sans-serif}.r{width:1000px;height:720px;padding:60px 72px;box-sizing:border-box}.b{font-size:52px;font-weight:900;margin-bottom:36px}.l{font-size:40px;font-weight:800;line-height:1.55;letter-spacing:.3px}.t{font-size:54px;font-weight:900;margin-top:32px;border-top:5px solid #111;padding-top:24px}</style><div class=r><div class=b>${merchant.replace(/[&<>"']/g,' ')}</div><div class=l>TANGGAL ${date}</div><div class=l>WAKTU ${time} WIB</div><div class=l>PEMBAYARAN QRIS BERHASIL</div><div class=t>TOTAL BAYAR RP ${amount}</div></div>`);
  const b=await p.screenshot({type:'png'});await p.close();return {buffer:b,date,time};
}

async function checkout(page){
  const r=await page.goto(ORIGIN,{waitUntil:'domcontentloaded',timeout:30000});if(!r||r.status()!==200)fail('http_'+r?.status());
  const h=r.headers(),csp=String(h['content-security-policy']||'');
  if(!csp.includes("'wasm-unsafe-eval'"))fail('page_csp_missing_wasm');
  if(h['x-rohmat-public-ocr-target']!=='verification<5s')fail('ocr_target_missing');
  await page.waitForSelector('#next',{timeout:15000});
  await page.evaluate(()=>{const x=document.querySelector('input[name="mode"][value="take-away"]')||document.querySelector('input[value="take-away"]');if(!x)throw Error('takeaway_missing');x.checked=true;x.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.locator('#next').click();await page.waitForSelector('.grid [data-id][data-a="+"]',{timeout:15000});await page.locator('.grid [data-id][data-a="+"]').first().click();
  await page.waitForSelector('#confirm:not(.hidden)',{timeout:5000});await page.locator('#confirm').click();
  await page.waitForSelector('#name',{timeout:5000});await page.locator('#name').fill('OCR TEST');await sleep(900);await page.locator('#pay').click();
  await page.waitForSelector('#proof',{timeout:7000});await page.waitForSelector('#ocrReview',{timeout:7000});
}

async function snapshot(page){return page.evaluate(()=>({verificationState:document.getElementById('ocrReview')?.dataset.verificationState||'',verificationPassed:document.getElementById('ocrReview')?.dataset.verificationPassed||'0',progress:document.getElementById('ocrProgress')?.textContent||'',proofDisabled:document.getElementById('proof')?.disabled===true,sendDisabled:document.getElementById('send')?.disabled===true,checks:[...document.querySelectorAll('#ocrChecks .ocrStrongItem')].map(x=>x.textContent.trim())}))}

async function upload(page,buf,label){
  const input=page.locator('#proof');await input.setInputFiles([]);const started=Date.now();await input.setInputFiles({name:`receipt-${label}.png`,mimeType:'image/png',buffer:buf});
  await page.waitForFunction(()=>{const r=document.getElementById('ocrReview'),p=document.getElementById('ocrProgress')?.textContent||'';return r?.dataset.verificationState==='done'&&(r?.dataset.verificationPassed==='1'||/belum dapat diverifikasi|Verifikasi belum berhasil/i.test(p))},null,{timeout:5000,polling:20});
  const elapsed=Date.now()-started,s=await snapshot(page);console.log('OCR_MEASUREMENT',JSON.stringify({label,elapsed_ms:elapsed,...s}));
  if(elapsed>=5000)fail(`${label}_over_5s:${elapsed}`);if(s.verificationState!=='done')fail(`${label}_not_done`);if(s.verificationPassed!=='1')fail(`${label}_not_passed:${JSON.stringify(s)}`);if(s.proofDisabled)fail(`${label}_proof_disabled`);return elapsed;
}

async function main(){
  const srv=server();await new Promise((ok,no)=>{srv.once('error',no);srv.listen(PORT,'127.0.0.1',ok)});const browser=await chromium.launch(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{headless:true,executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{headless:true});
  try{const ctx=await browser.newContext({viewport:{width:1280,height:900},locale:'id-ID'}),page=await ctx.newPage(),errors=[],workerResponses=[];
    page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push('console:'+m.text())});
    page.on('response',r=>{if(r.url().includes('/ocr-worker.js'))workerResponses.push({status:r.status(),contentType:r.headers()['content-type'],csp:r.headers()['content-security-policy'],worker:r.headers()['x-rohmat-ocr-worker']})});
    await page.route(url=>url.toString().startsWith(RUM),async route=>route.request().method()==='POST'?route.fulfill({status:204,headers:{'access-control-allow-origin':ORIGIN}}):route.continue());
    await checkout(page);const merchant=(await page.locator('.payroom h3').textContent()||'').trim(),amount=Number((await page.locator('.orderTotalV36 b').textContent()||'').replace(/\D/g,''));if(!merchant||!Number.isFinite(amount)||amount<1000)fail(`context_invalid:${merchant}:${amount}`);
    const proof=await receipt(browser,merchant,amount);await sleep(1800);const first=await upload(page,proof.buffer,'prewarmed');await sleep(250);const second=await upload(page,proof.buffer,'warm-reuse');
    if(errors.length)fail('browser_errors:'+errors.join('|'));if(!workerResponses.length)fail('worker_not_requested');const w=workerResponses.at(-1);if(w.status!==200||!String(w.csp||'').includes("'wasm-unsafe-eval'")||!String(w.worker||'').includes('tesseract7'))fail('worker_contract:'+JSON.stringify(w));
    console.log(JSON.stringify({ok:true,merchant,amount,receipt_date:proof.date,receipt_time:proof.time,runs_ms:[first,second],max_ms:Math.max(first,second),under_5s:first<5000&&second<5000,page_errors:errors.length,worker:w},null,2));console.log('PUBLIC_OCR_BROWSER_GATE_PASS=1');await ctx.close();
  }finally{await browser.close();await new Promise(r=>srv.close(r))}
}
main().catch(e=>{console.error(e);process.exit(1)});
