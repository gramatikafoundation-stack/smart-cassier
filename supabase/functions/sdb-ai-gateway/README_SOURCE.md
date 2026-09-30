// Canonical source is the deployed Supabase Edge Function sdb-ai-gateway v2.
// Security contract:
// - verify_jwt=true
// - POST only
// - OPENAI_API_KEY server-side secret only
// - SDB AI private service-role RPC config
// - reject credential/payment-secret field names
// - aggregate data only
// - atomic sdb_ai_admit_request before provider call
// - Responses API with store:false and strict JSON-schema output
// - no write/refund/financial action tools in v2
//
// This repository marker intentionally contains no credentials.
// Retrieve deployed source from Supabase when promoting/migrating versions.
// See docs/SDB_AI_CORE_BOOTSTRAP_20260930.md for the deployment contract.
