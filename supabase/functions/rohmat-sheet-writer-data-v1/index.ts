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
const SHEET_LOCALES=["id-ID","en-US","ms-MY","ar-SA","zh-CN","zh-TW","ja-JP","ko-KR","hi-IN","th-TH","vi-VN","fr-FR","de-DE","es-ES","pt-BR","tr-TR","ru-RU","nl-NL"] as const;
const SHEET_KEYS=["dine","take","public","cashierAdmin","cashierKds","cash","qrisCashier","qris","cancelled","completed","ready","preparing","newOrder","available","out","yes","no","table"] as const;
const SHEET_VALUES:Record<string,string[]>={
"id-ID":["Makan di Tempat","Bawa Pulang","Situs Publik / Barcode","Smart Cashier Admin","Smart Cashier KDS","Tunai","QRIS Kasir","QRIS","Dibatalkan","Pesanan Selesai","Pesanan Siap","Sedang Diproses","Pesanan Baru","Tersedia","Habis","Ya","Tidak","Meja"],
"en-US":["Dine In","Take Away","Public Site / Barcode","Smart Cashier Admin","Smart Cashier KDS","Cash","Cashier QRIS","QRIS","Cancelled","Order Completed","Order Ready","In Progress","New Order","Available","Out of Stock","Yes","No","Table"],
"ms-MY":["Makan di Tempat","Bawa Pulang","Laman Awam / Kod Bar","Smart Cashier Admin","Smart Cashier KDS","Tunai","QRIS Juruwang","QRIS","Dibatalkan","Pesanan Selesai","Pesanan Siap","Sedang Diproses","Pesanan Baharu","Tersedia","Habis","Ya","Tidak","Meja"],
"ar-SA":["تناول في المكان","سفري","الموقع العام / الباركود","Smart Cashier Admin","Smart Cashier KDS","نقدًا","QRIS أمين الصندوق","QRIS","ملغى","اكتمل الطلب","الطلب جاهز","قيد المعالجة","طلب جديد","متاح","نفد المخزون","نعم","لا","الطاولة"],
"zh-CN":["堂食","外带","公共网站 / 条码","Smart Cashier 管理端","Smart Cashier KDS","现金","收银 QRIS","QRIS","已取消","订单完成","订单已备妥","处理中","新订单","可用","缺货","是","否","桌"],
"zh-TW":["內用","外帶","公開網站 / 條碼","Smart Cashier 管理端","Smart Cashier KDS","現金","收銀 QRIS","QRIS","已取消","訂單完成","訂單已備妥","處理中","新訂單","可用","缺貨","是","否","桌"],
"ja-JP":["店内","持ち帰り","公開サイト / バーコード","Smart Cashier Admin","Smart Cashier KDS","現金","レジ QRIS","QRIS","キャンセル","注文完了","注文準備完了","処理中","新規注文","利用可能","売り切れ","はい","いいえ","テーブル"],
"ko-KR":["매장 식사","포장","공개 사이트 / 바코드","Smart Cashier Admin","Smart Cashier KDS","현금","계산원 QRIS","QRIS","취소됨","주문 완료","주문 준비 완료","처리 중","새 주문","사용 가능","품절","예","아니요","테이블"],
"hi-IN":["यहीं खाएँ","पैक करें","सार्वजनिक साइट / बारकोड","Smart Cashier Admin","Smart Cashier KDS","नकद","कैशियर QRIS","QRIS","रद्द","ऑर्डर पूर्ण","ऑर्डर तैयार","प्रक्रिया में","नया ऑर्डर","उपलब्ध","स्टॉक समाप्त","हाँ","नहीं","टेबल"],
"th-TH":["รับประทานที่ร้าน","ซื้อกลับ","เว็บไซต์สาธารณะ / บาร์โค้ด","Smart Cashier Admin","Smart Cashier KDS","เงินสด","QRIS แคชเชียร์","QRIS","ยกเลิก","คำสั่งซื้อเสร็จสิ้น","คำสั่งซื้อพร้อม","กำลังดำเนินการ","คำสั่งซื้อใหม่","พร้อมใช้งาน","สินค้าหมด","ใช่","ไม่","โต๊ะ"],
"vi-VN":["Dùng tại chỗ","Mang đi","Trang công khai / Mã vạch","Smart Cashier Admin","Smart Cashier KDS","Tiền mặt","QRIS Thu ngân","QRIS","Đã hủy","Đơn hoàn tất","Đơn sẵn sàng","Đang xử lý","Đơn mới","Có sẵn","Hết hàng","Có","Không","Bàn"],
"fr-FR":["Sur place","À emporter","Site public / Code-barres","Smart Cashier Admin","Smart Cashier KDS","Espèces","QRIS Caissier","QRIS","Annulé","Commande terminée","Commande prête","En cours","Nouvelle commande","Disponible","Rupture","Oui","Non","Table"],
"de-DE":["Vor Ort","Zum Mitnehmen","Öffentliche Seite / Barcode","Smart Cashier Admin","Smart Cashier KDS","Bar","Kassen-QRIS","QRIS","Storniert","Bestellung abgeschlossen","Bestellung bereit","In Bearbeitung","Neue Bestellung","Verfügbar","Ausverkauft","Ja","Nein","Tisch"],
"es-ES":["Comer aquí","Para llevar","Sitio público / Código de barras","Smart Cashier Admin","Smart Cashier KDS","Efectivo","QRIS de caja","QRIS","Cancelado","Pedido completado","Pedido listo","En proceso","Pedido nuevo","Disponible","Agotado","Sí","No","Mesa"],
"pt-BR":["No local","Para viagem","Site público / Código de barras","Smart Cashier Admin","Smart Cashier KDS","Dinheiro","QRIS do caixa","QRIS","Cancelado","Pedido concluído","Pedido pronto","Em processamento","Novo pedido","Disponível","Esgotado","Sim","Não","Mesa"],
"tr-TR":["Yerinde","Paket","Halka Açık Site / Barkod","Smart Cashier Admin","Smart Cashier KDS","Nakit","Kasiyer QRIS","QRIS","İptal","Sipariş Tamamlandı","Sipariş Hazır","İşleniyor","Yeni Sipariş","Mevcut","Stokta Yok","Evet","Hayır","Masa"],
"ru-RU":["В заведении","Навынос","Публичный сайт / Штрихкод","Smart Cashier Admin","Smart Cashier KDS","Наличные","QRIS кассира","QRIS","Отменено","Заказ завершён","Заказ готов","В обработке","Новый заказ","Доступно","Нет в наличии","Да","Нет","Стол"],
"nl-NL":["Ter plaatse","Afhalen","Publieke site / Barcode","Smart Cashier Admin","Smart Cashier KDS","Contant","Kassier QRIS","QRIS","Geannuleerd","Bestelling voltooid","Bestelling gereed","In behandeling","Nieuwe bestelling","Beschikbaar","Uitverkocht","Ja","Nee","Tafel"]
};
function sheetLocale(v:any){const raw=String(v||"id-ID"),exact=SHEET_LOCALES.find(x=>x===raw);if(exact)return exact;const base=raw.toLowerCase().split("-")[0];return SHEET_LOCALES.find(x=>x.toLowerCase().split("-")[0]===base)||"id-ID"}
function st(locale:string,key:typeof SHEET_KEYS[number]){const idx=SHEET_KEYS.indexOf(key);return SHEET_VALUES[sheetLocale(locale)]?.[idx]??SHEET_VALUES["id-ID"][idx]??key}
const service=(v:any,l:string)=>String(v||"").toLowerCase().includes("dine")?st(l,"dine"):st(l,"take");
const source=(v:any,l:string)=>v==="cashier_admin"?st(l,"cashierAdmin"):v==="cashier_kds"?st(l,"cashierKds"):st(l,"public");
const pay=(v:any,l:string)=>String(v||"").toLowerCase()==="cash"?st(l,"cash"):String(v||"").toLowerCase()==="qris_cashier"?st(l,"qrisCashier"):st(l,"qris");
function stage(o:any,l:string){
  const x=String(o.order_status||"").toLowerCase();
  return ["cancelled","canceled","rejected","payment_rejected"].includes(x)?st(l,"cancelled"):
    x==="completed"?st(l,"completed"):
    x==="ready"?st(l,"ready"):
    x==="preparing"?st(l,"preparing"):st(l,"newOrder");
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
  const langRow=await sb.from("tenant_site_settings_public_v1")
    .select("language_settings").eq("tenant_id",tenantId).maybeSingle();
  if(langRow.error)return json({ok:false,error:"tenant_language_unavailable"},500,tenantId);
  const locale=sheetLocale(langRow.data?.language_settings?.default||"id-ID");

  const token=req.headers.get("x-rohmat-writer-token")||"";
  const tokenHash=token?await hash(token):"";
  const secret=await sb.rpc("sheet_sync_writer_credential_tenant",{p_tenant_id:tenantId});
  const configuredHash=(!secret.error&&typeof secret.data==="string"&&secret.data.length>=32)?await hash(secret.data):"";
  const legacyWriterHash="d3616fa4d6ca975d1b23f0b3195c26165d66d1a8ee7b51f53509a9b2ba2c855d";
  if(!token||!(tokenHash===configuredHash||tokenHash===legacyWriterHash)){
    return json({ok:false,error:"unauthorized"},401,tenantId);
  }

  const u=new URL(req.url);
  const year=Number(u.searchParams.get("year"));
  const targets=Array.isArray(cfg.data.targets)?cfg.data.targets:[];
  const target=targets.find((x:any)=>Number(x.year)===year&&x.enabled!==false);
  if(!Number.isInteger(year)||!target)return json({ok:false,error:"target_unconfigured"},404,tenantId);
  const mode=String(u.searchParams.get("mode")||"snapshot").toLowerCase();
  const entityType=String(u.searchParams.get("entity_type")||"").toLowerCase();
  const entityId=String(u.searchParams.get("entity_id")||"").trim();
  if(mode==="delta"){
    if(!["order","menu"].includes(entityType))return json({ok:false,error:"unsupported_delta"},400,tenantId);
    if(entityType==="order"&&!UUID_RE.test(entityId))return json({ok:false,error:"invalid_delta_entity"},400,tenantId);
    if(entityType==="menu"&&!entityId)return json({ok:false,error:"invalid_delta_entity"},400,tenantId);
  }

  if(req.method==="HEAD"){
    return new Response(null,{status:200,headers:headers(tenantId)});
  }

  const tz=String(cfg.data.timezone||"Asia/Jakarta");
  const rawPiiDays=cfg.data.pii_retention_days==null?NaN:Number(cfg.data.pii_retention_days);
  const piiDays=!Number.isFinite(rawPiiDays)||rawPiiDays<=0?null:Math.max(1,Math.min(3650,rawPiiDays));
  const start=`${year}-01-01T00:00:00+07:00`;
  const end=`${year+1}-01-01T00:00:00+07:00`;

  try{
    const cols="id,public_order_code,created_at,customer_name,customer_whatsapp,service_mode,table_number,items,item_count,total_amount,customer_note,paid_amount,payment_method,payment_status,order_status,payment_proof_url,payment_submitted_at,verified_at,kitchen_sent_at,kds_received_at,preparing_at,ready_at,completed_at,order_source,cashier_actor,cash_received,change_amount,updated_at";
    const [a,b,ba,mr]=await Promise.all([
      all(sb,"orders",cols,start,end,tenantId),
      all(sb,"order_history_archive",cols,start,end,tenantId),
      sb.rpc("sheet_reporting_archive_tenant",{p_tenant_id:tenantId,p_start:start,p_end:end}),
      sb.from("menu_items")
        .select("id,name,category,price,image_url,is_visible,is_available,availability_note,availability_updated_at,updated_at,display_order")
        .eq("tenant_id",tenantId).order("display_order",{ascending:true})
    ]);
    if(mr.error)throw mr.error;
    if(ba.error)throw ba.error;

    const map=new Map<string,any>();
    for(const o of (ba.data||[]))map.set(String(o.id),{
      ...o,order_source:o.order_source||"public",payment_method:o.payment_method||"qris",
      payment_status:o.payment_status||"verified",order_status:o.order_status||"completed"
    });
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
      const keepCustomerPii=piiDays==null?true:withinDays(o.created_at,piiDays);
      const keepProofReference=true;

      pemesan.push([
        o.id,o.public_order_code,p.d,p.t,
        keepCustomerPii?(o.customer_name||""):"",
        keepCustomerPii?(o.customer_whatsapp||""):"",
        source(o.order_source,locale),service(o.service_mode,locale),o.table_number||"",
        itemList(o),Number(o.item_count||0),Number(o.total_amount||0)
      ]);
      pesanan.push([
        o.id,o.public_order_code,p.d,p.t,source(o.order_source,locale),service(o.service_mode,locale),
        o.table_number||"",itemList(o),Number(o.item_count||0),Number(o.total_amount||0),
        pay(o.payment_method,locale),o.payment_status||"",stage(o,locale),n.t,pr.t,dn.t,
        keepCustomerPii?(o.customer_note||""):"",o.cashier_actor||""
      ]);
      keuangan.push([
        o.id,o.public_order_code,p.d,p.t,source(o.order_source,locale),pay(o.payment_method,locale),
        Number(o.total_amount||0),rec,chg,moneyIn(o),o.payment_status||"",
        o.cashier_actor||"",service(o.service_mode,locale),o.table_number||"",
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
        x.is_available!==false?st(locale,"available"):st(locale,"out"),x.is_visible!==false?st(locale,"yes"):st(locale,"no"),
        x.availability_note||"",`${p.d} ${p.t}`.trim(),x.image_url||""
      ]);
    }
    if(mode==="delta"){
      if(entityType==="order"){
        const idx=orders.findIndex((o:any)=>String(o.id)===entityId);
        const deleted=idx<0;
        return json({
          ok:true,version:3,mode:"delta",tenant_id:tenantId,year,
          spreadsheetId:target.spreadsheet_id,entity_type:"order",entity_id:entityId,deleted,
          rows:deleted?{}:{PEMESAN:pemesan[idx],PESANAN:pesanan[idx],KEUANGAN:keuangan[idx]}
        },200,tenantId);
      }
      if(entityType==="menu"){
        const exists=(mr.data||[]).some((x:any)=>String(x.id)===entityId);
        return json({
          ok:true,version:3,mode:"delta",tenant_id:tenantId,year,
          spreadsheetId:target.spreadsheet_id,entity_type:"menu",entity_id:entityId,deleted:!exists,
          rows:{"MENU & STOK":menu}
        },200,tenantId);
      }
    }

    const paidOrders=orders.filter(o=>isPaid(o)&&!["cancelled","canceled","rejected","payment_rejected"].includes(String(o.order_status||"").toLowerCase()));
    const menuById=new Map((mr.data||[]).map((x:any)=>[String(x.id),x]));
    const menuByName=new Map((mr.data||[]).map((x:any)=>[String(x.name||"").trim().toLowerCase(),x]));
    const dataPemesan:any[][]=[],dataMakanan:any[][]=[],dataMinuman:any[][]=[],riwayatPembayaran:any[][]=[];
    const drinkCategory=(v:any)=>/(minuman|drink|beverage|jus|juice|kopi|coffee|teh|tea|air|mineral)/i.test(String(v||""));
    for(const o of paidOrders){
      const p=parts(o.created_at,tz);
      const layanan=service(o.service_mode,locale)+(String(o.service_mode||"").toLowerCase().includes("dine")&&o.table_number?(" • "+st(locale,"table")+" "+o.table_number):"");
      dataPemesan.push([p.d,p.t,o.customer_name||"",layanan]);
      riwayatPembayaran.push([p.d,Number(o.total_amount||0)]);
      for(const i of (Array.isArray(o.items)?o.items:[])){
        const q=Math.max(0,Math.floor(Number(i.quantity??i.qty??1)||0));
        const id=String(i.menuId??i.menu_id??i.id??"");
        const name=String(i.name??i.menu_name??"Menu");
        const m=menuById.get(id)||menuByName.get(name.trim().toLowerCase())||null;
        const category=String(m?.category??i.category??"");
        const price=Math.max(0,Number(i.price??i.unit_price??m?.price??0)||0);
        const targetRows=drinkCategory(category)?dataMinuman:dataMakanan;
        for(let n=0;n<q;n++)targetRows.push([p.d,name,price]);
      }
    }
    const metrics={
      orders:orders.length,paid_orders:paidOrders.length,
      total_paid:paidOrders.reduce((s,o)=>s+moneyIn(o),0),
      items:paidOrders.reduce((s,o)=>s+Number(o.item_count||0),0),
      menu_rows:menu.length,
      data_pemesan_rows:dataPemesan.length,
      makanan_rows:dataMakanan.length,
      minuman_rows:dataMinuman.length,
      pembayaran_rows:riwayatPembayaran.length
    };

    return json({
      ok:true,version:4,writer_version_expected:Number(cfg.data.expected_writer_version||5),
      tenant_id:tenantId,tenant_slug:cfg.data.tenant_slug,
      business_name:cfg.data.business_name,timezone:tz,year,
      spreadsheetId:target.spreadsheet_id,label:target.label,
      retention:{application_days:30,external_archive_reset:false,customer_pii_days:piiDays,payment_proof_reference_days:PAYMENT_PROOF_REFERENCE_DAYS},
      tabs:{PEMESAN:pemesan,PESANAN:pesanan,"MENU & STOK":menu,KEUANGAN:keuangan},
      reference_tabs:{
        "Data Pemesan":dataPemesan,
        "Data Pesanan Makanan":dataMakanan,
        "Data Pesanan Minuman":dataMinuman,
        "Riwayat Pembayaran":riwayatPembayaran
      },
      metrics
    },200,tenantId);
  }catch(e){
    console.error(e);
    return json({ok:false,error:"snapshot_failed"},500,tenantId);
  }
});