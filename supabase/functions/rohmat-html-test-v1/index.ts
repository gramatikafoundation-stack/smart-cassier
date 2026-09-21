import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const EXPECTED=Deno.env.get('MAINTENANCE_TOKEN_SHA256')||'';
const PAYMENT_BUCKET=Deno.env.get('PAYMENT_PROOF_BUCKET')||'payment-proofs';
const U=Deno.env.get('SUPABASE_URL')||'';
const K=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
async function sha256(s:string){const b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));return Array.from(new Uint8Array(b)).map(x=>x.toString(16).padStart(2,'0')).join('')}
const H={'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','referrer-policy':'no-referrer','x-frame-options':'DENY'};
const out=(x:any,s=200)=>new Response(JSON.stringify(x),{status:s,headers:H});
async function rpc(name:string,body:any={}){const r=await fetch(`${U}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:K,Authorization:`Bearer ${K}`,'content-type':'application/json'},body:JSON.stringify(body),cache:'no-store'});const j=await r.json().catch(()=>({}));if(!r.ok)throw new Error(`rpc_${name}_${r.status}`);return j}
async function del(bucket:string,path:string){const enc=path.split('/').map(encodeURIComponent).join('/');const r=await fetch(`${U}/storage/v1/object/${bucket}/${enc}`,{method:'DELETE',headers:{apikey:K,Authorization:`Bearer ${K}`},cache:'no-store'});if(r.ok||r.status===404)return true;throw new Error(`storage_delete_${bucket}_${r.status}`)}
Deno.serve(async(req:Request)=>{
 if(req.method==='GET'||req.method==='HEAD')return new Response('Gone',{status:410,headers:{'content-type':'text/plain; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'}});
 if(req.method!=='POST')return out({ok:false,error:'method_not_allowed'},405);
 const token=req.headers.get('x-rohmat-maintenance-token')||'';
 if(!EXPECTED||!token||await sha256(token)!==EXPECTED)return out({ok:false,error:'forbidden'},403);
 if(!K)return out({ok:false,error:'service_role_unavailable'},503);
 let due=0,deleted=0,errors=0,testDeleted=false;
 try{
   const j=await rpc('storage_retention_due_paths');
   const paths=Array.isArray(j?.paths)?j.paths:[]; due=paths.length;
   for(const p of paths){try{if(await del(PAYMENT_BUCKET,String(p)))deleted++}catch{errors++}}
   await rpc('storage_retention_record_run',{p_due:due,p_deleted:deleted,p_errors:errors,p_test_deleted:testDeleted});
   return out({ok:errors===0,due,deleted,errors,testDeleted,contract:'storage-retention-v2',canarySkipped:true},errors===0?200:207);
 }catch(e){try{await rpc('storage_retention_record_run',{p_due:due,p_deleted:deleted,p_errors:errors+1,p_test_deleted:testDeleted})}catch{}return out({ok:false,error:String((e as Error)?.message||e),due,deleted,errors:errors+1,testDeleted},502)}
});