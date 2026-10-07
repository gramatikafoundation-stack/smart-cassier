import baseHandler from '../lib/render-lifecycle.js';
import runtimeHandler from '../lib/runtime-lifecycle.js';
import { resolvePublicTenantConfig, failTenantConfig, escapeHtml } from '../lib/tenant-config.js';
import { FUTURE_PUBLIC_UI_PATCH, MOBILE_CHECKOUT_SCROLL_PATCH } from './render.js';

const MARKER = 'rohmat-seo-brand-v2';

function safeJson(value) {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}

function replaceMeta(html, selector, value) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`<meta\\s+([^>]*${escaped}[^>]*)>`, 'i');
  if (!re.test(html)) return html;
  return html.replace(re, (tag) => {
    if (/content="[^"]*"/i.test(tag)) return tag.replace(/content="[^"]*"/i, `content="${value}"`);
    return tag.replace(/>$/, ` content="${value}">`);
  });
}

function rewriteCanonicalOrigin(html, cfg) {
  const canonicalMatch = html.match(/<link\s+[^>]*rel=["']canonical["'][^>]*href=["']([^"']+)["'][^>]*>/i)
    || html.match(/<link\s+[^>]*href=["']([^"']+)["'][^>]*rel=["']canonical["'][^>]*>/i);
  let oldOrigin = '';
  if (canonicalMatch?.[1]) {
    try { oldOrigin = new URL(canonicalMatch[1]).origin; } catch {}
  }
  if (oldOrigin && oldOrigin !== cfg.origin) html = html.split(oldOrigin).join(cfg.origin);
  html = html.replace(
    /<link\s+([^>]*rel=["']canonical["'][^>]*)>/i,
    (tag) => /href=["'][^"']*["']/i.test(tag)
      ? tag.replace(/href=["'][^"']*["']/i, `href="${cfg.canonical}"`)
      : tag.replace(/>$/, ` href="${cfg.canonical}">`)
  );
  return html;
}

function normalizeExistingMetadata(html, cfg) {
  html = replaceMeta(html, 'name="description"', cfg.description);
  html = replaceMeta(html, 'name="robots"', 'index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1');
  html = replaceMeta(html, 'property="og:title"', cfg.title);
  html = replaceMeta(html, 'property="og:description"', cfg.description);
  html = replaceMeta(html, 'property="og:type"', 'website');
  html = replaceMeta(html, 'name="theme-color"', '#ff5a24');
  return html;
}

function injectSeoBrand(input, cfg) {
  let html = rewriteCanonicalOrigin(normalizeExistingMetadata(input, cfg), cfg);
  const nonce = html.match(/<script\s+nonce="([^"]+)"/)?.[1] || html.match(/<style\s+nonce="([^"]+)"/)?.[1] || '';
  if (!html.includes('smart-order-public-foodcode-v1')) {
    const uiPatch = FUTURE_PUBLIC_UI_PATCH.replace('<style ', '<style' + (nonce ? ' nonce="' + nonce + '"' : '') + ' ');
    const bodyAt = html.lastIndexOf('</body>');
    html = bodyAt >= 0 ? html.slice(0, bodyAt) + uiPatch + html.slice(bodyAt) : html + uiPatch;
  }
  if (!html.includes('smart-order-mobile-checkout-scroll-v2')) {
    let scrollPatch = MOBILE_CHECKOUT_SCROLL_PATCH;
    if (nonce) {
      scrollPatch = scrollPatch
        .replace('<style ', '<style nonce="' + nonce + '" ')
        .replace('<script ', '<script nonce="' + nonce + '" ');
    }
    const bodyAt = html.lastIndexOf('</body>');
    html = bodyAt >= 0 ? html.slice(0, bodyAt) + scrollPatch + html.slice(bodyAt) : html + scrollPatch;
  }
  if (html.includes(MARKER)) return html;
  const graph = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'ImageObject',
        '@id': `${cfg.canonical}#socialimage`,
        url: cfg.socialImage,
        contentUrl: cfg.socialImage,
        width: 1200,
        height: 630,
        caption: cfg.businessName
      },
      {
        '@type': 'Restaurant',
        '@id': `${cfg.canonical}#restaurant`,
        name: cfg.businessName,
        url: cfg.canonical,
        image: { '@id': `${cfg.canonical}#socialimage` },
        servesCuisine: cfg.cuisine,
        hasMenu: cfg.canonical,
        potentialAction: {
          '@type': 'OrderAction',
          target: {
            '@type': 'EntryPoint',
            urlTemplate: cfg.canonical,
            actionPlatform: [
              'https://schema.org/DesktopWebPlatform',
              'https://schema.org/MobileWebPlatform'
            ]
          }
        }
      },
      {
        '@type': 'WebSite',
        '@id': `${cfg.canonical}#website`,
        url: cfg.canonical,
        name: cfg.businessName,
        publisher: { '@id': `${cfg.canonical}#restaurant` },
        inLanguage: cfg.locale
      },
      {
        '@type': 'WebPage',
        '@id': `${cfg.canonical}#webpage`,
        url: cfg.canonical,
        name: cfg.title,
        description: cfg.description,
        isPartOf: { '@id': `${cfg.canonical}#website` },
        about: { '@id': `${cfg.canonical}#restaurant` },
        primaryEntity: { '@id': `${cfg.canonical}#restaurant` },
        primaryImageOfPage: { '@id': `${cfg.canonical}#socialimage` },
        inLanguage: cfg.locale
      }
    ]
  };

  const metadata = [
    `<!-- ${MARKER} -->`,
    `<meta name="application-name" content="${escapeHtml(cfg.businessName)}">`,
    `<meta name="apple-mobile-web-app-title" content="${escapeHtml(cfg.businessName)}">`,
    '<meta name="apple-mobile-web-app-capable" content="yes">',
    '<meta name="apple-mobile-web-app-status-bar-style" content="default">',
    '<meta name="mobile-web-app-capable" content="yes">',
    '<meta name="format-detection" content="telephone=no">',
    '<meta name="googlebot" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">',
    '<meta name="bingbot" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">',
    `<meta property="og:url" content="${cfg.canonical}">`,
    `<meta property="og:site_name" content="${escapeHtml(cfg.businessName)}">`,
    `<meta property="og:locale" content="${escapeHtml(cfg.ogLocale)}">`,
    `<meta property="og:image" content="${cfg.socialImage}">`,
    `<meta property="og:image:secure_url" content="${cfg.socialImage}">`,
    '<meta property="og:image:type" content="image/png">',
    '<meta property="og:image:width" content="1200">',
    '<meta property="og:image:height" content="630">',
    `<meta property="og:image:alt" content="${escapeHtml(cfg.title)}">`,
    '<meta name="twitter:card" content="summary_large_image">',
    `<meta name="twitter:title" content="${escapeHtml(cfg.title)}">`,
    `<meta name="twitter:description" content="${escapeHtml(cfg.description)}">`,
    `<meta name="twitter:image" content="${cfg.socialImage}">`,
    `<meta name="twitter:image:alt" content="${escapeHtml(cfg.title)}">`,
    `<link rel="alternate" hreflang="${escapeHtml(cfg.locale)}" href="${cfg.canonical}">`,
    `<link rel="alternate" hreflang="x-default" href="${cfg.canonical}">`,
    '<link rel="icon" href="/favicon.ico" sizes="any">',
    '<link rel="icon" type="image/png" sizes="192x192" href="/icon-192.png">',
    '<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">',
    '<link rel="manifest" href="/manifest.webmanifest">',
    `<script${nonce ? ` nonce="${nonce}"` : ''} type="application/ld+json" id="rohmat-seo-brand-jsonld-v2">${safeJson(graph)}</script>`
  ].join('');

  const headAt = html.lastIndexOf('</head>');
  return headAt >= 0 ? html.slice(0, headAt) + metadata + html.slice(headAt) : html;
}

function isLifecycleRuntimeRequest(req) {
  try {
    const url = new URL(req.url || '/', 'https://rohmat.local');
    return url.searchParams.get('rohmat_runtime') === 'lifecycle';
  } catch {
    return false;
  }
}

export default async function handler(req, res) {
  if (isLifecycleRuntimeRequest(req)) return runtimeHandler(req, res);

  const cfg = await resolvePublicTenantConfig(req);
  if (!cfg.ok) return failTenantConfig(res, cfg.missing);
  // Reuse this request-scoped tenant resolution downstream instead of resolving the same origin twice.
  if (req) req.__sdbPublicTenantConfig = cfg;

  const end = res.end.bind(res);
  res.end = (body, ...args) => {
    if (res.statusCode === 200 && typeof body === 'string' && body.includes('</head>') && body.includes('</body>')) {
      body = injectSeoBrand(body, cfg);
      res.setHeader('X-Rohmat-SEO-Brand', 'metadata-v2');
      res.setHeader('X-Rohmat-SEO-Brand-Scope', 'og-twitter-hreflang-jsonld-restaurant-icons-manifest');
    }
    return end(body, ...args);
  };
  return baseHandler(req, res);
}
