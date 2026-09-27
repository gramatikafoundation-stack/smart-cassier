#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const file=path.resolve(root,process.argv[2]||'prototype/tenant.example.json');
const c=JSON.parse(fs.readFileSync(file,'utf8'));
const templates=JSON.parse(fs.readFileSync(path.join(root,'prototype/google-drive-template-set.json'),'utf8'));

const REF=Object.freeze({
  tenant_id:'d8bb901c-7399-485b-8743-b319fde148ac',
  slug:'warung-nasi',
  canonical_origin:'https://smart-order-sdb.vercel.app'
});
const ROUTES={public:'/',admin:'/admin',kds:'/kds',database:'/database'};
const fail=m=>{console.error('TENANT_CONFIG_INVALID: '+m);process.exit(1)};
const uuid=v=>/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(v||''));
const origin=(v,k)=>{try{const u=new URL(v);if(u.protocol!=='https:'||u.pathname!=='/'||u.search||u.hash)fail(k+' must be bare https origin');return u.origin}catch{fail(k+' invalid')}};

if(c.schema_version!==2)fail('schema_version must be 2');
if(!uuid(c.tenant_id))fail('tenant_id must be UUID');
if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(c.tenant_slug||''))fail('tenant_slug format');
if(!String(c.business_name||'').trim())fail('business_name');
if(!String(c.merchant_name||'').trim())fail('merchant_name');
if(c.business_name!==c.merchant_name&&c.merchant_name_acknowledged!==true)fail('merchant_name difference must be acknowledged');
if(!/^[A-Z]{3}$/.test(c.currency||''))fail('currency');
try{new Intl.DateTimeFormat('en-US',{timeZone:c.timezone}).format(new Date())}catch{fail('timezone')}

const canonical=origin(c.canonical_origin,'canonical_origin');
if(JSON.stringify(c.surface_routes)!==JSON.stringify(ROUTES))fail('surface_routes must exactly match /, /admin, /kds, /database');
if(!Number.isInteger(c.table_count)||c.table_count<1||c.table_count>200)fail('table_count');
if(c.require_table_qr_signature!==true)fail('signed table QR is required');
if(!/^prototype\/.+\.json$/.test(c.menu_seed||''))fail('menu_seed must live under prototype/');
const menuPath=path.resolve(root,c.menu_seed);
if(!menuPath.startsWith(path.join(root,'prototype')+path.sep)||!fs.existsSync(menuPath))fail('menu_seed not found');
const menu=JSON.parse(fs.readFileSync(menuPath,'utf8'));
if(!Array.isArray(menu)||!menu.length)fail('menu_seed must be non-empty');

if(templates.contract!=='smart-cashier-google-drive-template-set-v1')fail('template manifest contract');
if(templates.template_set!=='smart-cashier-annual-2026-2030-v1')fail('template manifest id');
if(templates.writer_version!==5)fail('template manifest writer_version');
if(c.sheets?.provider!=='google_drive')fail('sheets.provider must be google_drive');
if(c.sheets?.template_set!==templates.template_set)fail('sheets.template_set');
if(!Array.isArray(c.sheets?.expected_tabs)||JSON.stringify(c.sheets.expected_tabs)!==JSON.stringify(templates.required_tabs))fail('expected_tabs must match canonical SMART CASHIER archive tabs');
if(c.sheets.start_year!==2026||c.sheets.years!==5)fail('master v1 uses 2026-2030 yearly templates');
if(Object.keys(templates.templates||{}).sort().join(',')!=='2026,2027,2028,2029,2030')fail('template years incomplete');
if(!c.storage?.namespace||c.storage.namespace!==c.tenant_slug)fail('storage.namespace must equal tenant_slug');

if(c.tenant_slug!==REF.slug){
  if(c.tenant_id===REF.tenant_id)fail('new tenant must not reuse reference tenant_id');
  if(canonical===REF.canonical_origin)fail('new tenant must not reuse master canonical origin');
}

console.log(JSON.stringify({
  ok:true,
  contract:'smart-order-master-tenant-v2',
  platform_supabase_project_ref:'xrepmvbccalzhlcznrff',
  tenant_id:c.tenant_id,
  tenant_slug:c.tenant_slug,
  canonical_origin:canonical,
  surface_routes:ROUTES,
  database_url:canonical+'/database',
  source_edits_required:false,
  source_clone_required:false,
  supabase_project_clone_required:false,
  tenancy_mode:'shared_database_rls',
  spreadsheet_provider:'google_drive',
  spreadsheet_template_set:templates.template_set,
  spreadsheet_template_years:Object.keys(templates.templates).map(Number),
  spreadsheet_tabs:templates.required_tabs,
  spreadsheet_copy_policy:templates.clone_policy.mode,
  writer_version:templates.writer_version
},null,2));
