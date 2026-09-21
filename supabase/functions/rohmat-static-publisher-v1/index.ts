import "jsr:@supabase/functions-js/edge-runtime.d.ts";
Deno.serve(()=>new Response(JSON.stringify({ok:false,error:'maintenance_locked',contract:'native-proof-v77-locked'}),{status:403,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','x-rohmat-publisher':'locked-native-proof-v77'}}));
