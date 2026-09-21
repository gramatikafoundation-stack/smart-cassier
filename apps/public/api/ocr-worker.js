const UPSTREAM='https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/worker.min.js';
let memo=null;

async function loadWorker(){
  if(memo)return memo;
  memo=fetch(UPSTREAM,{headers:{accept:'application/javascript,text/javascript,*/*'},cache:'force-cache'})
    .then(async r=>{if(!r.ok)throw new Error('ocr_worker_upstream_'+r.status);const text=await r.text();if(text.length<50000)throw new Error('ocr_worker_invalid');return text})
    .catch(e=>{memo=null;throw e});
  return memo;
}

export default async function handler(req,res){
  if(req.method!=='GET'&&req.method!=='HEAD'){
    res.statusCode=405;
    res.setHeader('Allow','GET, HEAD');
    return res.end('Method Not Allowed');
  }
  try{
    const body=await loadWorker();
    res.statusCode=200;
    res.setHeader('Content-Type','application/javascript; charset=utf-8');
    res.setHeader('Cache-Control','public, max-age=86400, s-maxage=604800, stale-while-revalidate=86400');
    res.setHeader('Content-Security-Policy',"default-src 'none'; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval' https://cdn.jsdelivr.net; connect-src 'self' https://cdn.jsdelivr.net https://tessdata.projectnaptha.com; img-src 'none'; style-src 'none'; object-src 'none'; worker-src 'none'; base-uri 'none'; frame-ancestors 'none'");
    res.setHeader('Cross-Origin-Resource-Policy','same-origin');
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('X-Rohmat-OCR-Worker','same-origin-v3-tesseract7');
    return res.end(req.method==='HEAD'?'':body);
  }catch{
    res.statusCode=503;
    res.setHeader('Content-Type','application/javascript; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    res.setHeader('X-Content-Type-Options','nosniff');
    return res.end('/* OCR worker temporarily unavailable */');
  }
}
