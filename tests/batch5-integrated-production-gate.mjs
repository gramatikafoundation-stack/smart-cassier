import { chromium } from 'playwright';

const BASE = process.env.BASE_URL || 'https://smart-cassier.vercel.app';
const SURFACES = ['/', '/admin', '/kds'];
const VIEWPORTS = [
  ['mobile', 390, 844, true],
  ['tablet', 834, 1112, true],
  ['desktop', 1366, 900, false],
];
const SECURITY_HEADERS = [
  'strict-transport-security',
  'x-content-type-options',
  'x-frame-options',
  'referrer-policy',
  'permissions-policy',
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function request(path, options = {}) {
  const started = Date.now();
  const response = await fetch(BASE + path, { redirect: 'manual', ...options });
  const body = await response.text();
  return {
    path,
    status: response.status,
    ms: Date.now() - started,
    headers: Object.fromEntries(response.headers),
    body,
  };
}

const browser = await chromium.launch({ headless: true });
const report = { viewports: [], headers: [], assets: [], stress: {}, boundaries: [] };

try {
  for (const [name, width, height, mobile] of VIEWPORTS) {
    const context = await browser.newContext({
      viewport: { width, height },
      isMobile: mobile,
      hasTouch: mobile,
      locale: 'id-ID',
    });

    for (const path of SURFACES) {
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', (error) => errors.push(String(error)));

      const response = await page.goto(BASE + path, {
        waitUntil: 'domcontentloaded',
        timeout: 30000,
      });
      await page.waitForTimeout(700);

      const state = await page.evaluate(() => ({
        title: document.title,
        scrollWidth: document.documentElement.scrollWidth,
        innerWidth: window.innerWidth,
        robots: document.querySelector('meta[name="robots"]')?.content || '',
      }));

      assert(response?.status() === 200, `${name} ${path}: HTTP ${response?.status()}`);
      assert(state.scrollWidth <= state.innerWidth + 3, `${name} ${path}: horizontal overflow`);
      assert(errors.length === 0, `${name} ${path}: page errors: ${errors.join(' | ')}`);
      if (path === '/') assert(!/noindex/i.test(state.robots), 'Public must remain indexable');
      else assert(/noindex/i.test(state.robots), `${path}: meta robots noindex missing`);

      report.viewports.push({ name, path, status: 200, ...state, pageErrors: 0 });
      await page.close();
    }
    await context.close();
  }

  for (const path of [...SURFACES, '/kds-assets/v4/app.js']) {
    const cold = await request(path);
    const warm = await request(path);
    assert(cold.status === 200 && warm.status === 200, `${path}: cold/warm HTTP failure`);
    for (const header of SECURITY_HEADERS) {
      assert(cold.headers[header], `${path}: missing ${header}`);
    }
    if (path === '/admin' || path === '/kds') {
      assert(/no-store/i.test(cold.headers['cache-control'] || ''), `${path}: no-store missing`);
      assert(/noindex/i.test(cold.headers['x-robots-tag'] || ''), `${path}: X-Robots-Tag missing`);
    }
    if (path.includes('/kds-assets/')) {
      const cache = cold.headers['cache-control'] || '';
      assert(/max-age=31536000/.test(cache) && /immutable/i.test(cache), 'KDS immutable cache missing');
    }
    report.headers.push({
      path,
      coldMs: cold.ms,
      warmMs: warm.ms,
      cache: cold.headers['cache-control'] || '',
      vercelCache: warm.headers['x-vercel-cache'] || '',
    });
  }

  for (const path of SURFACES) {
    const page = await browser.newPage();
    await page.goto(BASE + path, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(500);
    const urls = await page.evaluate(() =>
      [...document.querySelectorAll('a[href],link[href],script[src],img[src]')]
        .map((node) => node.href || node.src)
        .filter(Boolean)
    );
    for (const raw of [...new Set(urls)].slice(0, 100)) {
      const url = new URL(raw);
      if (url.origin !== BASE) continue;
      const response = await fetch(url, { redirect: 'manual' });
      assert(response.status < 400, `${path}: broken asset/link ${url.pathname} => ${response.status}`);
      report.assets.push({ surface: path, path: url.pathname, status: response.status });
    }
    await page.close();
  }

  for (const path of SURFACES) {
    const samples = await Promise.all(Array.from({ length: 20 }, () => request(path)));
    assert(samples.every((sample) => sample.status < 500), `${path}: stress produced 5xx`);
    const times = samples.map((sample) => sample.ms).sort((a, b) => a - b);
    report.stress[path] = {
      requests: samples.length,
      statuses: [...new Set(samples.map((sample) => sample.status))],
      p50: times[Math.floor(times.length * 0.5)],
      p95: times[Math.floor(times.length * 0.95)],
      max: times.at(-1),
    };
  }

  const kdsBoundary = await request('/api/kds', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: BASE },
    body: JSON.stringify({ action: 'session' }),
  });
  assert(kdsBoundary.status === 401 || kdsBoundary.status === 403, `KDS unauth boundary returned ${kdsBoundary.status}`);
  report.boundaries.push({ surface: 'kds', status: kdsBoundary.status });

  const adminBoundary = await request('/api/admin-edge?kind=order-history', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: BASE },
    body: '{}',
  });
  assert(adminBoundary.status >= 400, `Admin unauth boundary returned ${adminBoundary.status}`);
  report.boundaries.push({ surface: 'admin', status: adminBoundary.status });

  console.log(JSON.stringify({ ok: true, base: BASE, ...report }, null, 2));
  console.log('BATCH5_INTEGRATED_PRODUCTION_GATE_PASS=1');
} finally {
  await browser.close();
}
