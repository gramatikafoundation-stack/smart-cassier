(()=>{'use strict';
if(window.__rohmatKdsMenuMediaV4)return;
window.__rohmatKdsMenuMediaV4=1;
function ensurePaymentConfirm(){
  const root=document.getElementById('cashierRoot');if(!root)return;
  const payButtons=root.querySelector('.cashTwo [data-cash-pay]')?.parentElement;
  if(!payButtons)return;
  let box=root.querySelector('.cashPaymentConfirm');
  if(!box){
    box=document.createElement('div');
    box.className='cashPaymentConfirm';
    box.innerHTML='<b>Konfirmasi Pembayaran</b><span>Pilih metode pembayaran dan pastikan pembayaran sudah diterima sebelum pesanan dikirim ke dapur.</span>';
    payButtons.insertAdjacentElement('beforebegin',box);
  }
}
function normalize(){
  document.querySelectorAll('#cashierRoot .cashMediaFrame').forEach(frame=>{
    const fg=frame.querySelector('.cashMediaFg');
    if(fg&&frame.parentNode){
      fg.classList.remove('cashMediaFg');
      fg.classList.add('cashMediaSolo');
      frame.parentNode.insertBefore(fg,frame);
    }
    frame.remove();
  });
  document.querySelectorAll('#cashierRoot .cashMediaBg').forEach(x=>x.remove());
  document.querySelectorAll('#cashierRoot .cashItem>img').forEach(img=>{
    img.classList.add('cashMediaSolo');
    img.style.removeProperty('aspect-ratio');
    img.style.setProperty('object-fit','contain','important');
    img.style.setProperty('object-position','center','important');
    img.style.setProperty('width','100%','important');
    img.style.setProperty('height','100%','important');
    img.style.setProperty('padding','5px','important');
    img.style.setProperty('background','#f2f3f2','important');
    img.style.removeProperty('background-image');
  });
  ensurePaymentConfirm();
  document.documentElement.dataset.rohmatKdsMenuMedia='v4-public-card-parity';
}
let queued=false;
function schedule(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;normalize();setTimeout(normalize,40)})}
document.addEventListener('rohmat:kds-cashier-rendered',schedule);
document.addEventListener('click',e=>{if(e.target.closest?.('[data-cash-cat],[data-cash-add],[data-cash-plus],[data-cash-minus],[data-cash-pay],[data-cash-mode],#cashPayNow'))schedule()},true);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',normalize,{once:true});else normalize();
window.addEventListener('pageshow',schedule);
const root=document.getElementById('cashierRoot');if(root)new MutationObserver(schedule).observe(root,{childList:true,subtree:true});
})();