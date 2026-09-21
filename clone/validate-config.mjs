#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const target = process.argv[2] || 'clone/merchant.config.example.json';
const configPath = path.resolve(repoRoot, target);

const SOURCE_TENANT = Object.freeze({
  slug: 'rohmat-nasi-uduk',
  supabase_project_ref: 'yybhpmjuywjxqurrrrxl',
  urls: new Set([
    'https://rohmat-pesan-bayar-publik.vercel.app',
    'https://studio-pengelola-rohmat.vercel.app',
    'https://rohmat-kds-printer.vercel.app'
  ]),
  spreadsheet_id: '1rj3kXuBGjQC_bkJXJ_n6Jao7hkco7rpFF7avozcj-Ok'
});
const CANONICAL_TABS = ['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN'];

function fail(message) {
  console.error(`CONFIG_INVALID: ${message}`);
  process.exit(1);
}
function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (error) { fail(`${path.relative(repoRoot, file)}: ${error.message}`); }
}
function bareOrigin(value, key) {
  try {
    const u = new URL(value);
    if (u.protocol !== 'https:' || u.pathname !== '/' || u.search || u.hash) fail(`${key} must be a bare https origin`);
    return u.origin;
  } catch { fail(`${key} must be a valid https origin`); }
}
function validTimeZone(value) {
  try { new Intl.DateTimeFormat('en-US', { timeZone: value }).format(new Date()); return true; }
  catch { return false; }
}

const c = readJson(configPath);
const required = [
  'schema_version','merchant_slug','business_name','merchant_name','merchant_name_acknowledged',
  'locale','currency','timezone','public_url','admin_url','kds_url','qris_asset',
  'table_count','table_qr_secret_mode','require_table_qr_signature','menu_seed',
  'admin_owner_email','supabase_project_ref','spreadsheet_target','storage','sheets'
];
for (const key of required) if (c[key] === undefined || c[key] === null || c[key] === '') fail(`missing ${key}`);
if (c.schema_version !== 2) fail('schema_version must be 2');
if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(c.merchant_slug) || c.merchant_slug.length > 48) fail('merchant_slug format');
if (String(c.business_name).length < 2 || String(c.business_name).length > 100) fail('business_name length');
if (String(c.merchant_name).length < 2 || String(c.merchant_name).length > 100) fail('merchant_name length');
if (typeof c.merchant_name_acknowledged !== 'boolean') fail('merchant_name_acknowledged must be boolean');
if (c.business_name !== c.merchant_name && c.merchant_name_acknowledged !== true) fail('merchant_name differs from business_name and must be explicitly acknowledged');
if (!/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(c.locale)) fail('locale format');
if (!/^[A-Z]{3}$/.test(c.currency)) fail('currency must be ISO 4217 style 3-letter uppercase code');
if (!validTimeZone(c.timezone)) fail('timezone must be a valid IANA timezone');

const origins = ['public_url','admin_url','kds_url'].map(key => bareOrigin(c[key], key));
if (new Set(origins).size !== 3) fail('public/admin/KDS URLs must be distinct');

if (!Number.isInteger(c.table_count) || c.table_count < 1 || c.table_count > 200) fail('table_count must be integer 1..200');
if (!['generate-per-clone','external-secret'].includes(c.table_qr_secret_mode)) fail('table_qr_secret_mode');
if (c.require_table_qr_signature !== true) fail('MASTER CLONE v1 requires signed table QR by default');
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c.admin_owner_email)) fail('admin_owner_email');
if (String(c.supabase_project_ref).length < 8 || String(c.supabase_project_ref).length > 64) fail('supabase_project_ref length');
if (String(c.spreadsheet_target).length < 3) fail('spreadsheet_target');
if (!String(c.qris_asset).trim()) fail('qris_asset');

if (!/^clone\/.+\.json$/.test(c.menu_seed)) fail('menu_seed must point under clone/');
const menuPath = path.resolve(repoRoot, c.menu_seed);
if (!menuPath.startsWith(path.join(repoRoot, 'clone') + path.sep) || !fs.existsSync(menuPath)) fail('menu_seed not found');
const menu = readJson(menuPath);
if (!Array.isArray(menu) || menu.length < 1) fail('menu_seed must be a non-empty array');
const ids = new Set();
for (const [i,m] of menu.entries()) {
  for (const key of ['id','name','category','price']) if (m[key] === undefined || m[key] === '') fail(`menu[${i}] missing ${key}`);
  if (ids.has(m.id)) fail(`duplicate menu id ${m.id}`);
  ids.add(m.id);
  if (!Number.isFinite(Number(m.price)) || Number(m.price) < 0) fail(`menu[${i}] invalid price`);
}

for (const key of ['static_bucket','payment_bucket']) {
  if (!c.storage[key] || !/^[a-z0-9][a-z0-9-]{2,62}$/.test(c.storage[key])) fail(`storage.${key}`);
}
if (!Number.isInteger(c.sheets.start_year) || c.sheets.start_year < 2026 || c.sheets.start_year > 2100) fail('sheets.start_year');
if (!Number.isInteger(c.sheets.years) || c.sheets.years < 1 || c.sheets.years > 10) fail('sheets.years');
if (!Array.isArray(c.sheets.expected_tabs) || JSON.stringify(c.sheets.expected_tabs) !== JSON.stringify(CANONICAL_TABS)) {
  fail(`sheets.expected_tabs must exactly match ${CANONICAL_TABS.join(' | ')}`);
}

const isSourceTenant = c.merchant_slug === SOURCE_TENANT.slug;
if (!isSourceTenant) {
  if (c.supabase_project_ref === SOURCE_TENANT.supabase_project_ref) fail('clone must not reuse Rohmat production Supabase project');
  if (origins.some(origin => SOURCE_TENANT.urls.has(origin))) fail('clone must not reuse Rohmat production domain');
  if (String(c.spreadsheet_target).includes(SOURCE_TENANT.spreadsheet_id)) fail('clone must not reuse Rohmat production spreadsheet');
}

console.log(JSON.stringify({
  ok: true,
  config: path.relative(repoRoot, configPath),
  schema_version: c.schema_version,
  merchant_slug: c.merchant_slug,
  locale: c.locale,
  currency: c.currency,
  timezone: c.timezone,
  table_count: c.table_count,
  signed_table_qr: c.require_table_qr_signature,
  spreadsheet_tabs: c.sheets.expected_tabs,
  menu_items: menu.length,
  source_edits_required: false
}, null, 2));
