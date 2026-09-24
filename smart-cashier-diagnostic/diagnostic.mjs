import { JSDOM, VirtualConsole } from "jsdom";

const target = "https://smart-cashier-sdb-production.up.railway.app";
const jsUrl = target + "/assets/index-3G3c-487.js";

async function run() {
  console.log("DIAG_START", new Date().toISOString());
  const res = await fetch(jsUrl);
  console.log("JS_FETCH", res.status, res.headers.get("content-type"), res.headers.get("content-length"));
  const js = await res.text();
  console.log("JS_SIZE", js.length, "HEAD", JSON.stringify(js.slice(0,80)));
  const vc = new VirtualConsole();
  vc.on("jsdomError", e => console.error("JSDOM_ERROR", e?.stack || e?.message || String(e)));
  vc.on("error", (...args) => console.error("CONSOLE_ERROR", ...args));
  vc.on("warn", (...args) => console.warn("CONSOLE_WARN", ...args));
  vc.on("log", (...args) => console.log("CONSOLE_LOG", ...args));

  const dom = new JSDOM("<!doctype html><html><body><div id='root'></div></body></html>", {
    url: target + "/kasir/general",
    runScripts: "dangerously",
    pretendToBeVisual: true,
    virtualConsole: vc,
    beforeParse(window) {
      window.matchMedia ||= () => ({matches:false,media:"",onchange:null,addListener(){},removeListener(){},addEventListener(){},removeEventListener(){},dispatchEvent(){return false}});
      window.ResizeObserver ||= class { observe(){} unobserve(){} disconnect(){} };
      window.IntersectionObserver ||= class { observe(){} unobserve(){} disconnect(){} };
      window.BroadcastChannel ||= class { constructor(){} postMessage(){} close(){} addEventListener(){} removeEventListener(){} };
      window.confirm ||= () => true;
      window.scrollTo ||= () => {};
      window.requestAnimationFrame ||= cb => setTimeout(() => cb(Date.now()), 0);
      window.cancelAnimationFrame ||= id => clearTimeout(id);
      if (!window.crypto.randomUUID) window.crypto.randomUUID = () => "00000000-0000-4000-8000-" + Math.random().toString(16).slice(2,14).padEnd(12,"0");
    }
  });

  const { window } = dom;
  window.addEventListener("error", e => console.error("WINDOW_ERROR", e.message, e.filename, e.lineno, e.colno, e.error?.stack || ""));
  window.addEventListener("unhandledrejection", e => console.error("UNHANDLED_REJECTION", e.reason?.stack || e.reason || ""));

  try {
    window.eval(js);
    console.log("EVAL_RETURNED");
  } catch (e) {
    console.error("EVAL_THROW", e?.stack || e);
  }

  await new Promise(r => setTimeout(r, 3000));
  const root = window.document.getElementById("root");
  console.log("ROOT_CHILDREN", root?.children?.length ?? -1);
  console.log("ROOT_HTML_LEN", root?.innerHTML?.length ?? -1);
  console.log("BODY_TEXT", JSON.stringify((window.document.body.textContent || "").slice(0,500)));
  console.log("DIAG_DONE");
}
run().then(()=>setInterval(()=>{}, 1<<30)).catch(e=>{console.error("DIAG_FATAL", e?.stack||e); setInterval(()=>{},1<<30);});
