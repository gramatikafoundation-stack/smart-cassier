# ROHMAT MASTER PROTOTIPE v1 — Freeze Contract

## Keputusan arsitektur final

Rohmat dibekukan sebagai **MASTER PROTOTIPE / reference tenant** di bawah payung **SMART DIGITAL FOR BUSINESS**.

Model operasional:
- satu source canonical: `gramatikafoundation-stack/Rohmat-Master`;
- satu platform Supabase canonical: `yybhpmjuywjxqurrrrxl`;
- tenant baru ditambahkan sebagai logical tenant di platform yang sama;
- Rohmat adalah reference tenant, bukan source yang dicopy per klien;
- source/repository tidak digandakan per tenant;
- migration platform berlaku sekali untuk seluruh platform;
- perbedaan tenant berada pada `tenant_id`, konfigurasi, identitas bisnis, domain/origin, QRIS, Storage namespace, Spreadsheet target, credential, dan data operasional tenant;
- tenant resolution wajib fail-closed; Rohmat tidak boleh menjadi implicit fallback untuk tenant yang tidak teridentifikasi.

Nama branch/PR lama yang masih memuat kata `master-clone` dipertahankan hanya sebagai artefak historis agar tidak menimbulkan churn/risiko. Artefak final dan release tag menggunakan istilah MASTER PROTOTIPE.

## Prinsip keselamatan

1. Perubahan menuju tenancy harus additive dan backward-compatible sampai seluruh regression PASS.
2. Data bisnis Rohmat tidak boleh dihapus/reset/diubah untuk memaksa gate.
3. Historical failures tidak boleh dihapus atau diwaive.
4. Existing healthy production path tidak boleh dialihkan ke tenancy enforcement sebelum source, preview, browser regression, dan negative isolation test PASS.
5. Tidak membuat Supabase project/branch baru atau resource berbayar tanpa persetujuan biaya eksplisit.
6. Evidence yang masih valid tidak diulang kecuali source drift menyentuh scope evidence tersebut.

## Reference tenant

- tenant slug: `rohmat-nasi-uduk`
- role: `reference_tenant`
- production Supabase project: `yybhpmjuywjxqurrrrxl`
- source repository: `gramatikafoundation-stack/Rohmat-Master`

## Gate MASTER PROTOTIPE

Freeze final hanya boleh dilakukan bila:
- KDS production hotfix telah live dan terverifikasi;
- control-plane memakai SMART DIGITAL FOR BUSINESS + reference tenant;
- tenant data ownership contract tersedia;
- tenant resolver fail-closed tersedia;
- cross-tenant negative test PASS;
- tenant provisioning rehearsal A/B pada shared platform PASS tanpa source edit;
- Writer v4 provisioning contract tenant-scoped PASS;
- Stage 9–14 PASS;
- rolling reliability/preflight/maintainability/security/RUM PASS sesuai acceptance criteria;
- GitHub CI benar-benar mengeksekusi job dan PASS;
- Stage 15 final audit memiliki P0/P1 unresolved = 0.

## Final release identity

Final tag yang dituju setelah seluruh gate genuine PASS:

`rohmat-master-prototype-v1.0.0`

Tag harus menunjuk exact merged release commit yang evidence-nya lengkap dan tidak mengalami drift setelah audit final.

## Current-head CI checkpoint

A documentation-only checkpoint is used to trigger a current-head GitHub Actions run without changing runtime behavior or forcing application deployments. Runtime freeze remains fail-closed until that run genuinely executes and passes.
