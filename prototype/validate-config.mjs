#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const file=path.resolve(root,process.argv[2]||'prototype/tenant.example.json');
const c=JSON.parse(fs.readFileSync(file,'utf8'));
const REF=Object.freeze({
  tenant_id:'d8bb901c-7399-485b-8743-b319fde148ac',
  slug:'warung-nasi',
  urls:new Set(['https://smart-order-sdb.vercel.app']),
  spreadsheet_id:'1rj3kXuBGjQC_bkJXJ_n6Jao7hkco7rpFF7avozcj-Ok'
});
const TABS=['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN'];
const VISIBLE_TABS=['Dashboard','Data Pemesan','Data Pesanan Makanan','Data Pesanan Minuman','Riwayat Pembayaran'];
const VISUAL_TEMPLATE_ID='1OnUxxqbwRjjQY18J3A2ypkIlPBKqOMMeB11G_OsHzFM';
const fail=m=>{console.error('TENANT_CONFIG_INVALID: '+m);process.exit(1)};
const uuid=v=>/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(v||''));
const origin=(v,k)=>{try{const u=new URL(v);if(u.protocol!=='https:'||u.pathname!=='/'||u.search||u.hash)fail(k+' must be bare https origin');return u.origin}catch{fail(k+' invalid')}};
if(c.schema_version!==1)fail('schema_version must be 1');
if(!uuid(c.tenant_id))fail('tenant_id must be UUID');
if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(c.tenant_slug||''))fail('tenant_slug format');
if(!String(c.business_name||'').trim())fail('business_name');
if(!String(c.merchant_name||'').trim())fail('merchant_name');
if(c.business_name!==c.merchant_name&&c.merchant_name_acknowledged!==true)fail('merchant_name difference must be acknowledged');
if(!/^[A-Z]{3}$/.test(c.currency||''))fail('currency');
try{new Intl.DateTimeFormat('en-US',{timeZone:c.timezone}).format(new Date())}catch{fail('timezone')}
const origins=['public_url','admin_url','kds_url'].map(k=>origin(c[k],k));
// Unified SMART ORDER uses one origin with route-separated Public/Admin/KDS surfaces.
if(!Number.isInteger(c.table_count)||c.table_count<1||c.table_count>200)fail('table_count');
if(c.require_table_qr_signature!==true)fail('signed table QR is required');
if(Number(c.retention?.application_days)!==30)fail('application retention must be exactly 30 days');
if(c.retention?.external_spreadsheet_archive!=='permanent'||c.retention?.external_archive_reset!==false)fail('external spreadsheet archive must be permanent and never auto-reset');
if(!/^prototype\/.+\.json$/.test(c.menu_seed||''))fail('menu_seed must live under prototype/');
const menuPath=path.resolve(root,c.menu_seed);
if(!menuPath.startsWith(path.join(root,'prototype')+path.sep)||!fs.existsSync(menuPath))fail('menu_seed not found');
const menu=JSON.parse(fs.readFileSync(menuPath,'utf8'));
if(!Array.isArray(menu)||!menu.length)fail('menu_seed must be non-empty');
if(!Array.isArray(c.sheets?.expected_tabs)||JSON.stringify(c.sheets.expected_tabs)!==JSON.stringify(TABS))fail('expected_tabs must exactly match canonical five technical tabs');
if(!Array.isArray(c.sheets?.visible_tabs)||JSON.stringify(c.sheets.visible_tabs)!==JSON.stringify(VISIBLE_TABS))fail('visible_tabs must exactly match SMART CASHIER visual master');
if(String(c.sheets?.visual_template_source_spreadsheet_id||'')!==VISUAL_TEMPLATE_ID)fail('visual template source must be canonical SMART CASHIER DATABASE 2026');
if(!c.storage?.namespace||c.storage.namespace!==c.tenant_slug)fail('storage.namespace must equal tenant_slug');
if(c.tenant_slug!==REF.slug){
  if(c.tenant_id===REF.tenant_id)fail('new tenant must not reuse Rohmat tenant_id');
  if(origins.some(x=>REF.urls.has(x)))fail('new tenant must not reuse Rohmat production origin');
  if(String(c.spreadsheet_target||'').includes(REF.spreadsheet_id))fail('new tenant must not reuse Rohmat spreadsheet');
}
console.log(JSON.stringify({
  ok:true,
  contract:'smart-order-sdb-master-prototype-v9',
  master_tenant_reference:c.tenant_id===REF.tenant_id&&c.tenant_slug===REF.slug,
  platform_supabase_project_ref:'xrepmvbccalzhlcznrff',
  tenant_id:c.tenant_id,
  tenant_slug:c.tenant_slug,
  source_edits_required:false,
  source_clone_required:false,
  supabase_project_clone_required:false,
  tenancy_mode:'shared_database_rls',
  spreadsheet_tabs:c.sheets.expected_tabs,
  spreadsheet_visible_tabs:c.sheets.visible_tabs,
  spreadsheet_visual_template_source_id:c.sheets.visual_template_source_spreadsheet_id
},null,2));
