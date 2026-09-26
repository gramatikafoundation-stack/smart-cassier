import assert from 'node:assert/strict';
import { resolvePublicTenantConfig } from '../lib/tenant-config.js';

const base={
  MASTER_PROTOTYPE_STRICT:'1',
  SDB_TENANT_ID:'d8bb901c-7399-485b-8743-b319fde148ac',
  PUBLIC_ORIGIN:'https://smart-cassier.vercel.app',
  BUSINESS_NAME:'Rohmat Nasi Uduk',
  TENANT_LOCALE:'id-ID',
  SUPABASE_URL:'https://xrepmvbccalzhlcznrff.supabase.co',
  SUPABASE_PUBLISHABLE_KEY:'test-publishable'
};
const req={headers:{host:'branch-preview.vercel.app','x-forwarded-proto':'https'}};
const realFetch=globalThis.fetch;
try{
  globalThis.fetch=async()=>new Response(JSON.stringify({ok:false,error:'tenant_not_resolved'}),{
    status:404,headers:{'content-type':'application/json'}
  });

  const preview=await resolvePublicTenantConfig(req,{...base,VERCEL_ENV:'preview'});
  assert.equal(preview.ok,true);
  assert.equal(preview.tenantId,base.SDB_TENANT_ID);
  assert.equal(preview.origin,base.PUBLIC_ORIGIN);
  assert.equal(preview.requestOrigin,'https://branch-preview.vercel.app');
  assert.equal(preview.resolvedBy,'preview-environment-fallback');

  const production=await resolvePublicTenantConfig(req,{...base,VERCEL_ENV:'production'});
  assert.equal(production.ok,false);
  assert.deepEqual(production.missing,['TENANT_ORIGIN_MAPPING']);

  console.log('BATCH5_PREVIEW_TENANT_FALLBACK_GATE_PASS=1');
} finally {
  globalThis.fetch=realFetch;
}
