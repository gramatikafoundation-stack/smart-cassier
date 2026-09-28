import express from "express";
import crypto from "node:crypto";
import pg from "pg";
import { WebSocketServer } from "ws";

const { Pool } = pg;
const app = express();
const port = Number(process.env.PORT || 3000);
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 12, ssl: process.env.PGSSLMODE === "disable" ? false : { rejectUnauthorized: false } });
const allowedOrigins = (process.env.ALLOWED_ORIGINS || "https://smart-cashier-sdb.vercel.app").split(",").map(x=>x.trim()).filter(Boolean);
const bootstrapKey = process.env.BOOTSTRAP_KEY || "";
const platformKey = process.env.PLATFORM_KEY || "";

app.use(express.json({limit:"512kb"}));
app.use((req,res,next)=>{
  const origin=req.headers.origin;
  if(origin && allowedOrigins.includes(origin)){
    res.setHeader("Access-Control-Allow-Origin",origin);
    res.setHeader("Vary","Origin");
    res.setHeader("Access-Control-Allow-Credentials","true");
  }
  res.setHeader("Access-Control-Allow-Headers","Content-Type, Authorization, X-Bootstrap-Key, X-Platform-Key, X-Idempotency-Key");
  res.setHeader("Access-Control-Allow-Methods","GET,POST,PATCH,DELETE,OPTIONS");
  if(req.method==="OPTIONS") return res.sendStatus(204);
  next();
});

const sha256=(v)=>crypto.createHash("sha256").update(v).digest("hex");
const token=()=>crypto.randomBytes(32).toString("base64url");
const jsonError=(res,status,message,code="ERROR")=>res.status(status).json({ok:false,error:{code,message}});
const can=(role,roles)=>role==="OWNER"||roles.includes(role);

async function withAppRole(fn){
  const c=await pool.connect();
  try{
    await c.query("begin");
    await c.query("set local role smart_cashier_app");
    const out=await fn(c);
    await c.query("commit");
    return out;
  }catch(e){
    await c.query("rollback").catch(()=>{});
    throw e;
  }finally{ c.release(); }
}
async function withScope(s,fn){
  return withAppRole(async c=>{
    await c.query("select set_config('app.tenant_id',$1,true),set_config('app.outlet_id',$2,true),set_config('app.user_id',$3,true),set_config('app.role',$4,true)",[
      s.tenant_id,String(s.outlet_id||""),s.user_id,s.role
    ]);
    return fn(c);
  });
}
async function resolveBearer(req){
  const h=req.headers.authorization||"";
  const raw=h.startsWith("Bearer ")?h.slice(7).trim():"";
  if(!raw)return null;
  return withAppRole(async c=>{
    const {rows}=await c.query("select * from resolve_session($1)",[sha256(raw)]);
    return rows[0]||null;
  });
}
async function auth(req,res,next){
  try{
    const s=await resolveBearer(req);
    if(!s)return jsonError(res,401,"Sesi tidak valid atau sudah berakhir","UNAUTHENTICATED");
    req.session=s;
    next();
  }catch(e){next(e);}
}
function requireRoles(...roles){
  return (req,res,next)=>can(req.session.role,roles)?next():jsonError(res,403,"Role tidak diizinkan","FORBIDDEN");
}

const sockets=new Map();
function broadcast(tenantId,outletId,event){
  const payload=JSON.stringify({type:"event",...event});
  for(const [,meta] of sockets){
    if(meta.tenantId===tenantId && meta.outletId===outletId && meta.ws.readyState===1) meta.ws.send(payload);
  }
}

app.get("/health",async(_req,res)=>{
  try{await pool.query("select 1");res.json({ok:true,service:"smart-cashier-cloud-core",time:new Date().toISOString()});}
  catch(e){jsonError(res,503,"Database unavailable","DB_UNAVAILABLE");}
});

app.get("/bootstrap/status",async(_req,res)=>{
  const {rows}=await pool.query("select count(*)::int as count from tenants");
  res.json({ok:true,bootstrapped:rows[0].count>0});
});

app.post("/bootstrap/init",async(req,res,next)=>{
  try{
    if(!bootstrapKey)return jsonError(res,503,"Bootstrap disabled","BOOTSTRAP_DISABLED");
    const k=req.headers["x-bootstrap-key"];
    const b=req.body||{};
    const required=["tenantSlug","tenantName","outletCode","outletName","ownerEmail","ownerName","ownerPassword"];
    if(required.some(x=>!String(b[x]||"").trim()))return jsonError(res,400,"Data bootstrap belum lengkap","INVALID_INPUT");
    const result=await withAppRole(async c=>{
      const {rows}=await c.query("select bootstrap_master($1,$2,$3,$4,$5,$6,$7,$8,$9) as result",[
        k,bootstrapKey,b.tenantSlug,b.tenantName,b.outletCode,b.outletName,b.ownerEmail,b.ownerName,b.ownerPassword
      ]);return rows[0].result;
    });
    res.status(201).json({ok:true,...result});
  }catch(e){next(e);}
});

app.post("/platform/tenants",async(req,res,next)=>{
  try{
    if(!platformKey)return jsonError(res,503,"Provisioning disabled","PROVISIONING_DISABLED");
    const k=req.headers["x-platform-key"];
    const b=req.body||{};
    const required=["tenantSlug","tenantName","outletCode","outletName","ownerEmail","ownerName","ownerPassword"];
    if(required.some(x=>!String(b[x]||"").trim()))return jsonError(res,400,"Data tenant belum lengkap","INVALID_INPUT");
    const result=await withAppRole(async c=>{
      const {rows}=await c.query("select provision_tenant($1,$2,$3,$4,$5,$6,$7,$8,$9) as result",[
        k,platformKey,b.tenantSlug,b.tenantName,b.outletCode,b.outletName,b.ownerEmail,b.ownerName,b.ownerPassword
      ]);return rows[0].result;
    });
    res.status(201).json({ok:true,...result});
  }catch(e){next(e);}
});

app.post("/auth/login",async(req,res,next)=>{
  try{
    const email=String(req.body?.email||"").trim(), password=String(req.body?.password||"");
    if(!email||!password)return jsonError(res,400,"Email dan password wajib diisi","INVALID_INPUT");
    const out=await withAppRole(async c=>{
      const {rows}=await c.query("select * from authenticate_user($1,$2)",[email,password]);
      const u=rows[0]; if(!u)return null;
      const raw=token(), expires=new Date(Date.now()+12*60*60*1000).toISOString();
      await c.query("select create_session($1,$2,$3,$4,$5)",[u.user_id,u.tenant_id,u.outlet_id,sha256(raw),expires]);
      return {accessToken:raw,expiresAt:expires,user:{id:u.user_id,tenantId:u.tenant_id,outletId:u.outlet_id,role:u.role,displayName:u.display_name}};
    });
    if(!out)return jsonError(res,401,"Email atau password salah","INVALID_CREDENTIALS");
    res.json({ok:true,...out});
  }catch(e){next(e);}
});

app.post("/auth/logout",auth,async(req,res,next)=>{
  try{
    const raw=(req.headers.authorization||"").slice(7).trim();
    await withAppRole(c=>c.query("select revoke_session($1)",[sha256(raw)]));
    res.json({ok:true});
  }catch(e){next(e);}
});
app.get("/auth/me",auth,(req,res)=>res.json({ok:true,user:req.session}));

app.get("/snapshot",auth,async(req,res,next)=>{
  try{
    const data=await withScope(req.session,async c=>{
      const [settings,categories,menus,orders,items,payments,kds,activity]=await Promise.all([
        c.query("select payload,updated_at from settings order by updated_at desc limit 1"),
        c.query("select * from categories order by sort_order,name"),
        c.query("select * from menu_items order by sort_order,name"),
        c.query("select * from orders where created_at>=now()-interval '30 days' order by created_at desc limit 2000"),
        c.query("select oi.* from order_items oi join orders o on o.id=oi.order_id where o.created_at>=now()-interval '30 days' order by oi.created_at desc"),
        c.query("select p.* from payments p join orders o on o.id=p.order_id where o.created_at>=now()-interval '30 days' order by p.created_at desc"),
        c.query("select k.* from kds_events k join orders o on o.id=k.order_id where o.created_at>=now()-interval '30 days' order by k.occurred_at desc"),
        c.query("select * from activity_logs order by created_at desc limit 1000")
      ]);
      return {settings:settings.rows[0]?.payload||{},categories:categories.rows,menus:menus.rows,orders:orders.rows,orderItems:items.rows,payments:payments.rows,kdsEvents:kds.rows,activity:activity.rows};
    });
    res.json({ok:true,data});
  }catch(e){next(e);}
});

app.put("/settings",auth,requireRoles("ADMIN"),async(req,res,next)=>{
  try{
    const payload=req.body?.payload;
    if(!payload||typeof payload!=="object"||Array.isArray(payload))return jsonError(res,400,"Payload settings tidak valid","INVALID_INPUT");
    const row=await withScope(req.session,async c=>{
      const {rows}=await c.query("insert into settings(tenant_id,outlet_id,payload) values($1,$2,$3) on conflict(tenant_id,outlet_id) do update set payload=excluded.payload,updated_at=now() returning *",[req.session.tenant_id,req.session.outlet_id,payload]);
      await c.query("insert into activity_logs(tenant_id,outlet_id,actor_user_id,action,entity_type,entity_id,details) values($1,$2,$3,'SETTINGS_UPDATE','SETTINGS',$2::text,$4)",[req.session.tenant_id,req.session.outlet_id,req.session.user_id,JSON.stringify({keys:Object.keys(payload)})]);
      return rows[0];
    });
    res.json({ok:true,data:row});
  }catch(e){next(e);}
});

app.post("/menu",auth,requireRoles("ADMIN"),async(req,res,next)=>{
  try{
    const b=req.body||{};
    if(!String(b.sku||"").trim()||!String(b.name||"").trim()||!(Number(b.price)>0))return jsonError(res,400,"Menu tidak valid","INVALID_INPUT");
    const row=await withScope(req.session,async c=>{
      const {rows}=await c.query("insert into menu_items(tenant_id,outlet_id,category_id,sku,name,price,cost,status,station,stock,sort_order,image_url,description,internal_note) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) returning *",[
        req.session.tenant_id,req.session.outlet_id,b.categoryId||null,String(b.sku).trim(),String(b.name).trim(),Number(b.price),b.cost??null,b.status||"ACTIVE",b.station||"LAINNYA",b.stock??null,b.sortOrder||0,b.imageUrl||null,b.description||null,b.internalNote||null
      ]);
      await c.query("insert into activity_logs(tenant_id,outlet_id,actor_user_id,action,entity_type,entity_id,details) values($1,$2,$3,'MENU_CREATE','MENU',$4,$5)",[req.session.tenant_id,req.session.outlet_id,req.session.user_id,rows[0].id,JSON.stringify({sku:rows[0].sku,name:rows[0].name})]);
      return rows[0];
    });
    res.status(201).json({ok:true,data:row});
  }catch(e){next(e);}
});

app.patch("/menu/:id",auth,requireRoles("ADMIN"),async(req,res,next)=>{
  try{
    const allowed=["sku","name","price","cost","status","station","stock","sort_order","image_url","description","internal_note","category_id"];
    const entries=Object.entries(req.body||{}).filter(([k])=>allowed.includes(k));
    if(!entries.length)return jsonError(res,400,"Tidak ada perubahan","INVALID_INPUT");
    const row=await withScope(req.session,async c=>{
      const sets=entries.map(([k],i)=>`${k}=$${i+4}`).join(",");
      const vals=entries.map(([,v])=>v);
      const {rows}=await c.query(`update menu_items set ${sets},updated_at=now() where tenant_id=$1 and outlet_id=$2 and id=$3 returning *`,[req.session.tenant_id,req.session.outlet_id,req.params.id,...vals]);
      if(!rows[0])return null;
      await c.query("insert into activity_logs(tenant_id,outlet_id,actor_user_id,action,entity_type,entity_id,details) values($1,$2,$3,'MENU_UPDATE','MENU',$4,$5)",[req.session.tenant_id,req.session.outlet_id,req.session.user_id,req.params.id,JSON.stringify(Object.fromEntries(entries))]);
      return rows[0];
    });
    if(!row)return jsonError(res,404,"Menu tidak ditemukan","NOT_FOUND");
    res.json({ok:true,data:row});
  }catch(e){next(e);}
});

app.post("/orders",auth,requireRoles("ADMIN","CASHIER"),async(req,res,next)=>{
  try{
    const b=req.body||{}, items=Array.isArray(b.items)?b.items:[];
    const total=Number(b.grandTotal), subtotal=Number(b.subtotal), discount=Number(b.discount||0), tax=Number(b.tax||0);
    if(!String(b.orderCode||"").trim()||!String(b.idempotencyKey||"").trim()||!String(b.customerName||"").trim()||!items.length||!Number.isFinite(total)||total<=0)return jsonError(res,400,"Pesanan tidak valid","INVALID_INPUT");
    if(!["DINE_IN","TAKE_AWAY"].includes(b.serviceMode)|| (b.serviceMode==="DINE_IN"&&!b.tableNumber))return jsonError(res,400,"Mode layanan tidak valid","INVALID_SERVICE");
    if(!["CASH","QRIS","TRANSFER"].includes(b.paymentMethod))return jsonError(res,400,"Metode pembayaran tidak valid","INVALID_PAYMENT");
    if(b.paymentMethod==="CASH" && Number(b.cashReceived)<total)return jsonError(res,400,"Uang diterima kurang","INSUFFICIENT_CASH");
    if(b.paymentMethod!=="CASH" && b.verified!==true)return jsonError(res,400,"Pembayaran belum diverifikasi","PAYMENT_UNVERIFIED");
    const result=await withScope(req.session,async c=>{
      const existing=await c.query("select id,order_code from orders where tenant_id=$1 and outlet_id=$2 and idempotency_key=$3",[req.session.tenant_id,req.session.outlet_id,b.idempotencyKey]);
      if(existing.rows[0])return {order:existing.rows[0],deduplicated:true};
      const o=await c.query("insert into orders(tenant_id,outlet_id,order_code,idempotency_key,customer_name,service_mode,table_number,subtotal,discount,tax,grand_total,payment_method,payment_status,order_status,cashier_user_id,note) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'PAID','NEW',$13,$14) returning *",[
        req.session.tenant_id,req.session.outlet_id,String(b.orderCode).trim(),String(b.idempotencyKey).trim(),String(b.customerName).trim(),b.serviceMode,b.tableNumber||null,subtotal,discount,tax,total,b.paymentMethod,req.session.user_id,b.note||null
      ]);
      const order=o.rows[0];
      for(const i of items){
        const qty=Number(i.qty), unit=Number(i.unitPrice), line=qty*unit;
        if(!(qty>0)||unit<0)throw new Error("Invalid order item");
        await c.query("insert into order_items(tenant_id,outlet_id,order_id,menu_id,menu_name,station,qty,unit_price,subtotal,note) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",[
          req.session.tenant_id,req.session.outlet_id,order.id,i.menuId||null,String(i.menuName||"").trim(),i.station||"LAINNYA",qty,unit,line,i.note||null
        ]);
      }
      const received=b.paymentMethod==="CASH"?Number(b.cashReceived):null;
      await c.query("insert into payments(tenant_id,outlet_id,order_id,method,amount,cash_received,change_amount,reference,verified) values($1,$2,$3,$4,$5,$6,$7,$8,$9)",[
        req.session.tenant_id,req.session.outlet_id,order.id,b.paymentMethod,total,received,received===null?null:Math.max(0,received-total),b.reference||null,b.paymentMethod==="CASH"?true:true
      ]);
      await c.query("insert into kds_events(tenant_id,outlet_id,order_id,previous_status,new_status,actor_user_id,note) values($1,$2,$3,'PAID','NEW',$4,'Order paid')",[req.session.tenant_id,req.session.outlet_id,order.id,req.session.user_id]);
      await c.query("insert into activity_logs(tenant_id,outlet_id,actor_user_id,action,entity_type,entity_id,details) values($1,$2,$3,'ORDER_CREATE','ORDER',$4,$5)",[req.session.tenant_id,req.session.outlet_id,req.session.user_id,order.id,JSON.stringify({orderCode:order.order_code,total})]);
      const ev=await c.query("insert into realtime_events(tenant_id,outlet_id,topic,entity_id,payload) values($1,$2,'ORDER_NEW',$3,$4) returning id",[req.session.tenant_id,req.session.outlet_id,order.id,JSON.stringify({orderId:order.id,orderCode:order.order_code})]);
      return {order,eventId:ev.rows[0].id,deduplicated:false};
    });
    if(!result.deduplicated)broadcast(req.session.tenant_id,req.session.outlet_id,{topic:"ORDER_NEW",entityId:result.order.id,eventId:result.eventId});
    res.status(result.deduplicated?200:201).json({ok:true,...result});
  }catch(e){next(e);}
});

const transition={NEW:"PROCESSING",PROCESSING:"READY",READY:"COMPLETED"};
app.patch("/orders/:id/status",auth,requireRoles("ADMIN","KITCHEN"),async(req,res,next)=>{
  try{
    const requested=String(req.body?.status||"");
    const result=await withScope(req.session,async c=>{
      const q=await c.query("select * from orders where id=$1 and tenant_id=$2 and outlet_id=$3 for update",[req.params.id,req.session.tenant_id,req.session.outlet_id]);
      const order=q.rows[0]; if(!order)return null;
      const recall=order.order_status==="COMPLETED"&&requested==="READY";
      if(!recall && transition[order.order_status]!==requested)throw Object.assign(new Error("Invalid transition"),{statusCode:409,code:"INVALID_TRANSITION"});
      const prev=order.order_status;
      const u=await c.query("update orders set order_status=$1,updated_at=now(),completed_at=case when $1='COMPLETED' then now() else null end where id=$2 returning *",[requested,order.id]);
      await c.query("insert into kds_events(tenant_id,outlet_id,order_id,previous_status,new_status,actor_user_id,note) values($1,$2,$3,$4,$5,$6,$7)",[req.session.tenant_id,req.session.outlet_id,order.id,prev,requested,req.session.user_id,recall?"Recall completed":null]);
      await c.query("insert into activity_logs(tenant_id,outlet_id,actor_user_id,action,entity_type,entity_id,details) values($1,$2,$3,$4,'ORDER',$5,$6)",[req.session.tenant_id,req.session.outlet_id,req.session.user_id,recall?"KDS_RECALL":"KDS_STATUS",order.id,JSON.stringify({from:prev,to:requested})]);
      const ev=await c.query("insert into realtime_events(tenant_id,outlet_id,topic,entity_id,payload) values($1,$2,'ORDER_STATUS',$3,$4) returning id",[req.session.tenant_id,req.session.outlet_id,order.id,JSON.stringify({orderId:order.id,from:prev,to:requested})]);
      return {order:u.rows[0],eventId:ev.rows[0].id};
    });
    if(!result)return jsonError(res,404,"Pesanan tidak ditemukan","NOT_FOUND");
    broadcast(req.session.tenant_id,req.session.outlet_id,{topic:"ORDER_STATUS",entityId:result.order.id,eventId:result.eventId,status:result.order.order_status});
    res.json({ok:true,...result});
  }catch(e){next(e);}
});

app.get("/events",auth,async(req,res,next)=>{
  try{
    const after=Math.max(0,Number(req.query.after||0));
    const rows=await withScope(req.session,c=>c.query("select id,topic,entity_id,payload,created_at from realtime_events where id>$1 order by id asc limit 500",[after]));
    res.json({ok:true,events:rows.rows});
  }catch(e){next(e);}
});

app.post("/users",auth,requireRoles("ADMIN"),async(req,res,next)=>{
  try{
    const b=req.body||{}, role=String(b.role||"VIEWER");
    if(!["ADMIN","CASHIER","KITCHEN","VIEWER"].includes(role)||!String(b.email||"").trim()||String(b.password||"").length<10)return jsonError(res,400,"Data pengguna tidak valid","INVALID_INPUT");
    const row=await withScope(req.session,async c=>{
      const {rows}=await c.query("insert into app_users(tenant_id,outlet_id,email,display_name,password_hash,role) values($1,$2,lower($3),$4,crypt($5,gen_salt('bf',12)),$6) returning id,email,display_name,role,status",[req.session.tenant_id,req.session.outlet_id,b.email,String(b.displayName||b.email),b.password,role]);
      await c.query("insert into activity_logs(tenant_id,outlet_id,actor_user_id,action,entity_type,entity_id,details) values($1,$2,$3,'USER_CREATE','USER',$4,$5)",[req.session.tenant_id,req.session.outlet_id,req.session.user_id,rows[0].id,JSON.stringify({role})]);
      return rows[0];
    });
    res.status(201).json({ok:true,data:row});
  }catch(e){next(e);}
});

app.use((err,req,res,_next)=>{
  console.error(err?.message||err);
  if(err?.code==="23505")return jsonError(res,409,"Data duplikat","CONFLICT");
  if(err?.code==="23503"||err?.code==="23514")return jsonError(res,400,"Relasi/data tidak valid","INVALID_INPUT");
  return jsonError(res,err?.statusCode||500,err?.statusCode?err.message:"Internal server error",err?.code||"INTERNAL");
});

const server=app.listen(port,()=>console.log("smart-cashier-cloud-core listening",port));
const wss=new WebSocketServer({server,path:"/ws"});
wss.on("connection",async(ws,req)=>{
  try{
    const u=new URL(req.url,"http://localhost"), raw=u.searchParams.get("token")||"";
    if(!raw){ws.close(4401,"Unauthorized");return;}
    const s=await withAppRole(async c=>{
      const {rows}=await c.query("select * from resolve_session($1)",[sha256(raw)]);
      return rows[0]||null;
    });
    if(!s){ws.close(4401,"Unauthorized");return;}
    const id=crypto.randomUUID();
    sockets.set(id,{ws,tenantId:s.tenant_id,outletId:s.outlet_id});
    ws.send(JSON.stringify({type:"ready",tenantId:s.tenant_id,outletId:s.outlet_id}));
    ws.on("close",()=>sockets.delete(id));
  }catch{ws.close(1011,"Server error");}
});
