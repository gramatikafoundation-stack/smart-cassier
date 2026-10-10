import fs from 'node:fs';
import assert from 'node:assert/strict';

const adminRender=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-render/index.ts',import.meta.url),'utf8');
const adminApi=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const vercel=JSON.parse(fs.readFileSync(new URL('../../../vercel.json',import.meta.url),'utf8'));

for(const token of [
  'data-kds-live-mirror=\\"canonical-v2\\"',
  'data-kds-canonical-src=\\"\'+src+\'\\"',
  'title=\\"KDS Canonical Live\\"',
  "frame.dataset.kdsMirrorReady='canonical'",
  "src=login?'/kds/login':'/kds'"
]) assert.ok(adminRender.includes(token),'admin KDS canonical mirror contract missing: '+token);

assert.ok(adminApi.includes('"frame-src \'self\'"'),'Admin CSP must explicitly allow same-origin KDS iframe');
assert.ok(adminApi.includes('"frame-ancestors \'none\'"'),'Admin itself must remain non-frameable');

const bySource=s=>vercel.headers.find(x=>x.source===s);
const header=(s,k)=>bySource(s)?.headers?.find(x=>x.key===k)?.value;
assert.ok(!(bySource('/(.*)')?.headers||[]).some(x=>x.key==='X-Frame-Options'),'Global DENY must not override KDS same-origin frame policy');
for(const s of ['/','/admin','/database','/studio']) assert.equal(header(s,'X-Frame-Options'),'DENY',s+' must remain non-frameable');
for(const s of ['/kds','/kds/(.*)','/dapur','/dapur/(.*)']){
  assert.equal(header(s,'X-Frame-Options'),'SAMEORIGIN',s+' must allow only same-origin framing');
  const csp=header(s,'Content-Security-Policy')||'';
  assert.ok(csp.includes("frame-ancestors 'self'"),s+' CSP must allow same-origin admin mirror');
  assert.ok(!csp.includes("frame-ancestors 'none'"),s+' must not keep contradictory frame denial');
}

console.log('ADMIN_KDS_CANONICAL_MIRROR_GATE_PASS=1');
console.log('KDS_SAME_ORIGIN_FRAME_SECURITY_GATE_PASS=1');
