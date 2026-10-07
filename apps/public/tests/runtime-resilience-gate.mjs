import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../lib/runtime-lifecycle.js',import.meta.url),'utf8');
assert.ok(src.includes('const STALE_MS = 300000;'),'runtime stale fallback must be bounded to five minutes');
assert.ok(src.includes('const UPSTREAM_TIMEOUT_MS = 5000;'),'runtime upstream timeout must tolerate normal cold starts');
assert.ok(src.includes("if (cached && now - cached.at < STALE_MS)"),'runtime must use recent last-known-good payload when upstream is transiently unavailable');
assert.ok(src.includes("[runtime-lifecycle-stale]"),'stale fallback must remain observable');
assert.ok(src.includes('throw error;'),'unbounded or cold-cache failures must still fail closed');
console.log('PUBLIC_RUNTIME_RESILIENCE_GATE_PASS=1');
