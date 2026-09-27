# SMART ORDER Production Manifest — B1 Canonical Identity Candidate

## Canonical identity

- Product: SMART ORDER
- Canonical origin: https://smart-order-sdb.vercel.app
- Vercel project: smart-order-sdb / prj_5xph62xWBNqRRR3MZ3bgA0qZU9NK
- Git source: gramatikafoundation-stack/smart-cassier
- Integration branch: batch5-integrated-qa-security-freeze-20260926
- Supabase operational project: xrepmvbccalzhlcznrff
- Tenancy: shared_database_rls

## Canonical surfaces

| Surface | Route | Authority |
|---|---|---|
| Public | / | SMART ORDER unified Vercel project |
| Admin + Smart Cashier | /admin | SMART ORDER unified Vercel project |
| KDS | /kds | SMART ORDER unified Vercel project |
| Database | /database | Protected Admin database surface; Google Sheets are tenant resources |

Google Sheets remain external tenant resources and reporting/sync targets. They are not a fourth web domain.

## Legacy compatibility

https://smart-cassier.vercel.app is retained only as a compatibility alias and MUST redirect to the canonical origin.
Historical Rohmat Public/Admin/KDS projects are rollback/audit artifacts and are not canonical authorities for the SMART ORDER candidate.

## Batch 1 freeze rule

No production configuration, current manifest, runtime origin, SEO canonical, or tenant registry may identify a legacy hostname as the canonical SMART ORDER origin.
Historical migrations, recovery snapshots, and explicit compatibility tests may retain legacy hostnames when clearly scoped as history/rollback evidence.
