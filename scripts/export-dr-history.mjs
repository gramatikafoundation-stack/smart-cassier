import fs from 'node:fs';
import path from 'node:path';

const endpoint = process.env.DR_EXPORT_URL || 'https://yybhpmjuywjxqurrrrxl.supabase.co/functions/v1/rohmat-svg-test-v1';
const token = process.env.DR_EXPORT_TOKEN;
if (!token) throw new Error('DR_EXPORT_TOKEN is required');
const root = path.join('supabase', 'restore');
const out = path.join(root, 'history');
fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

const manifest = [];
for (let offset = 0; ; offset += 25) {
  const response = await fetch(`${endpoint}?offset=${offset}&limit=25`, {
    headers: { 'x-rohmat-dr-token': token },
  });
  if (!response.ok) throw new Error(`DR export HTTP ${response.status}`);
  let rows = await response.json();
  if (typeof rows === 'string') rows = JSON.parse(rows);
  if (!Array.isArray(rows)) throw new Error('Unexpected DR export payload');
  if (rows.length === 0) break;

  for (const row of rows) {
    const safeName = String(row.name || 'migration').replace(/[^a-zA-Z0-9_]+/g, '_');
    const file = `${row.version}_${safeName}.sql`;
    const sql = [
      '-- Sanitized DR-only replay snapshot from production migration history.',
      `-- Version: ${row.version}  Name: ${row.name}`,
      '-- Production-specific credentials, operator identities, and project endpoint were neutralized.',
      '',
      String(row.sql || ''),
      '',
    ].join('\n');
    fs.writeFileSync(path.join(out, file), sql);
    manifest.push({ version: String(row.version), name: String(row.name), file, bytes: Buffer.byteLength(sql) });
  }
  if (rows.length < 25) break;
}

if (manifest.length < 160) throw new Error(`Incomplete DR history export: ${manifest.length}`);
fs.writeFileSync(path.join(root, 'manifest.json'), JSON.stringify({
  generated_at: new Date().toISOString(),
  source: 'production-sanitized-migration-history',
  count: manifest.length,
  migrations: manifest,
}, null, 2) + '\n');
console.log(`Exported ${manifest.length} sanitized migrations.`);
