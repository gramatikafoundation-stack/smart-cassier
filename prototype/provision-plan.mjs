#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const file=path.resolve(root,process.argv[2]||'prototype/tenant.example.json');
const c=JSON.parse(fs.readFileSync(file,'utf8'));
const sharedRef='xrepmvbccalzhlcznrff';
const supabaseUrl='https://'+sharedRef+'.supabase.co';

const plan={
  contract:'master-prototype-tenant-provision-plan-v1',
  platform:'SMART DIGITAL FOR BUSINESS',
  source_edits_required:false,
  source_clone_required:false,
  database_project_clone_required:false,
  source:{
    repository:'gramatikafoundation-stack/smart-cassier',
    candidate_branch:'main',
    final_release_tag:'rohmat-master-prototype-v1.0.0'
  },
  tenant:{
    id:c.tenant_id,slug:c.tenant_slug,business_name:c.business_name,
    merchant_name:c.merchant_name,locale:c.locale,currency:c.currency,timezone:c.timezone
  },
  supabase:{
    shared_project_ref:sharedRef,
    shared_url:supabaseUrl,
    tenancy_mode:'shared_database_rls',
    operations:[
      'insert private.platform_tenants row',
      'insert private.tenant_runtime_config row',
      'insert private.tenant_memberships owner row',
      'insert private.tenant_sheet_targets rows',
      'insert private.tenant_table_qr_signatures rows',
      'seed tenant-scoped menu/config using tenant_id'
    ],
    edge_functions:'deploy-once-platform-wide',
    tenant_resolution:'explicit tenant id/slug/origin; fail closed when unresolved'
  },
  runtime:{
    required_env:{
      SDB_TENANT_ID:c.tenant_id,
      SDB_TENANT_SLUG:c.tenant_slug,
      SUPABASE_URL:supabaseUrl,
      BUSINESS_NAME:c.business_name,
      TENANT_LOCALE:c.locale,
      TENANT_CURRENCY:c.currency,
      TENANT_TIMEZONE:c.timezone
    },
    public_origin:c.public_url,admin_origin:c.admin_url,kds_origin:c.kds_url
  },
  storage:{namespace:c.storage.namespace,static_bucket:c.storage.static_bucket,payment_bucket:c.storage.payment_bucket,qris_asset:c.qris_asset},
  sheets:{
    target:c.spreadsheet_target,
    expected_tabs:c.sheets.expected_tabs,
    writer_source:'integrations/google-sheets/master-writer-v1/Code.gs',
    writer_version:4,
    deployment_mode:'one-webapp-per-tenant-same-canonical-source',
    script_properties:{
      SDB_TENANT_ID:c.tenant_id,
      SDB_DATA_ENDPOINT:supabaseUrl+'/functions/v1/rohmat-sheet-writer-data-v1',
      SDB_TARGETS_JSON:'generated from private.tenant_sheet_targets after workbook provisioning',
      SDB_TZ:c.timezone,
      SDB_BUSINESS_NAME:c.business_name,
      SDB_PII_RETENTION_DAYS:'365'
    },
    routing:'store deployed webapp URL in private.tenant_writer_config.writer_url',
    pii_retention_days:365,
    required_post_deploy_action:'installPiiRetentionTrigger'
  },
  acceptance:[
    'zero source edits per tenant',
    'same canonical Supabase project',
    'explicit tenant resolution',
    'cross-tenant read/write negative test PASS',
    'Public/Admin/KDS smoke PASS',
    'signed table QR PASS',
    '5-sheet consistency PASS',
    'Writer v4 tenant sync PASS'
  ]
};
console.log(JSON.stringify(plan,null,2));
