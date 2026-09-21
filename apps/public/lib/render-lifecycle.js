import baseHandler from './render-runtime-architecture.js';

const LOCAL_RUNTIME = '/runtime-lifecycle.js';
const RUNTIME_PATH = '/functions/v1/rohmat-public-element-runtime-v64';

function parseTenantRuntime(tag) {
  const src = tag.match(/\bsrc=["']([^"']+)["']/i)?.[1] || '';
  const u = new URL(src);
  if (u.protocol !== 'https:' || !u.hostname.endsWith('.supabase.co') || u.pathname !== RUNTIME_PATH || u.username || u.password) {
    throw new Error('lifecycle_invalid_tenant_runtime');
  }
  return u;
}

function replaceRequired(source, from, to, label, flags) {
  const count = source.split(from).length - 1;
  if (count !== 1) throw new Error(`lifecycle_marker_${label}_${count}`);
  flags.push(label);
  return source.replace(from, to);
}

function rewriteExternalRuntime(html, flags) {
  const tagRe = /<script\b[^>]*\bid=["']rohmat-public-element-runtime-v64["'][^>]*><\/script>/i;
  const match = html.match(tagRe);
  if (!match) throw new Error('lifecycle_marker_external_runtime');
  const upstream = parseTenantRuntime(match[0]);
  const local = LOCAL_RUNTIME + '?upstream=' + encodeURIComponent(upstream.href);
  const tag = match[0]
    .replace(/\bsrc=["'][^"']+["']/i, 'src="' + local + '"')
    .replace('rohmat-public-element-runtime-v64', 'rohmat-public-element-runtime-v65');
  flags.push('runtime-v65-same-origin');
  return { html: html.replace(match[0], tag), upstream };
}

function optimizeLifecycle(html) {
  const flags = [];
  const rewritten = rewriteExternalRuntime(html, flags);
  let out = rewritten.html;
  const qrisDownload = rewritten.upstream.origin + '/functions/v1/rohmat-qris-download';

  out = replaceRequired(
    out,
    "const PROFILE='rohmat-customer-history-v1',DOWNLOAD='" + qrisDownload + "';let scheduled=false;",
    "const PROFILE='rohmat-customer-history-v1',DOWNLOAD='" + qrisDownload + "';let scheduled=false,sendGuardObserver=null,sendGuardTarget=null;function clearSendGuard(){try{sendGuardObserver?.disconnect()}catch{}sendGuardObserver=null;sendGuardTarget=null}",
    'send-guard-owner', flags
  );
  out = replaceRequired(
    out,
    "function paymentState(){const pay=document.querySelector('.payroom');if(!pay)return;",
    "function paymentState(){const pay=document.querySelector('.payroom');if(!pay){clearSendGuard();return;}",
    'send-guard-detach', flags
  );
  out = replaceRequired(
    out,
    "if(send){send.disabled=true;if(!send.dataset.qrisCleanGuard){send.dataset.qrisCleanGuard='1';new MutationObserver(()=>{if(!document.querySelector('.qrisbox img')&&!send.disabled)send.disabled=true}).observe(send,{attributes:true,attributeFilter:['disabled']})}}",
    "if(send){send.disabled=true;if(sendGuardTarget!==send){clearSendGuard();sendGuardTarget=send;send.dataset.qrisCleanGuard='1';sendGuardObserver=new MutationObserver(()=>{if(document.body.contains(send)&&!document.querySelector('.qrisbox img')&&!send.disabled)send.disabled=true});sendGuardObserver.observe(send,{attributes:true,attributeFilter:['disabled']})}}else clearSendGuard()",
    'send-guard-rebind', flags
  );
  out = replaceRequired(
    out,
    "}else if(n)n.remove()}\nfunction patch(){scheduled=false;bindHistory();cleanProof();cleanDownload();paymentState()}",
    "}else{clearSendGuard();if(n)n.remove()}}\nfunction patch(){scheduled=false;bindHistory();cleanProof();cleanDownload();paymentState()}",
    'send-guard-ready-cleanup', flags
  );
  out = replaceRequired(
    out,
    "document.addEventListener('rohmat:dom-updated',schedule);/* identity-v4 owns debounced input persistence */document.addEventListener('click',e=>{if(e.target.closest('#confirm,#pay'))setTimeout(schedule,0)},{capture:true});patch();",
    "document.addEventListener('rohmat:dom-updated',schedule);/* identity-v4 owns debounced input persistence */document.addEventListener('click',e=>{if(e.target.closest('#backm'))clearSendGuard();if(e.target.closest('#confirm,#pay'))setTimeout(schedule,0)},{capture:true});window.addEventListener('pagehide',clearSendGuard);window.addEventListener('pageshow',schedule);patch();",
    'send-guard-pagehide', flags
  );
  out = replaceRequired(
    out,
    "window.addEventListener('pagehide',()=>{ocrRunSeq++;resetOcrWorker()},{once:true});patch();",
    "window.addEventListener('pagehide',()=>{ocrRunSeq++;resetOcrWorker()});window.addEventListener('pageshow',()=>{patch();if(document.getElementById('proof'))queueOcrWarm(false)});patch();",
    'ocr-bfcache-rearm', flags
  );
  out = replaceRequired(
    out,
    "window.addEventListener('pageshow',()=>{checkExpiry();schedulePayment()});document.addEventListener('visibilitychange',()=>{if(!document.hidden)checkExpiry()});setInterval(()=>{if(!document.hidden)checkExpiry()},60000);schedulePayment();})();",
    "let expiryTimer=0;function stopExpiryTimer(){clearTimeout(expiryTimer);expiryTimer=0}function armExpiryTimer(){stopExpiryTimer();if(document.hidden)return;expiryTimer=setTimeout(()=>{expiryTimer=0;if(!document.hidden)checkExpiry();armExpiryTimer()},60000)}window.addEventListener('pageshow',()=>{checkExpiry();schedulePayment();armExpiryTimer()});document.addEventListener('visibilitychange',()=>{if(document.hidden)stopExpiryTimer();else{checkExpiry();armExpiryTimer()}});window.addEventListener('pagehide',stopExpiryTimer);armExpiryTimer();schedulePayment();})();",
    'expiry-timer-pause-resume', flags
  );
  out = replaceRequired(
    out,
    "let startedAt=0,watch=null,watchTarget=null;\nfunction setText",
    "let startedAt=0,watch=null,watchTarget=null;function clearVerificationWatch(){try{watch?.disconnect()}catch{}watch=null;watchTarget=null}\nfunction setText",
    'verification-observer-owner', flags
  );
  out = replaceRequired(
    out,
    "if(!review)return null;let title=review.querySelector(':scope > b');",
    "if(!review){clearVerificationWatch();return null}let title=review.querySelector(':scope > b');",
    'verification-observer-detach', flags
  );
  out = replaceRequired(
    out,
    "if(watchTarget!==o.review){try{watch?.disconnect()}catch{}watchTarget=o.review;watch=new MutationObserver(()=>queueMicrotask(()=>apply(o.progress.textContent)));watch.observe(o.review,{childList:true,subtree:true,characterData:true})}",
    "if(watchTarget!==o.review){clearVerificationWatch();watchTarget=o.review;watch=new MutationObserver(()=>queueMicrotask(()=>apply(o.progress.textContent)));watch.observe(o.review,{childList:true,subtree:true,characterData:true})}",
    'verification-observer-rebind', flags
  );
  out = replaceRequired(
    out,
    "document.addEventListener('click',e=>{if(e.target.closest('#pay'))setTimeout(bind,0);if(e.target.closest('#send')&&document.getElementById('ocrReview')?.dataset.verificationPassed!=='1'){e.preventDefault();e.stopImmediatePropagation();bind()}},true);",
    "document.addEventListener('click',e=>{if(e.target.closest('#backm'))clearVerificationWatch();if(e.target.closest('#pay'))setTimeout(bind,0);if(e.target.closest('#send')&&document.getElementById('ocrReview')?.dataset.verificationPassed!=='1'){e.preventDefault();e.stopImmediatePropagation();bind()}},true);",
    'verification-observer-exit', flags
  );
  out = replaceRequired(
    out,
    "document.addEventListener('rohmat:dom-updated',()=>requestAnimationFrame(bind));\nbind();",
    "document.addEventListener('rohmat:dom-updated',()=>requestAnimationFrame(bind));window.addEventListener('pagehide',clearVerificationWatch);window.addEventListener('pageshow',bind);\nbind();",
    'verification-observer-bfcache', flags
  );

  if (out.includes('setInterval(()=>{if(!document.hidden)checkExpiry()},60000)')) throw new Error('expiry_interval_remains');
  if (out.includes("pagehide',()=>{ocrRunSeq++;resetOcrWorker()},{once:true}")) throw new Error('ocr_once_pagehide_remains');
  if (!out.includes('clearSendGuard') || !out.includes('clearVerificationWatch') || !out.includes('stopExpiryTimer') || !out.includes(LOCAL_RUNTIME)) throw new Error('lifecycle_validation_failed');
  return { html: out, flags };
}

export default async function handler(req, res) {
  const end = res.end.bind(res);
  res.end = (body, ...args) => {
    if (res.statusCode === 200 && typeof body === 'string' && body.includes('rohmat-public-a11y-v3')) {
      try {
        const optimized = optimizeLifecycle(body);
        body = optimized.html;
        res.setHeader('X-Rohmat-Public-Lifecycle', 'v1');
        res.setHeader('X-Rohmat-Public-Lifecycle-Scope', optimized.flags.join(','));
      } catch (error) {
        res.setHeader('X-Rohmat-Public-Lifecycle', `baseline-mismatch:${String(error?.message || error).slice(0,120)}`);
      }
    }
    return end(body, ...args);
  };
  return baseHandler(req, res);
}
