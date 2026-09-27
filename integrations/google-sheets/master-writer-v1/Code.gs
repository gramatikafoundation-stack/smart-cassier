const SDB_WRITER = (function() {
  const props = PropertiesService.getScriptProperties();
  const dataEndpoint = String(props.getProperty('SDB_DATA_ENDPOINT') || '').trim();
  const tenantId = String(props.getProperty('SDB_TENANT_ID') || '').trim();
  let targets = {};
  try { targets = JSON.parse(props.getProperty('SDB_TARGETS_JSON') || '{}'); } catch (_) {}
  if (!/^https:\/\//.test(dataEndpoint)) throw new Error('missing_SDB_DATA_ENDPOINT');
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(tenantId)) throw new Error('missing_or_invalid_SDB_TENANT_ID');
  if (!targets || typeof targets !== 'object' || !Object.keys(targets).length) throw new Error('missing_SDB_TARGETS_JSON');
  return Object.freeze({
    VERSION: 5,
    ARCHIVE_VERSION: 2,
    TENANT_ID: tenantId,
    TZ: String(props.getProperty('SDB_TZ') || 'Asia/Jakarta').trim() || 'Asia/Jakarta',
    BUSINESS_NAME: String(props.getProperty('SDB_BUSINESS_NAME') || 'Business').trim() || 'Business',
    DATA_ENDPOINT: dataEndpoint,
    TARGETS: Object.freeze(targets),
    PII_RETENTION_DAYS: Math.max(1, Number(props.getProperty('SDB_PII_RETENTION_DAYS') || 365)),
    REQUIRED_TABS: Object.freeze([
      'Dashboard',
      'Data Pemesan',
      'Data Pesanan Makanan',
      'Data Pesanan Minuman',
      'Riwayat Pembayaran'
    ]),
    HEADERS: Object.freeze({
      'Data Pemesan': ['Tanggal Transaksi','Waktu Pesanan','Nama Pemesan','Layanan / Meja'],
      'Data Pesanan Makanan': ['Tanggal Pesanan','Nama Makanan','Harga Satuan'],
      'Data Pesanan Minuman': ['Tanggal Pesanan','Nama Minuman','Harga Satuan'],
      'Riwayat Pembayaran': ['Tanggal Transaksi','Total Pembayaran']
    })
  });
})();

function doGet() {
  return json_({
    ok: true,
    service: SDB_WRITER.BUSINESS_NAME + ' Google Writer',
    version: SDB_WRITER.VERSION,
    archive_version: SDB_WRITER.ARCHIVE_VERSION,
    mode: 'smart-cashier-annual-archive',
    tenant_id: SDB_WRITER.TENANT_ID,
    targets: Object.keys(SDB_WRITER.TARGETS).map(Number).sort()
  });
}

function doPost(e) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return json_({ok:false,error:'writer_busy'});
  try {
    const req = parseRequest_(e);
    if (req.schema_version !== 1 || !req.writer_token || !Array.isArray(req.events) || !req.events.length) {
      return json_({ok:false,error:'invalid_request'});
    }
    if (String(req.tenant_id || '') !== SDB_WRITER.TENANT_ID) {
      return json_({ok:false,error:'tenant_mismatch'});
    }

    const years = targetYears_(req.events);
    const result = [];
    for (const year of years) {
      const snapshot = fetchSnapshot_(year, req.writer_token);
      const rows = syncYear_(year, snapshot);
      result.push({
        year: year,
        spreadsheetId: SDB_WRITER.TARGETS[year],
        rows: rows,
        mode: 'archive-full'
      });
    }
    return json_({
      ok:true,
      version:2,
      writer_version:SDB_WRITER.VERSION,
      archive_version:SDB_WRITER.ARCHIVE_VERSION,
      tenant_id:SDB_WRITER.TENANT_ID,
      years:years,
      result:result
    });
  } catch (err) {
    const message = String(err && err.message ? err.message : err || 'sync_failed');
    const safe = /unauthorized/i.test(message) ? 'unauthorized' : 'sync_failed';
    console.error(message);
    return json_({ok:false,error:safe,detail:message.slice(0,500)});
  } finally {
    lock.releaseLock();
  }
}

function selfTest() {
  const report = [];
  Object.keys(SDB_WRITER.TARGETS).map(Number).sort().forEach(function(year) {
    const id = SDB_WRITER.TARGETS[year];
    const ss = SpreadsheetApp.openById(id);
    const names = ss.getSheets().map(function(s){ return s.getName(); });
    const missing = SDB_WRITER.REQUIRED_TABS.filter(function(n){ return names.indexOf(n) < 0; });
    if (missing.length) throw new Error('Workbook '+year+' missing tabs: '+missing.join(', '));
    Object.keys(SDB_WRITER.HEADERS).forEach(function(name) {
      const sh = ss.getSheetByName(name);
      const headerRow = findHeaderRow_(sh,SDB_WRITER.HEADERS[name]);
      if (headerRow !== 4) throw new Error('Workbook '+year+' header row mismatch '+name+':'+headerRow);
    });
    report.push(year + ': OK — ' + ss.getName());
  });
  report.unshift('TENANT: ' + SDB_WRITER.TENANT_ID + ' | WRITER v' + SDB_WRITER.VERSION + ' | archive v' + SDB_WRITER.ARCHIVE_VERSION);
  Logger.log(report.join('\n'));
  return report;
}

function parseRequest_(e) {
  if (!e || !e.postData || !e.postData.contents) throw new Error('invalid_request');
  try { return JSON.parse(e.postData.contents); }
  catch (_) { throw new Error('invalid_request'); }
}

function targetYears_(events) {
  const allYears = Object.keys(SDB_WRITER.TARGETS).map(Number).sort();
  if (events.some(function(ev){ return ev.target_year === null || ev.target_year === undefined || ev.target_year === ''; })) return allYears;
  const set = {};
  events.forEach(function(ev) {
    const y = Number(ev.target_year);
    if (!SDB_WRITER.TARGETS[y]) throw new Error('unconfigured_target_year:'+y);
    set[y] = true;
  });
  return Object.keys(set).map(Number).sort();
}

function fetchSnapshot_(year, writerToken) {
  const response = UrlFetchApp.fetch(
    SDB_WRITER.DATA_ENDPOINT + '?year=' + encodeURIComponent(year) + '&tenant=' + encodeURIComponent(SDB_WRITER.TENANT_ID),
    {
      method:'get',
      headers:{
        'x-rohmat-writer-token':writerToken,
        'x-sdb-tenant-id':SDB_WRITER.TENANT_ID
      },
      muteHttpExceptions:true,
      followRedirects:true
    }
  );
  const status = response.getResponseCode();
  let body = null;
  try { body = JSON.parse(response.getContentText()); } catch (_) {}
  if (status === 401 || (body && body.error === 'unauthorized')) throw new Error('unauthorized');
  if (status < 200 || status > 299 || !body || body.ok !== true || body.year !== year) {
    throw new Error('snapshot_failed:'+year+':'+status+':' + (body && body.error ? body.error : 'invalid_response'));
  }
  if (body.tenant_id !== SDB_WRITER.TENANT_ID) throw new Error('tenant_data_mismatch:'+year);
  if (body.spreadsheetId !== SDB_WRITER.TARGETS[year]) throw new Error('spreadsheet_target_mismatch:'+year);
  if (Number(body.archive_version) !== SDB_WRITER.ARCHIVE_VERSION) throw new Error('archive_version_mismatch:'+year);
  if (!body.archive_quality || body.archive_quality.complete !== true || Number(body.archive_quality.unclassified_items || 0) !== 0) {
    throw new Error('archive_quality_incomplete:'+year);
  }
  if (!body.archive_tabs || typeof body.archive_tabs !== 'object') throw new Error('archive_tabs_missing:'+year);
  return body;
}

function syncYear_(year, snapshot) {
  const ss = SpreadsheetApp.openById(SDB_WRITER.TARGETS[year]);
  try { ss.setSpreadsheetTimeZone(SDB_WRITER.TZ); } catch (_) {}
  const counts = {};
  Object.keys(SDB_WRITER.HEADERS).forEach(function(name) {
    const rows = snapshot.archive_tabs && Array.isArray(snapshot.archive_tabs[name])
      ? snapshot.archive_tabs[name] : [];
    writeTab_(ss,name,rows);
    counts[name]=rows.length;
  });
  SpreadsheetApp.flush();
  validateYear_(ss,snapshot,counts);
  enforcePiiRetentionForSpreadsheet_(ss,new Date(Date.now()-SDB_WRITER.PII_RETENTION_DAYS*86400000));
  return counts;
}

function writeTab_(ss,name,sourceRows) {
  const sh=ss.getSheetByName(name);
  if(!sh)throw new Error('missing_sheet:'+name);
  const headers=SDB_WRITER.HEADERS[name];
  const headerRow=findHeaderRow_(sh,headers);
  if(!headerRow)throw new Error('header_mismatch:'+name);
  const startRow=headerRow+1;
  const rows=sourceRows.map(function(r){return normalizeRow_(name,r)});
  const existingRows=Math.max(0,sh.getLastRow()-headerRow);
  const clearRows=Math.max(existingRows,rows.length);
  if(clearRows>0)sh.getRange(startRow,1,clearRows,headers.length).clearContent();
  if(rows.length>0){
    ensureRows_(sh,headerRow+rows.length);
    sh.getRange(startRow,1,rows.length,headers.length).setValues(rows);
    applyFormatsAt_(sh,name,startRow,rows.length);
  }
}

function findHeaderRow_(sh,headers) {
  if(!sh)return 0;
  const scanRows=Math.min(10,Math.max(1,sh.getMaxRows()));
  const scan=sh.getRange(1,1,scanRows,headers.length).getDisplayValues();
  for(let r=0;r<scan.length;r++){
    let ok=true;
    for(let c=0;c<headers.length;c++){
      if(String(scan[r][c]||'').trim()!==headers[c]){ok=false;break}
    }
    if(ok)return r+1;
  }
  return 0;
}

function normalizeRow_(name,input) {
  const r=input.slice();
  if(name==='Data Pemesan'){
    r[0]=dateSerial_(r[0]);
    r[1]=timeFraction_(r[1]);
  }else if(name==='Data Pesanan Makanan'||name==='Data Pesanan Minuman'){
    r[0]=dateSerial_(r[0]);
    r[2]=Math.max(0,Number(r[2]||0));
  }else if(name==='Riwayat Pembayaran'){
    r[0]=dateSerial_(r[0]);
    r[1]=Math.max(0,Number(r[1]||0));
  }
  return r;
}

function dateSerial_(v) {
  const s=String(v||'');
  if(!s)return '';
  const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if(!m)return v;
  return (Date.UTC(Number(m[1]),Number(m[2])-1,Number(m[3]))-Date.UTC(1899,11,30))/86400000;
}

function timeFraction_(v) {
  const s=String(v||'');
  if(!s)return '';
  const m=/^(\d{2}):(\d{2}):(\d{2})$/.exec(s);
  if(!m)return v;
  return (Number(m[1])*3600+Number(m[2])*60+Number(m[3]))/86400;
}

function ensureRows_(sh,neededLastRow) {
  const max=sh.getMaxRows();
  if(max<neededLastRow)sh.insertRowsAfter(max,neededLastRow-max);
}

function applyFormatsAt_(sh,name,startRow,rowCount) {
  if(rowCount<=0)return;
  sh.getRange(startRow,1,rowCount,1).setNumberFormat('dd/mm/yyyy');
  if(name==='Data Pemesan'){
    sh.getRange(startRow,2,rowCount,1).setNumberFormat('hh:mm:ss');
  }else if(name==='Data Pesanan Makanan'||name==='Data Pesanan Minuman'){
    sh.getRange(startRow,3,rowCount,1).setNumberFormat('"Rp" #,##0');
  }else if(name==='Riwayat Pembayaran'){
    sh.getRange(startRow,2,rowCount,1).setNumberFormat('"Rp" #,##0');
  }
}

function validateYear_(ss,snapshot,counts) {
  Object.keys(SDB_WRITER.HEADERS).forEach(function(name){
    const expected=snapshot.archive_tabs[name].length;
    if(counts[name]!==expected)throw new Error('row_count_mismatch:'+name);
  });
  const m=snapshot.archive_metrics||{};
  if(counts['Data Pemesan']!==Number(m.transactions||0))throw new Error('transaction_count_mismatch');
  if(counts['Data Pesanan Makanan']!==Number(m.food_units||0))throw new Error('food_unit_count_mismatch');
  if(counts['Data Pesanan Minuman']!==Number(m.drink_units||0))throw new Error('drink_unit_count_mismatch');
  const total=Number((snapshot.archive_tabs['Riwayat Pembayaran']||[]).reduce(function(sum,row){return sum+Number(row[1]||0)},0));
  if(Math.abs(total-Number(m.total_paid||0))>0.001)throw new Error('payment_total_mismatch');
}

function enforcePiiRetention() {
  const lock=LockService.getScriptLock();
  if(!lock.tryLock(5000))return {ok:false,error:'writer_busy'};
  try{
    const cutoff=new Date(Date.now()-SDB_WRITER.PII_RETENTION_DAYS*86400000);
    const results=[];
    Object.keys(SDB_WRITER.TARGETS).sort().forEach(function(year){
      const ss=SpreadsheetApp.openById(SDB_WRITER.TARGETS[year]);
      results.push({year:Number(year),spreadsheetId:SDB_WRITER.TARGETS[year],retention:enforcePiiRetentionForSpreadsheet_(ss,cutoff)});
    });
    const out={ok:true,retention_days:SDB_WRITER.PII_RETENTION_DAYS,cutoff:cutoff.toISOString(),results:results};
    console.log(JSON.stringify(out));
    return out;
  }finally{lock.releaseLock()}
}

function enforcePiiRetentionForSpreadsheet_(ss,cutoff) {
  const sh=ss.getSheetByName('Data Pemesan');
  if(!sh)throw new Error('missing_sheet:Data Pemesan');
  const headerRow=findHeaderRow_(sh,SDB_WRITER.HEADERS['Data Pemesan']);
  if(!headerRow)throw new Error('retention_header_invalid:Data Pemesan');
  const startRow=headerRow+1;
  const lastRow=sh.getLastRow();
  if(lastRow<startRow)return {expired_rows:0,cleared_ranges:0};
  const dates=sh.getRange(startRow,1,lastRow-startRow+1,1).getValues();
  const expired=[];
  dates.forEach(function(row,i){
    const ms=retentionDateMillis_(row[0]);
    if(ms!==null&&ms<cutoff.getTime())expired.push(startRow+i);
  });
  let cleared=0;
  contiguousRuns_(expired).forEach(function(run){
    sh.getRange(run.start,3,run.end-run.start+1,1).clearContent();
    cleared++;
  });
  SpreadsheetApp.flush();
  return {expired_rows:expired.length,cleared_ranges:cleared};
}

function retentionDateMillis_(value) {
  if(Object.prototype.toString.call(value)==='[object Date]'&&!isNaN(value.getTime()))return value.getTime();
  if(typeof value==='number'&&isFinite(value))return Date.UTC(1899,11,30)+value*86400000;
  const s=String(value||'').trim();
  let m=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(s);
  if(m)return Date.UTC(Number(m[3]),Number(m[2])-1,Number(m[1]));
  m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if(m)return Date.UTC(Number(m[1]),Number(m[2])-1,Number(m[3]));
  return null;
}

function contiguousRuns_(rows) {
  if(!rows.length)return [];
  const out=[];
  let start=rows[0],end=rows[0];
  for(let i=1;i<rows.length;i++){
    if(rows[i]===end+1){end=rows[i];continue}
    out.push({start:start,end:end});
    start=end=rows[i];
  }
  out.push({start:start,end:end});
  return out;
}

function installPiiRetentionTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(function(t){return t.getHandlerFunction()==='enforcePiiRetention'})
    .forEach(function(t){ScriptApp.deleteTrigger(t)});
  ScriptApp.newTrigger('enforcePiiRetention').timeBased().everyDays(1).atHour(3).create();
  return {ok:true,handler:'enforcePiiRetention',cadence:'daily',retention_days:SDB_WRITER.PII_RETENTION_DAYS};
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
