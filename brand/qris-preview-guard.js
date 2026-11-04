/* Kedai Terserah — payment checkout guard. Auto OCR remains enabled for local proof evaluation; order submission stays disabled until verified merchant activation. */
(function(){
  'use strict';
  if(window.__KT_QRIS_PREVIEW_GUARD_V2__)return;
  window.__KT_QRIS_PREVIEW_GUARD_V2__=true;
  const src='/brand/qris-kedai-hq.jpg';
  const room=()=>document.querySelector('.checkout .payroom');
  let scheduled=false;
  function status(message){
    const r=room();if(!r)return;
    const input=r.querySelector('#proof');if(!input)return;
    let el=r.querySelector('#ktProofPreviewStatus');
    if(!el){
      el=document.createElement('p');
      el.id='ktProofPreviewStatus';el.setAttribute('role','status');el.setAttribute('aria-live','polite');
      el.style.cssText='font-size:12px;line-height:1.45;color:#765139;margin:8px 0';
      (input.closest('.proof')||input.parentElement||r).append(el);
    }
    if(el.textContent!==message)el.textContent=message;
  }
  function apply(){
    const r=room();if(!r)return;
    const box=r.querySelector('.qrisbox');
    if(box){
      const picture=box.querySelector('img');
      if(!picture||picture.getAttribute('src')!==src){
        const image=document.createElement('img');
        image.src=src;image.alt='QRIS KEDAI H&Q — nama lain Kedai Terserah';
        image.loading='eager';image.decoding='async';
        image.style.cssText='display:block;max-width:100%;max-height:355px;object-fit:contain';
        box.replaceChildren(image);
      }
    }
    const label=r.querySelector('.paygrid h3');
    if(label&&label.textContent!=='KEDAI H&Q')label.textContent='KEDAI H&Q';
    const input=r.querySelector('#proof');
    if(input&&input.disabled)input.disabled=false;
    if(input&&!input.dataset.ktLocalOnly)input.dataset.ktLocalOnly='1';
    const send=r.querySelector('#send');
    if(send){
      if(!send.disabled)send.disabled=true;
      if(send.textContent!=='Menunggu Verifikasi Pembayaran')send.textContent='Menunggu Verifikasi Pembayaran';
    }
    for(const b of r.querySelectorAll('button')){
      if(/unduh qris/i.test(b.textContent||'')){
        if(!b.disabled)b.disabled=true;
        b.title='Menunggu verifikasi penerima QRIS';
      }
    }
    if(input){
      r.querySelector('#ktRunMerchantOcr')?.remove();
      if(!r.querySelector('#ktProofPreviewStatus'))
        status('Pilih bukti pembayaran. Pemeriksaan OCR dimulai otomatis setelah file dipilih.');
    }
  }
  function schedule(){
    if(scheduled)return;
    scheduled=true;
    requestAnimationFrame(()=>{scheduled=false;apply();});
  }
  // Do not stop propagation: the existing OCR worker receives change events automatically.
  document.addEventListener('change',e=>{
    const input=e.target;
    if(!(input instanceof HTMLInputElement)||input.id!=='proof'||!room())return;
    const file=input.files?.[0];
    if(!file){status('Pilih bukti pembayaran.');return;}
    if(!['image/png','image/jpeg','image/webp'].includes(file.type)||!file.size||file.size>3145728){
      status('Gunakan gambar JPEG, PNG, atau WebP maksimal 3 MB.');
      return;
    }
    status('OCR sedang memeriksa bukti pembayaran secara otomatis. Pengiriman pesanan belum diaktifkan.');
  },true);
  document.addEventListener('click',e=>{
    const r=room(),button=e.target?.closest?.('button,a');if(!r||!button||!r.contains(button))return;
    if(button.id==='send'||/unduh qris/i.test(button.textContent||'')){
      e.preventDefault();e.stopImmediatePropagation();
      status('Nama merchant Kedai H&Q sudah dikenali sebagai alias Kedai Terserah. Pengiriman pembayaran masih menunggu aktivasi sistem.');
      schedule();
    }
  },true);
  function boot(){
    const root=document.getElementById('app')||document.body;
    if(root)new MutationObserver(schedule).observe(root,{childList:true,subtree:true});
    document.addEventListener('rohmat:dom-updated',schedule);
    schedule();
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
