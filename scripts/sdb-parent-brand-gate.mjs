import fs from "node:fs";
import assert from "node:assert/strict";

const canon = "https://smart-digital-for-business.vercel.app/";
const root = new URL("../", import.meta.url);
const read = p => fs.readFileSync(new URL(p, root), "utf8");

const publicRender = read("apps/public/api/render.js");
const adminRender = read("apps/admin/api/render.js");
const kdsLogin = read("apps/kds/login.html");
const kdsIndex = read("apps/kds/index.html");
const kdsCss = read("apps/kds/styles.css");
const vercel = JSON.parse(read("vercel.json"));
const asset = new URL("sdb-parent-brand.jpg", root);

assert.ok(fs.existsSync(asset), "canonical SDB asset missing");
assert.ok(fs.statSync(asset).size > 10000, "SDB asset unexpectedly small");

for (const pair of [
  ["public", publicRender],
  ["admin", adminRender],
  ["kds-login", kdsLogin],
  ["kds-index", kdsIndex],
]) {
  const name = pair[0], src = pair[1];
  assert.ok(src.includes(canon), name + ": canonical SDB URL missing");
  assert.ok(src.includes('rel="noopener noreferrer"'), name + ": noopener/noreferrer missing");
  assert.ok(src.includes('aria-label="Kunjungi Smart Digital for Business"'), name + ": accessible name missing");
  assert.ok(src.includes('/sdb-parent-brand.jpg'), name + ": canonical asset missing");
}

for (const nav of ["GENERAL","SITUS PUBLIK","SITUS ADMIN","KDS","DATABASE"]) {
  assert.ok(adminRender.includes(nav), "admin navigation regression: " + nav);
}
for (const nav of ["Pesanan Dapur","Smart Cashier","Ketersediaan Barang"]) {
  assert.ok(kdsIndex.includes(nav), "kds navigation regression: " + nav);
}

assert.equal((kdsLogin.match(/data-sdb-parent-signature="kds-login"/g)||[]).length,1,"duplicate KDS login signature");
assert.equal((kdsIndex.match(/data-sdb-parent-signature="kds-operational"/g)||[]).length,1,"duplicate KDS operational signature");
assert.ok(kdsCss.includes("sdb-parent-brand-kds-v1"),"KDS SDB signature CSS missing");
assert.ok(vercel.headers.some(x => x.source === "/sdb-parent-brand.jpg"), "immutable asset cache header missing");

console.log("SDB_PARENT_BRAND_GATE_PASS");
