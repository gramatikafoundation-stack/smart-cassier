import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const CRON_TOKEN_SHA256="36c91cef174eaec3619b67dd16032273842af6e5fa49e4120186a13b51dea747";
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function headers(requestId:string,tenantId=""){
  return{
    "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store, max-age=0, must-revalidate",
    "pragma":"no-cache",
    "x-content-type-options":"nosniff",
    "x-frame-options":"DENY",
    "referrer-policy":"no-referrer",
    "permissions-policy":"camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    "x-rohmat-security":"sheet-worker-master-prototype-v1",
    "x-rohmat-contract":"sheet-worker-tenant-v1",
    "x-request-id":requestId,
    ...(tenantId?{"x-sdb-tenant-id":tenantId}:{})
  };
}
async function sha256(s:string){
  const b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));
  return[...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
function json(body:unknown,status=200,requestId=crypto.randomUUID(),tenantId=""){
  return new Response(JSON.stringify(body),{status,headers:headers(requestId,tenantId)});
}
function backoffSeconds(attempt:number){
  return Math.min(3600,15*Math.pow(2,Math.min(Math.max(attempt,1),8)));
}
function validWriterUrl(value:string){
  try{
    const u=new URL(value);
    return u.protocol==="https:"&&u.hostname==="script.google.com"&&!u.port&&!u.username&&!u.password&&!u.search&&!u.hash
      &&/^\/macros\/s\/[A-Za-z0-9_-]+\/exec$/.test(u.pathname);
  }catch{return false}
}
function activeTargets(cfg:any){
  return(Array.isArray(cfg?.targets)?cfg.targets:[])
    .filter((t:any)=>t?.enabled!==false&&Number.isInteger(Number(t?.year))&&String(t?.spreadsheet_id||""));
}
function expectedTargets(events:any[],targets:any[]){
  const years=events.some(e=>e.target_year==null)
    ?targets.map(t=>Number(t.year))
    :[...new Set(events.map(e=>Number(e.target_year)))];
  if(years.some(y=>!targets.some(t=>Number(t.year)===y)))throw new Error("event_target_unconfigured");
  return targets.filter(t=>years.includes(Number(t.year)));
}
function validAcknowledgement(body:any,targets:any[],tenantId:string,writerVersion:number){
  if(body?.ok!==true||body?.version!==2||body?.writer_version!==writerVersion||body?.tenant_id!==tenantId)return false;
  if(!Array.isArray(body.years)||!Array.isArray(body.result)||body.years.length!==targets.length||body.result.length!==targets.length)return false;
  if(new Set(body.years).size!==targets.length||new Set(body.result.map((r:any)=>r?.year)).size!==targets.length)return false;
  return targets.every(t=>
    body.years.includes(Number(t.year))
    &&body.result.some((r:any)=>
      Number(r?.year)===Number(t.year)
      &&r.spreadsheetId===t.spreadsheet_id
      &&["PEMESAN","PESANAN","MENU & STOK","KEUANGAN"].every(k=>Number.isSafeInteger(r.rows?.[k])&&r.rows[k]>=0)
    )
  );
}
async function integration(
  sb:any,tenantId:string,requestId:string,outcome:string,status:number,started:number,
  metadata:any,errorCode:string|null=null
){
  try{
    await sb.rpc("integration_record_event_tenant",{
      p_tenant_id:tenantId,p_request_id:requestId,p_service_key:"sheet_worker",
      p_operation:"sync_batch",p_direction:"outbound",p_outcome:outcome,
      p_http_status:status,p_latency_ms:Date.now()-started,p_error_code:errorCode,
      p_metadata:{...metadata,tenant_id:tenantId}
    });
  }catch{}
}

Deno.serve(async(req:Request)=>{
  const started=Date.now();
  const runId=crypto.randomUUID();
  if(req.method!=="POST")return json({ok:false,error:"method_not_allowed"},405,runId);
  const ct=(req.headers.get("content-type")||"").toLowerCase();
  if(!ct.startsWith("application/json"))return json({ok:false,error:"unsupported_media_type"},415,runId);
  const token=req.headers.get("x-rohmat-cron-token")||"";
  if(!token||await sha256(token)!==CRON_TOKEN_SHA256)return json({ok:false,error:"unauthorized"},401,runId);

  const su=Deno.env.get("SUPABASE_URL");
  const sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!su||!sk)return json({ok:false,error:"service_unavailable"},503,runId);
  const sb=createClient(su,sk,{auth:{persistSession:false,autoRefreshToken:false}});

  const now=new Date().toISOString();
  const {error:recoverErr}=await sb.from("sheet_sync_outbox")
    .update({status:"failed",next_attempt_at:now,locked_until:null,locked_by:null,last_error:"Previous event-processing lease expired; retrying authoritative refresh."})
    .eq("status","processing").lt("locked_until",now);
  if(recoverErr)return json({ok:false,error:"lease_recovery_failed"},500,runId);

  const requestedTenant=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  if(requestedTenant&&!UUID_RE.test(requestedTenant))return json({ok:false,error:"invalid_tenant"},400,runId);

  let tenantId=requestedTenant;
  if(!tenantId){
    const dueTenants=await sb.rpc("sheet_writer_due_tenants",{p_limit:1});
    if(dueTenants.error)return json({ok:false,error:"outbox_read_failed"},500,runId);
    tenantId=String(dueTenants.data?.[0]?.tenant_id||"");
  }
  if(!tenantId){
    return json({ok:true,state:"idle",processed:0,requestId:runId},200,runId);
  }

  const {data:cfg,error:cfgErr}=await sb.rpc("tenant_sheet_sync_config",{p_tenant_id:tenantId});
  if(cfgErr||!cfg?.ok)return json({ok:false,error:"tenant_config_read_failed"},500,runId,tenantId);
  if(!cfg.enabled||!cfg.writer_url){
    return json({ok:true,state:"disabled_or_writer_unconfigured",tenant_id:tenantId,processed:0,requestId:runId},200,runId,tenantId);
  }
  if(!validWriterUrl(cfg.writer_url))return json({ok:false,error:"invalid_writer_url"},503,runId,tenantId);
  const targets=activeTargets(cfg);
  if(!targets.length)return json({ok:false,error:"target_read_failed"},500,runId,tenantId);

  const {data:writerToken,error:secretErr}=await sb.rpc("sheet_sync_writer_credential_tenant",{p_tenant_id:tenantId});
  if(secretErr||typeof writerToken!=="string"||writerToken.length<32){
    return json({ok:false,error:"writer_auth_unconfigured"},503,runId,tenantId);
  }

  const {data:leaseAcquired,error:leaseErr}=await sb.rpc("sheet_writer_try_acquire_lease_tenant",{p_tenant_id:tenantId,p_run_id:runId,p_ttl_seconds:115});
  if(leaseErr)return json({ok:false,error:"writer_lease_acquire_failed"},500,runId,tenantId);
  if(leaseAcquired!==true)return json({ok:true,state:"writer_lease_busy",tenant_id:tenantId,processed:0,requestId:runId},202,runId,tenantId);

  try{
    const claim=await sb.rpc("sheet_writer_claim_tenant_events",{
      p_tenant_id:tenantId,p_run_id:runId,p_limit:100,p_lease_seconds:120
    });
    if(claim.error)return json({ok:false,error:"claim_failed"},500,runId,tenantId);
    const events=claim.data||[];
    if(!events.length)return json({ok:true,state:"claim_empty",tenant_id:tenantId,processed:0,requestId:runId},200,runId,tenantId);

    const ids=events.map((e:any)=>e.event_id);
    const correlations=events.slice(0,25).map((e:any)=>({
      event_id:e.event_id,request_id:e.request_id,entity_type:e.entity_type,entity_id:e.entity_id
    }));

    let httpStatus=0;
    let errorCode="writer_unavailable";
    let ack=false;
    let ackBody:any=null;
    let consistency:any=null;

    try{
      const expected=expectedTargets(events,targets);
      const writerEvents=events.map(({request_id,tenant_id,...rest}:any)=>rest);
      const writerResponse=await fetch(cfg.writer_url,{
        method:"POST",redirect:"follow",signal:AbortSignal.timeout(90000),
        headers:{"content-type":"application/json"},
        body:JSON.stringify({
          schema_version:1,
          tenant_id:tenantId,
          writer_token:writerToken,
          sent_at:new Date().toISOString(),
          events:writerEvents
        })
      });
      httpStatus=writerResponse.status;
      if(writerResponse.ok){
        ackBody=await writerResponse.json().catch(()=>null);
        ack=validAcknowledgement(ackBody,expected,tenantId,Number(cfg.expected_writer_version||4));
        if(ack){
          const cr=await sb.rpc("record_sheet_sync_ack_tenant",{
            p_tenant_id:tenantId,p_request_id:runId,p_http_status:httpStatus,p_ack:ackBody
          });
          consistency=cr.data;
          if(cr.error||!cr.data?.ok){ack=false;errorCode="writer_consistency_mismatch"}
          else errorCode="";
        }else{
          const codes=["unauthorized","writer_busy","sync_failed","invalid_request","tenant_mismatch"];
          errorCode=codes.includes(ackBody?.error)?ackBody.error:"writer_ack_invalid";
        }
      }else errorCode="writer_http_error";
    }catch(e:any){
      errorCode=e?.name==="TimeoutError"?"writer_timeout":
        e?.message==="event_target_unconfigured"?"event_target_unconfigured":"writer_request_failed";
    }

    if(ack){
      const updated=await sb.from("sheet_sync_outbox")
        .update({status:"synced",synced_at:new Date().toISOString(),last_http_status:httpStatus,last_error:null,locked_until:null,locked_by:null})
        .eq("tenant_id",tenantId).in("event_id",ids).eq("locked_by",runId).eq("status","processing")
        .select("event_id");
      if(updated.error||updated.data?.length!==ids.length){
        await integration(sb,tenantId,runId,"failed",500,started,{processed:0,correlations,consistency,singleflight:true},"sync_ack_failed");
        return json({ok:false,error:"sync_ack_failed"},500,runId,tenantId);
      }
      await integration(sb,tenantId,runId,"success",httpStatus||200,started,{processed:ids.length,correlations,consistency,singleflight:true});
      return json({ok:true,state:"synced",tenant_id:tenantId,processed:ids.length,http_status:httpStatus,consistency,requestId:runId},200,runId,tenantId);
    }

    const outcomes=await Promise.all(events.map(async(ev:any)=>{
      const attempt=Number(ev.attempts||0)+1;
      const upd=await sb.from("sheet_sync_outbox")
        .update({
          status:attempt>=Number(cfg.max_attempts||10)?"dead":"failed",
          attempts:attempt,
          next_attempt_at:new Date(Date.now()+backoffSeconds(attempt)*1000).toISOString(),
          last_http_status:httpStatus||null,last_error:errorCode,locked_until:null,locked_by:null
        })
        .eq("tenant_id",tenantId).eq("event_id",ev.event_id).eq("locked_by",runId).eq("status","processing");
      return!upd.error;
    }));
    if(outcomes.some(ok=>!ok)){
      await integration(sb,tenantId,runId,"failed",500,started,{processed:0,correlations,consistency,singleflight:true},"retry_record_failed");
      return json({ok:false,error:"retry_record_failed"},500,runId,tenantId);
    }
    await integration(sb,tenantId,runId,"failed",502,started,{processed:0,http_status:httpStatus,correlations,consistency,singleflight:true},errorCode);
    return json({ok:false,state:"writer_failed",tenant_id:tenantId,processed:0,http_status:httpStatus,error:errorCode,consistency,requestId:runId},502,runId,tenantId);
  }finally{
    try{await sb.rpc("sheet_writer_release_lease_tenant",{p_tenant_id:tenantId,p_run_id:runId})}catch{}
  }
});
