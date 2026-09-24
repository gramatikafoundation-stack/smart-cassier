import http from 'node:http';
import { chromium } from 'playwright';


// Self-contained fail-closed tenant fixture for local/CI gates.
process.env.MASTER_PROTOTYPE_STRICT ||= '1';
process.env.SDB_TENANT_ID ||= 'd8bb901c-7399-485b-8743-b319fde148ac';
process.env.SUPABASE_URL ||= 'https://xrepmvbccalzhlcznrff.supabase.co';
process.env.PUBLIC_LKG_PATH ||= '/storage/v1/object/public/merchant-static/public-lkg-v1.html';
process.env.BUSINESS_NAME ||= 'Master Prototype Test Merchant';
process.env.PUBLIC_ORIGIN ||= 'https://master-prototype-test.invalid';
process.env.TENANT_LOCALE ||= 'id-ID';
const { default: renderHandler } = await import('../api/render-seo-brand.js');
const { default: runtimeHandler } = await import('../lib/runtime-lifecycle.js');
const PORT = 4183;
const ORIGIN = `http://127.0.0.1:${PORT}`;
const SIG = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const fail = (message) => { throw new Error(message); };

function server() {
  return http.createServer((req, res) => {
    const url = new URL(req.url || '/', ORIGIN);
    if (url.pathname === '/runtime-lifecycle.js') {
      return Promise.resolve(runtimeHandler(req, res)).catch((error) => {
        res.statusCode = 500;
        res.end(String(error));
      });
    }
    if (url.pathname === '/functions/v1/create-order-v6') {
      let raw = '';
      req.setEncoding('utf8');
      req.on('data', (chunk) => { raw += chunk; });
      req.on('end', () => {
        res.statusCode = 200;
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.end(raw || '{}');
      });
      return;
    }
    return Promise.resolve(renderHandler(req, res)).catch((error) => {
      console.error('LOCAL_HANDLER_ERROR', error);
      if (!res.headersSent) res.statusCode = 500;
      if (!res.writableEnded) res.end('handler error');
    });
  });
}

function count(text, needle) {
  return text.split(needle).length - 1;
}

async function main() {
  const srv = server();
  await new Promise((resolve, reject) => { srv.once('error', reject); srv.listen(PORT, '127.0.0.1', resolve); });
  const browser = await chromium.launch({ headless: true });
  try {
    const rawResponse = await fetch(`${ORIGIN}/?table=5&sig=${SIG}`);
    const html = await rawResponse.text();
    if (rawResponse.status !== 200) fail(`http_${rawResponse.status}`);
    if (rawResponse.headers.get('x-rohmat-public-runtime-architecture') !== 'fetch-pipeline-v1') fail('architecture_header_missing');
    if (count(html, 'window.fetch=async function') !== 1) fail(`fetch_wrapper_count_${count(html, 'window.fetch=async function')}`);
    if (html.includes('const base=window.fetch.bind(window)') || html.includes('const oldFetch=window.fetch.bind(window)')) fail('nested_fetch_wrapper_remains');
    const bootAt = html.indexOf('rohmat-fetch-pipeline-v1');
    const signedAt = html.indexOf('rohmat-signed-table-v22');
    const ocrAt = html.indexOf('rohmat-ocr-smart-v6');
    if (!(bootAt >= 0 && bootAt < signedAt && signedAt < ocrAt)) fail('runtime_order_invalid');

    const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'id-ID' });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    page.on('console', (message) => { if (message.type() === 'error') errors.push(`console:${message.text()}`); });
    const response = await page.goto(`${ORIGIN}/?table=5&sig=${SIG}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    if (!response || response.status() !== 200) fail(`browser_http_${response?.status()}`);
    await page.waitForFunction(() => window.__rohmatFetchPipelineV1?.size() === 2, null, { timeout: 10000 });

    const state = await page.evaluate(async ({ sig }) => {
      const pipeline = window.__rohmatFetchPipelineV1;
      const before = pipeline.names();
      const duplicateAccepted = pipeline.use('signed-table-v22', () => ({ input: '/should-not-run' }));
      const after = pipeline.names();
      const result = await fetch('/functions/v1/create-order-v6', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ serviceMode: 'dine-in', tableNumber: 5, proofOcrText: 'seed-proof' })
      });
      return {
        before,
        after,
        duplicateAccepted,
        size: pipeline.size(),
        dataset: document.documentElement.dataset.rohmatFetchPipeline || '',
        architecture: document.documentElement.dataset.rohmatRuntimeArchitecture || '',
        body: await result.json(),
        expectedSig: sig
      };
    }, { sig: SIG });

    if (JSON.stringify(state.before) !== JSON.stringify(['signed-table-v22', 'ocr-smart-v6'])) fail(`pipeline_order_${JSON.stringify(state.before)}`);
    if (JSON.stringify(state.after) !== JSON.stringify(state.before) || state.duplicateAccepted !== false || state.size !== 2) fail('pipeline_idempotency_failed');
    if (state.dataset !== 'signed-table-v22>ocr-smart-v6' || state.architecture !== 'fetch-pipeline-v1') fail('runtime_dataset_invalid');
    if (state.body.tableSignature !== SIG) fail(`signed_table_missing_${state.body.tableSignature || ''}`);
    if (state.body.proofOcrText !== 'seed-proof') fail(`ocr_payload_changed_${state.body.proofOcrText || ''}`);
    if (errors.length) fail(`browser_errors:${errors.join('|')}`);

    console.log(JSON.stringify({ ok: true, wrapperCount: 1, pipeline: state.before, payload: state.body, browserErrors: errors.length }, null, 2));
    console.log('PUBLIC_RUNTIME_ARCHITECTURE_GATE_PASS=1');
    await context.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => srv.close(resolve));
  }
}

main().catch((error) => { console.error(error); process.exit(1); });
