import fs from 'node:fs';
import assert from 'node:assert/strict';

process.env.BUSINESS_NAME='Rohmat Nasi Uduk';
process.env.ADMIN_RENDERER_URL='https://example.supabase.co/functions/v1/rohmat-admin-render?mode=optimized';
process.env.SUPABASE_ORIGIN='https://example.supabase.co';
process.env.SDB_TENANT_ID='d8bb901c-7399-485b-8743-b319fde148ac';
process.env.SUPABASE_ANON_KEY='test-anon-jwt';

const renderSrc=fs.readFileSync(new URL('../api/render.js',import.meta.url),'utf8');
const runtimeSrc=fs.readFileSync(new URL('../api/runtime.js',import.meta.url),'utf8');
assert.match(renderSrc,/secure-api-v5-retained/);
assert.match(renderSrc,/script-src 'self'/);
assert.doesNotMatch(renderSrc,/script-src 'self' \$\{SUPABASE_ORIGIN\}/);
assert.match(runtimeSrc,/canonical runtime v60/);
assert.match(runtimeSrc,/same-origin-proxy-v60/);

const renderMod=await import('data:text/javascript;base64,'+Buffer.from(renderSrc).toString('base64'));
const runtimeMod=await import('data:text/javascript;base64,'+Buffer.from(runtimeSrc).toString('base64'));

const fixture=[
'<!doctype html><html><head><title>Studio Pengelola Warung Nasi - Design System</title>',
'<style id="admin-foundation-css-v1">.a{color:red}</style>',
'<style id="admin-design-system-v41">.b{color:blue}</style>',
'<style id="admin-theme14-v50">.c{color:green}</style>',
'<style id="admin-final-layout-v50">.d{color:black}</style>',
'<script id="rohmat-admin-bootstrap-dedup-v1">window.__b=1</script>',
'<script id="admin-design-system-runtime-v41">window.__v41=1</script>',
'<script id="rohmat-admin-style-runtime-loader-v59" src="https://example.supabase.co/functions/v1/rohmat-admin-style-runtime-v59"></script>',
'<script id="admin-theme14-runtime-v50">window.__v50=1</script>',
'<script id="admin-secure-rpc-v50">const API="https://example.supabase.co/functions/v1/rohmat-secure-api-v1";const KEEP="secure";</script>',
'<script id="admin-fast-navigation-v50">window.__fast=1</script>',
'<script id="admin-final-links-v50">window.__links=1</script>',
'<script id="rohmat-visual-editor-loader-v50" src="https://example.supabase.co/functions/v1/rohmat-admin-visual-editor-v1"></script>',
'</head><body><div>Warung Nasi</div>',
'<script id="rohmat-admin-cashier-current-v36" src="https://example.supabase.co/functions/v1/rohmat-admin-cashier-loader-v1"></script><!-- rohmat-admin-smart-cashier-subnav-v30 -->',
'</body></html>'
].join('\n');

const out=renderMod.canonicalizeAdminShell(fixture);
assert.match(out,/Rohmat Nasi Uduk/);
assert.doesNotMatch(out,/Warung Nasi/);
assert.match(out,/name="robots" content="noindex,nofollow,noarchive"/);
assert.match(out,/src="\/admin\/runtime\/core\.js"/);
assert.match(out,/src="\/admin\/runtime\/visual-editor\.js"/);
assert.match(out,/src="\/admin\/runtime\/cashier\.js"/);
for(const old of ['admin-design-system-runtime-v41','rohmat-admin-style-runtime-loader-v59','admin-theme14-runtime-v50','admin-fast-navigation-v50','admin-final-links-v50','rohmat-visual-editor-loader-v50','rohmat-admin-cashier-current-v36']) {
  assert.ok(!out.includes('id="'+old+'"'),old);
}
assert.match(out,/admin-secure-rpc-v50/);
assert.match(out,/rohmat-secure-api-v1/);
assert.match(out,/admin-design-system-v41 consolidated-v60/);
assert.match(out,/admin-theme14-v50 consolidated-v60/);
assert.equal((out.match(/<style\b/g)||[]).length,1);

const core=runtimeMod.buildCanonicalCoreFromHtml(fixture,'window.__v59=1');
assert.match(core,/window\.__v41=1/);
assert.match(core,/window\.__v50=1/);
assert.match(core,/window\.__v59=1/);
assert.match(core,/rohmatAdminCanonicalNavigationV60/);
assert.match(core,/rohmatAdminCanonicalRuntime="v60"/);
console.log('BATCH3_ADMIN_CANONICALIZATION_GATE_PASS=1');
