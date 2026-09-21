(()=>{'use strict';
let cashierWarmStarted=false;
function warmCashier(){
  const app=document.getElementById('app');
  if(cashierWarmStarted||!app||app.hidden)return;
  cashierWarmStarted=true;
  queueMicrotask(()=>{try{if(typeof cashLoad==='function')cashLoad(false)}catch{}});
}
document.addEventListener('pointerdown',event=>{
  const tab=event.target.closest?.('[data-tab]');
  if(!tab)return;
  try{if(typeof switchTab==='function')switchTab(tab.dataset.tab)}catch{}
},{passive:true});
document.addEventListener('pointerover',event=>{
  const tab=event.target.closest?.('[data-tab="cashier"]');
  if(tab)warmCashier();
},{passive:true});
})();
