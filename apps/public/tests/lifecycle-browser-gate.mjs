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
const PORT = 4181;
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RUM = 'https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-public-element-runtime-v64';
const fail = (message) => { throw new Error(message); };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

const probeScript = () => {
  const RealMO = window.MutationObserver;
  const observers = new Map();
  let observerSeq = 0;
  class TrackedMO {
    constructor(callback) {
      this.id = ++observerSeq;
      this.real = new RealMO(callback);
      observers.set(this.id, { active: false, observes: 0, disconnects: 0 });
    }
    observe(...args) {
      const row = observers.get(this.id);
      row.active = true; row.observes += 1;
      return this.real.observe(...args);
    }
    disconnect() {
      const row = observers.get(this.id);
      row.active = false; row.disconnects += 1;
      return this.real.disconnect();
    }
    takeRecords() { return this.real.takeRecords(); }
  }
  window.MutationObserver = TrackedMO;

  const realSetTimeout = window.setTimeout.bind(window);
  const realClearTimeout = window.clearTimeout.bind(window);
  const timeouts = new Map();
  window.setTimeout = (fn, delay = 0, ...args) => {
    let id = 0;
    const wrapped = typeof fn === 'function' ? () => { timeouts.delete(id); return fn(...args); } : fn;
    id = realSetTimeout(wrapped, delay);
    timeouts.set(id, Number(delay) || 0);
    return id;
  };
  window.clearTimeout = (id) => { timeouts.delete(id); return realClearTimeout(id); };

  const realSetInterval = window.setInterval.bind(window);
  const realClearInterval = window.clearInterval.bind(window);
  const intervals = new Map();
  window.setInterval = (fn, delay = 0, ...args) => {
    const id = realSetInterval(fn, delay, ...args);
    intervals.set(id, Number(delay) || 0);
    return id;
  };
  window.clearInterval = (id) => { intervals.delete(id); return realClearInterval(id); };

  const realAdd = EventTarget.prototype.addEventListener;
  const realRemove = EventTarget.prototype.removeEventListener;
  const listenerIds = new WeakMap();
  let listenerSeq = 0;
  const registrations = new Map();
  const listenerId = (listener) => {
    if ((typeof listener !== 'function' && typeof listener !== 'object') || listener === null) return null;
    if (!listenerIds.has(listener)) listenerIds.set(listener, ++listenerSeq);
    return listenerIds.get(listener);
  };
  const captureOf = (options) => typeof options === 'boolean' ? options : !!options?.capture;
  const scopedOf = (options) => typeof options === 'object' && options !== null && (options.once === true || !!options.signal);
  const targetKey = (target) => target === window ? 'window' : 'document';
  const registrationKey = (target, type, listener, options) => {
    const id = listenerId(listener);
    return id === null ? null : `${targetKey(target)}:${type}:${id}:${captureOf(options) ? 1 : 0}`;
  };
  EventTarget.prototype.addEventListener = function(type, listener, options) {
    if ((this === window || this === document) && !scopedOf(options)) {
      const key = registrationKey(this, type, listener, options);
      if (key) registrations.set(key, { target: targetKey(this), type: String(type) });
    }
    return realAdd.call(this, type, listener, options);
  };
  EventTarget.prototype.removeEventListener = function(type, listener, options) {
    if (this === window || this === document) {
      const key = registrationKey(this, type, listener, options);
      if (key) registrations.delete(key);
    }
    return realRemove.call(this, type, listener, options);
  };

  window.__rohmatLifecycleProbe = {
    snapshot() {
      const rows = [...observers.values()];
      const globalListeners = {};
      for (const row of registrations.values()) {
        const key = `${row.target}:${row.type}`;
        globalListeners[key] = (globalListeners[key] || 0) + 1;
      }
      return {
        observersCreated: rows.length,
        activeObservers: rows.filter((x) => x.active).length,
        observerDisconnects: rows.reduce((n, x) => n + x.disconnects, 0),
        intervals: intervals.size,
        pendingTimeouts: timeouts.size,
        longTimeouts: [...timeouts.values()].filter((ms) => ms >= 1000).length,
        globalListeners: Object.fromEntries(Object.entries(globalListeners).sort())
      };
    }
  };
};

async function snapshot(page, label) {
  const value = await page.evaluate(() => window.__rohmatLifecycleProbe?.snapshot());
  if (!value) fail(`${label}:probe_missing`);
  console.log('LIFECYCLE_SNAPSHOT', label, JSON.stringify(value));
  return value;
}

function mergeListenerBaseline(...states) {
  const merged = {};
  for (const state of states) for (const [key, value] of Object.entries(state || {})) merged[key] = Math.max(Number(merged[key] || 0), Number(value || 0));
  return merged;
}

function assertNoListenerGrowth(current, baseline, label) {
  for (const [key, value] of Object.entries(current)) {
    const allowed = Number(baseline[key] || 0);
    if (Number(value) > allowed) fail(`${label}:global_listener_growth:${key}:${value}/${allowed}`);
  }
}

async function enterMenu(page) {
  await page.waitForSelector('#next', { timeout: 10000 });
  await page.evaluate(() => {
    const input = document.querySelector('input[name="mode"][value="take-away"]') || document.querySelector('input[value="take-away"]');
    if (!input) throw new Error('takeaway_missing');
    input.checked = true;
    input.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await page.locator('#next').click();
  await page.waitForSelector('.grid [data-id][data-a="+"]', { timeout: 10000 });
}

async function backHome(page) {
  const back = page.locator('#back');
  if (await back.count()) {
    await back.click();
    await page.waitForSelector('#next', { timeout: 10000 });
  }
}

async function main() {
  const srv = server();
  await new Promise((resolve, reject) => { srv.once('error', reject); srv.listen(PORT, '127.0.0.1', resolve); });
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'id-ID' });
    await context.addInitScript(probeScript);
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(`console:${m.text()}`); });
    await page.route(url => url.toString().startsWith(RUM), async (route) => route.request().method() === 'POST' ? route.fulfill({ status: 204, headers: { 'access-control-allow-origin': ORIGIN } }) : route.continue());

    const response = await page.goto(ORIGIN, { waitUntil: 'domcontentloaded', timeout: 30000 });
    if (!response || response.status() !== 200) fail(`http_${response?.status()}`);
    if (response.headers()['x-rohmat-public-lifecycle'] !== 'v1') fail(`lifecycle_header_${response.headers()['x-rohmat-public-lifecycle']}`);
    await page.waitForFunction(() => document.documentElement.dataset.rohmatLifecycleRuntime === 'v65', null, { timeout: 10000 });
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
    await sleep(300);

    const initial = await snapshot(page, 'initial');
    if (initial.intervals !== 0) fail(`initial_interval_leak_${initial.intervals}`);
    let listenerBaseline = { ...initial.globalListeners };
    const warmupCycles = 2;
    const verificationCycles = 8;
    const totalCycles = warmupCycles + verificationCycles;

    let maxActive = initial.activeObservers;
    let maxLongTimers = initial.longTimeouts;
    for (let i = 0; i < totalCycles; i += 1) {
      await enterMenu(page);
      const menuState = await snapshot(page, `menu-${i + 1}`);
      maxActive = Math.max(maxActive, menuState.activeObservers);
      maxLongTimers = Math.max(maxLongTimers, menuState.longTimeouts);
      if (menuState.intervals !== 0) fail(`menu_${i + 1}_interval_leak_${menuState.intervals}`);
      if (i < warmupCycles) listenerBaseline = mergeListenerBaseline(listenerBaseline, menuState.globalListeners);
      else assertNoListenerGrowth(menuState.globalListeners, listenerBaseline, `menu_${i + 1}`);
      await backHome(page);
      await sleep(i < warmupCycles ? 250 : 40);
      const homeState = await snapshot(page, `home-${i + 1}`);
      maxActive = Math.max(maxActive, homeState.activeObservers);
      maxLongTimers = Math.max(maxLongTimers, homeState.longTimeouts);
      if (homeState.intervals !== 0) fail(`home_${i + 1}_interval_leak_${homeState.intervals}`);
      if (i < warmupCycles) listenerBaseline = mergeListenerBaseline(listenerBaseline, homeState.globalListeners);
      else assertNoListenerGrowth(homeState.globalListeners, listenerBaseline, `home_${i + 1}`);
      if (homeState.activeObservers > initial.activeObservers + 1) fail(`observer_growth_${homeState.activeObservers}_${initial.activeObservers}`);
    }

    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })));
    await sleep(80);
    const hidden = await snapshot(page, 'pagehide');
    if (hidden.intervals !== 0) fail(`pagehide_interval_leak_${hidden.intervals}`);
    if (hidden.activeObservers > initial.activeObservers) fail(`pagehide_observer_not_cleaned_${hidden.activeObservers}_${initial.activeObservers}`);
    if (hidden.longTimeouts >= maxLongTimers && maxLongTimers > 0) fail(`pagehide_long_timers_not_reduced_${hidden.longTimeouts}_${maxLongTimers}`);

    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
    await sleep(150);
    const restored = await snapshot(page, 'pageshow-restored');
    if (restored.intervals !== 0) fail(`restore_interval_leak_${restored.intervals}`);
    assertNoListenerGrowth(restored.globalListeners, listenerBaseline, 'restore');
    if (restored.activeObservers > initial.activeObservers + 1) fail(`restore_observer_growth_${restored.activeObservers}_${initial.activeObservers}`);
    if (errors.length) fail(`browser_errors:${errors.join('|')}`);

    console.log(JSON.stringify({
      ok: true,
      warmupCycles,
      verificationCycles,
      stabilizedPersistentGlobalListeners: listenerBaseline,
      initial,
      pagehide: hidden,
      restored,
      maxActiveObservers: maxActive,
      maxLongTimeouts: maxLongTimers,
      browserErrors: errors.length
    }, null, 2));
    console.log('PUBLIC_LIFECYCLE_BROWSER_GATE_PASS=1');
    await context.close();
  } finally {
    await browser.close();
    await new Promise((resolve) => srv.close(resolve));
  }
}

main().catch((error) => { console.error(error); process.exit(1); });
