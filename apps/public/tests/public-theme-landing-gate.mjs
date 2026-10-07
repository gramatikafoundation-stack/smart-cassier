import assert from 'node:assert/strict';
import fs from 'node:fs';

const runtime=fs.readFileSync(new URL('../../../supabase/functions/rohmat-public-element-runtime-v64/index.ts',import.meta.url),'utf8');
const media=fs.readFileSync(new URL('./public-media-visual-gate.mjs',import.meta.url),'utf8');

assert.ok(runtime.includes("tenant_site_settings_public_v1?select=updated_at,typography,design_system"),'Public theme must read tenant design_system');
assert.ok(runtime.includes("X-SDB-Tenant-ID"),'Public theme fetch must carry tenant identity');
assert.ok(runtime.includes("x-rohmat-theme-source':'tenant-design-system-v25'"),'tenant theme source response marker missing');
assert.ok(runtime.includes('rohmat-public-landing-v27'),'premium landing runtime missing');
assert.ok(runtime.includes('min-height:100svh'),'landing must retain full viewport contract');
assert.ok(runtime.includes('grid-template-columns:minmax(0,48fr) minmax(0,52fr)'),'desktop hero balance contract missing');
assert.ok(runtime.includes("document.documentElement.dataset.sdbPublicTheme=id"),'public active theme identity marker missing');
assert.ok(runtime.includes("img.addEventListener('error'"),'hero image failure guard missing');
assert.ok(runtime.includes("window.addEventListener('storage'"),'cross-tab theme refresh listener missing');
assert.ok(runtime.includes("s.id='rohmatPublicDesignV24';document.body.appendChild(s)"),'tenant theme style must be placed after legacy body stylesheet');
assert.ok(runtime.includes('document.body.appendChild(s);return s'),'premium landing style must be placed after legacy body stylesheet');
assert.ok(runtime.includes(".hero{width:100%!important;max-width:100%!important"),'mobile hero must size against the containing block, not viewport units');
assert.ok(runtime.includes(".welcome{width:100%!important;max-width:100%!important"),'mobile landing must not use scrollbar-inclusive 100vw sizing');
assert.ok(!runtime.includes("width:calc(100vw - 20px)!important"),'mobile landing must not reintroduce scrollbar-width clipping');
assert.ok(runtime.includes("grid-template-columns:minmax(0,1fr) minmax(0,1fr)!important"),'mobile service controls must remain symmetric');
assert.ok(runtime.includes("overflow-x:hidden!important"),'mobile horizontal overflow guard missing');
assert.ok(runtime.includes("font-size:clamp(34px,10vw,44px)!important"),'mobile heading scale guard missing');
assert.ok(media.includes('/rohmat-assets/hero/rohmat-nasi-uduk-hero-v1.jpg'),'canonical Rohmat hero contract missing');
console.log('PUBLIC_THEME_LANDING_GATE_PASS=1');
