const http=require("http");

const ORIGIN="https://smart-digital-for-business.vercel.app";
const PORT=Number(process.env.PORT||3000);

const VISUAL_CSS=String.raw`
/* SDB TRUE-HQ VISUAL RECOVERY — presentation layer only */
.hero-photo{
  background:#fff url("https://unsplash.com/photos/QVVHV24DA_o/download?force=true") center center/cover no-repeat!important;
  filter:none!important;box-shadow:none!important;
}
.hero-photo:before{
  content:""!important;display:block!important;position:absolute!important;inset:0!important;z-index:2!important;
  background:linear-gradient(90deg,#fff 0%,#fff 28%,rgba(255,255,255,.985) 40%,rgba(255,255,255,.90) 51%,rgba(255,255,255,.56) 63%,rgba(255,255,255,.14) 78%,transparent 92%)!important;
}
.hero-photo:after{display:none!important}

.about-photo{
  background-image:linear-gradient(90deg,rgba(255,255,255,.18),transparent 28%),url("https://unsplash.com/photos/kI54hVB5tm0/download?force=true")!important;
  background-size:cover!important;background-position:center center!important;background-repeat:no-repeat!important;
  filter:none!important;
}
.about-photo:before,.about-photo:after{display:none!important}
.about-brand{
  display:block!important;position:absolute!important;z-index:5!important;
  left:62.8%!important;right:auto!important;top:42%!important;
  font-size:clamp(78px,6.4vw,118px)!important;font-weight:950!important;letter-spacing:-.07em!important;
  color:#fff!important;line-height:.9!important;
  text-shadow:0 5px 18px rgba(4,37,83,.28),0 0 2px rgba(255,255,255,.9)!important;
  transform:none!important;pointer-events:none!important;
}

.contact-photo{
  background-image:url("https://unsplash.com/photos/wlHBYkK2y4k/download?force=true")!important;
  background-size:cover!important;background-position:56% center!important;background-repeat:no-repeat!important;
  filter:none!important;
}
.contact-photo:before,.contact-photo:after{display:none!important}

.needs-visual{
  background-image:url("https://unsplash.com/photos/kI54hVB5tm0/download?force=true")!important;
  background-size:cover!important;background-position:center center!important;
  opacity:.11!important;filter:none!important;
}

.product-card-visual{display:flex!important;align-items:center!important;justify-content:center!important}
.product-card-visual img{
  width:624px!important;max-width:100%!important;height:100%!important;
  object-fit:cover!important;object-position:center!important;image-rendering:auto!important;
}
.pkl-device{max-width:624px!important}
.pkl-preview-screen{
  display:flex!important;align-items:center!important;justify-content:center!important;
  padding:10px!important;background:#eef5fc!important;
}
.pkl-preview-shot{
  display:block!important;width:auto!important;height:auto!important;
  max-width:min(100%,399px)!important;max-height:100%!important;
  object-fit:contain!important;object-position:center!important;margin:auto!important;
}

@media(max-width:760px){
  .hero-photo{background-position:center center!important}
  .hero-photo:before{
    background:linear-gradient(90deg,#fff 0%,rgba(255,255,255,.97) 48%,rgba(255,255,255,.72) 72%,rgba(255,255,255,.18) 100%)!important
  }
  .about-brand{display:none!important}
  .about-photo,.contact-photo{background-position:center center!important}
}
`;

function copyHeaders(src,res,isHtml){
  const skip=new Set(["content-length","content-encoding","transfer-encoding","connection","content-security-policy"]);
  src.headers.forEach((v,k)=>{if(!skip.has(k.toLowerCase()))res.setHeader(k,v)});
  if(isHtml){
    res.setHeader("content-type","text/html; charset=utf-8");
    res.setHeader("cache-control","no-store, max-age=0");
    res.setHeader("x-sdb-visual-recovery","true-hq-live");
  }
}

http.createServer(async(req,res)=>{
  try{
    const target=new URL(req.url||"/",ORIGIN);
    const headers={};
    for(const [k,v] of Object.entries(req.headers)){
      if(v && !["host","connection","content-length","accept-encoding"].includes(k.toLowerCase())) headers[k]=v;
    }
    const upstream=await fetch(target,{method:req.method||"GET",headers,redirect:"follow"});
    const ct=upstream.headers.get("content-type")||"";
    const isHtml=ct.includes("text/html");
    copyHeaders(upstream,res,isHtml);
    res.statusCode=upstream.status;
    if(isHtml){
      let html=await upstream.text();
      const marker='<meta name="sdb-visual-recovery" content="true-hq-live">';
      const style='<style id="sdb-true-hq-live">'+VISUAL_CSS+'</style>';
      if(html.includes("</head>")) html=html.replace("</head>",marker+style+"</head>");
      else html=marker+style+html;
      res.end(html);
    }else{
      const buf=Buffer.from(await upstream.arrayBuffer());
      res.end(buf);
    }
  }catch(err){
    res.statusCode=502;
    res.setHeader("content-type","text/plain; charset=utf-8");
    res.end("SDB recovery proxy error: "+String(err&&err.message||err));
  }
}).listen(PORT,"0.0.0.0",()=>console.log("SDB Visual Recovery listening on",PORT));
