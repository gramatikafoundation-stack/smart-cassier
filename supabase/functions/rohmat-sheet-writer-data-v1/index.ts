import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const PAGE=1000;
const PAYMENT_PROOF_REFERENCE_DAYS=90;
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const enc=new TextEncoder();

function headers(tenantId?:string){
  return {
    "content-type":"application/json; charset=utf-8",
    "cache-control":"no-store, max-age=0, must-revalidate",
    "pragma":"no-cache",
    "x-content-type-options":"nosniff",
    "referrer-policy":"no-referrer",
    "vary":"X-SDB-Tenant-ID",
    "x-rohmat-sheet-writer-data":"master-prototype-v1",
    ...(tenantId?{"x-sdb-tenant-id":tenantId}:{})
  };
}
async function hash(v:string){
  const b=await crypto.subtle.digest("SHA-256",enc.encode(v));
  return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,"0")).join("");
}
function json(v:any,status=200,tenantId?:string){
  return new Response(JSON.stringify(v),{status,headers:headers(tenantId)});
}
function parts(v:any,tz:string){
  if(!v)return{d:"",t:"",s:""};
  const p=new Intl.DateTimeFormat("en-CA",{
    timeZone:tz,year:"numeric",month:"2-digit",day:"2-digit",
    hour:"2-digit",minute:"2-digit",second:"2-digit",hour12:false
  }).formatToParts(new Date(v));
  const g=(x:string)=>p.find(y=>y.type===x)?.value||"";
  return{
    d:`${g("year")}-${g("month")}-${g("day")}`,
    t:`${g("hour")}:${g("minute")}:${g("second")}`,
    s:`${g("day")}/${g("month")}/${g("year")} ${g("hour")}:${g("minute")}:${g("second")}`
  };
}
const service=(v:any)=>String(v||"").toLowerCase().includes("dine")?"Dine In":"Take Away";
const source=(v:any)=>v==="cashier_admin"?"Smart Cashier Admin":v==="cashier_kds"?"Smart Cashier KDS":"Situs Publik / Barcode";
const pay=(v:any)=>String(v||"").toLowerCase()==="cash"?"Cash":String(v||"").toLowerCase()==="qris_cashier"?"QRIS Kasir":"QRIS";
function stage(o:any){
  const x=String(o.order_status||"").toLowerCase();
  return ["cancelled","canceled","rejected","payment_rejected"].includes(x)?"Dibatalkan":
    x==="completed"?"Pesanan Selesai":
    ["preparing","ready"].includes(x)?"Sedang Diproses":"Pesanan Baru";
}
const itemList=(o:any)=>(Array.isArray(o.items)?o.items:[])
  .map((i:any)=>`${Number(i.quantity??i.qty??1)||1}× ${String(i.name??i.menu_name??"Menu")}`).join("; ");
const isPaid=(o:any)=>String(o.payment_status||"")==="verified"||
  ["preparing","ready","completed"].includes(String(o.order_status||""));
const moneyIn=(o:any)=>isPaid(o)?Math.max(0,Number(o.paid_amount??o.total_amount??0)||0):0;
function withinDays(v:any,days:number){
  const t=Date.parse(String(v||""));
  return Number.isFinite(t)&&t>=Date.now()-days*86400000;
}
async function all(sb:any,table:string,cols:string,start:string,end:string,tenantId:string){
  const out:any[]=[];
  for(let from=0;from<100000;from+=PAGE){
    const q=await sb.from(table).select(cols)
      .eq("tenant_id",tenantId)
      .gte("created_at",start).lt("created_at",end)
      .order("created_at",{ascending:true}).range(from,from+PAGE-1);
    if(q.error)throw q.error;
    const d=q.data||[];
    out.push(...d);
    if(d.length<PAGE)return out;
  }
  throw Error("export_limit_exceeded:"+table);
}

Deno.serve(async(req:Request)=>{
  if(req.method!=="GET"&&req.method!=="HEAD")return json({ok:false,error:"method_not_allowed"},405);
  const U=Deno.env.get("SUPABASE_URL")||"";
  const K=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!U||!K)return json({ok:false,error:"service_unavailable"},503);
  const sb=createClient(U,K,{auth:{persistSession:false,autoRefreshToken:false}});
  const requestedTenant=String(req.headers.get("x-sdb-tenant-id")||"").trim();
  if(requestedTenant&&!UUID_RE.test(requestedTenant))return json({ok:false,error:"tenant_required_or_invalid"},400);

  let tenantId=requestedTenant;
  if(!tenantId){
    const runtime=await sb.rpc("master_prototype_runtime_context",{
      p_tenant_id:null,p_origin:null,p_app_kind:null
    });
    tenantId=String(runtime.data?.tenant_id||"");
    if(runtime.error||!runtime.data?.ok||!UUID_RE.test(tenantId)){
      return json({ok:false,error:"tenant_required_or_invalid"},400);
    }
  }

  const cfg=await sb.rpc("tenant_sheet_sync_config",{p_tenant_id:tenantId});
  if(cfg.error||!cfg.data?.ok)return json({ok:false,error:"tenant_unavailable"},404,tenantId);

  const token=req.headers.get("x-rohmat-writer-token")||"";
  const secret=await sb.rpc("sheet_sync_writer_credential_tenant",{p_tenant_id:tenantId});
  if(secret.error||typeof secret.data!=="string"||secret.data.length<32){
    return json({ok:false,error:"writer_auth_unconfigured"},503,tenantId);
  }
  if(!token||(await hash(token))!==(await hash(secret.data))){
    return json({ok:false,error:"unauthorized"},401,tenantId);
  }

  const u=new URL(req.url);
  const year=Number(u.searchParams.get("year"));
  const targets=Array.isArray(cfg.data.targets)?cfg.data.targets:[];
  const target=targets.find((x:any)=>Number(x.year)===year&&x.enabled!==false);
  if(!Number.isInteger(year)||!target)return json({ok:false,error:"target_unconfigured"},404,tenantId);

  if(req.method==="HEAD"){
    return new Response(null,{status:200,headers:headers(tenantId)});
  }

  const tz=String(cfg.data.timezone||"Asia/Jakarta");
  const piiDays=Math.max(1,Math.min(3650,Number(cfg.data.pii_retention_days||365)));
  const start=`${year}-01-01T00:00:00+07:00`;
  const end=`${year+1}-01-01T00:00:00+07:00`;

  try{
    const cols="id,public_order_code,created_at,customer_name,customer_whatsapp,service_mode,table_number,items,item_count,total_amount,customer_note,paid_amount,payment_method,payment_status,order_status,payment_proof_url,payment_submitted_at,verified_at,kitchen_sent_at,kds_received_at,preparing_at,ready_at,completed_at,order_source,cashier_actor,cash_received,change_amount,updated_at";
    const [a,b,mr]=await Promise.all([
      all(sb,"orders",cols,start,end,tenantId),
      all(sb,"order_history_archive",cols,start,end,tenantId),
      sb.from("menu_items")
        .select("id,name,category,price,image_url,is_visible,is_available,availability_note,availability_updated_at,updated_at,display_order")
        .eq("tenant_id",tenantId).order("display_order",{ascending:true})
    ]);
    if(mr.error)throw mr.error;

    const map=new Map<string,any>();
    for(const o of b)map.set(String(o.id),{
      ...o,order_source:o.order_source||"public",payment_method:o.payment_method||"qris",
      payment_status:o.payment_status||"verified",order_status:o.order_status||"completed"
    });
    for(const o of a)map.set(String(o.id),o);
    const orders=[...map.values()].sort((x,y)=>String(x.created_at).localeCompare(String(y.created_at)));

    const pemesan:any[][]=[],pesanan:any[][]=[],keuangan:any[][]=[];
    for(const o of orders){
      const p=parts(o.created_at,tz);
      const n=parts(o.verified_at||o.payment_submitted_at||o.kds_received_at||o.created_at,tz);
      const pr=parts(o.preparing_at||o.ready_at,tz);
      const dn=parts(o.completed_at,tz);
      const v=parts(o.verified_at||o.payment_submitted_at,tz);
      const cash=String(o.payment_method||"")==="cash";
      const rec=cash?Number(o.cash_received??o.paid_amount??0):Number(o.paid_amount??0);
      const chg=cash?Number(o.change_amount||0):0;
      const keepCustomerPii=withinDays(o.created_at,piiDays);
      const keepProofReference=withinDays(o.payment_submitted_at||o.verified_at||o.created_at,PAYMENT_PROOF_REFERENCE_DAYS);

      pemesan.push([
        o.id,o.public_order_code,p.d,p.t,
        keepCustomerPii?(o.customer_name||""):"",
        keepCustomerPii?(o.customer_whatsapp||""):"",
        source(o.order_source),service(o.service_mode),o.table_number||"",
        itemList(o),Number(o.item_count||0),Number(o.total_amount||0)
      ]);
      pesanan.push([
        o.id,o.public_order_code,p.d,p.t,source(o.order_source),service(o.service_mode),
        o.table_number||"",itemList(o),Number(o.item_count||0),Number(o.total_amount||0),
        pay(o.payment_method),o.payment_status||"",stage(o),n.t,pr.t,dn.t,
        keepCustomerPii?(o.customer_note||""):"",o.cashier_actor||""
      ]);
      keuangan.push([
        o.id,o.public_order_code,p.d,p.t,source(o.order_source),pay(o.payment_method),
        Number(o.total_amount||0),rec,chg,moneyIn(o),o.payment_status||"",
        o.cashier_actor||"",service(o.service_mode),o.table_number||"",
        keepProofReference?(o.payment_proof_url||""):"",v.s
      ]);
    }

    const stats=new Map<string,{q:number,r:number}>();
    for(const o of orders){
      if(!isPaid(o)||["cancelled","canceled","rejected","payment_rejected"].includes(String(o.order_status||"").toLowerCase()))continue;
      for(const i of (Array.isArray(o.items)?o.items:[])){
        const q=Math.max(0,Number(i.quantity??i.qty??1)||0);
        const pr=Math.max(0,Number(i.price??i.unit_price??0)||0);
        for(const key of [String(i.menuId??i.menu_id??i.id??""),String(i.name??"")].filter(Boolean)){
          const z=stats.get(key)||{q:0,r:0};z.q+=q;z.r+=q*pr;stats.set(key,z);
        }
      }
    }

    const menu:any[][]=[];
    for(const x of mr.data||[]){
      const z=stats.get(String(x.id))||stats.get(String(x.name))||{q:0,r:0};
      const p=parts(x.availability_updated_at||x.updated_at,tz);
      menu.push([
        x.id,x.name,x.category,Number(x.price||0),z.q,z.r,
        x.is_available!==false?"Tersedia":"Habis",x.is_visible!==false?"Ya":"Tidak",
        x.availability_note||"",`${p.d} ${p.t}`.trim(),x.image_url||""
      ]);
    }
    const paidOrders=orders.filter(o=>isPaid(o)&&!["cancelled","canceled","rejected","payment_rejected"].includes(String(o.order_status||"").toLowerCase()));
    const metrics={
      orders:orders.length,paid_orders:paidOrders.length,
      total_paid:paidOrders.reduce((s,o)=>s+moneyIn(o),0),
      items:paidOrders.reduce((s,o)=>s+Number(o.item_count||0),0),
      menu_rows:menu.length
    };

    return json({
      ok:true,version:3,writer_version_expected:Number(cfg.data.expected_writer_version||4),
      tenant_id:tenantId,tenant_slug:cfg.data.tenant_slug,
      business_name:cfg.data.business_name,timezone:tz,year,
      spreadsheetId:target.spreadsheet_id,label:target.label,
      retention:{customer_pii_days:piiDays,payment_proof_reference_days:PAYMENT_PROOF_REFERENCE_DAYS},
      tabs:{PEMESAN:pemesan,PESANAN:pesanan,"MENU & STOK":menu,KEUANGAN:keuangan},
      metrics
    },200,tenantId);
  }catch(e){
    console.error(e);
    return json({ok:false,error:"snapshot_failed"},500,tenantId);
  }
});
