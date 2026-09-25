(()=>{'use strict';
if(window.__rohmatKdsRealtimeV1)return;window.__rohmatKdsRealtimeV1=1;
const state={connected:false,mode:'connecting',lastGoodAt:0,lastEventAt:0,lastStatusAt:Date.now(),eventCount:0,safetyPollMs:45000,staleAfterMs:75000};
window.__ROHMAT_KDS_REALTIME__=state;
let client=null,channel=null,refreshTimer=0,staleTimer=0;

function syncEl(){return document.getElementById('sync')}
function label(mode){
  if(mode==='realtime')return '● Realtime';
  if(mode==='fallback')return '● Fallback';
  if(mode==='stale')return '● Data Stale';
  if(mode==='offline')return '● Offline';
  return '● Menghubungkan';
}
function render(mode=state.mode){
  state.mode=mode;state.lastStatusAt=Date.now();
  const el=syncEl();if(!el)return;
  el.dataset.syncState=mode;el.textContent=label(mode);
  el.setAttribute('role','status');el.setAttribute('aria-live','polite');
  el.title=mode==='realtime'?'Realtime aktif; polling hanya safety-net.':mode==='fallback'?'Realtime terputus; fallback polling aktif.':mode==='stale'?'Data belum berhasil diperbarui melewati batas aman.':'Status sinkronisasi KDS.';
}
function armPolling(){
  try{if(typeof schedulePolling==='function')schedulePolling()}catch{}
}
function markConnected(on){
  state.connected=!!on;
  render(on?'realtime':(navigator.onLine?'fallback':'offline'));
  armPolling();
}
function markFresh(at=Date.now()){
  state.lastGoodAt=Number(at)||Date.now();
  if(state.connected)render('realtime');
  else render(navigator.onLine?'fallback':'offline');
}
async function pull(kind){
  clearTimeout(refreshTimer);
  refreshTimer=setTimeout(async()=>{
    try{
      if(kind==='menu'){
        const jobs=[typeof refresh==='function'?refresh(false):Promise.resolve()];
        if(typeof cashLoad==='function'&&typeof cashSnap!=='undefined'&&cashSnap)jobs.push(cashLoad(false));
        await Promise.all(jobs);
      }else if(typeof refresh==='function'){
        await refresh(false);
      }
    }catch{}
  },90);
}
function onBroadcast(message){
  state.eventCount++;state.lastEventAt=Date.now();
  const payload=message?.payload&&typeof message.payload==='object'?message.payload:message;
  void pull(String(payload?.kind||'orders'));
}
function checkStale(){
  clearInterval(staleTimer);
  staleTimer=setInterval(()=>{
    if(document.hidden)return;
    if(!navigator.onLine){render('offline');return}
    if(state.lastGoodAt&&Date.now()-state.lastGoodAt>state.staleAfterMs){render('stale');return}
    if(state.connected&&state.mode!=='realtime')render('realtime');
  },5000);
}
async function start(){
  render(navigator.onLine?'connecting':'offline');
  try{
    await window.__SDB_TENANT_CONFIG_READY;
    const cfg=window.__SDB_TENANT_CONFIG||{};
    if(!cfg.supabaseUrl||!cfg.publishableKey||typeof window.RohmatRealtimeClient!=='function')throw new Error('realtime_client_unavailable');
    const ticket=await call({action:'realtime'});
    const info=ticket?.realtime||{};
    if(!String(info.topic||'').startsWith('kds:'))throw new Error('realtime_ticket_invalid');
    state.safetyPollMs=Math.max(30000,Number(info.safety_poll_seconds||45)*1000);
    state.staleAfterMs=Math.max(state.safetyPollMs+15000,Number(info.stale_after_seconds||75)*1000);
    client=new window.RohmatRealtimeClient(String(cfg.supabaseUrl).replace(/\/$/,'')+'/realtime/v1',{
      params:{apikey:String(cfg.publishableKey)},
      heartbeatIntervalMs:25000,
      reconnectAfterMs:tries=>[1000,2000,5000,10000][Math.min(Math.max(tries-1,0),3)]
    });
    channel=client.channel(String(info.topic),{config:{broadcast:{ack:false,self:false},private:false}});
    channel.on('broadcast',{event:String(info.event||'kds_change')},onBroadcast);
    channel.subscribe(status=>{
      if(status==='SUBSCRIBED')markConnected(true);
      else if(status==='CHANNEL_ERROR'||status==='TIMED_OUT'||status==='CLOSED')markConnected(false);
    });
  }catch{
    markConnected(false);
  }
  checkStale();
}
document.addEventListener('rohmat:kds-snapshot',e=>{if(e.detail?.ok)markFresh(e.detail.at||Date.now());else if(!state.connected)render(navigator.onLine?'fallback':'offline')});
document.addEventListener('rohmat:kds-session-ready',()=>{void start()},{once:true});
window.addEventListener('online',()=>{render(state.connected?'realtime':'fallback');if(!state.connected&&typeof syncCurrent==='function')void syncCurrent(false);armPolling()});
window.addEventListener('offline',()=>render('offline'));
window.addEventListener('pagehide',()=>{clearTimeout(refreshTimer);clearInterval(staleTimer);try{channel?.unsubscribe()}catch{}try{client?.disconnect()}catch{}},{once:true});
if(document.readyState!=='loading'&&!document.getElementById('app')?.hidden)void start();
})();