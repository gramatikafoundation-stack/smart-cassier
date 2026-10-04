(()=>{'use strict';
if(window.__rohmatKdsMenuMediaV3)return;
window.__rohmatKdsMenuMediaV3=1;
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
    img.style.removeProperty('background-image');
  });
  document.documentElement.dataset.rohmatKdsMenuMedia='v3-single-image';
}
let queued=false;
function schedule(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;normalize()})}
document.addEventListener('rohmat:kds-cashier-rendered',schedule);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',normalize,{once:true});else normalize();
window.addEventListener('pageshow',schedule);
})();
