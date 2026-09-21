import http from 'node:http';
import { chromium } from 'playwright';


// Self-contained fail-closed tenant fixture for local/CI gates.
process.env.MASTER_PROTOTYPE_STRICT ||= '1';
process.env.SDB_TENANT_ID ||= 'ad126431-b148-471d-ba62-a7b3a5d0a8c1';
process.env.SUPABASE_URL ||= 'https://yybhpmjuywjxqurrrrxl.supabase.co';
process.env.PUBLIC_LKG_PATH ||= '/storage/v1/object/public/rohmat-static/public-lkg-v1.html';
process.env.BUSINESS_NAME ||= 'Master Prototype Test Merchant';
process.env.PUBLIC_ORIGIN ||= 'https://master-prototype-test.invalid';
process.env.TENANT_LOCALE ||= 'id-ID';
const { default: renderHandler } = await import('../api/render-seo-brand.js');
const { default: runtimeHandler } = await import('../lib/runtime-lifecycle.js');
const PORT = 4189;
const ORIGIN = `http://127.0.0.1:${PORT}`;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const fail = (message) => { throw new Error(message); };

function server() {
  return http.createServer((req, res) => {
    const path = (req.url || '').split('?')[0];
    const handler = path === '/runtime-lifecycle.js' ? runtimeHandler : renderHandler;
    Promise.resolve(handler(req, res)).catch((error) => {
      console.error('LOCAL_HANDLER_ERROR', error);
      if (!res.headersSent) res.statusCode = 500;
      if (!res.writableEnded) res.end('handler error');
    });
  });
}

async function cycle(page) {
  await page.locator('#next').waitFor({ timeout: 10000 });
  await page.evaluate(() => {
    const input = document.querySelector('input[value="take-away"]');
    if (!input) throw new Error('takeaway_missing');
    input.checked = true;
    input.dispatchEvent(new Event('change', { bubbles: true }));
    document.getElementById('next')?.click();
  });
  await page.locator('.grid [data-id][data-a="+"]').first().waitFor({ timeout: 10000 });
  await page.evaluate(() => document.getElementById('back')?.click());
  await page.locator('#next').waitFor({ timeout: 10000 });
}

async function measuredRun(browser, cycles) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'id-ID' });
  const page = await context.newPage();
  await page.route('https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-public-element-runtime-v64', async (route) => {
    if (route.request().method() === 'POST') return route.fulfill({ status: 204, body: '' });
    return route.continue();
  });
  const errors = [];
  page.on('pageerror', (error) => errors.push(String(error)));
  page.on('console', (message) => { if (message.type() === 'error') errors.push(`console:${message.text()}`); });
  const response = await page.goto(ORIGIN, { waitUntil: 'domcontentloaded', timeout: 30000 });
  if (!response || response.status() !== 200) fail(`http_${response?.status()}`);
  await page.waitForFunction(() => window.__rohmatFetchPipelineV1?.size() === 2, null, { timeout: 10000 });
  const cdp = await context.newCDPSession(page);
  await cdp.send('Performance.enable');
  await cdp.send('HeapProfiler.enable');
  for (let i = 0; i < cycles; i += 1) await cycle(page);
  await sleep(1200);
  const runtime = await page.evaluate(() => ({
    pipelineSize: window.__rohmatFetchPipelineV1?.size() || 0,
    pipelineNames: window.__rohmatFetchPipelineV1?.names() || [],
    architecture: document.documentElement.dataset.rohmatRuntimeArchitecture || '',
    lifecycle: document.documentElement.dataset.rohmatLifecycleRuntime || ''
  }));
  await cdp.send('Memory.forciblyPurgeJavaScriptMemory').catch(() => {});
  await cdp.send('HeapProfiler.collectGarbage').catch(() => {});
  await sleep(350);
  const raw = await cdp.send('Performance.getMetrics');
  const m = Object.fromEntries(raw.metrics.map((x) => [x.name, x.value]));
  await context.close();
  return { cycles, heap: m.JSHeapUsedSize, listeners: m.JSEventListeners, nodes: m.Nodes, documents: m.Documents, frames: m.Frames, errors, runtime };
}

async function main() {
  const srv = server();
  await new Promise((resolve, reject) => { srv.once('error', reject); srv.listen(PORT, '127.0.0.1', resolve); });
  const browser = await chromium.launch({ headless: true });
  try {
    const base = await measuredRun(browser, 3);
    const stress = await measuredRun(browser, 33);
    const delta = { heap: stress.heap - base.heap, listeners: stress.listeners - base.listeners, nodes: stress.nodes - base.nodes, documents: stress.documents - base.documents, frames: stress.frames - base.frames };
    const heapLimit = Math.max(750000, base.heap * 0.25);
    if (delta.heap > heapLimit) fail(`heap_growth_${Math.round(delta.heap)}_${Math.round(heapLimit)}`);
    if (delta.listeners > 2) fail(`listener_growth_${stress.listeners}_${base.listeners}`);
    if (delta.nodes > 40) fail(`node_growth_${stress.nodes}_${base.nodes}`);
    if (delta.documents !== 0 || delta.frames !== 0) fail(`context_growth_${JSON.stringify(delta)}`);
    if (base.errors.length || stress.errors.length) fail(`browser_errors_${[...base.errors, ...stress.errors].join('|')}`);
    if (!stress.runtime || stress.runtime.pipelineSize !== 2 || stress.runtime.architecture !== 'fetch-pipeline-v1' || stress.runtime.lifecycle !== 'v65') fail(`runtime_marker_${JSON.stringify(stress.runtime)}`);
    if (JSON.stringify(stress.runtime.pipelineNames) !== JSON.stringify(['signed-table-v22','ocr-smart-v6'])) fail('pipeline_order_changed');
    console.log(JSON.stringify({ ok: true, baseline: base, stress, delta, heapLimit }, null, 2));
    console.log('PUBLIC_RUNTIME_MEMORY_STRESS_GATE_PASS=1');
  } finally {
    await browser.close();
    await new Promise((resolve) => srv.close(resolve));
  }
}

main().catch((error) => { console.error(error); process.exit(1); });
