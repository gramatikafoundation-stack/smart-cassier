import baseHandler from './render-runtime-architecture.js';

const LOCAL_RUNTIME = '/runtime-lifecycle.js';
const RUNTIME_PATH = '/functions/v1/rohmat-public-element-runtime-v64';

const PAYMENT_RUNTIME_CONST_OLD = "const LS='rohmat-public-v5',TTL=30*60*1000;const imp=";
const PAYMENT_BOOT_CONST_OLD = "id=\"rohmat-cart-expiry-boot-v72\">(()=>{'use strict';const LS='rohmat-public-v5',TTL=30*60*1000;try{";
const PAYMENT_BOOT_CONST_NEW = "id=\"rohmat-cart-expiry-boot-v72\">(()=>{'use strict';const LS='rohmat-public-v5',CART_TTL=30*60*1000,PAYMENT_TTL=5*60*1000;try{";
const PAYMENT_BOOT_EXPIRY_OLD = "const last=Number(s.lastActivityAt||0),started=s.orderStartedAt?Date.parse(s.orderStartedAt):0,anchor=Math.max(Number.isFinite(last)?last:0,Number.isFinite(started)?started:0);if(!anchor||Date.now()-anchor>=TTL){";
const PAYMENT_BOOT_EXPIRY_NEW = "const last=Number(s.lastActivityAt||0),started=s.orderStartedAt?Date.parse(s.orderStartedAt):0,expired=Number.isFinite(started)&&started>0?Date.now()-started>=PAYMENT_TTL:(!last||Date.now()-last>=CART_TTL);if(expired){";
const OCR_DATE_DMY_OLD = "([0-9OIlSB]{1,2})\\s*[\\/.-]\\s*([0-9OIlSB]{1,2})(?:\\s*[\\/.-]\\s*([0-9OIlSB]{2,4}))?";
const OCR_DATE_DMY_NEW = "([0-9OIlSBZG]{1,2})\\s*[\\/.-]\\s*([0-9OIlSBZG]{1,2})(?:\\s*[\\/.-]\\s*([0-9OIlSBZG]{2,4}))?";
const OCR_DATE_YMD_OLD = "([0-9OIlSB]{4})\\s*[\\/.-]\\s*([0-9OIlSB]{1,2})\\s*[\\/.-]\\s*([0-9OIlSB]{1,2})";
const OCR_DATE_YMD_NEW = "([0-9OIlSBZG]{4})\\s*[\\/.-]\\s*([0-9OIlSBZG]{1,2})\\s*[\\/.-]\\s*([0-9OIlSBZG]{1,2})";
const OCR_AMOUNT_DIGITS_OLD = "([0-9OIlSB][0-9OIlSB., \\t]{2,18})";
const OCR_AMOUNT_DIGITS_NEW = "([0-9OIlSBZG][0-9OIlSBZG., \\t]{2,18})";
const PAYMENT_RUNTIME_CONST_NEW = "const LS='rohmat-public-v5',CART_TTL=30*60*1000,PAYMENT_TTL=5*60*1000;const imp=";
const PAYMENT_EXPIRY_OLD = "function checkExpiry(){const s=read();if(!hasOrder(s))return;const last=Number(s.lastActivityAt||0),started=s.orderStartedAt?Date.parse(s.orderStartedAt):0,anchor=Math.max(Number.isFinite(last)?last:0,Number.isFinite(started)?started:0);if(!anchor||Date.now()-anchor>=TTL){clearOrder();location.reload()}}";
const PAYMENT_EXPIRY_NEW = "function checkExpiry(){const s=read();if(!hasOrder(s))return;const now=Date.now(),started=s.orderStartedAt?Date.parse(s.orderStartedAt):0;if(Number.isFinite(started)&&started>0){if(now-started>=PAYMENT_TTL){clearOrder();try{alert('Konfirmasi pembayaran telah kedaluwarsa karena melewati batas 5 menit. Silakan buat pesanan kembali.')}catch{}location.reload();return}}else{const last=Number(s.lastActivityAt||0);if(last&&now-last>=CART_TTL){clearOrder();location.reload()}}}";
const PAYMENT_PAYLOAD_OLD = "proofOcrText:'',paidAmount:null,createdAt:new Date().toISOString()";
const PAYMENT_PAYLOAD_NEW = "proofOcrText:'',paidAmount:null,paymentStartedAt:st.orderStartedAt||null,createdAt:new Date().toISOString()";
const OCR_DIGIT_OLD = "function digitFix(s){return String(s||'').replace(/[Oo]/g,'0').replace(/[Il|]/g,'1').replace(/[Ss]/g,'5').replace(/[Bb]/g,'8')}";
const OCR_DIGIT_NEW = "function digitFix(s){return String(s||'').replace(/[Oo]/g,'0').replace(/[Il|]/g,'1').replace(/[Ss]/g,'5').replace(/[Bb]/g,'8').replace(/[Zz]/g,'2').replace(/[Gg]/g,'6')}";
const OCR_MERCHANT_OLD = "function merchantScore(text,merchant){const stop=new Set(['dan','and','qr','qris','merchant','payment','pembayaran','store','toko']);const exp=[...new Set(norm(merchant).split(' ').filter(x=>x.length>=2&&!stop.has(x)))],lines=String(text||'').split(/\\r?\\n/).map(norm).filter(Boolean);if(!exp.length)return 0;let hits=0,phrase=0;const target=exp.join(' ');for(const x of exp){let best=0;for(const line of lines){for(const y of line.split(' '))best=Math.max(best,sim(x,y))}if(best>=(x.length>=6?.70:.78))hits++}for(const line of lines){const clean=line.split(' ').filter(x=>!stop.has(x)).join(' ');phrase=Math.max(phrase,sim(target,clean),clean.includes(target)?1:0)}const token=hits/exp.length;return Math.min(1,Math.max(token,phrase*.96,token>=.67?.84:0))}";
const OCR_MERCHANT_NEW = "function merchantScore(text,merchant){const stop=new Set(['dan','and','qr','qris','merchant','payment','pembayaran','store','toko']);const exp=[...new Set(norm(merchant).split(' ').filter(x=>x.length>=2&&!stop.has(x)))],lines=String(text||'').split(/\\r?\\n/).map(norm).filter(Boolean);if(!exp.length)return 0;let hits=0,phrase=0;const target=exp.join(' '),compact=target.replace(/\\s+/g,'');for(const x of exp){let best=0;for(const line of lines){for(const y of line.split(' '))best=Math.max(best,sim(x,y));const lc=line.replace(/\\s+/g,'');if(lc.includes(x))best=Math.max(best,.94)}if(best>=(x.length>=6?.68:.75))hits++}for(const line of lines){const clean=line.split(' ').filter(x=>!stop.has(x)).join(' '),lc=clean.replace(/\\s+/g,'');phrase=Math.max(phrase,sim(target,clean),clean.includes(target)?1:0,lc.includes(compact)?1:0)}const token=hits/exp.length;return Math.min(1,Math.max(token,phrase*.96,token>=.67?.84:0))}";
const OCR_ANALYSE_MERCHANT_OLD = "function analyse(text){const merchant=(document.querySelector('.payroom h3')?.textContent||'Rohmat Nasi Uduk').trim(),expected=";
const OCR_ANALYSE_MERCHANT_NEW = "function analyse(text){const merchant=String(window.__rohmatPublicConfigV25?.merchant_name||window.__rohmatPublicConfigV24?.merchant_name||document.querySelector('.payroom h3')?.textContent||'Rohmat Nasi Uduk').trim(),expected=";
const OCR_TIME_OLD = "function timeCandidates(text){const out=[],lines=String(text||'').split(/\\r?\\n/);for(const raw of lines){const low=norm(raw),ctx=/waktu|jam|time|pukul|transaksi|transaction/.test(low)?6:0;for(const m of raw.matchAll(/\\b([0-9OIlSB]{1,2})\\s*[:.]\\s*([0-9OIlSB]{2})(?:\\s*[:.]\\s*[0-9OIlSB]{2})?\\s*(wib|am|pm)?\\b/gi)){let h=Number(digitFix(m[1])),mi=Number(digitFix(m[2])),ap=(m[3]||'').toLowerCase();if(ap==='pm'&&h<12)h+=12;if(ap==='am'&&h===12)h=0;if(h<=23&&mi<=59)out.push({value:String(h).padStart(2,'0')+':'+String(mi).padStart(2,'0'),score:ctx+2,label:ctx>0})}}const best=new Map();for(const x of out){const p=best.get(x.value);if(!p||x.score>p.score)best.set(x.value,x)}return [...best.values()].sort((a,b)=>b.score-a.score)}";
const OCR_TIME_NEW = "function timeCandidates(text){const out=[],lines=String(text||'').split(/\\r?\\n/);for(const raw of lines){const low=norm(raw),ctx=/waktu|jam|time|pukul|transaksi|transaction/.test(low)?6:0,re=ctx?/\\b([0-9OIlSBZG]{1,2})\\s*(?::|\\.|h|\\s)\\s*([0-9OIlSBZG]{2})(?:\\s*(?::|\\.)\\s*[0-9OIlSBZG]{2})?\\s*(wib|am|pm)?\\b/gi:/\\b([0-9OIlSBZG]{1,2})\\s*[:.]\\s*([0-9OIlSBZG]{2})(?:\\s*[:.]\\s*[0-9OIlSBZG]{2})?\\s*(wib|am|pm)?\\b/gi;for(const m of raw.matchAll(re)){let h=Number(digitFix(m[1])),mi=Number(digitFix(m[2])),ap=(m[3]||'').toLowerCase();if(ap==='pm'&&h<12)h+=12;if(ap==='am'&&h===12)h=0;if(h<=23&&mi<=59)out.push({value:String(h).padStart(2,'0')+':'+String(mi).padStart(2,'0'),score:ctx+2,label:ctx>0})}}const best=new Map();for(const x of out){const p=best.get(x.value);if(!p||x.score>p.score)best.set(x.value,x)}return [...best.values()].sort((a,b)=>b.score-a.score)}";
const OCR_TIME_OK_OLD = "function timeOK(v,target){if(!v)return false;const c=tmin(v),ds=[c-target,c-target-1440,c-target+1440].sort((a,b)=>Math.abs(a)-Math.abs(b)),d=ds[0]??9999;return d>=-240&&d<=30}";
const OCR_TIME_OK_NEW = "function timeOK(v,target){if(!v)return false;const c=tmin(v),ds=[c-target,c-target-1440,c-target+1440].sort((a,b)=>Math.abs(a)-Math.abs(b)),d=ds[0]??9999;return d>=-5&&d<=1}";
const OCR_DRAW_OLD = "function draw(a){const box=document.getElementById('ocrChecks');if(!box)return;box.innerHTML=cell('Nama Usaha',a.merchant,a.merchantOk,a.merchantConfidence)+cell('Tanggal',a.date,a.date?a.dateOk:false,a.dateConfidence)+cell('Waktu',a.time,a.time?a.timeOk:false,a.timeConfidence)+cell('Nominal',a.amount==null?'Belum terbaca':rp(a.amount),a.amountOk,a.amountConfidence)}";
const OCR_DRAW_NEW = "function draw(a){const box=document.getElementById('ocrChecks');if(!box)return;box.innerHTML=cell('Nama Usaha',a.merchant,a.merchantOk,a.merchantConfidence)+cell('Tanggal Pemesanan',a.date,a.date?a.dateOk:false,a.dateConfidence)+cell('Waktu Pemesanan',a.time,a.time?a.timeOk:false,a.timeConfidence)+cell('Nominal Pembayaran',a.amount==null?'Belum terbaca':rp(a.amount),a.amountOk,a.amountConfidence)}";
const OCR_VARIANTS_OLD = "async function variants(file){try{if(!('createImageBitmap'in window))return[file];const b=await createImageBitmap(file),max=960,sc=Math.min(1,max/Math.max(b.width,b.height)),c=document.createElement('canvas');c.width=Math.max(1,Math.round(b.width*sc));c.height=Math.max(1,Math.round(b.height*sc));const x=c.getContext('2d',{alpha:false});if(!x){b.close?.();return[file]}x.imageSmoothingEnabled=true;try{x.imageSmoothingQuality='high'}catch{}x.fillStyle='#fff';x.fillRect(0,0,c.width,c.height);try{x.filter='grayscale(1) contrast(1.30)'}catch{}x.drawImage(b,0,0,c.width,c.height);try{x.filter='none'}catch{}b.close?.();return[c]}catch{return[file]}}";
const OCR_VARIANTS_NEW = "async function variants(file){try{if(!('createImageBitmap'in window))return[file];const b=await createImageBitmap(file),max=1280,sc=Math.min(1,max/Math.max(b.width,b.height)),c=document.createElement('canvas');c.width=Math.max(1,Math.round(b.width*sc));c.height=Math.max(1,Math.round(b.height*sc));const x=c.getContext('2d',{alpha:false});if(!x){b.close?.();return[file]}x.imageSmoothingEnabled=true;try{x.imageSmoothingQuality='high'}catch{}x.fillStyle='#fff';x.fillRect(0,0,c.width,c.height);try{x.filter='grayscale(1) brightness(1.04) contrast(1.42)'}catch{}x.drawImage(b,0,0,c.width,c.height);try{x.filter='none'}catch{}b.close?.();return[c]}catch{return[file]}}";
const EXPIRY_TIMER_OLD = "let expiryTimer=0;function stopExpiryTimer(){clearTimeout(expiryTimer);expiryTimer=0}function armExpiryTimer(){stopExpiryTimer();if(document.hidden)return;expiryTimer=setTimeout(()=>{expiryTimer=0;if(!document.hidden)checkExpiry();armExpiryTimer()},60000)}window.addEventListener('pageshow',()=>{checkExpiry();schedulePayment();armExpiryTimer()});document.addEventListener('visibilitychange',()=>{if(document.hidden)stopExpiryTimer();else{checkExpiry();armExpiryTimer()}});window.addEventListener('pagehide',stopExpiryTimer);armExpiryTimer();schedulePayment();})();";
const EXPIRY_TIMER_NEW = "let expiryTimer=0;function stopExpiryTimer(){clearTimeout(expiryTimer);expiryTimer=0}function nextExpiryDelay(){const s=read(),started=s.orderStartedAt?Date.parse(s.orderStartedAt):0;if(Number.isFinite(started)&&started>0)return Math.max(100,Math.min(60000,started+PAYMENT_TTL-Date.now()+25));return 60000}function armExpiryTimer(){stopExpiryTimer();if(document.hidden)return;expiryTimer=setTimeout(()=>{expiryTimer=0;if(!document.hidden)checkExpiry();armExpiryTimer()},nextExpiryDelay())}window.addEventListener('pageshow',()=>{checkExpiry();schedulePayment();armExpiryTimer()});document.addEventListener('visibilitychange',()=>{if(document.hidden)stopExpiryTimer();else{checkExpiry();armExpiryTimer()}});window.addEventListener('pagehide',stopExpiryTimer);armExpiryTimer();schedulePayment();})();";
const OCR_NOWPARTS_OLD = "function nowParts(){const p=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Jakarta',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(new Date()),g=t=>p.find(x=>x.type===t)?.value||'';return{date:g('year')+'-'+g('month')+'-'+g('day'),min:Number(g('hour'))*60+Number(g('minute'))}}";
const OCR_NOWPARTS_NEW = "function nowParts(){const p=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Jakarta',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(new Date()),g=t=>p.find(x=>x.type===t)?.value||'';return{date:g('year')+'-'+g('month')+'-'+g('day'),min:Number(g('hour'))*60+Number(g('minute'))}}function paymentWindow(){let startMs=NaN;try{const s=JSON.parse(localStorage.getItem('rohmat-public-v5')||'{}')||{};startMs=Date.parse(s.orderStartedAt||'')}catch{}const now=Date.now(),sp=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Jakarta',year:'numeric',month:'2-digit',day:'2-digit'});return{startMs,nowMs:now,startDate:Number.isFinite(startMs)?sp.format(new Date(startMs)):''}}function proofMomentOK(date,time,startMs){if(!date||!time||!Number.isFinite(startMs))return false;const ms=Date.parse(date+'T'+time+':00+07:00'),now=Date.now();return Number.isFinite(ms)&&ms>=startMs-60000&&ms<=now+60000&&now-startMs<5*60*1000+1500}";
const OCR_ANALYSE_WINDOW_OLD = "dc=dateCandidates(text),dBest=dc.find(x=>x.value===n.date)||dc[0]||null,date=dBest?.value||null,dateOk=date===n.date,tc=timeCandidates(text),validTimes=tc.filter(x=>timeOK(x.value,n.min)),tBest=(validTimes[0]||tc[0]||null),time=tBest?.value||null,timeOk=timeOK(time,n.min),ac=";
const OCR_ANALYSE_WINDOW_NEW = "w=paymentWindow(),dc=dateCandidates(text),dBest=dc.find(x=>x.value===w.startDate||x.value===n.date)||dc[0]||null,date=dBest?.value||null,dateOk=!!date&&(date===w.startDate||date===n.date),tc=timeCandidates(text),validTimes=tc.filter(x=>timeOK(x.value,n.min)),tBest=(validTimes[0]||tc[0]||null),time=tBest?.value||null,timeOk=timeOK(time,n.min)&&proofMomentOK(date,time,w.startMs),ac=";
const OCR_STATE_TRACK_OLD = "let strongText='',busy=false,patchedInput=null,worker=null,workerPromise=null,scriptPromise=null,workerEpoch=0,workerIdleTimer=0,ocrQueuedFile=null,ocrRunSeq=0;";
const OCR_STATE_TRACK_NEW = "let strongText='',busy=false,patchedInput=null,worker=null,workerPromise=null,scriptPromise=null,workerEpoch=0,workerIdleTimer=0,ocrQueuedFile=null,ocrRunSeq=0,lastOcrMerchant='';";
const OCR_RUN_MERCHANT_OLD = "const z=analyse(text);draw(z);ocrMetricStatus='success';";
const OCR_RUN_MERCHANT_NEW = "const z=analyse(text);lastOcrMerchant=String(z.merchant||'');draw(z);ocrMetricStatus='success';";
const OCR_SETTINGS_SYNC_OLD = "window.addEventListener('pagehide',()=>{ocrRunSeq++;resetOcrWorker()});window.addEventListener('pageshow',()=>{patch();if(document.getElementById('proof'))queueOcrWarm(false)});patch();";
const OCR_SETTINGS_SYNC_NEW = "window.addEventListener('pagehide',()=>{ocrRunSeq++;resetOcrWorker()});window.addEventListener('pageshow',()=>{patch();if(document.getElementById('proof'))queueOcrWarm(false)});document.addEventListener('rohmat:settings-updated',()=>{const current=String(window.__rohmatPublicConfigV25?.merchant_name||window.__rohmatPublicConfigV24?.merchant_name||document.querySelector('.payroom h3')?.textContent||'').trim(),p=document.getElementById('proof'),f=p?.files?.[0];if(f&&current&&current!==lastOcrMerchant){strongText='';const r=document.getElementById('ocrReview');if(r){r.dataset.verificationPassed='0';r.dataset.verificationState='working'}setTimeout(()=>run(f),0)}else patch()});patch();";



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
  const qrisDownloadSource = rewritten.upstream.origin + '/functions/v1/rohmat-qris-download';
  const qrisDownload = '/qris-download';

  out = replaceRequired(
    out,
    "const PROFILE='rohmat-customer-history-v1',DOWNLOAD='" + qrisDownloadSource + "';let scheduled=false;",
    "const PROFILE='rohmat-customer-history-v1',DOWNLOAD='" + qrisDownload + "';let scheduled=false,sendGuardObserver=null,sendGuardTarget=null;function clearSendGuard(){try{sendGuardObserver?.disconnect()}catch{}sendGuardObserver=null;sendGuardTarget=null}",
    'send-guard-owner', flags
  );
  out = replaceRequired(
    out,
    "function cleanDownload(){const pay=document.querySelector('.payroom');if(!pay)return;let old=[...pay.querySelectorAll('button')].find(x=>/unduh qris/i.test(x.textContent||''));if(!old||old.dataset.cleanDownload)return;const b=old.cloneNode(true);b.disabled=false;b.removeAttribute('disabled');b.dataset.cleanDownload='1';b.type='button';old.replaceWith(b);b.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();const img=pay.querySelector('.qrisbox img');if(!img||!img.src){alert('QRIS resmi Rohmat Nasi Uduk belum diunggah. Setelah QRIS diaktifkan oleh pengelola, tombol ini akan langsung mengunduh QRIS.');return}window.location.assign(DOWNLOAD)})}",
    "function downloadQrisFile(){const direct=()=>{const a=document.createElement('a');a.href=DOWNLOAD;a.rel='noopener';a.download='QRIS.jpg';a.style.display='none';document.body.appendChild(a);a.click();setTimeout(()=>a.remove(),0)};return fetch(DOWNLOAD,{method:'GET',credentials:'same-origin',cache:'no-store'}).then(r=>{if(!r.ok)throw Error('QRIS tidak dapat diunduh.');const cd=r.headers.get('content-disposition')||'',m=cd.match(/filename=\\\"?([^\\\";]+)\\\"?/i),name=(m&&m[1])||'QRIS.jpg';return r.blob().then(blob=>({blob,name}))}).then(({blob,name})=>{const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.rel='noopener';a.style.display='none';document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(url);a.remove()},1500)}).catch(()=>direct())}function cleanDownload(){const pay=document.querySelector('.payroom');if(!pay)return;let old=[...pay.querySelectorAll('button')].find(x=>/unduh qris/i.test(x.textContent||''));if(!old||old.dataset.cleanDownload)return;const b=old.cloneNode(true);b.disabled=false;b.removeAttribute('disabled');b.dataset.cleanDownload='1';b.type='button';old.replaceWith(b);b.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();const img=pay.querySelector('.qrisbox img');if(!img||!img.src){alert('QRIS resmi Rohmat Nasi Uduk belum diunggah. Setelah QRIS diaktifkan oleh pengelola, tombol ini akan langsung mengunduh QRIS.');return}void downloadQrisFile()})}",
    'qris-download-cross-device', flags
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

  out = replaceRequired(out, PAYMENT_BOOT_CONST_OLD, PAYMENT_BOOT_CONST_NEW, 'payment-boot-ttl-5m', flags);
  out = replaceRequired(out, PAYMENT_RUNTIME_CONST_OLD, PAYMENT_RUNTIME_CONST_NEW, 'payment-ttl-5m-const', flags);
  out = replaceRequired(out, PAYMENT_EXPIRY_OLD, PAYMENT_EXPIRY_NEW, 'payment-expiry-absolute-5m', flags);
  out = replaceRequired(out, PAYMENT_BOOT_EXPIRY_OLD, PAYMENT_BOOT_EXPIRY_NEW, 'payment-boot-expiry-absolute-5m', flags);
  out = replaceRequired(out, PAYMENT_PAYLOAD_OLD, PAYMENT_PAYLOAD_NEW, 'payment-started-at-payload', flags);
  out = replaceRequired(out, OCR_DIGIT_OLD, OCR_DIGIT_NEW, 'ocr-digit-normalization-v2', flags);
  out = replaceRequired(out, OCR_DATE_DMY_OLD, OCR_DATE_DMY_NEW, 'ocr-date-dmy-zg', flags);
  out = replaceRequired(out, OCR_DATE_YMD_OLD, OCR_DATE_YMD_NEW, 'ocr-date-ymd-zg', flags);
  out = replaceRequired(out, OCR_AMOUNT_DIGITS_OLD, OCR_AMOUNT_DIGITS_NEW, 'ocr-amount-zg', flags);
  out = replaceRequired(out, OCR_MERCHANT_OLD, OCR_MERCHANT_NEW, 'ocr-merchant-compact-fuzzy', flags);
  out = replaceRequired(out, OCR_ANALYSE_MERCHANT_OLD, OCR_ANALYSE_MERCHANT_NEW, 'ocr-merchant-live-admin-source', flags);
  out = replaceRequired(out, OCR_TIME_OLD, OCR_TIME_NEW, 'ocr-time-labelled-flex', flags);
  out = replaceRequired(out, OCR_TIME_OK_OLD, OCR_TIME_OK_NEW, 'ocr-time-window-5m', flags);
  out = replaceRequired(out, OCR_VARIANTS_OLD, OCR_VARIANTS_NEW, 'ocr-image-1280-enhanced', flags);
  out = replaceRequired(out, OCR_DRAW_OLD, OCR_DRAW_NEW, 'ocr-four-variable-labels', flags);
  out = replaceRequired(
    out,
    "window.addEventListener('pageshow',()=>{checkExpiry();schedulePayment()});document.addEventListener('visibilitychange',()=>{if(!document.hidden)checkExpiry()});setInterval(()=>{if(!document.hidden)checkExpiry()},60000);schedulePayment();})();",
    "let expiryTimer=0;function stopExpiryTimer(){clearTimeout(expiryTimer);expiryTimer=0}function armExpiryTimer(){stopExpiryTimer();if(document.hidden)return;expiryTimer=setTimeout(()=>{expiryTimer=0;if(!document.hidden)checkExpiry();armExpiryTimer()},60000)}window.addEventListener('pageshow',()=>{checkExpiry();schedulePayment();armExpiryTimer()});document.addEventListener('visibilitychange',()=>{if(document.hidden)stopExpiryTimer();else{checkExpiry();armExpiryTimer()}});window.addEventListener('pagehide',stopExpiryTimer);armExpiryTimer();schedulePayment();})();",
    'expiry-timer-pause-resume', flags
  );
  out = replaceRequired(out, EXPIRY_TIMER_OLD, EXPIRY_TIMER_NEW, 'payment-expiry-exact-timer', flags);
  out = replaceRequired(out, OCR_NOWPARTS_OLD, OCR_NOWPARTS_NEW, 'ocr-payment-window-helper', flags);
  out = replaceRequired(out, OCR_ANALYSE_WINDOW_OLD, OCR_ANALYSE_WINDOW_NEW, 'ocr-session-bound-date-time', flags);
  out = replaceRequired(out, OCR_STATE_TRACK_OLD, OCR_STATE_TRACK_NEW, 'ocr-merchant-reference-state', flags);
  out = replaceRequired(out, OCR_RUN_MERCHANT_OLD, OCR_RUN_MERCHANT_NEW, 'ocr-merchant-reference-capture', flags);
  out = replaceRequired(out, OCR_SETTINGS_SYNC_OLD, OCR_SETTINGS_SYNC_NEW, 'ocr-admin-merchant-live-resync', flags);
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
  if (!out.includes('clearSendGuard') || !out.includes('clearVerificationWatch') || !out.includes('stopExpiryTimer') || !out.includes(LOCAL_RUNTIME) || !out.includes("PAYMENT_TTL=5*60*1000") || !out.includes("paymentStartedAt:st.orderStartedAt||null") || !out.includes("d>=-5&&d<=1") || !out.includes("max=1280") || !out.includes("nextExpiryDelay") || !out.includes("window.__rohmatPublicConfigV24?.merchant_name") || !out.includes("proofMomentOK") || !out.includes("lastOcrMerchant") || !out.includes("rohmat:settings-updated")) throw new Error('lifecycle_validation_failed');
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
