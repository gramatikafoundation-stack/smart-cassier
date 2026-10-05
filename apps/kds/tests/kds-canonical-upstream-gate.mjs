import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../api/kds.js',import.meta.url),'utf8');

assert.ok(src.includes("process.env.SUPABASE_URL || process.env.SUPABASE_ORIGIN"),'KDS must trust configured canonical Supabase origin');
assert.ok(src.includes("upstreamUrl.origin !== trustedProjectOrigin"),'KDS must match upstream origin to canonical project origin');
assert.ok(src.includes("upstreamUrl.pathname !== expectedPath"),'KDS must pin expected Edge Function path');
assert.ok(src.includes("expectedPath = '/functions/v1/rohmat-kds-api'"),'KDS Edge Function path pin missing');
assert.ok(!src.includes("hostname !== 'yybhpmjuywjxqurrrrxl.supabase.co'"),'legacy Supabase hostname guard must not return');
assert.ok(src.includes("kds_upstream_not_canonical"),'canonical upstream failure marker missing');

console.log('KDS_CANONICAL_UPSTREAM_GATE_PASS=1');
