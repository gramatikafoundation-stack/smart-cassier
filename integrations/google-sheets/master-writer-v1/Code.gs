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
    VERSION: 4,
    TENANT_ID: tenantId,
    TZ: String(props.getProperty('SDB_TZ') || 'Asia/Jakarta').trim() || 'Asia/Jakarta',
    BUSINESS_NAME: String(props.getProperty('SDB_BUSINESS_NAME') || 'Business').trim() || 'Business',
    DATA_ENDPOINT: dataEndpoint,
    TARGETS: Object.freeze(targets),
    PII_RETENTION_DAYS: Math.max(1, Number(props.getProperty('SDB_PII_RETENTION_DAYS') || 365)),
    HEADERS: Object.freeze({
      'PEMESAN': ['ID Pesanan','Kode Pesanan','Tanggal Pesan','Waktu Pesan','Nama Pemesan','No. WhatsApp','Sumber Pesanan','Layanan','Nomor Meja','Pesanan','Jumlah Item','Total Belanja'],
      'PESANAN': ['ID Pesanan','Kode Pesanan','Tanggal','Waktu','Sumber','Layanan','Nomor Meja','Daftar Menu','Jumlah Item','Total','Metode Bayar','Status Bayar','Status Pesanan','Waktu Pesanan Baru','Waktu Diproses','Waktu Selesai','Catatan Konsumen','Petugas Kasir'],
      'MENU & STOK': ['ID Menu','Nama Menu','Kategori','Harga','Item Terjual Tahun Ini','Omzet Menu Tahun Ini','Status Ketersediaan','Tampil di Publik','Catatan Ketersediaan','Terakhir Diperbarui','URL Foto'],
      'KEUANGAN': ['ID Pesanan','Kode Pesanan','Tanggal','Waktu','Sumber','Metode Bayar','Total Tagihan','Uang Diterima','Kembalian','Uang Masuk','Status Pembayaran','Petugas','Layanan','Nomor Meja','Bukti Pembayaran','Waktu Verifikasi']
    })
  });
})();

function doGet() {
  return json_({
    ok: true,
    service: SDB_WRITER.BUSINESS_NAME + ' Google Writer',
    version: SDB_WRITER.VERSION,
    mode: 'event-driven-delta',
    tenant_id: SDB_WRITER.TENANT_ID,
    targets: Object.keys(SDB_WRITER.TARGETS).map(Number)
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
      const events = eventsForYear_(req.events, year);
      let rows;
      let mode;
      if (req.force_full === true || requiresFull_(events)) {
        const snapshot = fetchSnapshot_(year, req.writer_token);
        rows = syncYear_(year, snapshot);
        mode = 'full';
      } else {
        try {
          rows = syncDeltaYear_(year, events, req.writer_token);
          mode = 'delta';
        } catch (deltaErr) {
          console.warn('delta_fallback:'+year+':' + String(deltaErr && deltaErr.message ? deltaErr.message : deltaErr));
          const snapshot = fetchSnapshot_(year, req.writer_token);
          rows = syncYear_(year, snapshot);
          mode = 'full-fallback';
        }
      }
      result.push({year: year, spreadsheetId: SDB_WRITER.TARGETS[year], rows: rows, mode: mode});
    }
    return json_({ok:true,version:2,writer_version:SDB_WRITER.VERSION,tenant_id:SDB_WRITER.TENANT_ID,years:years,result:result});
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
    const missing = ['DASHBOARD','PEMESAN','PESANAN','MENU & STOK','KEUANGAN'].filter(function(n){ return names.indexOf(n) < 0; });
    if (missing.length) throw new Error('Workbook '+year+' missing tabs: '+missing.join(', '));
    report.push(year + ': OK — ' + ss.getName());
  });
  report.unshift('TENANT: ' + SDB_WRITER.TENANT_ID + ' | WRITER v' + SDB_WRITER.VERSION);
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
function eventsForYear_(events, year) {
  const picked = events.filter(function(ev) {
    return ev.target_year === null || ev.target_year === undefined || ev.target_year === '' || Number(ev.target_year) === year;
  });
  const byEntity = {};
  picked.forEach(function(ev) {
    byEntity[String(ev.entity_type||'') + ':' + String(ev.entity_id||'')] = ev;
  });
  return Object.keys(byEntity).map(function(k){ return byEntity[k]; });
}
function requiresFull_(events) {
  return events.some(function(ev) {
    const type = String(ev.entity_type || '').toLowerCase();
    const op = String(ev.operation || '').toUpperCase();
    return op === 'RECONCILE' || ['order','menu'].indexOf(type) < 0;
  });
}
function fetchSnapshot_(year, writerToken) {
  const response = UrlFetchApp.fetch(SDB_WRITER.DATA_ENDPOINT + '?year=' + encodeURIComponent(year) + '&tenant=' + encodeURIComponent(SDB_WRITER.TENANT_ID), {
    method: 'get',
    headers: {'x-rohmat-writer-token': writerToken, 'x-sdb-tenant-id': SDB_WRITER.TENANT_ID},
    muteHttpExceptions: true,
    followRedirects: true
  });
  const status = response.getResponseCode();
  let body = null;
  try { body = JSON.parse(response.getContentText()); } catch (_) {}
  if (status === 401 || (body && body.error === 'unauthorized')) throw new Error('unauthorized');
  if (status < 200 || status > 299 || !body || body.ok !== true || body.year !== year) {
    throw new Error('snapshot_failed:'+year+':'+status+':' + (body && body.error ? body.error : 'invalid_response'));
  }
  if (body.tenant_id !== SDB_WRITER.TENANT_ID) throw new Error('tenant_data_mismatch:'+year);
  if (body.spreadsheetId !== SDB_WRITER.TARGETS[year]) throw new Error('spreadsheet_target_mismatch:'+year);
  return body;
}
function fetchDeltas_(year, events, writerToken) {
  const requests = events.map(function(ev) {
    const url = SDB_WRITER.DATA_ENDPOINT
      + '?year=' + encodeURIComponent(year)
      + '&tenant=' + encodeURIComponent(SDB_WRITER.TENANT_ID)
      + '&mode=delta'
      + '&entity_type=' + encodeURIComponent(String(ev.entity_type || ''))
      + '&entity_id=' + encodeURIComponent(String(ev.entity_id || ''))
      + '&operation=' + encodeURIComponent(String(ev.operation || ''));
    return {
      url: url,
      method: 'get',
      headers: {'x-rohmat-writer-token': writerToken, 'x-sdb-tenant-id': SDB_WRITER.TENANT_ID},
      muteHttpExceptions: true,
      followRedirects: true
    };
  });
  const responses = UrlFetchApp.fetchAll(requests);
  return responses.map(function(response, i) {
    const status = response.getResponseCode();
    let body = null;
    try { body = JSON.parse(response.getContentText()); } catch (_) {}
    if (status === 401 || (body && body.error === 'unauthorized')) throw new Error('unauthorized');
    if (status < 200 || status > 299 || !body || body.ok !== true || body.mode !== 'delta' || body.version !== 3 || body.year !== year) {
      throw new Error('delta_fetch_failed:'+year+':'+status+':' + (body && body.error ? body.error : 'invalid_response'));
    }
    if (body.tenant_id !== SDB_WRITER.TENANT_ID) throw new Error('tenant_data_mismatch:'+year);
    if (body.spreadsheetId !== SDB_WRITER.TARGETS[year]) throw new Error('spreadsheet_target_mismatch:'+year);
    if (String(body.entity_type) !== String(events[i].entity_type) || String(body.entity_id) !== String(events[i].entity_id)) {
      throw new Error('delta_identity_mismatch:'+year);
    }
    return body;
  });
}
function syncDeltaYear_(year, events, writerToken) {
  if (!events.length) throw new Error('delta_events_empty');
  const ss = SpreadsheetApp.openById(SDB_WRITER.TARGETS[year]);
  try { ss.setSpreadsheetTimeZone(SDB_WRITER.TZ); } catch (_) {}
  const deltas = fetchDeltas_(year, events, writerToken);
  let menuRows = null;
  deltas.forEach(function(delta) {
    if (delta.entity_type === 'order') {
      if (delta.deleted) {
        ['PEMESAN','PESANAN','KEUANGAN'].forEach(function(name){ clearId_(ss, name, delta.entity_id); });
      } else {
        ['PEMESAN','PESANAN','KEUANGAN'].forEach(function(name) {
          const row = delta.rows && delta.rows[name];
          if (!Array.isArray(row)) throw new Error('delta_row_missing:'+name);
          upsertRow_(ss, name, delta.entity_id, row);
        });
      }
    }
    if (delta.rows && Array.isArray(delta.rows['MENU & STOK'])) menuRows = delta.rows['MENU & STOK'];
  });
  if (menuRows !== null) writeTab_(ss, 'MENU & STOK', menuRows);
  updateDashboardStatus_(ss);
  SpreadsheetApp.flush();
  const counts = countRows_(ss);
  validateDeltaCounts_(ss, counts);
  return counts;
}
function syncYear_(year, snapshot) {
  const ss = SpreadsheetApp.openById(SDB_WRITER.TARGETS[year]);
  try { ss.setSpreadsheetTimeZone(SDB_WRITER.TZ); } catch (_) {}
  const counts = {};
  ['PEMESAN','PESANAN','MENU & STOK','KEUANGAN'].forEach(function(name) {
    const rows = snapshot.tabs && Array.isArray(snapshot.tabs[name]) ? snapshot.tabs[name] : [];
    writeTab_(ss, name, rows);
    counts[name] = rows.length;
  });
  updateDashboardStatus_(ss);
  SpreadsheetApp.flush();
  validateYear_(ss, snapshot, counts);
  enforcePiiRetentionForSpreadsheet_(ss, new Date(Date.now() - SDB_WRITER.PII_RETENTION_DAYS * 86400000));
  return counts;
}
function writeTab_(ss, name, sourceRows) {
  const sh = ss.getSheetByName(name);
  if (!sh) throw new Error('missing_sheet:'+name);
  const headers = SDB_WRITER.HEADERS[name];
  const headerRow = findHeaderRow_(sh, headers);
  if (!headerRow) throw new Error('header_mismatch:'+name);
  const rows = sourceRows.map(function(r){ return normalizeRow_(name, r); });
  const existingRows = Math.max(0, sh.getLastRow() - 7);
  const clearRows = Math.max(existingRows, rows.length);
  if (clearRows > 0) sh.getRange(8,1,clearRows,headers.length).clearContent();
  if (rows.length > 0) {
    ensureRows_(sh, 7 + rows.length);
    sh.getRange(8,1,rows.length,headers.length).setValues(rows);
    applyFormatsAt_(sh, name, 8, rows.length);
  }
}
function upsertRow_(ss, name, id, sourceRow) {
  const sh = ss.getSheetByName(name);
  if (!sh) throw new Error('missing_sheet:'+name);
  const headers = SDB_WRITER.HEADERS[name];
  if (!findHeaderRow_(sh, headers)) throw new Error('header_mismatch:'+name);
  const found = findIdCell_(sh, id);
  const row = found ? found.getRow() : Math.max(8, sh.getLastRow() + 1);
  ensureRows_(sh, row);
  sh.getRange(row,1,1,headers.length).setValues([normalizeRow_(name, sourceRow)]);
  if (!found) applyFormatsAt_(sh, name, row, 1);
}
function clearId_(ss, name, id) {
  const sh = ss.getSheetByName(name);
  if (!sh) throw new Error('missing_sheet:'+name);
  const found = findIdCell_(sh, id);
  if (found) sh.getRange(found.getRow(),1,1,SDB_WRITER.HEADERS[name].length).clearContent();
}
function findIdCell_(sh, id) {
  const last = Math.max(8, sh.getLastRow());
  const rows = Math.max(1, last - 7);
  return sh.getRange(8,1,rows,1).createTextFinder(String(id)).matchEntireCell(true).findNext();
}
function countRows_(ss) {
  const counts = {};
  ['PEMESAN','PESANAN','MENU & STOK','KEUANGAN'].forEach(function(name) {
    const sh = ss.getSheetByName(name);
    if (!sh) throw new Error('missing_sheet:'+name);
    const last = sh.getLastRow();
    if (last < 8) { counts[name] = 0; return; }
    counts[name] = sh.getRange(8,1,last-7,1).getDisplayValues().filter(function(r){ return String(r[0] || '').trim() !== ''; }).length;
  });
  return counts;
}
function validateDeltaCounts_(ss, counts) {
  if (counts.PEMESAN !== counts.PESANAN || counts.PESANAN !== counts.KEUANGAN) throw new Error('delta_order_count_mismatch');
  const pem = ss.getSheetByName('PEMESAN');
  if (counts.PEMESAN > 0) {
    const last = Math.max(8, pem.getLastRow());
    const ids = pem.getRange(8,1,last-7,1).getDisplayValues().flat().filter(String);
    if (new Set(ids).size !== ids.length) throw new Error('duplicate_order_id');
  }
}
function findHeaderRow_(sh, headers) {
  const scan = sh.getRange(1,1,7,headers.length).getDisplayValues();
  for (let r=0;r<scan.length;r++) {
    let ok = true;
    for (let c=0;c<headers.length;c++) {
      if (String(scan[r][c] || '').trim() !== headers[c]) { ok = false; break; }
    }
    if (ok) return r + 1;
  }
  return 0;
}
function normalizeRow_(name, input) {
  const r = input.slice();
  if (name === 'PEMESAN') {
    r[2] = dateSerial_(r[2]); r[3] = timeFraction_(r[3]);
  } else if (name === 'PESANAN') {
    r[2] = dateSerial_(r[2]); r[3] = timeFraction_(r[3]);
    r[13] = timeFraction_(r[13]); r[14] = timeFraction_(r[14]); r[15] = timeFraction_(r[15]);
  } else if (name === 'MENU & STOK') {
    r[9] = localStamp_(r[9]);
  } else if (name === 'KEUANGAN') {
    r[2] = dateSerial_(r[2]); r[3] = timeFraction_(r[3]);
  }
  return r;
}
function dateSerial_(v) {
  const s = String(v || '');
  if (!s) return '';
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return v;
  return (Date.UTC(Number(m[1]),Number(m[2])-1,Number(m[3])) - Date.UTC(1899,11,30)) / 86400000;
}
function timeFraction_(v) {
  const s = String(v || '');
  if (!s) return '';
  const m = /^(\d{2}):(\d{2}):(\d{2})$/.exec(s);
  if (!m) return v;
  return (Number(m[1])*3600 + Number(m[2])*60 + Number(m[3])) / 86400;
}
function localStamp_(v) {
  const s = String(v || '');
  const m = /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}:\d{2}:\d{2})$/.exec(s);
  return m ? (m[3]+'/'+m[2]+'/'+m[1]+' '+m[4]+' WIB') : s;
}
function ensureRows_(sh, neededLastRow) {
  const max = sh.getMaxRows();
  if (max < neededLastRow) sh.insertRowsAfter(max, neededLastRow - max);
}
function applyFormatsAt_(sh, name, startRow, rowCount) {
  if (rowCount <= 0) return;
  if (name === 'PEMESAN') {
    sh.getRange(startRow,3,rowCount,1).setNumberFormat('dd/mm/yyyy');
    sh.getRange(startRow,4,rowCount,1).setNumberFormat('hh:mm:ss');
    sh.getRange(startRow,12,rowCount,1).setNumberFormat('"Rp" #,##0');
  } else if (name === 'PESANAN') {
    sh.getRange(startRow,3,rowCount,1).setNumberFormat('dd/mm/yyyy');
    sh.getRange(startRow,4,rowCount,1).setNumberFormat('hh:mm:ss');
    sh.getRange(startRow,10,rowCount,1).setNumberFormat('"Rp" #,##0');
    sh.getRange(startRow,14,rowCount,3).setNumberFormat('hh:mm:ss');
  } else if (name === 'MENU & STOK') {
    sh.getRange(startRow,4,rowCount,1).setNumberFormat('"Rp" #,##0');
    sh.getRange(startRow,5,rowCount,1).setNumberFormat('0');
    sh.getRange(startRow,6,rowCount,1).setNumberFormat('"Rp" #,##0');
  } else if (name === 'KEUANGAN') {
    sh.getRange(startRow,3,rowCount,1).setNumberFormat('dd/mm/yyyy');
    sh.getRange(startRow,4,rowCount,1).setNumberFormat('hh:mm:ss');
    sh.getRange(startRow,7,rowCount,4).setNumberFormat('"Rp" #,##0');
  }
}
function updateDashboardStatus_(ss) {
  const sh = ss.getSheetByName('DASHBOARD');
  if (!sh) throw new Error('missing_sheet:DASHBOARD');
  const now = Utilities.formatDate(new Date(), SDB_WRITER.TZ, 'dd/MM/yyyy HH:mm:ss');
  sh.getRange('M7:M9').setValues([
    ['Sinkron event-driven • otomatis delta'],
    ['Sumber utama: Supabase • event-driven'],
    ['Aktif • ' + now + ' WIB']
  ]);
  sh.getRange('I17').setValue('Supabase → Google Sheets • delta event-driven + full reconciliation failsafe');
}
function validateYear_(ss, snapshot, counts) {
  ['PEMESAN','PESANAN','MENU & STOK','KEUANGAN'].forEach(function(name) {
    if (counts[name] !== snapshot.tabs[name].length) throw new Error('row_count_mismatch:'+name);
  });
  const expectedOrders = Number(snapshot.metrics && snapshot.metrics.orders || 0);
  if (counts.PEMESAN !== expectedOrders || counts.PESANAN !== expectedOrders || counts.KEUANGAN !== expectedOrders) {
    throw new Error('order_count_mismatch');
  }
  const pem = ss.getSheetByName('PEMESAN');
  if (expectedOrders > 0) {
    const ids = pem.getRange(8,1,expectedOrders,1).getDisplayValues().flat().filter(String);
    if (new Set(ids).size !== expectedOrders) throw new Error('duplicate_order_id');
  }
}
function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/**
 * Privacy retention contract for reporting mirrors.
 * Preserves transaction rows and financial facts; clears only PII cells after retention expiry.
 */
function enforcePiiRetention() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return {ok:false,error:'writer_busy'};
  try {
    const cutoff = new Date(Date.now() - SDB_WRITER.PII_RETENTION_DAYS * 86400000);
    const results = [];
    Object.keys(SDB_WRITER.TARGETS).sort().forEach(function(year) {
      const ss = SpreadsheetApp.openById(SDB_WRITER.TARGETS[year]);
      try { ss.setSpreadsheetTimeZone(SDB_WRITER.TZ); } catch (_) {}
      results.push({
        year: Number(year),
        spreadsheetId: SDB_WRITER.TARGETS[year],
        retention: enforcePiiRetentionForSpreadsheet_(ss, cutoff)
      });
    });
    const out = {ok:true,retention_days:SDB_WRITER.PII_RETENTION_DAYS,cutoff:cutoff.toISOString(),results:results};
    console.log(JSON.stringify(out));
    return out;
  } finally {
    lock.releaseLock();
  }
}

function enforcePiiRetentionForSpreadsheet_(ss, cutoff) {
  const specs = [
    {name:'PEMESAN', dateCol:3, clearCols:[[5,6]]},
    {name:'PESANAN', dateCol:3, clearCols:[[17,18]]},
    {name:'KEUANGAN', dateCol:3, clearCols:[[12,12],[15,15]]}
  ];
  const summary = {};
  specs.forEach(function(spec) {
    const sh = ss.getSheetByName(spec.name);
    if (!sh) throw new Error('missing_sheet:'+spec.name);
    const headerRow = findHeaderRow_(sh, SDB_WRITER.HEADERS[spec.name]);
    if (!headerRow || headerRow > 7) throw new Error('retention_header_invalid:'+spec.name);
    const startRow = 8;
    const lastRow = sh.getLastRow();
    if (lastRow < startRow) {
      summary[spec.name] = {expired_rows:0,cleared_ranges:0};
      return;
    }
    const dates = sh.getRange(startRow, spec.dateCol, lastRow-startRow+1, 1).getValues();
    const expiredRows = [];
    dates.forEach(function(row, i) {
      const ms = retentionDateMillis_(row[0]);
      if (ms !== null && ms < cutoff.getTime()) expiredRows.push(startRow+i);
    });
    let clearedRanges = 0;
    contiguousRuns_(expiredRows).forEach(function(run) {
      spec.clearCols.forEach(function(cols) {
        sh.getRange(run.start, cols[0], run.end-run.start+1, cols[1]-cols[0]+1).clearContent();
        clearedRanges++;
      });
    });
    summary[spec.name] = {expired_rows:expiredRows.length,cleared_ranges:clearedRanges};
  });
  SpreadsheetApp.flush();
  return summary;
}

function retentionDateMillis_(value) {
  if (Object.prototype.toString.call(value) === '[object Date]' && !isNaN(value.getTime())) return value.getTime();
  if (typeof value === 'number' && isFinite(value)) return Date.UTC(1899,11,30) + value * 86400000;
  const s = String(value || '').trim();
  let m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(s);
  if (m) return Date.UTC(Number(m[3]),Number(m[2])-1,Number(m[1]));
  m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (m) return Date.UTC(Number(m[1]),Number(m[2])-1,Number(m[3]));
  return null;
}

function contiguousRuns_(rows) {
  if (!rows.length) return [];
  const out = [];
  let start = rows[0], end = rows[0];
  for (let i=1;i<rows.length;i++) {
    if (rows[i] === end + 1) { end = rows[i]; continue; }
    out.push({start:start,end:end});
    start = end = rows[i];
  }
  out.push({start:start,end:end});
  return out;
}

function installPiiRetentionTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(function(t){ return t.getHandlerFunction() === 'enforcePiiRetention'; })
    .forEach(function(t){ ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('enforcePiiRetention').timeBased().everyDays(1).atHour(3).create();
  return {ok:true,handler:'enforcePiiRetention',cadence:'daily',retention_days:SDB_WRITER.PII_RETENTION_DAYS};
}
