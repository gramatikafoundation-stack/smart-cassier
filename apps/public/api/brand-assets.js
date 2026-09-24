import zlib from 'node:zlib';
import { resolvePublicTenantConfig, failTenantConfig } from '../lib/tenant-config.js';

const COLORS = {
  bg: [245, 239, 227, 255],
  primary: [49, 83, 67, 255],
  accent: [184, 116, 68, 255],
  light: [255, 253, 248, 255]
};

const FONT = {
  A:['01110','10001','10001','11111','10001','10001','10001'],B:['11110','10001','10001','11110','10001','10001','11110'],D:['11110','10001','10001','10001','10001','10001','11110'],E:['11111','10000','10000','11110','10000','10000','11111'],H:['10001','10001','10001','11111','10001','10001','10001'],I:['11111','00100','00100','00100','00100','00100','11111'],K:['10001','10010','10100','11000','10100','10010','10001'],M:['10001','11011','10101','10101','10001','10001','10001'],N:['10001','11001','10101','10011','10001','10001','10001'],O:['01110','10001','10001','10001','10001','10001','01110'],P:['11110','10001','10001','11110','10000','10000','10000'],R:['11110','10001','10001','11110','10100','10010','10001'],S:['01111','10000','10000','01110','00001','00001','11110'],T:['11111','00100','00100','00100','00100','00100','00100'],U:['10001','10001','10001','10001','10001','10001','01110'],Y:['10001','10001','01010','00100','00100','00100','00100'],
  ' ':['00000','00000','00000','00000','00000','00000','00000'],
  '&':['01100','10010','10100','01000','10101','10010','01101']
};

function crcTable(){const t=[];for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?(0xedb88320^(c>>>1)):(c>>>1);t[n]=c>>>0;}return t;}
const CRC=crcTable();
function crc32(buf){let c=0xffffffff;for(const b of buf)c=CRC[(c^b)&0xff]^(c>>>8);return (c^0xffffffff)>>>0;}
function chunk(type,data){const t=Buffer.from(type);const len=Buffer.alloc(4);len.writeUInt32BE(data.length);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(Buffer.concat([t,data])));return Buffer.concat([len,t,data,crc]);}
function png(width,height,pixels){const raw=Buffer.alloc((width*4+1)*height);for(let y=0;y<height;y++){const row=y*(width*4+1);raw[row]=0;pixels.copy(raw,row+1,y*width*4,(y+1)*width*4);}const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width,0);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=6;return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',zlib.deflateSync(raw,{level:9})),chunk('IEND',Buffer.alloc(0))]);}
function canvas(width,height,color=COLORS.bg){const p=Buffer.alloc(width*height*4);for(let i=0;i<p.length;i+=4){p[i]=color[0];p[i+1]=color[1];p[i+2]=color[2];p[i+3]=color[3];}return p;}
function rect(p,w,h,x,y,rw,rh,c){for(let yy=Math.max(0,y);yy<Math.min(h,y+rh);yy++)for(let xx=Math.max(0,x);xx<Math.min(w,x+rw);xx++){const i=(yy*w+xx)*4;p[i]=c[0];p[i+1]=c[1];p[i+2]=c[2];p[i+3]=c[3];}}
function text(p,w,h,s,x,y,scale,c){let cx=x;for(const ch of s){const g=FONT[ch]||FONT[' '];for(let gy=0;gy<7;gy++)for(let gx=0;gx<5;gx++)if(g[gy][gx]==='1')rect(p,w,h,cx+gx*scale,y+gy*scale,scale,scale,c);cx+=6*scale;}return cx;}
function centeredText(p,w,h,s,y,scale,c){const width=s.length*6*scale-scale;return text(p,w,h,s,Math.max(0,Math.floor((w-width)/2)),y,scale,c);}
function icon(size,initial='B'){const p=canvas(size,size,COLORS.primary);const pad=Math.floor(size*.12);rect(p,size,size,pad,pad,size-pad*2,size-pad*2,COLORS.bg);rect(p,size,size,pad,Math.floor(size*.68),size-pad*2,Math.floor(size*.12),COLORS.accent);const scale=Math.max(2,Math.floor(size/14));const glyph=FONT[initial]?initial:'B';centeredText(p,size,size,glyph,Math.floor(size*.24),scale,COLORS.primary);return png(size,size,p);}
function og(businessName='Business'){const w=1200,h=630,p=canvas(w,h,COLORS.bg);rect(p,w,h,0,0,30,h,COLORS.accent);rect(p,w,h,65,65,1070,500,COLORS.light);rect(p,w,h,65,65,1070,18,COLORS.primary);const label=String(businessName||'BUSINESS').normalize('NFKD').toUpperCase().replace(/[^A-Z& ]+/g,' ').replace(/\s+/g,' ').trim().slice(0,40)||'BUSINESS';const scale=Math.max(5,Math.min(12,Math.floor(940/Math.max(1,label.length*6))));centeredText(p,w,h,label,175,scale,COLORS.primary);centeredText(p,w,h,'PESAN & BAYAR',350,12,COLORS.accent);rect(p,w,h,430,475,340,10,COLORS.primary);return png(w,h,p);}
function ico(initial){const image=icon(64,initial);const head=Buffer.alloc(6);head.writeUInt16LE(0,0);head.writeUInt16LE(1,2);head.writeUInt16LE(1,4);const dir=Buffer.alloc(16);dir[0]=64;dir[1]=64;dir[2]=0;dir[3]=0;dir.writeUInt16LE(1,4);dir.writeUInt16LE(32,6);dir.writeUInt32LE(image.length,8);dir.writeUInt32LE(22,12);return Buffer.concat([head,dir,image]);}

export default async function handler(req,res){
  const cfg=await resolvePublicTenantConfig(req);
  if(!cfg.ok)return failTenantConfig(res,cfg.missing);
  const initial=String(cfg.businessName||'B').trim().toUpperCase().charAt(0)||'B';
  const kind=String(req.query?.kind||'').toLowerCase();
  let body,type,cache='public, max-age=86400, s-maxage=604800, stale-while-revalidate=86400';
  if(kind==='favicon'){body=ico(initial);type='image/x-icon';}
  else if(kind==='apple'){body=icon(180,initial);type='image/png';}
  else if(kind==='icon192'){body=icon(192,initial);type='image/png';}
  else if(kind==='icon512'){body=icon(512,initial);type='image/png';}
  else if(kind==='og'){body=og(cfg.businessName);type='image/png';}
  else {res.statusCode=404;res.setHeader('Content-Type','text/plain; charset=utf-8');return res.end('Not found');}
  res.statusCode=200;res.setHeader('Content-Type',type);res.setHeader('Cache-Control',cache);res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('X-Rohmat-Public-Brand-Asset','tenant-v2');res.end(body);
}
