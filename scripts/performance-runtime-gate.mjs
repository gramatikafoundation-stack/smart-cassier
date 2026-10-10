import fs from 'node:fs';
import assert from 'node:assert/strict';

const root=new URL('../',import.meta.url);
const read=p=>fs.readFileSync(new URL(p,root),'utf8');
const i18n=read('apps/shared/i18n-runtime.js');
const pub=read('apps/public/api/render.js');
const admin=read('supabase/functions/rohmat-admin-render/index.ts');
const adminProxy=read('apps/admin/api/render.js');
const kds=read('apps/kds/index.html');
const kdsLogin=read('apps/kds/login.html');

for(const token of [
  'function setNodeText(node,next){if(node.nodeValue===next)return false',
  'function setElementText(el,next){if(el.textContent===next)return false',
  'function setAttr(el,name,next){if(el.getAttribute(name)===next)return false',
  'let resolveCache=new Map()',
  'function translateSubtree(',
  'const pendingRoots=new Set()',
  'function queueRoot(root)',
  'function dynamicRoot()',
  "document.addEventListener('rohmat:dom-updated',()=>queueRoot(dynamicRoot()))"
]) assert.ok(i18n.includes(token),'missing performance token: '+token);

assert.ok(!i18n.includes("new MutationObserver(rs=>{if(rs.some(r=>r.addedNodes?.length))requestAnimationFrame(()=>translate(document))})"),'full-document MutationObserver translation loop must stay removed');
assert.ok(!i18n.includes("document.addEventListener('rohmat:dom-updated',()=>requestAnimationFrame(()=>translate(document)))"),'full-document dom-updated translation must stay removed');
assert.ok(!i18n.includes("if(x!==current)setLocale(x);else translate(document)"),'same-locale hydrate must not re-scan the full document');
assert.ok(!/function routeKey\([^)]*\)\{[^}]*\.matches\(/.test(i18n),'routeKey must use stable datasets without repeated selector matching');

for(const [name,src] of [['public',pub],['admin-edge',admin],['admin-proxy',adminProxy],['kds',kds],['kds-login',kdsLogin]])
  assert.ok(src.includes('20261010-global-v3'),'i18n cache-bust version missing in '+name);

console.log('SMART_ORDER_I18N_PERFORMANCE_GATE_PASS=1');
