import { resolvePublicTenantConfig } from '../lib/tenant-config.js';

const env = {
  MASTER_PROTOTYPE_STRICT: '1',
  SDB_TENANT_ID: 'd8bb901c-7399-485b-8743-b319fde148ac',
  PUBLIC_ORIGIN: 'https://smart-cassier.vercel.app',
  BUSINESS_NAME: 'Rohmat Nasi Uduk',
  SUPABASE_URL: 'https://xrepmvbccalzhlcznrff.supabase.co',
  SUPABASE_ANON_KEY: 'test-key'
};

let fetchCalls = 0;
const realFetch = globalThis.fetch;
globalThis.fetch = async () => { fetchCalls += 1; throw new Error('unexpected_fetch'); };
try {
  const req = { headers: { 'x-forwarded-proto': 'https', 'x-forwarded-host': 'smart-cassier.vercel.app' } };
  const cfg = await resolvePublicTenantConfig(req, env);
  if (!cfg.ok || cfg.tenantId !== env.SDB_TENANT_ID || cfg.resolvedBy !== 'environment-canonical' || fetchCalls !== 0) {
    throw new Error('canonical_fastpath_failed');
  }
  console.log(JSON.stringify({ ok:true, tenantId:cfg.tenantId, resolvedBy:cfg.resolvedBy, fetchCalls }));
  console.log('BATCH5_TENANT_CANONICAL_FASTPATH_PASS=1');
} finally {
  globalThis.fetch = realFetch;
}
