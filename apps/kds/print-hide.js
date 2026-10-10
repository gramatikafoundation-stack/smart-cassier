(()=>{'use strict';
if(window.__SDB_KDS_LEGACY_PRINT_HIDE_V2)return;
window.__SDB_KDS_LEGACY_PRINT_HIDE_V2=1;
function purgeLegacyPrint(){
  document.querySelectorAll('[data-print]').forEach(el=>el.remove());
}
const lanes=document.getElementById('lanes');
if(lanes)new MutationObserver(purgeLegacyPrint).observe(lanes,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',purgeLegacyPrint,{once:true});else purgeLegacyPrint();
})();