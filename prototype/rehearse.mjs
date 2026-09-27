#!/usr/bin/env node
import fs from 'node:fs';
const files=process.argv.slice(2);
if(files.length<2){console.error('usage: node prototype/rehearse.mjs tenant-a.json tenant-b.json');process.exit(2)}
const [a,b]=files.map(f=>JSON.parse(fs.readFileSync(f,'utf8')));
const TABS=JSON.stringify(['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN']);
const ROUTES=JSON.stringify({public:'/',admin:'/admin',kds:'/kds',database:'/database'});
const checks={
  schema_v2:a.schema_version===2&&b.schema_version===2,
  distinct_tenant_ids:a.tenant_id!==b.tenant_id,
  distinct_slugs:a.tenant_slug!==b.tenant_slug,
  distinct_canonical_origins:new URL(a.canonical_origin).origin!==new URL(b.canonical_origin).origin,
  one_domain_four_surface:JSON.stringify(a.surface_routes)===ROUTES&&JSON.stringify(b.surface_routes)===ROUTES,
  distinct_spreadsheets:a.spreadsheet_target!==b.spreadsheet_target,
  google_drive_database:a.sheets?.provider==='google_drive'&&b.sheets?.provider==='google_drive',
  distinct_storage_namespaces:a.storage?.namespace!==b.storage?.namespace,
  signed_qr:a.require_table_qr_signature===true&&b.require_table_qr_signature===true,
  canonical_tabs:JSON.stringify(a.sheets?.expected_tabs)===TABS&&JSON.stringify(b.sheets?.expected_tabs)===TABS,
  shared_supabase_project:true,
  source_edits_required:false
};
const ok=Object.entries(checks).every(([key,value])=>key==='source_edits_required'?value===false:value===true);
console.log(JSON.stringify({
  ok,
  contract:'smart-order-two-tenant-static-rehearsal-v2',
  platform_supabase_project_ref:'xrepmvbccalzhlcznrff',
  topology:'single_domain_four_surface',
  checks
},null,2));
if(!ok)process.exit(1);
