import fs from 'node:fs';
import assert from 'node:assert/strict';

const adminRender=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-render/index.ts',import.meta.url),'utf8');
const adminApi=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const adminRuntime=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
const vercel=JSON.parse(fs.readFileSync(new URL('../../../vercel.json',import.meta.url),'utf8'));

assert.ok(!adminRender.includes("openSettings()},false)}}\\nfunction schedule(){"),'Admin settings runtime must not emit a literal backslash-n token');

for(const token of [
  "function renderKdsLive(v,mode='orders')",
  "src=login?'/admin/kds-login-live':'/admin/kds-live'",
  'data-kds-live-mirror=\\"v1\\"',
  'data-kds-live-frame=\\"1\\"',
  'title=\\"KDS Live\\"',
  "frame.dataset.kdsMirrorReady='1'",
  "target=mode==='stock'?'stock':'orders'"
]) assert.ok(adminRender.includes(token),'admin KDS scoped canonical mirror contract missing: '+token);

assert.ok(adminApi.includes('"frame-src \'self\'"'),'Admin CSP must explicitly allow same-origin KDS iframe');
assert.ok(adminApi.includes("const CDN_CACHE = 'no-store';"),'Admin shell CDN cache must be disabled for security/runtime freshness');
assert.ok(adminApi.includes("out = out.replace(/<meta\\s+http-equiv=[\"']Content-Security-Policy[\"'][^>]*>/gi, '');"),'Admin canonicalizer must strip conflicting CSP meta tags');
assert.ok(adminApi.includes('"frame-ancestors \'none\'"'),'Admin itself must remain non-frameable');
assert.ok(adminRuntime.includes("out = out.replace(\"frame-src 'none'; worker-src\", \"frame-src 'self'; worker-src\");"),'Canonical core normalizer must preserve Browser Security while allowing same-origin KDS');
assert.ok(adminRuntime.includes("kind === 'core' ? 'no-store'"),'Canonical core runtime must not be served stale from CDN');

const rewrite=s=>vercel.rewrites.find(x=>x.source===s)?.destination||'';
assert.equal(rewrite('/admin/kds-live'),'/apps/kds/index.html','Admin KDS embed must use the exact canonical KDS document');
assert.equal(rewrite('/admin/kds-login-live'),'/apps/kds/login.html','Admin KDS login embed must use the exact canonical KDS login document');
assert.equal(rewrite('/kds'),'/apps/kds/index.html','Canonical KDS route must use the same document as Admin KDS embed');
assert.equal(rewrite('/kds/login'),'/apps/kds/login.html','Canonical KDS login route must use the same document as Admin login embed');

const bySource=s=>vercel.headers.find(x=>x.source===s);
const header=(s,k)=>bySource(s)?.headers?.find(x=>x.key===k)?.value;
for(const s of ['/admin/kds-live','/admin/kds-login-live']){
  assert.equal(header(s,'X-Frame-Options'),'SAMEORIGIN',s+' must allow only same-origin Admin framing');
  assert.equal(header(s,'X-Rohmat-KDS-Embed'),'admin-same-origin-v1',s+' must expose scoped embed marker');
  const csp=header(s,'Content-Security-Policy')||'';
  assert.ok(csp.includes("frame-ancestors 'self'"),s+' CSP must allow only same-origin Admin framing');
  assert.ok(!csp.includes("frame-ancestors 'none'"),s+' must not keep contradictory frame denial');
}
for(const s of ['/','/admin','/database','/studio']) assert.equal(header(s,'X-Frame-Options'),'DENY',s+' must remain non-frameable');

console.log('ADMIN_KDS_CANONICAL_MIRROR_GATE_PASS=1');
console.log('KDS_SCOPED_SAME_ORIGIN_FRAME_SECURITY_GATE_PASS=1');
