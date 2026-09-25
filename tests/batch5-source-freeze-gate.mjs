import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const vercel=JSON.parse(read('vercel.json'));
const pkg=JSON.parse(read('package.json'));
const adminRender=read('apps/admin/api/render.js');
const adminRuntime=read('apps/admin/api/runtime.js');
const adminEdge=read('apps/admin/api/edge.js');
const inp=read('apps/public/api/render-inp.js');
const perf=read('apps/public/tests/performance-browser-gate.mjs');
const ocr=read('apps/public/tests/ocr-browser-gate.mjs');
const ocrRuntime=read('apps/public/tests/ocr-runtime-gate.cjs');
const rum=read('apps/public/tests/rum-v3-gate.mjs');
const validate=read('prototype/validate-config.mjs');
const rehearse=read('prototype/rehearse.mjs');
const provision=read('prototype/provision-plan.mjs');
const kdsGate=read('apps/kds/tests/batch4-kds-hardening-gate.mjs');

assert.equal(pkg.name,'rohmat-platform-unified');
assert.deepEqual(vercel.regions,['sin1']);
const routes=new Map(vercel.rewrites.map(x=>[x.source,x.destination]));
assert.equal(routes.get('/'),'/api/public-render-seo-brand');
assert.equal(routes.get('/admin'),'/api/admin-render');
assert.equal(routes.get('/kds'),'/apps/kds/index.html');
assert.equal(routes.get('/kds/login'),'/apps/kds/login.html');
assert.equal(routes.get('/api/kds'),'/api/kds-handler');
const immutable=vercel.headers.find(x=>x.source==='/kds-assets/v4/(.*)');
assert.ok(immutable);
assert.match(JSON.stringify(immutable),/max-age=31536000, immutable/);

for(const src of [adminRender,adminRuntime,adminEdge,perf,ocr,ocrRuntime,rum,validate,rehearse,provision]){
  assert.match(src,/xrepmvbccalzhlcznrff/);
}
assert.match(adminRender,/resolveCanonicalBusinessName/);
assert.match(adminRender,/tenant_site_settings_public_v1/);
assert.match(adminRender,/canonicalizeAdminShell\(html, canonicalBusinessName\)/);
assert.match(inp,/CONFIRM_ROUTE_START_NEW/);
assert.match(inp,/if\(e\.target\.closest\('#next'\)\)queueOcrWarm\(false\)/);
assert.match(inp,/if\(e\.target\.closest\('#confirm'\)\)queueOcrWarm\(true\)/);
assert.match(rum,/replaceAll\('__SDB_RUM_ENDPOINT__',ENDPOINT\)/);
assert.match(validate,/surfaceOriginCount!==1&&surfaceOriginCount!==3/);
assert.match(rehearse,/master-prototype-two-tenant-static-rehearsal-v2/);
assert.match(provision,/gramatikafoundation-stack\/smart-cassier/);
assert.match(kdsGate,/BATCH4_KDS_HARDENING_SOURCE_GATE_PASS/);

const activeRoots=['api','apps','prototype','supabase/functions'];
const code=[];
const walk=d=>{
  for(const e of fs.readdirSync(path.join(root,d),{withFileTypes:true})){
    const p=path.join(d,e.name).replaceAll('\\','/');
    if(e.isDirectory()) walk(p);
    else if(/\.(?:js|mjs|cjs|ts)$/.test(e.name)) code.push([p,read(p)]);
  }
};
for(const d of activeRoots) walk(d);
for(const [p,s] of code) assert.doesNotMatch(s,/\burl\.parse\s*\(/i,p+': legacy url.parse');
for(const [p,s] of code.filter(([p])=>p.startsWith('apps/'))) {
  assert.doesNotMatch(s,/SUPABASE_SERVICE_ROLE_KEY/,p+': service role in frontend');
}

console.log(JSON.stringify({
  ok:true,
  contract:'batch5-integrated-source-freeze-v1',
  region:vercel.regions[0],
  routes:['/','/admin','/kds','/api/kds'],
  active_code_files:code.length
},null,2));
console.log('BATCH5_SOURCE_FREEZE_GATE_PASS=1');
