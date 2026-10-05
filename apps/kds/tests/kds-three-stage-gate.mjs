import assert from 'node:assert/strict';
import fs from 'node:fs';

const app=fs.readFileSync(new URL('../app.js',import.meta.url),'utf8');
const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const css=fs.readFileSync(new URL('../styles.css',import.meta.url),'utf8');

for(const label of ['Pesanan Baru','Sedang Diproses','Pesanan Siap']) assert.ok(app.includes(label)||html.includes(label),'missing KDS stage: '+label);
assert.doesNotMatch(html,/Pesanan Selesai/,'KDS primary workflow must not expose Pesanan Selesai');
assert.doesNotMatch(app,/lane\('Pesanan Selesai'/,'KDS primary workflow must not render completed lane');
assert.match(app,/order_status==='preparing'/,'processing lane must use preparing status');
assert.match(app,/order_status==='ready'/,'ready lane must use ready status');
assert.match(app,/data-act="ready"/,'processing stage must advance to ready');
assert.match(app,/stage==='ready'.*data-act="complete"/s,'ready stage must provide archive handoff without creating a fourth lane');
assert.match(app,/Pesanan Diserahkan/,'ready-stage handoff label missing');
assert.doesNotMatch(app,/data-act="finish"/,'KDS primary workflow must not advance directly to completed');
assert.ok(html.includes('id="sReady"'),'ready summary counter missing');
assert.ok(css.includes('.ticket.stage-ready'),'ready ticket visual state missing');
console.log('KDS_THREE_STAGE_WORKFLOW_GATE_PASS=1');
