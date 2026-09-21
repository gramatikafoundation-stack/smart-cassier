import baseHandler from './render-a11y-v2.js';

const MARKER = 'rohmat-public-a11y-v3';

const A11Y_V3_STYLE = String.raw`<style nonce="__NONCE__" id="rohmat-public-a11y-v3-style">
.field input::placeholder,.field textarea::placeholder{color:#6D6A63!important;opacity:1!important}
</style>`;

const A11Y_V3_SCRIPT = String.raw`<script nonce="__NONCE__" id="rohmat-public-a11y-v3">(()=>{'use strict';if(window.__rohmatPublicA11yV3)return;window.__rohmatPublicA11yV3=1;let queued=false;const afterPaint=fn=>requestAnimationFrame(()=>requestAnimationFrame(()=>setTimeout(fn,0)));function brand(){return (document.querySelector('h1.brand')?.textContent||document.querySelector('[data-tenant-business]')?.textContent||'Business').trim()}function titleFor(view){const b=brand();return view==='menu'?'Pilih Menu — '+b:view==='checkout'?'Pembayaran — '+b:view==='success'?'Pesanan Terkirim — '+b:b+' — Pesan & Bayar'}function currentView(){if(document.querySelector('.success'))return'success';if(document.querySelector('.checkout'))return'checkout';if(document.querySelector('.grid'))return'menu';return'home'}function safeId(s){return String(s||'').replace(/[^a-zA-Z0-9_-]+/g,'-').replace(/^-+|-+$/g,'')||'item'}function primaryHeading(view){if(view==='success')return document.querySelector('.success h2');if(view==='checkout')return document.querySelector('.checkout .headin>div>b');if(view==='menu')return document.querySelector('.headin>b');return document.querySelector('h1.brand')}function patch(){queued=false;const view=currentView(),title=titleFor(view);if(document.title!==title)document.title=title;const main=document.querySelector('#app main'),primary=primaryHeading(view);if(primary){if(!primary.id)primary.id='rohmat-view-heading-v3-'+view;primary.setAttribute('role','heading');primary.setAttribute('aria-level','1');if(main)main.setAttribute('aria-labelledby',primary.id)}const tbl=document.getElementById('tbl');if(tbl){tbl.setAttribute('aria-required','true');tbl.setAttribute('required','')}document.querySelectorAll('.grid .card').forEach((card,i)=>{const h=card.querySelector('h3'),name=(h?.textContent||'Menu').trim(),seed=card.querySelector('[data-id]')?.dataset.id||String(i+1);if(h){if(!h.id)h.id='rohmat-menu-title-v3-'+safeId(seed);card.setAttribute('aria-labelledby',h.id)}const qty=card.querySelector('.qty');if(qty){const value=qty.querySelector('b')?.textContent?.trim()||'0';qty.setAttribute('role','group');qty.setAttribute('aria-label','Atur jumlah '+name+', saat ini '+value)}const sold=card.querySelector('.foot .btn[disabled]');if(sold&&/habis/i.test(sold.textContent||''))sold.setAttribute('aria-label',name+' sedang habis')});const summary=document.querySelector('.orderSummaryV35');if(summary){const ey=summary.querySelector(':scope>.ey');if(ey){if(!ey.id)ey.id='rohmatOrderSummaryHeadingV3';ey.setAttribute('role','heading');ey.setAttribute('aria-level','2');summary.setAttribute('aria-labelledby',ey.id)}}const pay=document.querySelector('.checkout .payroom');if(pay){const h=pay.querySelector('h2');if(h){if(!h.id)h.id='rohmatPaymentHeadingV3';pay.setAttribute('aria-labelledby',h.id)}const box=pay.querySelector('.qrisStepsBoxV72');if(box){box.setAttribute('role','region');box.setAttribute('aria-label','Instruksi dan konfirmasi pembayaran QRIS')}const send=document.getElementById('send'),review=document.getElementById('ocrReview');if(send&&review)send.setAttribute('aria-describedby',review.id)}const code=document.querySelector('.success .code');if(code&&code.textContent?.trim())code.setAttribute('aria-label','Nomor pesanan '+code.textContent.trim())}function schedule(){if(queued)return;queued=true;requestAnimationFrame(patch)}document.addEventListener('click',e=>{if(e.target.closest('#confirm,#pay,#backm,#back,#next,#send,#again'))afterPaint(schedule);else if(e.target.closest('[data-id],.cat'))setTimeout(schedule,0)},true);document.addEventListener('change',e=>{if(e.target?.matches('.opts input[type="radio"],#proof,#tbl'))schedule()},true);document.addEventListener('rohmat:dom-updated',schedule);window.addEventListener('pageshow',schedule);patch()})();</script>`;

function injectV3(html) {
  if (html.includes(MARKER)) return html;
  const nonce = html.match(/<script\s+nonce="([^"]+)"/)?.[1] || html.match(/<style\s+nonce="([^"]+)"/)?.[1];
  if (!nonce) return html;
  const style = A11Y_V3_STYLE.replaceAll('__NONCE__', nonce);
  const script = A11Y_V3_SCRIPT.replaceAll('__NONCE__', nonce);
  const headAt = html.lastIndexOf('</head>');
  let out = headAt >= 0 ? html.slice(0, headAt) + style + html.slice(headAt) : style + html;
  const bodyAt = out.lastIndexOf('</body>');
  out = bodyAt >= 0 ? out.slice(0, bodyAt) + script + out.slice(bodyAt) : out + script;
  return out;
}

export default async function handler(req, res) {
  const end = res.end.bind(res);
  res.end = (body, ...args) => {
    if (res.statusCode === 200 && typeof body === 'string' && body.includes('rohmat-public-a11y-v2')) {
      body = injectV3(body);
      res.setHeader('X-Rohmat-Public-A11y', 'wcag22-aa-v3.1');
      res.setHeader('X-Rohmat-Public-A11y-Target', 'keyboard-screenreader-touch-contrast-focus-motion-spa-semantics');
    }
    return end(body, ...args);
  };
  return baseHandler(req, res);
}
