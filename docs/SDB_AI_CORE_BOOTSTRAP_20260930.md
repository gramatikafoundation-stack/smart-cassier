# SDB AI Core — Bootstrap & Integration Status

Date: 2026-10-01 (Asia/Jakarta)

## Purpose

SDB AI Core is the private AI control plane for Smart Digital For Business. It serves SMART CASHIER, SMART INSIGHT, SMART ASISTEN, Media AI, and future SDB products through one governed backend integration with the OpenAI Responses API.

## Current validated state

- Supabase secret `OPENAI_API_KEY`: **configured**
- OpenAI API key: **valid**
- OpenAI organization/project: **Smart Digital For Business**
- Live model availability verified: `gpt-6-luna`, `gpt-6-sol`, `gpt-5.6-luna`, `gpt-5.6-sol`
- Production routing:
  - simple / standard / vision → `gpt-6-luna`
  - complex → `gpt-6-sol`
  - fallbacks → GPT-5.6 equivalents
- Paid synthetic smoke test reached OpenAI successfully but returned:
  - HTTP 429
  - type `insufficient_quota`
  - code `credit_balance_exhausted`
- Therefore the only provider-side activation blocker is **OpenAI API prepaid credit/billing**.
- Temporary paid-smoke endpoint was immediately disabled after the test.
- Health probe was hardened after validation and no longer accepts anonymous JWTs.

## Security principles

- No OpenAI secret is stored in GitHub, browser code, or public tables.
- The `sdb_ai` schema is private by default; PUBLIC, anon, and authenticated have no direct table access.
- Service-role-only RPCs expose only internal control-plane operations.
- Prompts/model outputs are not persisted in the usage ledger.
- Incoming business data is screened for credential/payment-secret field names.
- Business data is treated as untrusted data, never as model instructions.
- OpenAI requests use `store:false`.
- Gateway v2 has no transaction/refund/write tools; current scope is read-only analysis.
- Critical/external actions remain policy-only and require approval if implemented later.
- Atomic per-product admission control prevents parallel requests from bypassing local budgets.

## Current deployment

Temporary host project: Supabase `smart-cassier-platform` (`xrepmvbccalzhlcznrff`).

The module remains isolated under schema `sdb_ai`. Legacy Rohmat objects are out of scope and must remain untouched.

Permanent cost architecture: keep only **two active Supabase projects**. Do **not** create a third `sdb-ai-core` project. `sdb_ai` remains an isolated private schema inside `smart-cassier-platform`, with separate Edge Functions, grants, policies, secrets, usage ledger, and cost governor. This avoids an additional PostgreSQL compute charge while preserving logical isolation.

## Products registered

- `sdb-core`
- `smart-cashier`
- `smart-insight`
- `smart-asisten`
- `media-ai`

## Active prompt contracts

- SMART CASHIER: `business.insight`
- SMART INSIGHT: `survey.insight`
- SMART ASISTEN: `reasoning.advice`
- Media AI: `editorial.assist`
- SDB Core: `business.advisor`

All contracts use strict structured JSON schemas.

## Cost & abuse governance

The database control plane implements:
- per-product request/minute limit
- per-product daily request limit
- monthly input token limit
- monthly output token limit
- PostgreSQL advisory-lock atomic admission
- token/latency/status metadata ledger
- model-rate registry
- estimated USD cost per request

Current standard text-rate registry includes:
- GPT-6 Luna: $0.10 / 1M input, $0.50 / 1M output
- GPT-6 Sol: $2.00 / 1M input, $10.00 / 1M output
- GPT-5.6 fallbacks retained

Gateway v2 performs admission before provider calls and does not fallback on billing, quota, rate-limit, or other 4xx errors.

## SMART CASHIER pilot

The first production use case remains read-only business insight:
1. deterministic SQL/backend calculates business metrics;
2. only required aggregates are sent to SDB AI Core;
3. AI interprets those metrics;
4. strict structured result returns findings/actions/limitations/confidence;
5. AI cannot modify or refund transactions.

Source of truth remains PostgreSQL/Supabase.

## Remaining activation gates

1. Add OpenAI API prepaid credits to resolve `credit_balance_exhausted`.
2. Rerun the tiny synthetic Responses/Structured Output smoke test.
3. Verify usage/token/cost ledger from the successful provider call.
4. Integrate SMART CASHIER backend with read-only gateway using server-to-server authorization compatible with its current custom auth/session model.
5. Run tenant/outlet/role negative tests on AI access.
6. Keep the Supabase organization at **two active projects only**; do not create a dedicated third AI project.\n7. Configure OpenAI project spend alert + hard spend limit before broad production traffic.\n8. Revalidate schema isolation and project-level cost controls after the Supabase Pro upgrade.

## No-rework rule

This AI integration extends the validated SMART CASHIER state. It must not redesign or rebuild Batch 1–3. Only dependencies materially affected by AI/database migration are adapted and revalidated.


## 2026-10-02 live activation validation

- OpenAI API billing is active and has propagated.
- Supabase -> OpenAI Responses API returned HTTP 200 using `gpt-6-luna`.
- Strict Structured Output validation passed.
- Full backend QA passed: gateway config, atomic admission/cost governor, provider request, structured output, usage ledger, and cost estimation.
- QA sample: 223 input tokens, 279 output tokens, 502 total tokens, estimated cost USD 0.000162, latency 4427 ms.
- Production `sdb-ai-gateway` upgraded to v4 for modern Supabase `sb_secret_*` RPC authentication: secret keys are sent on `apikey` only; legacy service-role JWT fallback remains transitional.
- Temporary smoke probe is disabled after validation.
- Permanent cost architecture remains two active Supabase projects maximum; no third AI project.
