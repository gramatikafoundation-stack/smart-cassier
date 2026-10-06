import assert from 'node:assert/strict';
import fs from 'node:fs';

const login=fs.readFileSync(new URL('../login.html',import.meta.url),'utf8');
const index=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const css=fs.readFileSync(new URL('../styles.css',import.meta.url),'utf8');
const pub=fs.readFileSync(new URL('../../../supabase/functions/rohmat-public-element-runtime-v64/index.ts',import.meta.url),'utf8');

assert.ok(login.includes('class="skipLink" href="#kdsLoginMain"'),'KDS login skip link missing');
assert.ok(login.includes('id="kdsLoginMain"'),'KDS login main target missing');
assert.ok(index.includes('class="skipLink"'),'KDS operational skip link missing');
assert.ok(css.includes('kds-accessible-heritage-contrast-v1'),'KDS accessible contrast layer missing');
assert.ok(css.includes('var(--kds-panel,#FFFDF8) 75%,var(--kds-accent,#B87444) 25%'),'KDS accent-on-primary contrast token missing');
assert.ok(css.includes('var(--kds-accent,#B87444) 80%,var(--kds-text,#24362F) 20%'),'KDS accent-on-panel contrast token missing');
assert.ok(pub.includes('var(--ds-accent,#B87444) 80%,var(--ds-text,#24362F) 20%'),'Public accent text contrast token missing');
assert.ok(pub.includes('var(--ds-muted,#7C776E) 80%,var(--ds-text,#24362F) 20%'),'Public muted text contrast token missing');
console.log('KDS_PUBLIC_ACCESSIBILITY_GATE_PASS=1');
