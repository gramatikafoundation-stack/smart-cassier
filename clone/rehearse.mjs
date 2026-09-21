#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = process.argv.slice(2).length ? process.argv.slice(2) : ['clone/rehearsal-a.json','clone/rehearsal-b.json'];
const CANONICAL_TABS = ['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN'];
const SOURCE_REF = 'yybhpmjuywjxqurrrrxl';
const SOURCE_DOMAINS = [
  'rohmat-pesan-bayar-publik.vercel.app',
  'studio-pengelola-rohmat.vercel.app',
  'rohmat-kds-printer.vercel.app'
];

function fail(message) {
  console.error(`REHEARSAL_FAIL: ${message}`);
  process.exit(1);
}
function run(script, config) {
  const r = spawnSync(process.execPath, [path.join(repoRoot, script), config], { cwd: repoRoot, encoding: 'utf8' });
  if (r.status !== 0) fail(`${script} ${config}: ${(r.stderr || r.stdout).trim()}`);
  try { return JSON.parse(r.stdout); } catch { fail(`${script} ${config}: invalid JSON output`); }
}
function runText(script, config) {
  const r = spawnSync(process.execPath, [path.join(repoRoot, script), config], { cwd: repoRoot, encoding: 'utf8' });
  if (r.status !== 0) fail(`${script} ${config}: ${(r.stderr || r.stdout).trim()}`);
  return r.stdout;
}
function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === '.DS_Store') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full)); else if (entry.isFile()) out.push(full);
  }
  return out;
}
function sourceFingerprint() {
  const roots = ['apps','supabase'];
  const h = crypto.createHash('sha256');
  for (const root of roots) {
    for (const file of walk(path.join(repoRoot, root)).sort()) {
      h.update(path.relative(repoRoot, file).replaceAll(path.sep, '/'));
      h.update('\0');
      h.update(fs.readFileSync(file));
      h.update('\0');
    }
  }
  return h.digest('hex');
}

const required = [
  'apps/public/api/render.js','apps/public/vercel.json',
  'apps/admin/api/render.js','apps/admin/vercel.json',
  'apps/kds/api/kds.js','apps/kds/api/config.js','apps/kds/tenant-runtime.js','apps/kds/vercel.json',
  'clone/merchant.config.schema.json','clone/runtime-env-contract.json','clone/migration-policy.json','clone/pre-bootstrap.sql','clone/generate-finalization-sql.mjs','clone/menu.example.json','integrations/google-sheets/master-writer-v1/Code.gs',
  'ops/canonical-edge-functions-v1.json',
  'supabase/migrations/20260913_kds_bff_bound_login_v1.sql',
  'supabase/migrations/20260913_privacy_least_privilege_phase2.sql'
];
for (const file of required) if (!fs.existsSync(path.join(repoRoot, file))) fail(`missing required master source: ${file}`);

const edgeInventory = JSON.parse(fs.readFileSync(path.join(repoRoot,'ops/canonical-edge-functions-v1.json'),'utf8'));
const migrationPolicy = JSON.parse(fs.readFileSync(path.join(repoRoot,'clone/migration-policy.json'),'utf8'));
for (const requiredExclude of [
  '20260918192858_smart_digital_indonesia_platform_foundation_v1.sql',
  '20260918192947_smart_digital_indonesia_platform_hardening_v1.sql',
  '20260919053827_create_rdc_recovery_channel.sql',
  '20260919053901_secure_rdc_recovery_rest_policies.sql'
]) if (!migrationPolicy.exclude_exact.includes(requiredExclude)) fail(`migration policy must exclude ${requiredExclude}`);
const expectedFunctions = edgeInventory.functions.filter(x => x.deploy_on_clone === true).map(x => x.slug).sort();
if (!expectedFunctions.length) fail('canonical Edge Function inventory is empty');

const bootstrapSql = fs.readFileSync(path.join(repoRoot,'clone/pre-bootstrap.sql'),'utf8');
if (!/create\s+extension\s+if\s+not\s+exists\s+pg_net\s+with\s+schema\s+extensions/i.test(bootstrapSql)) fail('pg_net pre-bootstrap must install into extensions');
if (!bootstrapSql.includes("expected extensions")) fail('pg_net pre-bootstrap schema assertion missing');

const writerSource = fs.readFileSync(path.join(repoRoot,'integrations/google-sheets/master-writer-v1/Code.gs'),'utf8');
if (!writerSource.includes("function enforcePiiRetention()")
    || !writerSource.includes("function installPiiRetentionTrigger()")
    || !writerSource.includes("SDB_PII_RETENTION_DAYS")
    || !writerSource.includes("enforcePiiRetentionForSpreadsheet_")) {
  fail('writer retention source contract missing');
}
for (const forbidden of ['yybhpmjuywjxqurrrrxl','rohmat-pesan-bayar-publik.vercel.app','Rohmat Nasi Uduk']) {
  if (writerSource.includes(forbidden)) fail('writer tenant leak: '+forbidden);
}

const before = sourceFingerprint();
const results = fixtures.map(config => {
  const validation = run('clone/validate-config.mjs', config);
  const plan = run('clone/provision-plan.mjs', config);
  const finalSql = runText('clone/generate-finalization-sql.mjs', config);
  const configJson = JSON.parse(fs.readFileSync(path.join(repoRoot,config),'utf8'));

  if (validation.source_edits_required !== false || plan.source_edits_required !== false) fail(`${config}: source edit flag is not false`);
  if (validation.schema_version !== 2) fail(`${config}: schema v2 required`);
  if (validation.signed_table_qr !== true) fail(`${config}: signed table QR required`);
  if (JSON.stringify(validation.spreadsheet_tabs) !== JSON.stringify(CANONICAL_TABS)) fail(`${config}: spreadsheet tabs drift`);
  if (plan.contract !== 'master-clone-provision-plan-v2') fail(`${config}: provision plan v2 required`);
  if (plan.supabase?.migrations?.policy !== 'clone/migration-policy.json') fail(`${config}: migration policy missing from plan`);
  if (plan.supabase?.migrations?.pre_bootstrap !== 'clone/pre-bootstrap.sql' || plan.supabase?.migrations?.pre_bootstrap_before_history !== true) fail(`${config}: pg_net pre-bootstrap ordering missing`);
  if (plan.supabase?.security?.pg_net_schema !== 'extensions') fail(`${config}: pg_net schema contract missing`);
  if (plan.supabase?.security?.leaked_password_protection_required_for_production !== true) fail(`${config}: leaked-password production gate missing`);
  if (plan.sheets?.writer?.source !== 'integrations/google-sheets/master-writer-v1/Code.gs'
      || plan.sheets?.writer?.version !== 4
      || plan.sheets?.writer?.pii_retention_days !== 365
      || plan.sheets?.writer?.required_post_deploy_action !== 'installPiiRetentionTrigger') {
    fail(`${config}: writer v4 contract missing`);
  }
  if (plan.sheets?.writer?.script_properties?.SDB_BUSINESS_NAME !== configJson.business_name
      || plan.sheets?.writer?.script_properties?.SDB_TZ !== configJson.timezone
      || plan.sheets?.writer?.script_properties?.SDB_PII_RETENTION_DAYS !== '365') {
    fail(`${config}: writer tenant Script Properties drift`);
  }
  if (plan.supabase?.migrations?.finalization_generator !== 'clone/generate-finalization-sql.mjs') fail(`${config}: tenant finalization generator missing`);
  if ((plan.supabase?.migrations?.exclude_exact||[]).some(x=>!migrationPolicy.exclude_exact.includes(x))) fail(`${config}: migration exclusion drift`);
  if ((plan.supabase?.required_edge_functions||[]).includes('rohmat-static-publisher-v1')) fail(`${config}: locked legacy publisher must not deploy on clone`);
  if (plan.source?.roots?.public !== 'apps/public' || plan.source?.roots?.admin !== 'apps/admin' || plan.source?.roots?.kds !== 'apps/kds') fail(`${config}: invalid app roots`);

  for (const app of ['public','admin','kds']) {
    if (plan.vercel?.[app]?.env?.MASTER_CLONE_STRICT !== '1') fail(`${config}: ${app} strict mode missing`);
  }

  const actualFunctions = [...(plan.supabase?.required_edge_functions || [])].sort();
  if (JSON.stringify(actualFunctions) !== JSON.stringify(expectedFunctions)) fail(`${config}: Edge Function inventory mismatch`);

  const serialized = JSON.stringify(plan);
  if (serialized.includes(SOURCE_REF)) fail(`${config}: Rohmat production Supabase ref leaked into clone plan`);
  for (const domain of SOURCE_DOMAINS) if (serialized.includes(domain)) fail(`${config}: Rohmat production domain leaked into clone plan`);
  if (finalSql.includes(SOURCE_REF)) fail(`${config}: Rohmat production Supabase ref leaked into finalization SQL`);
  for (const domain of SOURCE_DOMAINS) if (finalSql.includes(domain)) fail(`${config}: Rohmat production domain leaked into finalization SQL`);
  if (!finalSql.includes(configJson.supabase_project_ref) || !finalSql.includes(new URL(configJson.public_url).origin) || !finalSql.includes(new URL(configJson.admin_url).origin) || !finalSql.includes(new URL(configJson.kds_url).origin)) fail(`${config}: finalization SQL missing tenant resources`);
  if (!finalSql.includes('require_table_qr_signature=true')) fail(`${config}: finalization SQL does not enforce signed table QR`);

  if (configJson.business_name !== configJson.merchant_name && configJson.merchant_name_acknowledged !== true) {
    fail(`${config}: differing payment merchant name must be acknowledged`);
  }

  if (!Array.isArray(plan.acceptance) || plan.acceptance.length < 7) fail(`${config}: incomplete acceptance gates`);
  return { config, validation, plan };
});
const after = sourceFingerprint();
if (before !== after) fail('master application/database source changed during rehearsal');

const slugs = results.map(x => x.validation.merchant_slug);
if (new Set(slugs).size !== slugs.length) fail('rehearsal merchant slugs must be distinct');
const urls = results.flatMap(x => [x.plan.merchant.public_url, x.plan.merchant.admin_url, x.plan.merchant.kds_url]);
if (new Set(urls).size !== urls.length) fail('rehearsal URLs must be distinct across merchants/apps');
const refs = results.map(x => x.plan.supabase.project_ref);
if (new Set(refs).size !== refs.length) fail('rehearsal Supabase project refs must be distinct');
const sheets = results.map(x => x.plan.sheets.target);
if (new Set(sheets).size !== sheets.length) fail('rehearsal spreadsheet targets must be distinct');

console.log(JSON.stringify({
  ok: true,
  contract: 'master-clone-rehearsal-v2',
  rehearsal_count: results.length,
  zero_source_edits: before === after,
  strict_clone_mode: true,
  signed_table_qr: true,
  canonical_spreadsheet_tabs: CANONICAL_TABS,
  canonical_edge_functions: expectedFunctions.length,
  source_fingerprint_sha256: before,
  rehearsals: results.map(x => ({
    config: x.config,
    merchant_slug: x.validation.merchant_slug,
    locale: x.validation.locale,
    currency: x.validation.currency,
    timezone: x.validation.timezone,
    table_count: x.validation.table_count,
    menu_items: x.validation.menu_items,
    public_root: x.plan.source.roots.public,
    admin_root: x.plan.source.roots.admin,
    kds_root: x.plan.source.roots.kds,
    source_edits_required: false
  }))
}, null, 2));
