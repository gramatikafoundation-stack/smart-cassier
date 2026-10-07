import assert from 'node:assert/strict';
import fs from 'node:fs';
const src=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const seo=fs.readFileSync(new URL('../api/render-seo-brand.js',import.meta.url),'utf8');
for(const marker of [
  'smart-order-mobile-checkout-scroll-v1',
  'html.soCheckoutScrollFix,body.soCheckoutScrollFix',
  'overflow-y:auto!important',
  'touch-action:pan-y!important',
  '-webkit-overflow-scrolling:touch!important',
  'body.soCheckoutScrollFix .checkout',
  "document.documentElement.classList.toggle('soCheckoutScrollFix',checkout)",
  "document.body?.classList.toggle('soCheckoutScrollFix',checkout)",
  'new MutationObserver(schedule).observe(app,{childList:true,subtree:true})'
]) assert.ok(src.includes(marker),'missing mobile checkout scroll contract: '+marker);
assert.ok(seo.includes('MOBILE_CHECKOUT_SCROLL_PATCH'),'production public renderer must import checkout scroll patch');
assert.ok(seo.includes("!html.includes('smart-order-mobile-checkout-scroll-v2')"),'production public renderer must inject checkout scroll patch independently of legacy UI marker');
console.log('PUBLIC_MOBILE_CHECKOUT_SCROLL_GATE_PASS=1');
