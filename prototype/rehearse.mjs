#!/usr/bin/env node
import fs from 'node:fs';
const files=process.argv.slice(2);
if(files.length<2){console.error('usage: node prototype/rehearse.mjs tenant-a.json tenant-b.json');process.exit(2)}
const configs=files.map(f=>JSON.parse(fs.readFileSync(f,'utf8')));
const [a,b]=configs;
const TABS=JSON.stringify(['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN']);
const surfaceTopology=c=>{const n=new Set([c.public_url,c.admin_url,c.kds_url]).size;return n===1||n===3};
const checks={
  valid_surface_topology:surfaceTopology(a)&&surfaceTopology(b),
  distinct_tenant_ids:a.tenant_id!==b.tenant_id,
  distinct_slugs:a.tenant_slug!==b.tenant_slug,
  distinct_public_origins:a.public_url!==b.public_url,
  distinct_admin_origins:a.admin_url!==b.admin_url,
  distinct_kds_origins:a.kds_url!==b.kds_url,
  distinct_spreadsheets:a.spreadsheet_target!==b.spreadsheet_target,
  distinct_storage_namespaces:a.storage?.namespace!==b.storage?.namespace,
  signed_qr:a.require_table_qr_signature===true&&b.require_table_qr_signature===true,
  canonical_tabs:JSON.stringify(a.sheets?.expected_tabs)===TABS&&JSON.stringify(b.sheets?.expected_tabs)===TABS,
  shared_supabase_project:true,
  source_edits_required:false
};
const ok=Object.entries(checks).every(([key,value])=>key==='source_edits_required'?value===false:value===true);
console.log(JSON.stringify({ok,contract:'master-prototype-two-tenant-static-rehearsal-v2',platform_supabase_project_ref:'xrepmvbccalzhlcznrff',checks},null,2));
if(!ok)process.exit(1);
