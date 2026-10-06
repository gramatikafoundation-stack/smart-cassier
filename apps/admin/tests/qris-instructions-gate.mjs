import assert from 'node:assert/strict';
import fs from 'node:fs';

const src=fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-render/index.ts',import.meta.url),'utf8');

for(const marker of [
  'Instruksi pembayaran',
  'id=\\\"pinstr\\\" rows=\\\"1\\\"',
  'overflow-y:hidden',
  'min-height:190px',
  'fitPaymentInstructions',
  "pinstr.style.height='auto'",
  "pinstr.scrollHeight+2",
  "pinstr?.addEventListener('input',fitPaymentInstructions)",
  "setTimeout(fitPaymentInstructions,120)",
  "'ResizeObserver'in window",
  "pinstrResizeObserver.observe(pinstr)",
  'Seluruh instruksi ditampilkan utuh'
]) assert.ok(src.includes(marker),'QRIS instruction UX marker missing: '+marker);

console.log('ADMIN_QRIS_INSTRUCTIONS_GATE_PASS=1');
