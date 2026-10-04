import assert from 'node:assert/strict';
import fs from 'node:fs';

const src = fs.readFileSync(new URL('../../../supabase/functions/rohmat-admin-visual-editor-v1/index.ts', import.meta.url), 'utf8');

for (const prop of ['font-family','font-size','font-weight','font-style','text-align','color']) {
  assert.match(src, new RegExp("setProperty\\('"+prop.replace('-','\\-')+"'"), 'missing authoritative live typography property: '+prop);
}
assert.match(src, /font-size:[^\n]*!important/, 'saved typography size must survive runtime CSS');
assert.match(src, /font-family:[^\n]*!important/, 'saved typography family must survive runtime CSS');
assert.match(src, /text-align:[^\n]*!important/, 'saved alignment must survive runtime CSS');
assert.match(src, /if\(h&&!h\.style\.getPropertyValue\('font-size'\)\)set\(h,'font-size'/, 'responsive login fit must not overwrite an explicit user font size');
assert.doesNotMatch(src, /const h=brand\?\.querySelector\('h1'\);if\(h\)set\(h,'font-size'/, 'unguarded login font-size override reintroduced');
assert.match(src,/v25-settings-theme-sync/,'visual editor runtime v25 marker missing');

console.log('ADMIN_VISUAL_EDITOR_TYPOGRAPHY_GATE_PASS=1');
