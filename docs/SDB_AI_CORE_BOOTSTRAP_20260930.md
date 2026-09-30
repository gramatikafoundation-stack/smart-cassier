# SDB AI Core — Bootstrap & Integration Status

Date: 2026-09-30 (Asia/Jakarta)

## Purpose

SDB AI Core is the private AI control plane for Smart Digital For Business. It is designed to serve SMART CASHIER, SMART INSIGHT, SMART ASISTEN, Media AI, and future SDB products through one governed backend integration with the OpenAI Responses API.

## Security principles

- No OpenAI secret is stored in GitHub, browser code, or public tables.
- The current gateway is JWT protected and backend-only.
- The `sdb_ai` schema is private by default; PUBLIC, anon, and authenticated receive no direct table access.
- Service-role-only RPCs expose the minimum internal control-plane operations.
- Prompts/model outputs are not persisted in the usage ledger.
- Incoming business data is screened for credential/payment-secret field names.
- Supplied business data is explicitly treated as untrusted data, not model instructions.
- OpenAI requests use `store:false`.
- V1/V2 gateway has no transaction/refund/write tools. It is read-only analysis.
- Critical/external actions are modeled in policy but require approval and are not implemented as executable tools.

## Current deployment

Temporary host project: Supabase `smart-cassier-platform` (`xrepmvbccalzhlcznrff`).

This is temporary because the Supabase organization is currently at the Free-plan maximum of two active projects. A dedicated `sdb-ai-core` project should be created after the planned Supabase upgrade. Do not delete or pause existing projects to make room.

The temporary module is isolated under schema `sdb_ai` and new function `sdb-ai-gateway`; legacy Rohmat objects are out of scope and must remain untouched.

## OpenAI organization target

- Organization: Smart Digital For Business
- OpenAI project: Smart Digital For Business
- API credential strategy: project-scoped, server-side only, expiring/rotated.
- A 90-day encrypted credential has been created through the official OpenAI connector, but it is not committed here and must not be exposed in chat/source.
- Live provider traffic remains disabled until a supported secret-store path contains `OPENAI_API_KEY` and API billing is active.

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

All contracts use structured JSON schemas.

## Model routing

Initial conservative routing:
- simple/standard/vision: GPT-5.6 Luna primary
- complex: GPT-5.6 Sol primary
- server-availability fallback only

Model IDs are configuration, not hard-wired product behavior. Before switching to newer families, verify model availability through the actual SDB API account.

## Cost & abuse governance

The database control plane implements:
- per-product request/minute limit
- per-product daily request limit
- monthly input token limit
- monthly output token limit
- atomic admission using a PostgreSQL advisory transaction lock
- token/latency/status metadata ledger
- model-rate registry and estimated USD cost calculation

Gateway v2 performs admission before a provider call. It does not fall back for 4xx/rate-limit/billing errors.

## SMART CASHIER pilot

The first production use case is read-only business insight:
1. deterministic SQL/backend calculates business metrics;
2. only the required aggregate is sent to SDB AI Core;
3. AI interprets those metrics;
4. structured result returns summary, findings, recommended actions, limitations, confidence;
5. AI cannot modify/refund a transaction.

Source of truth remains PostgreSQL/Supabase.

## Remaining activation gates

1. Supabase secret `OPENAI_API_KEY` must be added via a supported secure secret-store flow. Never paste it in chat.
2. OpenAI API billing/credit must be active.
3. Run synthetic provider smoke test.
4. Verify model availability for the business OpenAI project.
5. Verify token/cost ledger after the test.
6. Integrate SMART CASHIER UI/backend with the read-only gateway.
7. After Supabase upgrade, create dedicated `sdb-ai-core` project and migrate this module using the committed migration source.
8. Keep temporary module until dedicated-project parity QA passes.

## No-rework rule

This AI integration extends the validated SMART CASHIER state. It must not redesign or rebuild Batch 1–3. Database-dependent components are adapted/revalidated only where materially affected.

