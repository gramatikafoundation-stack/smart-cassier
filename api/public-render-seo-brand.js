import baseHandler from '../apps/public/api/render-seo-brand.js';

// Tenant-scoped presentation parity: do not disclose payment verification
// rules to public customers. Other tenants keep the Golden Master response.
const KEDAI_TENANT_ID = 'f90dba28-021b-4bb4-bc4d-1e50f70c7809';
const EXPOSED_INTERNAL_NOTE = /<div class="kt-qris-note" role="status">[\s\S]*?<\/div>/g;

export default async function handler(req, res) {
  if (String(process.env.SDB_TENANT_ID || '').trim().toLowerCase() !== KEDAI_TENANT_ID) {
    return baseHandler(req, res);
  }
  const end = res.end.bind(res);
  res.end = (payload, ...args) => {
    if (res.statusCode === 200 && typeof payload === 'string') {
      payload = payload.replace(EXPOSED_INTERNAL_NOTE, '')
        .replaceAll('table<=20', 'table<=6')
        .replaceAll('n<=20', 'n<=6')
        .replace('Array.from({length:20}', 'Array.from({length:6}');
    }
    return end(payload, ...args);
  };
  return baseHandler(req, res);
}
