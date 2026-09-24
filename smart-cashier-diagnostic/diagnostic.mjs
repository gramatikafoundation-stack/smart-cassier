import { JSDOM, VirtualConsole } from "jsdom";
import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const target = "https://smart-cashier-sdb-production.up.railway.app";
const jsUrl = target + "/assets/index-3G3c-487.js";

async function run() {
  console.log("DIAG_START", new Date().toISOString());
  const res = await fetch(jsUrl);
  console.log("JS_FETCH", res.status, res.headers.get("content-type"), res.headers.get("content-length"));
  const js = await res.text();
  console.log("JS_SIZE", js.length, "HEAD", JSON.stringify(js.slice(0,80)));
  await writeFile("/tmp/sc-bundle.mjs", js, "utf8");

  const vc = new VirtualConsole();
  vc.on("jsdomError", e => console.error("JSDOM_ERROR", e?.stack || e?.message || String(e)));
  vc.on("error", (...args) => console.error("CONSOLE_ERROR", ...args));
  vc.on("warn", (...args) => console.warn("CONSOLE_WARN", ...args));
  vc.on("log", (...args) => console.log("CONSOLE_LOG", ...args));

  const dom = new JSDOM("<!doctype html><html><head></head><body><div id='root'></div></body></html>", {
    url: target + "/kasir/general",
    pretendToBeVisual: true,
    virtualConsole: vc
  });
  const w = dom.window;

  w.matchMedia ||= () => ({matches:false,media:"",onchange:null,addListener(){},removeListener(){},addEventListener(){},removeEventListener(){},dispatchEvent(){return false}});
  w.ResizeObserver ||= class { observe(){} unobserve(){} disconnect(){} };
  w.IntersectionObserver ||= class { observe(){} unobserve(){} disconnect(){} };
  w.BroadcastChannel ||= class { constructor(){} postMessage(){} close(){} addEventListener(){} removeEventListener(){} };
  w.confirm ||= () => true;
  w.scrollTo ||= () => {};
  w.requestAnimationFrame ||= cb => setTimeout(() => cb(Date.now()), 0);
  w.cancelAnimationFrame ||= id => clearTimeout(id);
  if (!w.crypto.randomUUID) w.crypto.randomUUID = () => "00000000-0000-4000-8000-" + Math.random().toString(16).slice(2,14).padEnd(12,"0");

  const names = Object.getOwnPropertyNames(w);
  for (const name of names) {
    if (name in globalThis) continue;
    try { globalThis[name] = w[name]; } catch {}
  }
  const bindGlobal = (name, value) => {
    try { Object.defineProperty(globalThis, name, { value, configurable:true, writable:true }); }
    catch { try { globalThis[name] = value; } catch {} }
  };
  bindGlobal("window", w);
  bindGlobal("document", w.document);
  bindGlobal("navigator", w.navigator);
  bindGlobal("location", w.location);
  bindGlobal("history", w.history);
  bindGlobal("localStorage", w.localStorage);
  bindGlobal("sessionStorage", w.sessionStorage);
  bindGlobal("BroadcastChannel", w.BroadcastChannel);
  bindGlobal("matchMedia", w.matchMedia);
  bindGlobal("ResizeObserver", w.ResizeObserver);
  bindGlobal("IntersectionObserver", w.IntersectionObserver);
  bindGlobal("crypto", w.crypto);

  process.on("uncaughtException", e => console.error("UNCAUGHT", e?.stack || e));
  process.on("unhandledRejection", e => console.error("UNHANDLED_REJECTION", e?.stack || e));

  try {
    const url = pathToFileURL("/tmp/sc-bundle.mjs").href + "?t=" + Date.now();
    await import(url);
    console.log("MODULE_IMPORTED");
  } catch (e) {
    console.error("MODULE_THROW", e?.stack || e);
  }

  await new Promise(r => setTimeout(r, 3500));
  const root = w.document.getElementById("root");
  console.log("ROOT_CHILDREN", root?.children?.length ?? -1);
  console.log("ROOT_HTML_LEN", root?.innerHTML?.length ?? -1);
  console.log("ROOT_HEAD", JSON.stringify((root?.innerHTML || "").slice(0,500)));
  console.log("BODY_TEXT", JSON.stringify((w.document.body.textContent || "").slice(0,700)));
  console.log("DIAG_DONE");
}

run().then(()=>setInterval(()=>{}, 1<<30)).catch(e=>{console.error("DIAG_FATAL", e?.stack||e); setInterval(()=>{},1<<30);});
