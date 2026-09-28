import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const headers={
  "cache-control":"no-store, max-age=0, must-revalidate",
  "pragma":"no-cache",
  "x-content-type-options":"nosniff",
  "x-frame-options":"DENY",
  "referrer-policy":"no-referrer",
  "permissions-policy":"camera=(), microphone=(), geolocation=(), payment=(), usb=()",
  "content-security-policy":"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'none'; font-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
};
const html=`<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><title>Recovery Admin SMART ORDER</title><style>
:root{color-scheme:light}*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f4f1eb;color:#20352d;font:15px/1.5 Inter,Segoe UI,Arial,sans-serif;padding:24px}.card{width:min(520px,100%);background:#fff;border:1px solid #d9d1c5;border-radius:24px;box-shadow:0 18px 60px rgba(31,51,44,.12);overflow:hidden}.head{padding:24px 28px;background:linear-gradient(135deg,#245443,#173f32);color:#fff}.ey{font-size:11px;font-weight:900;letter-spacing:.14em;opacity:.78}.head h1{margin:6px 0 0;font-size:28px}.body{padding:26px 28px}.body p{color:#66736d;margin:0 0 18px}.field{display:grid;gap:7px}.field label{font-size:12px;font-weight:800}.field input{width:100%;border:1px solid #d9d1c5;border-radius:12px;padding:12px 13px;font:inherit}.btn{width:100%;margin-top:16px;border:0;border-radius:12px;padding:12px 16px;background:#245443;color:#fff;font-weight:900;cursor:pointer}.btn:disabled{opacity:.6;cursor:wait}.msg{display:none;margin-top:14px;padding:11px 12px;border-radius:12px;background:#edf5f0;color:#2f6652;font-weight:700}.msg.bad{background:#fff0ed;color:#9a4238}.note{margin-top:14px;font-size:12px;color:#7a817d}</style></head><body><main class="card"><header class="head"><div class="ey">SMART ORDER • ONE-TIME RECOVERY</div><h1>Tetapkan Password Admin</h1></header><section class="body"><p>Masukkan password baru. Token recovery hanya berlaku sekali dan akan otomatis dinonaktifkan setelah berhasil.</p><form id="f"><div class="field"><label>Password Baru</label><input id="pw" type="password" autocomplete="new-password" minlength="12" required autofocus></div><button id="b" class="btn" type="submit">Tetapkan Password</button><div id="m" class="msg"></div></form><div class="note">Password tidak disimpan di halaman ini dan dikirim langsung melalui koneksi HTTPS ke backend SMART ORDER.</div></section></main><script>
const f=document.getElementById('f'),pw=document.getElementById('pw'),b=document.getElementById('b'),m=document.getElementById('m');
const token=location.hash.replace(/^#/,'').trim();
history.replaceState(null,'',location.pathname);
function show(t,bad=false){m.textContent=t;m.className='msg'+(bad?' bad':'');m.style.display='block'}
if(!/^[a-f0-9]{64}$/i.test(token)){show('Token recovery tidak valid atau sudah tidak tersedia.',true);b.disabled=true}
f.addEventListener('submit',async e=>{e.preventDefault();if(b.disabled)return;b.disabled=true;b.textContent='Menyimpan…';m.style.display='none';try{
 const r=await fetch(location.pathname,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token,new_password:pw.value}),cache:'no-store'});
 const j=await r.json();if(!r.ok||!j.ok)throw new Error(j.error||'recovery_failed');
 pw.value='';show('Password berhasil diperbarui. Anda akan diarahkan ke halaman Login Admin.');
 setTimeout(()=>location.replace('https://smart-order-sdb.vercel.app/admin'),1200);
}catch(err){show(({new_password_weak:'Password belum memenuhi standar keamanan.',recovery_invalid_or_expired:'Token recovery tidak valid, sudah dipakai, atau kedaluwarsa.'}[err.message])||'Password gagal diperbarui.',true);b.disabled=false;b.textContent='Tetapkan Password'}});</script></body></html>`;

Deno.serve(async(req)=>{
  if(req.method==="GET") return new Response(html,{status:200,headers:{...headers,"content-type":"text/html; charset=utf-8"}});
  if(req.method!=="POST") return new Response(JSON.stringify({ok:false,error:"method_not_allowed"}),{status:405,headers:{...headers,"content-type":"application/json"}});
  const U=Deno.env.get("SUPABASE_URL")||"";
  const K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!U||!K) return new Response(JSON.stringify({ok:false,error:"service_unavailable"}),{status:503,headers:{...headers,"content-type":"application/json"}});
  let body:any={};try{body=await req.json()}catch{return new Response(JSON.stringify({ok:false,error:"invalid_json"}),{status:400,headers:{...headers,"content-type":"application/json"}})}
  const token=String(body?.token||"").trim();
  const password=String(body?.new_password||"");
  if(!/^[a-f0-9]{64}$/i.test(token)||password.length>256) return new Response(JSON.stringify({ok:false,error:"recovery_invalid_or_expired"}),{status:400,headers:{...headers,"content-type":"application/json"}});
  const sb=createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await sb.rpc("admin_password_recovery_once",{p_token:token,p_new_password:password});
  const ok=!error&&data?.ok===true;
  return new Response(JSON.stringify(ok?data:{ok:false,error:data?.error||"recovery_failed"}),{status:ok?200:400,headers:{...headers,"content-type":"application/json"}});
});