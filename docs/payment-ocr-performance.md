# Payment OCR Performance Contract

## Goal

Payment-proof verification should normally complete in approximately 3–5 seconds on supported mobile browsers and must stop waiting after 6.5 seconds. The customer UI must never remain indefinitely in `Memverifikasi bukti pembayaran…`.

## Production implementation

- OCR engine: Tesseract.js 6.0.1
- Worker pre-warm starts when the payment page is rendered
- Uploaded proof image is downscaled to a maximum long side of 1280 px before OCR
- Only one optimized OCR pass is performed
- The previous full-resolution second-pass fallback is removed
- Hard verification deadline: 6500 ms
- On deadline expiry, the worker is terminated and the UI reports that verification was not completed within 6.5 seconds
- Order submission remains guarded by the existing merchant/date/time verification UI and backend validation

## Rollback

Pre-change Last-Known-Good HTML is stored at:

`rohmat-static/backups/public-lkg-pre-ocr-fast-v1.html`

The LKG maintainer rollback reference is:

`edge:rohmat-static-publisher-v1:v9`

## Acceptance criteria

1. Public production HTML contains `rohmat-ocr-fast-v1`.
2. Public production HTML contains `OCR_FAST_DEADLINE_MS=6500`.
3. Tesseract source is pinned to `6.0.1`.
4. There is no second full-resolution OCR fallback pass in the fast path.
5. Browser verification must terminate by 6.5 seconds after proof selection even when OCR cannot complete.
6. Typical warm-worker verification target is 3–5 seconds; this must be confirmed during mobile acceptance testing on the target device/network.
7. Existing checkout, proof upload, proof OCR text forwarding, and create-order contracts remain unchanged.

## Release

Production release baseline: `rohmat-prod-2026-09-13-r13-fast-payment-ocr` (superseded by later freeze-prep baselines as source-control state evolves).
