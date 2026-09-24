const CACHE_MS = 30000;
const RUNTIME_PATH = '/functions/v1/rohmat-public-element-runtime-v64';
const memo = new Map();

function canonicalUpstream() {
  const base = String(process.env.SUPABASE_URL || '').trim().replace(/\/$/, '');
  const tenant = String(process.env.SDB_TENANT_ID || '').trim();
  if (!base || !tenant) throw new Error('canonical_tenant_runtime_unavailable');
  const baseUrl = new URL(base);
  if (baseUrl.protocol !== 'https:' || !baseUrl.hostname.endsWith('.supabase.co') || baseUrl.username || baseUrl.password) {
    throw new Error('invalid_canonical_runtime_origin');
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(tenant)) {
    throw new Error('invalid_canonical_runtime_tenant');
  }
  return base + RUNTIME_PATH + '?tenant=' + encodeURIComponent(tenant);
}

function readUpstream(req) {
  const rawQuery = Array.isArray(req?.query?.upstream) ? req.query.upstream[0] : req?.query?.upstream;
  const requested = String(rawQuery || new URL(req?.url || '/', 'https://runtime.invalid').searchParams.get('upstream') || '').trim();
  const raw = requested || canonicalUpstream();
  const u = new URL(raw);
  const tenant = String(u.searchParams.get('tenant') || '').trim();
  const configured = new URL(String(process.env.SUPABASE_URL || '').trim());
  if (
    u.protocol !== 'https:' ||
    configured.protocol !== 'https:' ||
    !configured.hostname.endsWith('.supabase.co') ||
    u.origin !== configured.origin ||
    u.pathname !== RUNTIME_PATH ||
    u.username ||
    u.password ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(tenant)
  ) {
    throw new Error('invalid_tenant_runtime_upstream');
  }
  u.hash = '';
  return u.href;
}

function replaceRequired(source, from, to, label, flags) {
  const count = source.split(from).length - 1;
  if (count !== 1) throw new Error(`lifecycle_marker_${label}_${count}`);
  flags.push(label);
  return source.replace(from, to);
}

function optimizeLifecycle(raw) {
  const flags = [];
  let out = raw;

  out = replaceRequired(
    out,
    "if(window.__rohmatPublicUXV17)return;window.__rohmatPublicUXV17=1;document.documentElement.dataset.rohmatPublicUx='v17';let pendingFocus=false,lastPage='';",
    "if(window.__rohmatPublicUXV17)return;window.__rohmatPublicUXV17=1;document.documentElement.dataset.rohmatPublicUx='v17';let pendingFocus=false,lastPage='',dialogObserver=null,dialogObserverTarget=null;function clearDialogObserver(){try{dialogObserver?.disconnect()}catch{}dialogObserver=null;dialogObserverTarget=null}",
    'dialog-observer-owner', flags
  );
  out = replaceRequired(
    out,
    "function dialog(){const d=document.getElementById('dlg');if(!d)return;",
    "function dialog(){const d=document.getElementById('dlg');if(!d){clearDialogObserver();return;}",
    'dialog-observer-detach', flags
  );
  out = replaceRequired(
    out,
    "if(!d.dataset.uxObs){d.dataset.uxObs='1';new MutationObserver(()=>{if(d.open){setTimeout(()=>document.getElementById('name')?.focus({preventScroll:true}),0)}else document.getElementById('confirm')?.focus({preventScroll:true})}).observe(d,{attributes:true,attributeFilter:['open']})}",
    "if(dialogObserverTarget!==d){clearDialogObserver();dialogObserverTarget=d;d.dataset.uxObs='1';dialogObserver=new MutationObserver(()=>{if(d.open){setTimeout(()=>document.getElementById('name')?.focus({preventScroll:true}),0)}else document.getElementById('confirm')?.focus({preventScroll:true})});dialogObserver.observe(d,{attributes:true,attributeFilter:['open']})}",
    'dialog-observer-rebind', flags
  );
  out = replaceRequired(
    out,
    "window.addEventListener('pageshow',schedule);patch();window.__rohmatUX=",
    "window.addEventListener('pageshow',schedule);window.addEventListener('pagehide',clearDialogObserver);patch();window.__rohmatUX=",
    'dialog-pagehide-cleanup', flags
  );
  out = replaceRequired(
    out,
    "function armPoll(){clearTimeout(pollTimer);const base=(navigator.connection&&navigator.connection.saveData)?60000:30000;pollTimer=setTimeout(async()=>{if(!document.hidden)await refresh(false);armPoll()},base+Math.floor(Math.random()*5000))}",
    "let pollActive=false;function stopPoll(){pollActive=false;clearTimeout(pollTimer);pollTimer=0}function armPoll(){stopPoll();if(document.hidden)return;pollActive=true;const base=(navigator.connection&&navigator.connection.saveData)?60000:30000;pollTimer=setTimeout(async()=>{pollTimer=0;if(!pollActive||document.hidden)return;await refresh(false);if(pollActive&&!document.hidden)armPoll()},base+Math.floor(Math.random()*5000))}function resumePoll(){if(document.hidden)return;if(!pollActive||!pollTimer)armPoll()}",
    'design-poll-owner', flags
  );
  out = replaceRequired(
    out,
    "window.addEventListener('pageshow',e=>{if(e.persisted)refresh(false)});window.addEventListener('focus',()=>refresh(false));document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh(false)});armPoll();",
    "window.addEventListener('pageshow',e=>{if(e.persisted)refresh(false);resumePoll()});window.addEventListener('focus',()=>{refresh(false);resumePoll()});document.addEventListener('visibilitychange',()=>{if(document.hidden)stopPoll();else{refresh(false);resumePoll()}});window.addEventListener('pagehide',stopPoll);armPoll();",
    'design-poll-pause-resume', flags
  );

  if (out.includes("setTimeout(async()=>{if(!document.hidden)await refresh(false);armPoll()")) throw new Error('hidden_poll_loop_remains');
  if (!out.includes('clearDialogObserver') || !out.includes('stopPoll') || !out.includes('resumePoll')) throw new Error('lifecycle_validation_failed');
  out += "\n;document.documentElement.dataset.rohmatLifecycleRuntime='v65';/* rohmat-lifecycle-runtime-v65 */\n";
  return { body: out, flags };
}

async function getRuntime(upstream) {
  const now = Date.now();
  const cached = memo.get(upstream);
  if (cached && now - cached.at < CACHE_MS) return cached.body;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2500);
  try {
    const response = await fetch(upstream, { cache: 'no-store', signal: controller.signal });
    if (!response.ok) throw new Error(`upstream_${response.status}`);
    const raw = await response.text();
    const mode = String(response.headers.get('x-rohmat-runtime-mode') || '').toLowerCase();
    if (mode === 'rum-only') {
      if (raw.length < 5000 || !raw.includes('__rohmatRumV3') || !raw.includes("rohmatRuntime='rum-only-batch1-v1'")) throw new Error('upstream_rum_invalid');
      memo.set(upstream, { body: raw, at: now });
      if (memo.size > 8) memo.delete(memo.keys().next().value);
      return raw;
    }
    if (raw.length < 40000 || !raw.includes('__rohmatPublicUXV17') || !raw.includes('__rohmatPublicDesignV24')) throw new Error('upstream_invalid');
    const optimized = optimizeLifecycle(raw);
    memo.set(upstream, { body: optimized.body, at: now });
    if (memo.size > 8) memo.delete(memo.keys().next().value);
    return optimized.body;
  } finally {
    clearTimeout(timer);
  }
}

export default async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.statusCode = 405;
    res.setHeader('Allow', 'GET, HEAD');
    return res.end('Method Not Allowed');
  }
  try {
    const upstream = readUpstream(req);
    const body = await getRuntime(upstream);
    res.statusCode = 200;
    res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=30, s-maxage=30, stale-while-revalidate=30');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    res.setHeader('X-Rohmat-Runtime', 'v68-origin-bound+canonical-fallback+lifecycle-or-rum');
    res.setHeader('X-Rohmat-Lifecycle', 'dialog-observer-owner+design-poll-pause-pagehide-bfcache');
    if (req.method === 'HEAD') return res.end();
    return res.end(body);
  } catch (error) {
    console.error('[runtime-lifecycle-503]', JSON.stringify({status:503,error:String(error?.message || error).slice(0,160)}));
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    return res.end(`/* lifecycle runtime unavailable: ${String(error?.message || error)} */`);
  }
}
