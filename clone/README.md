# Rohmat Master Clone Contract

This directory defines merchant-specific input for `ROHMAT MASTER CLONE v1.0`. Merchant cloning is configuration/provisioning work, not source editing.

## Invariant

`apps/**` and `supabase/**` are master source. A merchant clone may provide configuration, menu seed data, branding/media, credentials/secrets, target infrastructure identifiers, and spreadsheet destinations. It must not require merchant-specific edits inside master source.

## Files

- `merchant.config.schema.json` — configuration contract.
- `merchant.config.example.json` — canonical example.
- `menu.example.json` — seed fixture.
- `validate-config.mjs` — fail-fast configuration validator.
- `provision-plan.mjs` — deterministic infrastructure/bootstrap plan generator.
- `rehearsal-a.json` and `rehearsal-b.json` — deliberately different clone fixtures.
- `rehearse.mjs` — validates both fixtures, generates their plans, fingerprints master source before/after, and asserts zero source edits.

## Local/CI commands

```bash
node clone/validate-config.mjs clone/merchant.config.example.json
node clone/provision-plan.mjs clone/merchant.config.example.json
node clone/rehearse.mjs
```

A successful rehearsal must report:

```text
ok: true
rehearsal_count: 2
zero_source_edits: true
```

## Provisioning boundary

Automation is expected to provision/configure, at minimum: Supabase migrations and required Edge Functions, Storage buckets/assets, merchant settings/menu seed/admin owner/table signing secret, table QR artifacts, Google Sheets targets, and three Vercel applications using roots `apps/public`, `apps/admin`, and `apps/kds`.

Secrets are never committed to merchant config. They are injected at provisioning time through the target platform secret stores.

## Certification

Static A/B rehearsal proves the configuration contract is capable of generating two distinct merchant plans without editing master source. A production-grade freeze additionally requires two isolated end-to-end clone deployments, smoke tests, data isolation checks, and disaster-recovery restore evidence.
