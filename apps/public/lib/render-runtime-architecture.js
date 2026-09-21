import baseHandler from '../api/render-a11y-v3.js';

const PIPELINE_MARKER = 'rohmat-fetch-pipeline-v1';
const SIGNED_START = 'const base=window.fetch.bind(window);window.fetch=async function(input,init){';
const SIGNED_END = 'return base(input,init)};';
const OCR_START = 'const oldFetch=window.fetch.bind(window);';
const OCR_END = 'return oldFetch(input,init)};';

function count(text, needle) {
  return text.split(needle).length - 1;
}

function replaceSegment(source, start, end, replacement, label, flags) {
  const startCount = count(source, start);
  if (startCount !== 1) throw new Error(`runtime_arch_${label}_start_${startCount}`);
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  if (to < 0) throw new Error(`runtime_arch_${label}_end_0`);
  const duplicateEnd = source.indexOf(end, to + end.length);
  if (duplicateEnd >= 0 && label === 'signed-table') throw new Error(`runtime_arch_${label}_end_ambiguous`);
  flags.push(label);
  return source.slice(0, from) + replacement + source.slice(to + end.length);
}

function bootstrap(nonce) {
  return `<script nonce="${nonce}" id="${PIPELINE_MARKER}">(()=>{'use strict';if(window.__rohmatFetchPipelineV1)return;const nativeFetch=window.fetch.bind(window),steps=[],names=new Set();const api={use(name,fn){name=String(name||'');if(!name||typeof fn!=='function'||names.has(name))return false;names.add(name);steps.push({name,fn});document.documentElement.dataset.rohmatFetchPipeline=steps.map(x=>x.name).join('>');return true},names(){return steps.map(x=>x.name)},size(){return steps.length}};window.__rohmatFetchPipelineV1=api;window.fetch=async function(input,init){let currentInput=input,currentInit=init;for(const step of steps){try{const next=await step.fn(currentInput,currentInit);if(next&&typeof next==='object'){if(Object.prototype.hasOwnProperty.call(next,'input'))currentInput=next.input;if(Object.prototype.hasOwnProperty.call(next,'init'))currentInit=next.init}}catch{}}return nativeFetch(currentInput,currentInit)};document.documentElement.dataset.rohmatRuntimeArchitecture='fetch-pipeline-v1'})();</script>`;
}

const SIGNED_MIDDLEWARE = "window.__rohmatFetchPipelineV1.use('signed-table-v22',(input,init)=>{try{const url=typeof input==='string'?input:(input&&input.url)||'';if((url.includes('/functions/v1/create-order-v6')||url.endsWith('/functions/v1/create-order'))&&init&&typeof init.body==='string'){const b=JSON.parse(init.body),v=get();if(b.serviceMode==='dine-in')b.tableSignature=v&&Number(b.tableNumber)===v.table?v.signature:'';init=Object.assign({},init,{body:JSON.stringify(b)});}}catch{}return{input,init}});";

const OCR_MIDDLEWARE = "window.__rohmatFetchPipelineV1.use('ocr-smart-v6',(input,init)=>{try{const u=typeof input==='string'?input:(input&&input.url)||'';if(u.includes('/functions/v1/create-order')&&init&&typeof init.body==='string'){const b=JSON.parse(init.body);b.proofOcrText=strongText||b.proofOcrText||'';init=Object.assign({},init,{body:JSON.stringify(b)})}}catch{}return{input,init}});";

function optimizeRuntimeArchitecture(html) {
  const flags = [];
  let out = html;
  const nonce = out.match(/<script\s+nonce="([^"]+)"/)?.[1] || '';
  if (!nonce) throw new Error('runtime_arch_nonce_missing');
  if (out.includes(PIPELINE_MARKER)) return { html: out, flags: ['already-patched'] };

  const signedTag = out.match(/<script\b[^>]*\bid=["']rohmat-signed-table-v22["'][^>]*>/i);
  if (!signedTag || signedTag.index == null) throw new Error('runtime_arch_signed_script_missing');
  out = out.slice(0, signedTag.index) + bootstrap(nonce) + out.slice(signedTag.index);
  flags.push('fetch-pipeline-bootstrap');

  out = replaceSegment(out, SIGNED_START, SIGNED_END, SIGNED_MIDDLEWARE, 'signed-table', flags);
  out = replaceSegment(out, OCR_START, OCR_END, OCR_MIDDLEWARE, 'ocr-smart', flags);

  const wrapperCount = count(out, 'window.fetch=async function');
  if (wrapperCount !== 1) throw new Error(`runtime_arch_fetch_wrapper_${wrapperCount}`);
  if (out.includes('const base=window.fetch.bind(window)') || out.includes('const oldFetch=window.fetch.bind(window)')) throw new Error('runtime_arch_nested_wrapper_remains');
  if (count(out, "use('signed-table-v22'") !== 1 || count(out, "use('ocr-smart-v6'") !== 1) throw new Error('runtime_arch_middleware_count');
  const bootstrapAt = out.indexOf(PIPELINE_MARKER), signedAt = out.indexOf('rohmat-signed-table-v22'), ocrAt = out.indexOf('rohmat-ocr-smart-v6');
  if (!(bootstrapAt >= 0 && bootstrapAt < signedAt && signedAt < ocrAt)) throw new Error('runtime_arch_order_invalid');

  return { html: out, flags };
}

export default async function handler(req, res) {
  const end = res.end.bind(res);
  res.end = (body, ...args) => {
    if (res.statusCode === 200 && typeof body === 'string' && body.includes('rohmat-public-a11y-v3')) {
      try {
        const optimized = optimizeRuntimeArchitecture(body);
        body = optimized.html;
        res.setHeader('X-Rohmat-Public-Runtime-Architecture', 'fetch-pipeline-v1');
        res.setHeader('X-Rohmat-Public-Runtime-Order', 'signed-table-v22>ocr-smart-v6>native-fetch');
        res.setHeader('X-Rohmat-Public-Runtime-Architecture-Scope', optimized.flags.join(','));
      } catch (error) {
        res.setHeader('X-Rohmat-Public-Runtime-Architecture', `baseline-mismatch:${String(error?.message || error).slice(0,120)}`);
      }
    }
    return end(body, ...args);
  };
  return baseHandler(req, res);
}
