const fs = require('fs');

function read(path) {
  return fs.readFileSync(path, 'utf8');
}
function must(haystack, needle, label) {
  if (!haystack.includes(needle)) throw new Error('missing: ' + label);
}
function mustNot(haystack, needle, label) {
  if (haystack.includes(needle)) throw new Error('forbidden: ' + label);
}
function count(haystack, needle) {
  return haystack.split(needle).length - 1;
}
function exactly(haystack, needle, n, label) {
  const got = count(haystack, needle);
  if (got !== n) throw new Error(label + ': expected ' + n + ', got ' + got);
}

const admin = read('supabase/functions/rohmat-admin-render/index.ts');
const secure = read('supabase/functions/rohmat-secure-api-v1/index.ts');
const cashier = read('supabase/functions/rohmat-admin-cashier-loader-v1/index.ts');
const migration = read('supabase/migrations/20260928173000_smart_order_v1_1_categories_database_summary.sql');

// Menu categories: real tenant-aware management, not a UI-only control.
must(admin, 'Kelola Kategori', 'category manager navigation');
must(admin, 'admin_console_save_category', 'category mutation RPC call');
must(admin, 'function menuCategories()', 'dynamic category source');
must(admin, 'function categoryDialog()', 'category manager dialog');
must(admin, "const cats=menuCategories();", 'menu dialog dynamic category list');
mustNot(admin, "['Nasi','Lauk','Minuman','Jus Buah'].map", 'hard-coded category select');
must(secure, 'admin_console_save_category:"admin_console_save_category_tenant"', 'secure category RPC mapping');
must(migration, 'create or replace function public.admin_console_save_category_tenant', 'tenant category RPC');
must(migration, 'update public.menu_items', 'category rename menu migration');
must(migration, "settings=jsonb_set(coalesce(settings,'{}'::jsonb),'{menu_categories}'", 'category persistence');
mustNot(migration, "case when coalesce(p_menu->>'category','') in ('Nasi','Lauk','Minuman','Jus Buah')", 'legacy category whitelist');

// Database: exactly one focused page with two content clusters.
must(admin, 'database:[]', 'database single-page navigation');
mustNot(admin, "database:['Riwayat','Spreadsheet']", 'legacy database sub-navigation');
must(admin, '<h3>Buka Spreadsheet</h3>', 'spreadsheet cluster');
must(admin, 'RINGKASAN 30 HARI', '30-day summary cluster');
must(admin, 'Pelanggan Teraktif', 'top customer metric');
must(admin, 'Menu Terlaris #1', 'top menu #1 metric');
must(admin, 'Menu Terlaris #2', 'top menu #2 metric');
must(admin, 'Jam Kunjungan Tersibuk', 'busiest hour metric');
must(admin, 'Total Transaksi 30 Hari', '30-day transaction metric');
must(secure, 'admin_console_database_summary:"admin_console_database_summary_tenant"', 'secure summary RPC mapping');
must(secure, 'content-type, x-requested-with, x-sdb-tenant-id, apikey, authorization', 'secure login CORS headers');
must(migration, 'create or replace function public.admin_console_database_summary_tenant', 'database summary RPC');

// Receipt: all user-required information and modern line-item structure.
for (const label of [
  'Kode Pesanan',
  'Nama Pemesan',
  'Tanggal & Waktu',
  'Tipe Layanan',
  'Jenis Pesanan',
  'Jumlah',
  'Harga Satuan',
  'Subtotal',
  'Total Harga Keseluruhan'
]) must(cashier, label, 'receipt label ' + label);
must(cashier, "return table>0?'Dine In • Meja '", 'dine-in service label');
must(cashier, "return 'Take Away'", 'take-away service label');
must(cashier, 'rc6ReceiptCard', 'premium modal receipt');
must(cashier, '@media print', 'print-specific receipt styling');
must(cashier, 'Struk Pesanan', 'professional receipt title');

// Scope/no-regression checks.
exactly(secure, 'admin_console_save_category:"admin_console_save_category_tenant"', 1, 'category RPC mapping uniqueness');
exactly(secure, 'admin_console_database_summary:"admin_console_database_summary_tenant"', 1, 'summary RPC mapping uniqueness');
must(migration, 'revoke all on function public.admin_console_save_category_tenant', 'category RPC fail-closed ACL');
must(migration, 'revoke all on function public.admin_console_database_summary_tenant', 'summary RPC fail-closed ACL');

console.log(JSON.stringify({
  ok: true,
  contract: 'smart-order-v1.1.0-refinement-gate',
  categories: 'dynamic-add-rename-tenant-aware',
  database: 'two-cluster-30-day-summary',
  receipt: 'premium-required-fields',
  checked: {
    admin_renderer: true,
    secure_gateway: true,
    migration: true,
    cashier_receipt: true
  }
}, null, 2));
