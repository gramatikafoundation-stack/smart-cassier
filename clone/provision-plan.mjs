#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const target = process.argv[2] || 'clone/merchant.config.example.json';
const configPath = path.resolve(repoRoot, target);
const c = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const edgeInventory = JSON.parse(fs.readFileSync(path.join(repoRoot, 'ops/canonical-edge-functions-v1.json'), 'utf8'));
const runtimeContract = JSON.parse(fs.readFileSync(path.join(repoRoot, 'clone/runtime-env-contract.json'), 'utf8'));
const migrationPolicy = JSON.parse(fs.readFileSync(path.join(repoRoot, 'clone/migration-policy.json'), 'utf8'));
const supabaseUrl = `https://${c.supabase_project_ref}.supabase.co`;
const supabaseOrigin = new URL(supabaseUrl).origin;
const slug = c.merchant_slug;
const requiredEdgeFunctions = edgeInventory.functions.filter(x => x.deploy_on_clone === true).map(x => x.slug);

const plan = {
  contract: 'master-clone-provision-plan-v2',
  source_edits_required: false,
  source: {
    repository: 'gramatikafoundation-stack/Rohmat-Master',
    production_branch: 'main',
    candidate_branch: 'release/master-clone-v1-freeze-20260919',
    final_release_tag: 'master-clone-v1.0.0',
    roots: { public: 'apps/public', admin: 'apps/admin', kds: 'apps/kds' }
  },
  merchant: {
    slug,
    business_name: c.business_name,
    merchant_name: c.merchant_name,
    merchant_name_acknowledged: c.merchant_name_acknowledged,
    locale: c.locale,
    currency: c.currency,
    timezone: c.timezone,
    table_count: c.table_count,
    public_url: c.public_url,
    admin_url: c.admin_url,
    kds_url: c.kds_url
  },
  supabase: {
    project_ref: c.supabase_project_ref,
    url: supabaseUrl,
    migrations: {
      source_glob: migrationPolicy.source_glob,
      policy: 'clone/migration-policy.json',
      pre_bootstrap: migrationPolicy.pre_bootstrap?.sql || 'clone/pre-bootstrap.sql',
      pre_bootstrap_before_history: migrationPolicy.pre_bootstrap?.run_before_history_replay === true,
      exclude_exact: migrationPolicy.exclude_exact,
      finalization_generator: migrationPolicy.finalization.generator
    },
    edge_env: {
      SUPABASE_URL: supabaseUrl,
      SUPABASE_PUBLISHABLE_KEY: '<provision-from-project>',
      BUSINESS_NAME: c.business_name,
      PUBLIC_ORIGIN: c.public_url,
      ADMIN_ORIGIN: c.admin_url,
      KDS_ORIGIN: c.kds_url,
      PUBLIC_ALLOWED_ORIGINS: c.public_url,
      ADMIN_ALLOWED_ORIGINS: c.admin_url,
      KDS_ALLOWED_ORIGINS: c.kds_url,
      PUBLIC_STATIC_BUCKET: c.storage?.static_bucket || 'merchant-static',
      PAYMENT_PROOF_BUCKET: c.storage?.payment_bucket || 'payment-proofs',
      ASSET_BUCKET: 'merchant-assets'
    },
    required_edge_functions: requiredEdgeFunctions,
    security: {
      pg_net_schema: 'extensions',
      leaked_password_protection_required_for_production: true,
      leaked_password_protection_minimum_plan: 'pro'
    },
    storage: {
      static_bucket: c.storage?.static_bucket || 'merchant-static',
      payment_bucket: c.storage?.payment_bucket || 'payment-proofs',
      qris_asset: c.qris_asset || null
    },
    seed: {
      menu: c.menu_seed,
      site_settings: {
        id: 1,
        business_name: c.business_name,
        merchant_name: c.merchant_name,
        locale: c.locale,
        currency: c.currency,
        timezone: c.timezone,
        public_url: c.public_url,
        admin_url: c.admin_url,
        kds_url: c.kds_url,
        qris_enabled: false,
        require_table_qr_signature: c.require_table_qr_signature !== false
      }
    }
  },
  vercel: {
    public: {
      suggested_project_name: `${slug}-public`,
      root_directory: 'apps/public',
      env: {
        MASTER_CLONE_STRICT: '1',
        SUPABASE_URL: supabaseUrl,
        PUBLIC_ORIGIN: c.public_url,
        PUBLIC_LKG_PATH: `/storage/v1/object/public/${c.storage.static_bucket}/public-lkg-v1.html`,
        BUSINESS_NAME: c.business_name,
        TENANT_LOCALE: c.locale,
        TENANT_CURRENCY: c.currency,
        TENANT_TIMEZONE: c.timezone
      }
    },
    admin: {
      suggested_project_name: `${slug}-admin`,
      root_directory: 'apps/admin',
      env: {
        MASTER_CLONE_STRICT: '1',
        ADMIN_RENDERER_URL: `${supabaseUrl}/functions/v1/rohmat-admin-render?mode=optimized`,
        ADMIN_CASHIER_LOADER_URL: `${supabaseUrl}/functions/v1/rohmat-admin-cashier-loader-v1?v=36`,
        SUPABASE_ORIGIN: supabaseOrigin,
        BUSINESS_NAME: c.business_name
      }
    },
    kds: {
      suggested_project_name: `${slug}-kds`,
      root_directory: 'apps/kds',
      env: {
        MASTER_CLONE_STRICT: '1',
        KDS_BFF_URL: `${supabaseUrl}/functions/v1/rohmat-kds-api`,
        SUPABASE_URL: supabaseUrl,
        SUPABASE_PUBLISHABLE_KEY: '<provision-from-project>',
        BUSINESS_NAME: c.business_name,
        TENANT_LOCALE: c.locale,
        TENANT_CURRENCY: c.currency,
        TENANT_TIMEZONE: c.timezone
      }
    }
  },
  sheets: {
    target: c.spreadsheet_target,
    start_year: c.sheets?.start_year || new Date().getUTCFullYear(),
    years: c.sheets?.years || 5,
    expected_tabs: c.sheets.expected_tabs,
    writer: {
      source: 'integrations/google-sheets/master-writer-v1/Code.gs',
      version: 4,
      deploy_mode: 'update-active-webapp-deployment',
      script_properties: {
        SDB_DATA_ENDPOINT: `${supabaseUrl}/functions/v1/rohmat-sheet-writer-data-v1`,
        SDB_TARGETS_JSON: '<generated-year-to-spreadsheet-id-json>',
        SDB_TZ: c.timezone,
        SDB_BUSINESS_NAME: c.business_name,
        SDB_PII_RETENTION_DAYS: '365'
      },
      required_post_deploy_action: 'installPiiRetentionTrigger',
      pii_retention_days: 365,
      pii_retention_scope: {
        PEMESAN: ['Nama Pemesan','No. WhatsApp'],
        PESANAN: ['Catatan Konsumen','Petugas Kasir'],
        KEUANGAN: ['Petugas','Bukti Pembayaran']
      }
    }
  },
  bootstrap: {
    admin_owner_email: c.admin_owner_email,
    table_qr_secret_mode: c.table_qr_secret_mode || 'generate-per-clone',
    generated_artifacts: ['table QR signatures','table QR images','initial site settings','menu seed','sheet target rows']
  },
  runtime_env_contract: runtimeContract,
  required_external_secrets: [
    'SUPABASE_SERVICE_ROLE_KEY',
    'SUPABASE_PUBLISHABLE_KEY',
    'ADMIN_OWNER_INITIAL_PASSWORD',
    'KDS_OWNER_INITIAL_PASSWORD',
    'TABLE_QR_SIGNING_SECRET',
    'SHEETS_WRITER_URL',
    'SHEETS_WRITER_SECRET'
  ],
  acceptance: [
    'no merchant-specific source edit',
    'Public smoke test PASS',
    'Admin smoke test PASS',
    'KDS smoke test PASS',
    'payment flow PASS',
    '5-sheet consistency PASS',
    'Google Sheets writer v4 deployed with tenant Script Properties and daily 365-day PII retention trigger',
    'table QR validation PASS',
    'monitoring health PASS',
    'pg_net extension installed outside public schema',
    'leaked-password protection enabled before production certification on Supabase Pro+'
  ]
};

console.log(JSON.stringify(plan, null, 2));
