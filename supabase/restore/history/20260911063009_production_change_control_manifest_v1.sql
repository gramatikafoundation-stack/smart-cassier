-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260911063009  Name: production_change_control_manifest_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

CREATE TABLE IF NOT EXISTS private.production_change_control (
  component text PRIMARY KEY,
  component_type text NOT NULL,
  locked boolean NOT NULL DEFAULT true,
  baseline_version text,
  baseline_sha256 text,
  canonical_target text,
  allowed_change_scope text NOT NULL DEFAULT 'explicit-target-only',
  note text,
  updated_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON private.production_change_control FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO private.production_change_control(component,component_type,locked,baseline_version,baseline_sha256,canonical_target,allowed_change_scope,note)
VALUES
('public-site','vercel-production',true,'current-production',null,'https://rohmat-pesan-bayar-publik.vercel.app/','explicit-target-only','Do not modify when a request targets Admin, KDS, Sheets, or unrelated components.'),
('admin-site','vercel-production',true,'v28',null,'https://studio-pengelola-rohmat.vercel.app','explicit-target-only','Only modify the explicitly requested Admin page or element.'),
('kds-site','vercel-production',true,'current-production',null,'https://rohmat-kds-printer.vercel.app','explicit-target-only','Canonical KDS host; never substitute an Edge Function HTML host.'),
('secure-api','edge-function',true,'v7','8b0d7a9bd7bc6b5506cf089874f6e9e57d59f1d0cf42fd4013bcf02f3a287ead','rohmat-secure-api-v1','security-only','Backend security bridge.'),
('admin-runtime','edge-function',true,'v43','fd25d120c69db821a3c6657fca802fc830e6a47781aa4f2769fdf2b34b3c48ca','rohmat-admin-style-runtime-v59','admin-target-only','Current sidebar and cashier-safe baseline.'),
('admin-visual-editor','edge-function',true,'v12','a89044626150b0e822f14d778ddf8339b149541cb86e2d6d9d0493d4be4350e8','rohmat-admin-visual-editor-v1','admin-visual-target-only','Do not replace operational native pages unless explicitly requested.'),
('public-runtime','edge-function',true,'v11','e2fccf708145e4f370d4faba0a45abb4ee40b4f8bfc5affc2ffb15bb3cbe98b1','rohmat-public-element-runtime-v64','public-target-only','Preserve QRIS companion elements and payment flow.'),
('kds-redirect','edge-function',true,'v5','b89df8ab2a72990674e3025cc59a115383de3207abca4e8d3fa1253c7a1031de','rohmat-kds-production-v2','kds-routing-only','Redirect-only compatibility endpoint.'),
('sheets-worker','edge-function',true,'v3','beb82e2d99d6c920d4c35fb094a7f69d11c0ff4a5679d5828671b790a5aa8a5c','rohmat-sheet-sync-worker-v1','sheets-only','Retry worker; event-driven writer remains primary.')
ON CONFLICT(component) DO UPDATE SET
component_type=excluded.component_type,locked=excluded.locked,baseline_version=excluded.baseline_version,
baseline_sha256=excluded.baseline_sha256,canonical_target=excluded.canonical_target,
allowed_change_scope=excluded.allowed_change_scope,note=excluded.note,updated_at=now();
