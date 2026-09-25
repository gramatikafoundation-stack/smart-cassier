import baseHandler from './render.js';

const OCR_EAGER = "function patch(){bindProof();warmOcrFast()}";
const OCR_CONTEXT_WARM = "let ocrIdleWarmQueued=false,ocrIdleWarmHandle=0;function queueOcrWarm(immediate=false){const fire=()=>{ocrIdleWarmQueued=false;ocrIdleWarmHandle=0;if(!busy)warmOcrFast()};if(worker||workerPromise||ocrWarmStarted)return;if(immediate){if(ocrIdleWarmQueued){try{if('cancelIdleCallback'in window&&ocrIdleWarmHandle)cancelIdleCallback(ocrIdleWarmHandle);else clearTimeout(ocrIdleWarmHandle)}catch{}ocrIdleWarmQueued=false;ocrIdleWarmHandle=0}fire();return}if(ocrIdleWarmQueued)return;ocrIdleWarmQueued=true;if('requestIdleCallback'in window)ocrIdleWarmHandle=requestIdleCallback(fire,{timeout:650});else ocrIdleWarmHandle=setTimeout(fire,120)}function patch(){bindProof();if(document.getElementById('proof'))queueOcrWarm(true)}";
const OCR_STATE_OLD = "let strongText='',busy=false,patchedInput=null,worker=null,workerPromise=null,scriptPromise=null;";
const OCR_STATE_NEW = "let strongText='',busy=false,patchedInput=null,worker=null,workerPromise=null,scriptPromise=null,workerEpoch=0,workerIdleTimer=0,ocrQueuedFile=null,ocrRunSeq=0;";
const OCR_LOADER_OLD = "const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js';";
const OCR_LOADER_NEW = "const s=document.createElement('script');s.dataset.rohmatOcrLoader='1';s.src='https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/tesseract.min.js';";
const OCR_ERROR_OLD = "s.onerror=()=>no(Error('Mesin OCR gagal dimuat.'));document.head.appendChild(s)";
const OCR_ERROR_NEW = "s.onerror=()=>{scriptPromise=null;s.remove();no(Error('Mesin OCR gagal dimuat.'))};document.head.appendChild(s)";
const OCR_WORKER_OLD = "async function getWorker(){if(worker)return worker;if(workerPromise)return workerPromise;const T=await ensureT();if(!T.createWorker)return null;workerPromise=T.createWorker('eng').then(async w=>{try{await w.setParameters({tessedit_pageseg_mode:'11',preserve_interword_spaces:'1',user_defined_dpi:'150'})}catch{}worker=w;return w}).finally(()=>{workerPromise=null});return workerPromise}";
const OCR_WORKER_NEW = "async function resetOcrWorker(){workerEpoch++;clearTimeout(workerIdleTimer);workerIdleTimer=0;const w=worker;worker=null;workerPromise=null;ocrWarmStarted=false;if(w)Promise.resolve(w.terminate()).catch(()=>{})}function keepOcrWorkerWarm(ms=90000){clearTimeout(workerIdleTimer);workerIdleTimer=0;if(!worker)return;workerIdleTimer=setTimeout(()=>{if(!busy)resetOcrWorker()},ms)}async function getWorker(){if(worker){clearTimeout(workerIdleTimer);workerIdleTimer=0;return worker}if(workerPromise)return workerPromise;const T=await ensureT();if(!T.createWorker)return null;const epoch=workerEpoch;workerPromise=(async()=>{const w=await T.createWorker('eng',1,{workerPath:location.origin+'/ocr-worker.js',workerBlobURL:false});if(epoch!==workerEpoch){Promise.resolve(w.terminate()).catch(()=>{});throw Error('OCR_WORKER_STALE')}try{await w.setParameters({tessedit_pageseg_mode:'11',preserve_interword_spaces:'1',user_defined_dpi:'150'})}catch{}if(epoch!==workerEpoch){Promise.resolve(w.terminate()).catch(()=>{});throw Error('OCR_WORKER_STALE')}worker=w;return w})();try{return await workerPromise}finally{workerPromise=null}}";
const OCR_LIMITS_OLD = "const OCR_SOFT_TARGET_MS=4000,OCR_FALLBACK_TARGET_MS=4500,OCR_HARD_DEADLINE_MS=4950;let ocrWarmStarted=false;";
const OCR_LIMITS_NEW = "const OCR_SOFT_TARGET_MS=3400,OCR_FALLBACK_TARGET_MS=4100,OCR_HARD_DEADLINE_MS=4700;let ocrWarmStarted=false;";
const OCR_WARM_OLD = "async function warmOcrFast(){if(ocrWarmStarted)return;ocrWarmStarted=true;try{await getWorker()}catch{ocrWarmStarted=false}}";
const OCR_WARM_NEW = "async function warmOcrFast(){if(worker||workerPromise||ocrWarmStarted)return;ocrWarmStarted=true;try{await getWorker();keepOcrWorkerWarm(90000)}catch{ocrWarmStarted=false}}";
const OCR_TIMEOUT_FN_OLD = "function ocrTimeout(ms){return new Promise((_,no)=>setTimeout(()=>no(new Error('OCR_FAST_TIMEOUT')),ms))}";
const OCR_TIMEOUT_FN_NEW = "function ocrDeadline(task,ms){let timer=0;return Promise.race([task,new Promise((_,no)=>{timer=setTimeout(()=>no(new Error('OCR_FAST_TIMEOUT')),ms)})]).finally(()=>clearTimeout(timer))}";
const OCR_IMAGE_OLD = "const b=await createImageBitmap(file),max=1080,sc=Math.min(1,max/Math.max(b.width,b.height))";
const OCR_IMAGE_NEW = "const b=await createImageBitmap(file),max=960,sc=Math.min(1,max/Math.max(b.width,b.height))";
const OCR_RUN_OLD = "async function run(file){if(!file||busy)return;busy=true;strongText='';";
const OCR_RUN_NEW = "async function run(file){if(!file)return;if(busy){ocrQueuedFile=file;return}busy=true;ocrQueuedFile=null;const runSeq=++ocrRunSeq,ocrMetricStart=performance.now();let ocrMetricStatus='error';strongText='';";
const OCR_RACE_OLD = "const text=String(await Promise.race([task,ocrTimeout(OCR_HARD_DEADLINE_MS)])||'');if(!text.trim())throw Error('OCR_EMPTY_TEXT');strongText=text.slice(0,7800);";
const OCR_RACE_NEW = "const text=String(await ocrDeadline(task,OCR_HARD_DEADLINE_MS)||'');if(runSeq!==ocrRunSeq)throw Error('OCR_STALE_RESULT');if(!text.trim())throw Error('OCR_EMPTY_TEXT');strongText=text.slice(0,7800);";
const OCR_SUCCESS_OLD = "const z=analyse(text);draw(z);const elapsed=Math.max(0,performance.now()-started);";
const OCR_SUCCESS_NEW = "const z=analyse(text);draw(z);ocrMetricStatus='success';const elapsed=Math.max(0,performance.now()-started);";
const OCR_CATCH_OLD = "catch(e){const timeout=String(e?.message||e).includes('OCR_FAST_TIMEOUT');";
const OCR_CATCH_NEW = "catch(e){const timeout=String(e?.message||e).includes('OCR_FAST_TIMEOUT');ocrMetricStatus=timeout?'timeout':'error';";
const OCR_RESET_OLD = "if(worker){try{await worker.terminate()}catch{}worker=null}ocrWarmStarted=false;";
const OCR_RESET_NEW = "resetOcrWorker();if(timeout){scriptPromise=null;document.querySelector('script[data-rohmat-ocr-loader=\"1\"]')?.remove()}";
const OCR_FINALLY_OLD = "finally{clearTimeout(softTimer);clearTimeout(fallbackTimer);busy=false;if(proof){proof.disabled=false;proof.removeAttribute('aria-busy')}}";
const OCR_FINALLY_NEW = "finally{clearTimeout(softTimer);clearTimeout(fallbackTimer);try{document.dispatchEvent(new CustomEvent('rohmat:ocr-metric',{detail:{duration:Math.max(0,performance.now()-ocrMetricStart),status:ocrMetricStatus}}))}catch{}busy=false;if(proof){proof.disabled=false;proof.removeAttribute('aria-busy')}keepOcrWorkerWarm(90000);const next=ocrQueuedFile;ocrQueuedFile=null;if(next)setTimeout(()=>run(next),0)}";
const OCR_HOOK_OLD = "document.addEventListener('rohmat:dom-updated',()=>requestAnimationFrame(patch));document.addEventListener('click',e=>{if(e.target.closest('#pay'))setTimeout(patch,0)},{capture:true});patch();";
const OCR_HOOK_NEW = "document.addEventListener('rohmat:dom-updated',()=>requestAnimationFrame(patch));document.addEventListener('click',e=>{if(e.target.closest('#next'))queueOcrWarm(false);if(e.target.closest('#confirm'))queueOcrWarm(true);if(e.target.closest('#pay')){queueOcrWarm(true);setTimeout(patch,0)}if(e.target.closest('#backm'))keepOcrWorkerWarm(15000)},{capture:true});window.addEventListener('pagehide',()=>{ocrRunSeq++;resetOcrWorker()},{once:true});patch();";
const PAYMENT_TIMERS = "function schedulePayment(){setTimeout(payment,0);setTimeout(payment,120);setTimeout(payment,380);setTimeout(payment,980);setTimeout(payment,1500)}";
const PAYMENT_RAF = "let paymentQueued=false;function schedulePayment(){if(paymentQueued)return;paymentQueued=true;requestAnimationFrame(()=>{paymentQueued=false;payment()})}";
const PAYMENT_DOM_TIMER = "document.addEventListener('rohmat:dom-updated',()=>{setTimeout(payment,20);const s=read();";
const PAYMENT_DOM_RAF = "document.addEventListener('rohmat:dom-updated',()=>{schedulePayment();const s=read();";
const PAYMENT_RESIZE_TIMER = "window.addEventListener('resize',()=>setTimeout(payment,80));";
const PAYMENT_RESIZE_RAF = "window.addEventListener('resize',schedulePayment);";
const REDUNDANT_IDENTITY_INPUT = "document.addEventListener('input',e=>{const t=e.target;if(t&&((t.id==='name')||(t.id==='wa'))){const n=document.getElementById('name')?.value.trim()||'',w=document.getElementById('wa')?.value.trim()||'';if(n)writeProfile({name:n,wa:w})}},true);";
const UI_YIELD_HELPER_OLD = "function go(r){route=r;render()}function home(){";
const UI_YIELD_HELPER_NEW = "function afterInteraction(fn){requestAnimationFrame(()=>requestAnimationFrame(()=>setTimeout(fn,0)))}function go(r){route=r;render()}function home(){";
const NEXT_ROUTE_OLD = "go('menu')}}function cards(){";
const NEXT_ROUTE_NEW = "afterInteraction(()=>go('menu'))}}function cards(){";
const PAY_ROUTE_OLD = "checkoutSnapshot=confirmed.map(i=>Object.assign({},i));save();d.close();go('checkout')};d.classList.add('user-open');";
const PAY_ROUTE_NEW = "checkoutSnapshot=confirmed.map(i=>Object.assign({},i));save();afterInteraction(()=>{d.close();go('checkout')})};d.classList.add('user-open');";
const CONFIRM_ROUTE_START_OLD = "if(cf)cf.onclick=()=>{let d=document.getElementById('dlg');";
const CONFIRM_ROUTE_START_NEW = "if(cf)cf.onclick=()=>afterInteraction(()=>{let d=document.getElementById('dlg');";
const CONFIRM_ROUTE_END_OLD = "d.classList.add('user-open');d.showModal()}}function checkout(){";
const CONFIRM_ROUTE_END_NEW = "d.classList.add('user-open');d.showModal()})}function checkout(){";
const BACK_ROUTE_OLD = "document.getElementById('backm').onclick=()=>{checkoutSnapshot=null;go('menu')};";
const BACK_ROUTE_NEW = "document.getElementById('backm').onclick=()=>{checkoutSnapshot=null;afterInteraction(()=>go('menu'))};";
const OCR_PRECONNECT = '<link id="rohmat-ocr-cdn-preconnect-v1" rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin><link id="rohmat-ocr-lang-preconnect-v1" rel="preconnect" href="https://tessdata.projectnaptha.com" crossorigin>';

function replaceOnce(html, from, to, flag, flags) {
  const count = html.split(from).length - 1;
  if (count !== 1) return html;
  flags.push(flag);
  return html.replace(from, to);
}

function optimizeInp(html) {
  const flags = [];
  let out = html;
  out = replaceOnce(out, OCR_EAGER, OCR_CONTEXT_WARM, 'ocr-context-prewarm', flags);
  out = replaceOnce(out, OCR_STATE_OLD, OCR_STATE_NEW, 'ocr-worker-epoch-state', flags);
  out = replaceOnce(out, OCR_LOADER_OLD, OCR_LOADER_NEW, 'ocr-loader-v7-tracked', flags);
  out = replaceOnce(out, OCR_ERROR_OLD, OCR_ERROR_NEW, 'ocr-loader-retry-on-error', flags);
  out = replaceOnce(out, OCR_WORKER_OLD, OCR_WORKER_NEW, 'ocr-same-origin-worker', flags);
  out = replaceOnce(out, OCR_LIMITS_OLD, OCR_LIMITS_NEW, 'ocr-hard-deadline-4.7s', flags);
  out = replaceOnce(out, OCR_WARM_OLD, OCR_WARM_NEW, 'ocr-worker-reuse-90s', flags);
  out = replaceOnce(out, OCR_TIMEOUT_FN_OLD, OCR_TIMEOUT_FN_NEW, 'ocr-deadline-timer-cleanup', flags);
  out = replaceOnce(out, OCR_IMAGE_OLD, OCR_IMAGE_NEW, 'ocr-image-cap-960', flags);
  out = replaceOnce(out, OCR_RUN_OLD, OCR_RUN_NEW, 'ocr-latest-file-queue', flags);
  out = replaceOnce(out, OCR_RACE_OLD, OCR_RACE_NEW, 'ocr-stale-result-guard', flags);
  out = replaceOnce(out, OCR_SUCCESS_OLD, OCR_SUCCESS_NEW, 'ocr-success-metric-status', flags);
  out = replaceOnce(out, OCR_CATCH_OLD, OCR_CATCH_NEW, 'ocr-error-metric-status', flags);
  out = replaceOnce(out, OCR_RESET_OLD, OCR_RESET_NEW, 'ocr-reset-generation-safe', flags);
  out = replaceOnce(out, OCR_FINALLY_OLD, OCR_FINALLY_NEW, 'ocr-worker-idle-cleanup', flags);
  out = replaceOnce(out, OCR_HOOK_OLD, OCR_HOOK_NEW, 'ocr-context-hooks-pagehide-cleanup', flags);
  out = replaceOnce(out, PAYMENT_TIMERS, PAYMENT_RAF, 'payment-raf-coalesced', flags);
  out = replaceOnce(out, PAYMENT_DOM_TIMER, PAYMENT_DOM_RAF, 'payment-dom-coalesced', flags);
  out = replaceOnce(out, PAYMENT_RESIZE_TIMER, PAYMENT_RESIZE_RAF, 'payment-resize-coalesced', flags);
  out = replaceOnce(out, REDUNDANT_IDENTITY_INPUT, '/* identity-v4 owns debounced input persistence */', 'identity-input-deduped', flags);
  out = replaceOnce(out, UI_YIELD_HELPER_OLD, UI_YIELD_HELPER_NEW, 'interaction-yield-helper', flags);
  out = replaceOnce(out, NEXT_ROUTE_OLD, NEXT_ROUTE_NEW, 'next-route-after-paint', flags);
  out = replaceOnce(out, PAY_ROUTE_OLD, PAY_ROUTE_NEW, 'pay-route-after-paint', flags);
  out = replaceOnce(out, CONFIRM_ROUTE_START_OLD, CONFIRM_ROUTE_START_NEW, 'confirm-route-after-paint-start', flags);
  out = replaceOnce(out, CONFIRM_ROUTE_END_OLD, CONFIRM_ROUTE_END_NEW, 'confirm-route-after-paint-end', flags);
  out = replaceOnce(out, BACK_ROUTE_OLD, BACK_ROUTE_NEW, 'back-route-after-paint', flags);
  if (!out.includes('rohmat-ocr-cdn-preconnect-v1')) {
    out = out.replace('</head>', `${OCR_PRECONNECT}</head>`);
    flags.push('ocr-cdn-preconnect');
  }
  return { html: out, flags };
}

export default async function handler(req, res) {
  const end = res.end.bind(res);
  res.end = (body, ...args) => {
    if (res.statusCode === 200 && typeof body === 'string' && body.includes('rohmat-ocr-smart-v6')) {
      const optimized = optimizeInp(body);
      body = optimized.html;
      res.setHeader('X-Rohmat-Public-INP', optimized.flags.join(',') || 'baseline');
      res.setHeader('X-Rohmat-Public-INP-Target', 'p75<=200ms');
      res.setHeader('X-Rohmat-Public-OCR', 'tesseract7,same-origin-worker,context-prewarm,worker-epoch-guard,latest-file-queue,stale-result-guard,image-cap-960,soft-3.4s,fallback-4.1s,hard-4.7s,idle-cleanup-90s,pagehide-cleanup');
      res.setHeader('X-Rohmat-Public-OCR-Target', 'verification<5s');
    }
    return end(body, ...args);
  };
  return baseHandler(req, res);
}
