import baseHandler from './render-a11y.js';

const MARKER = 'rohmat-public-a11y-v2';

const A11Y_V2_STYLE = String.raw`<style nonce="__NONCE__" id="rohmat-public-a11y-v2-style">
.grid .qty button{width:44px!important;min-width:44px!important;height:44px!important;min-height:44px!important;display:grid!important;place-items:center!important}
.grid .qty b{min-width:36px!important;min-height:44px!important;display:grid!important;place-items:center!important}
.grid .foot .btn[data-id]{min-height:44px!important}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto!important}.btn,.cat,.card,button,.opt,.cartgo,.grid .food img{transition:none!important;animation:none!important;transform:none!important}.btn:hover,.cat:hover,.card:hover,button:hover,.opt:hover{transform:none!important}}
</style>`;

const A11Y_V2_SCRIPT = String.raw`<script nonce="__NONCE__" id="rohmat-public-a11y-v2">(()=>{'use strict';if(window.__rohmatPublicA11yV2)return;window.__rohmatPublicA11yV2=1;let queued=false;const afterPaint=fn=>requestAnimationFrame(()=>requestAnimationFrame(()=>setTimeout(fn,0)));function patch(){queued=false;document.querySelectorAll('.opts .opt input[type="radio"]').forEach(r=>{const selected=!!r.closest('.opt')?.classList.contains('on');if(r.checked!==selected)r.checked=selected;r.setAttribute('aria-checked',selected?'true':'false')});document.querySelectorAll('.grid .qty').forEach(q=>{const value=q.querySelector('b')?.textContent?.trim();if(value)q.setAttribute('aria-label','Jumlah '+value)});const cart=document.getElementById('confirm');if(cart){const total=cart.querySelector('b')?.textContent?.trim()||'';cart.setAttribute('aria-label','Konfirmasi menu dan identitas'+(total?' dengan total '+total:''))}const proof=document.getElementById('proof');if(proof){proof.setAttribute('aria-describedby','rohmatProofHelpV2');let help=document.getElementById('rohmatProofHelpV2');if(!help){help=document.createElement('div');help.id='rohmatProofHelpV2';help.className='a11yLiveV1';help.textContent='Unggah bukti pembayaran berformat JPEG, PNG, atau WebP dengan ukuran maksimal 3 MB.';proof.insertAdjacentElement('afterend',help)}}}function schedule(){if(queued)return;queued=true;requestAnimationFrame(patch)}document.addEventListener('change',e=>{if(e.target?.matches('.opts input[type="radio"],#proof'))schedule()},true);document.addEventListener('click',e=>{if(e.target.closest('#confirm,#pay,#backm,#back,#next'))afterPaint(schedule);else if(e.target.closest('[data-id],.cat'))setTimeout(schedule,0)},true);document.addEventListener('rohmat:dom-updated',schedule);window.addEventListener('pageshow',schedule);patch()})();</script>`;

function injectV2(html) {
  if (html.includes(MARKER)) return html;
  const nonce = html.match(/<script\s+nonce="([^"]+)"/)?.[1] || html.match(/<style\s+nonce="([^"]+)"/)?.[1];
  if (!nonce) return html;
  const style = A11Y_V2_STYLE.replaceAll('__NONCE__', nonce);
  const script = A11Y_V2_SCRIPT.replaceAll('__NONCE__', nonce);
  const headAt = html.lastIndexOf('</head>');
  let out = headAt >= 0 ? html.slice(0, headAt) + style + html.slice(headAt) : style + html;
  const bodyAt = out.lastIndexOf('</body>');
  out = bodyAt >= 0 ? out.slice(0, bodyAt) + script + out.slice(bodyAt) : out + script;
  return out;
}

export default async function handler(req, res) {
  const end = res.end.bind(res);
  res.end = (body, ...args) => {
    if (res.statusCode === 200 && typeof body === 'string' && body.includes('rohmat-public-a11y-v1')) {
      body = injectV2(body);
      res.setHeader('X-Rohmat-Public-A11y', 'wcag22-aa-v2');
      res.setHeader('X-Rohmat-Public-A11y-Target', 'keyboard-screenreader-touch-contrast-focus-motion');
    }
    return end(body, ...args);
  };
  return baseHandler(req, res);
}
