import baseHandler from './render-inp.js';

const MARKER = 'rohmat-public-a11y-v1';

const A11Y_STYLE = String.raw`<style nonce="__NONCE__" id="rohmat-public-a11y-v1-style">
:root{--rohmat-a11y-accent:#A85E34;--rohmat-a11y-muted:#6D6A63;--rohmat-a11y-focus:#10291F}
.a11ySkipV1{position:fixed;left:12px;top:12px;z-index:9999;transform:translateY(-180%);padding:10px 14px;border-radius:9px;background:#10291F;color:#fff!important;font:700 15px/1.2 system-ui,-apple-system,"Segoe UI",sans-serif;text-decoration:none;box-shadow:0 4px 14px rgba(0,0,0,.18)}
.a11ySkipV1:focus,.a11ySkipV1:focus-visible{transform:none!important}
.a11yLiveV1{position:absolute!important;width:1px!important;height:1px!important;padding:0!important;margin:-1px!important;overflow:hidden!important;clip:rect(0,0,0,0)!important;white-space:nowrap!important;border:0!important}
.opts .opt{position:relative!important}
.opts .opt input[type="radio"]{display:block!important;position:absolute!important;width:1px!important;height:1px!important;padding:0!important;margin:-1px!important;overflow:hidden!important;clip:rect(0,0,0,0)!important;clip-path:inset(50%)!important;white-space:nowrap!important;border:0!important;opacity:.01!important}
.opts .opt:focus-within{outline:3px solid var(--rohmat-a11y-focus)!important;outline-offset:3px!important;box-shadow:0 0 0 2px #fff!important}
button:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible,[tabindex]:focus-visible,.a11ySkipV1:focus-visible{outline:3px solid var(--rohmat-a11y-focus)!important;outline-offset:3px!important;box-shadow:0 0 0 2px #fff!important}
main#main-content:focus{outline:none!important;box-shadow:none!important}
button,input,select,textarea,[tabindex]{scroll-margin-block:90px 120px}
.price,.checkout .panel:not(.payroom) .ey{color:var(--rohmat-a11y-accent)!important}
.accent,.cartgo,#send{background:var(--rohmat-a11y-accent)!important}
.muted,.copy>.muted{color:var(--rohmat-a11y-muted)!important}
.checkout .payroom .qrisStepsBoxV72 .proofSelectedName{color:var(--rohmat-a11y-muted)!important}
#ocrReview .ocrStrongRaw,#ocrReview .ocrStrongItem small{color:#65716B!important}
@media(prefers-reduced-motion:reduce){.a11ySkipV1{transition:none!important}.btn,.cat,.card,button{transition:none!important}}
</style>`;

const A11Y_SHELL = '<a id="rohmatA11ySkipV1" class="a11ySkipV1" href="#main-content">Lewati ke konten utama</a><div id="rohmatA11yLiveV1" class="a11yLiveV1" role="status" aria-live="polite" aria-atomic="true"></div>';

const A11Y_SCRIPT = String.raw`<script nonce="__NONCE__" id="rohmat-public-a11y-v1">(()=>{'use strict';if(window.__rohmatPublicA11yV1)return;window.__rohmatPublicA11yV1=1;let queued=false,lastView='',pendingRouteFocus=false;const afterPaint=fn=>requestAnimationFrame(()=>requestAnimationFrame(()=>setTimeout(fn,0)));const app=document.getElementById('app');function brand(){return (document.querySelector('h1.brand')?.textContent||document.querySelector('[data-tenant-business]')?.textContent||'Business').trim()}function ensureShell(){let skip=document.getElementById('rohmatA11ySkipV1');if(!skip){skip=document.createElement('a');skip.id='rohmatA11ySkipV1';skip.className='a11ySkipV1';skip.href='#main-content';skip.textContent='Lewati ke konten utama';document.body.insertBefore(skip,document.body.firstChild)}if(!skip.dataset.a11yBoundV1){skip.dataset.a11yBoundV1='1';skip.addEventListener('click',()=>setTimeout(()=>document.getElementById('main-content')?.focus(),0))}let live=document.getElementById('rohmatA11yLiveV1');if(!live){live=document.createElement('div');live.id='rohmatA11yLiveV1';live.className='a11yLiveV1';document.body.appendChild(live)}live.setAttribute('role','status');live.setAttribute('aria-live','polite');live.setAttribute('aria-atomic','true');return live}function say(text){const live=ensureShell();live.textContent='';setTimeout(()=>{live.textContent=String(text||'')},20)}function view(){if(document.querySelector('.success'))return['success','Pesanan berhasil dikirim'];if(document.querySelector('.checkout'))return['checkout','Pembayaran Pesanan'];if(document.querySelector('.grid'))return['menu','Pilih Menu Favorit Anda'];return['home',brand()]}function heading(){if(document.querySelector('.success'))return document.querySelector('.success h2');if(document.querySelector('.checkout'))return document.querySelector('.checkout .headin>div>b');if(document.querySelector('.grid'))return document.querySelector('.headin>b');return document.querySelector('h1.brand')}function focusView(){const h=heading();if(!h)return;if(!/^H[1-6]$/.test(h.tagName)){h.setAttribute('role','heading');h.setAttribute('aria-level','1')}h.setAttribute('tabindex','-1');try{h.focus({preventScroll:false})}catch{h.focus()}}function patch(){queued=false;const live=ensureShell(),main=document.querySelector('#app main');if(main){main.id='main-content';main.setAttribute('tabindex','-1')}const h=heading();if(h){if(!/^H[1-6]$/.test(h.tagName)){h.setAttribute('role','heading');h.setAttribute('aria-level','1')}h.setAttribute('tabindex','-1')}const opts=document.querySelector('.opts');if(opts){opts.setAttribute('role','radiogroup');opts.setAttribute('aria-label','Jenis layanan');opts.querySelectorAll('input[type="radio"]').forEach(r=>{r.setAttribute('aria-label',r.value==='dine-in'?'Dine in':'Take away')})}const tbl=document.getElementById('tbl');if(tbl)tbl.setAttribute('aria-required','true');const name=document.getElementById('name');if(name){name.setAttribute('aria-required','true');name.setAttribute('required','');if(name.value.trim().length>=2)name.removeAttribute('aria-invalid')}document.querySelectorAll('.cat').forEach(b=>b.setAttribute('aria-pressed',b.classList.contains('on')?'true':'false'));document.querySelectorAll('.grid .card').forEach(card=>{const n=(card.querySelector('h3')?.textContent||'menu').trim();const add=card.querySelector('.foot .btn[data-a="+"]');if(add)add.setAttribute('aria-label','Tambah '+n+' ke pesanan');card.querySelectorAll('.qty button').forEach(b=>b.setAttribute('aria-label',(b.dataset.a==='+'?'Tambah jumlah ':'Kurangi jumlah ')+n));const img=card.querySelector('.food img');if(img&&!String(img.getAttribute('alt')||'').trim())img.setAttribute('alt',n)});const confirm=document.getElementById('confirm');if(confirm){confirm.setAttribute('aria-haspopup','dialog');confirm.setAttribute('aria-controls','dlg')}const dlg=document.getElementById('dlg');if(dlg){const title=dlg.querySelector('h2');if(title){title.id='rohmatConfirmTitleV1';dlg.setAttribute('aria-labelledby',title.id);dlg.removeAttribute('aria-label')}if(!dlg.dataset.a11yCloseV1){dlg.dataset.a11yCloseV1='1';dlg.addEventListener('close',()=>{dlg.classList.remove('user-open');if(document.body.contains(confirm))confirm?.focus()})}}const review=document.getElementById('ocrReview');if(review){review.setAttribute('role','status');review.setAttribute('aria-live','polite');review.setAttribute('aria-atomic','false')}const status=document.getElementById('status');if(status){status.setAttribute('role','status');status.setAttribute('aria-live','polite');status.setAttribute('aria-atomic','true')}const q=document.querySelector('.qrisbox img');if(q){const merchant=(document.querySelector('.payroom h3')?.textContent||brand()).trim();q.setAttribute('alt','Kode QRIS pembayaran '+merchant)}const [key,label]=view();if(lastView&&key!==lastView){say(label);if(pendingRouteFocus){pendingRouteFocus=false;setTimeout(focusView,0)}}lastView=key;void live}function schedule(){if(queued)return;queued=true;requestAnimationFrame(patch)}document.addEventListener('click',e=>{const t=e.target.closest('button,[data-c],[data-id]');if(!t)return;if(['next','back','backm','pay','send','again'].includes(t.id))pendingRouteFocus=true;if(t.id==='confirm')afterPaint(()=>{schedule();document.getElementById('name')?.focus()});if(t.id==='pay')afterPaint(()=>{const dlg=document.getElementById('dlg'),n=document.getElementById('name');if(dlg?.open){pendingRouteFocus=false;if(n&&n.value.trim().length<2){n.setAttribute('aria-invalid','true');n.focus();say('Nama pemesan wajib diisi sebelum melanjutkan pembayaran.')}}});if(t.id==='next')afterPaint(()=>{const tbl=document.getElementById('tbl');if(document.querySelector('input[name="mode"][value="dine-in"]:checked')&&tbl&&!tbl.value){pendingRouteFocus=false;tbl.focus();say('Pilih nomor meja terlebih dahulu.')}});if(t.matches('.cat'))afterPaint(()=>{schedule();const label=(t.textContent||'').trim(),count=document.querySelectorAll('.grid .card').length;say('Kategori '+label+' dipilih. '+count+' menu ditampilkan.')});if(t.matches('[data-id]'))afterPaint(()=>{schedule();const card=t.closest('.card'),name=(card?.querySelector('h3')?.textContent||'Menu').trim(),qty=card?.querySelector('.qty b')?.textContent?.trim()||'0';say(name+', jumlah '+qty)})},true);document.addEventListener('input',e=>{if(e.target?.id==='name'&&e.target.value.trim().length>=2)e.target.removeAttribute('aria-invalid')},true);document.addEventListener('rohmat:dom-updated',schedule);window.addEventListener('pageshow',schedule);if(app)new MutationObserver(schedule).observe(app,{childList:true,subtree:true});patch()})();</script>`;

function injectAccessibility(html) {
  if (html.includes(MARKER)) return html;
  const nonce = html.match(/<script\s+nonce="([^"]+)"/)?.[1] || html.match(/<style\s+nonce="([^"]+)"/)?.[1];
  if (!nonce) return html;
  const style = A11Y_STYLE.replaceAll('__NONCE__', nonce);
  const script = A11Y_SCRIPT.replaceAll('__NONCE__', nonce);
  const headAt = html.lastIndexOf('</head>');
  let out = headAt >= 0 ? html.slice(0, headAt) + style + html.slice(headAt) : style + html;
  if (!out.includes('id="rohmatA11ySkipV1"')) out = out.replace('<body>', '<body>'+A11Y_SHELL);
  const bodyAt = out.lastIndexOf('</body>');
  out = bodyAt >= 0 ? out.slice(0, bodyAt) + script + out.slice(bodyAt) : out + script;
  return out;
}

export default async function handler(req, res) {
  res.setHeader('X-Rohmat-Public-A11y', 'wcag22-aa-v1');
  res.setHeader('X-Rohmat-Public-A11y-Target', 'keyboard-screenreader-contrast-focus');
  const end = res.end.bind(res);
  res.end = (body, ...args) => {
    if (res.statusCode === 200 && typeof body === 'string' && body.includes('rohmat-public-bundle-v29')) {
      body = injectAccessibility(body);
    }
    return end(body, ...args);
  };
  return baseHandler(req, res);
}
