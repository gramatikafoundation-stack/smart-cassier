import fs from 'node:fs';
import assert from 'node:assert/strict';

const root = new URL('../../../', import.meta.url);
const read = p => fs.readFileSync(new URL(p, root), 'utf8');

const proxy = read('apps/public/api/qris-download.js');
const lifecycle = read('apps/public/lib/render-lifecycle.js');
const vercel = read('apps/public/vercel.json');
const rootVercel = read('vercel.json');
const wrapper = read('api/public-qris-download.js');

assert.match(proxy, /resolvePublicTenantConfig/);
assert.match(proxy, /SUPABASE_PUBLISHABLE_KEY/);
assert.match(proxy, /Authorization: 'Bearer ' \+ publishableKey/);
assert.match(proxy, /'x-sdb-tenant-id': cfg\.tenantId/);
assert.match(proxy, /Content-Disposition/);
assert.match(proxy, /attachment; filename=/);
assert.ok(proxy.includes("if (!/^image\\/(png|jpe?g|webp)$/.test(type))"));
assert.ok(lifecycle.includes("const qrisDownload = '/qris-download';"));
assert.ok(lifecycle.includes("qrisDownloadSource = rewritten.upstream.origin + '/functions/v1/rohmat-qris-download'"));
assert.ok(lifecycle.includes("function downloadQrisFile()"));
assert.ok(lifecycle.includes("a.href=DOWNLOAD"));
assert.ok(lifecycle.includes("a.download=''"));
assert.ok(lifecycle.includes("a.target='_self'"));
assert.ok(lifecycle.includes("window.location.assign(DOWNLOAD)"));
assert.ok(!lifecycle.includes("URL.createObjectURL(blob)"));
assert.ok(!lifecycle.includes("fetch(DOWNLOAD,{method:'GET',credentials:'same-origin',cache:'no-store'})"));
assert.ok(lifecycle.includes("void downloadQrisFile()"));
assert.ok(lifecycle.includes("'qris-download-cross-device', flags"));
assert.ok(vercel.includes('"source": "/qris-download", "destination": "/api/qris-download"'));
const rootCfg=JSON.parse(rootVercel);
assert.ok(rootCfg.rewrites?.some(x=>x.source==='/qris-download'&&x.destination==='/api/public-qris-download'),'root QRIS rewrite missing');
assert.ok(wrapper.includes("../apps/public/api/qris-download.js"));
assert.ok(!lifecycle.includes("const qrisDownload = rewritten.upstream.origin + '/functions/v1/rohmat-qris-download';"));

console.log('PUBLIC_QRIS_DOWNLOAD_CROSS_DEVICE_GATE_PASS=1');
