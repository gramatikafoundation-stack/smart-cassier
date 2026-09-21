# Payment Verification Performance Contract

Freeze candidate contract for browser-side QRIS proof verification.

## Target

- Typical verification target: **3–5 seconds** on a normal mobile device after the Public app has had time to warm the OCR worker.
- Hard UI deadline: **4.8 seconds** so the verification state exits before 5 seconds.
- Verification must never remain indefinitely in a pending state.

## Production smart single-pass path

- Tesseract.js pinned to **6.0.1**.
- OCR worker is eagerly warmed from the Public app runtime instead of waiting until the payment panel is first shown.
- Browser preconnect/DNS-prefetch is enabled for the Tesseract CDN and tessdata origin.
- The Tesseract script is loaded with high fetch priority and anonymous CORS mode.
- Exactly **one OCR pass** is used; no full-resolution second pass is allowed.
- Input image is downscaled to a maximum long-side dimension of **800 px** and encoded at JPEG quality **0.80**.
- Before OCR, the browser applies lightweight grayscale + contrast preprocessing (`contrast(1.18)`) on canvas.
- Merchant matching uses normalized token matching, fuzzy edit-distance matching, stop-word removal, and alias-tolerant phrase scoring.
- Numeric OCR confusion correction handles common substitutions such as `O↔0`, `I/l↔1`, `S↔5`, and `B↔8` when parsing date/time/amount candidates.
- Date parsing accepts digit-confused values first, then validates actual day/month/year ranges through the date validator.
- Time parsing accepts digit-confused values first, then validates hour/minute ranges (`hour <= 23`, `minute <= 59`).
- Nominal parsing prioritizes `total`, `jumlah bayar`, `nominal`, `amount`, `Rp`, and `IDR`, while penalizing reference/RRN/transaction-ID lines.
- Merchant, date, time, and nominal each receive a confidence score shown in the verification UI.
- The downstream gate reads nominal only from the nominal value element, so the confidence percentage cannot contaminate the parsed amount.
- Nominal mismatch remains non-blocking and is surfaced to KDS; merchant/date/time remain critical checks.
- At 4.8 seconds, the UI exits the pending state and reports that verification did not complete. The send action remains blocked for critical verification failure.

## Rollback

- Pre-Smart-OCR-v6 LKG backup: `rohmat-static/backups/public-lkg-pre-ocr-smart-v6.html`
- Previous known-good maintainer: `rohmat-static-publisher-v1:v15`

## Current production evidence

- LKG marker: `rohmat-ocr-smart-v6`
- Digit parser fix marker: `rohmat-ocr-smart-v6-fixed-digits`
- `OCR_FAST_DEADLINE_MS=4800`
- `max=800`
- Single OCR pass: enabled
- Grayscale + contrast preprocessing: enabled
- Context parser: enabled
- Confidence scoring: enabled
- Corrected date/time digit-class parsing: enabled
- Nominal confidence contamination fix: enabled
- Tesseract `6.0.1`
- Eager worker warm-up enabled
- Preconnect to `cdn.jsdelivr.net` and `tessdata.projectnaptha.com`
- Tesseract script fetch priority: `high`
- Maintainer: `rohmat-static-publisher-v1:v16`
- Maintainer SHA-256: `ef9c74380a8798ff7fd0ad2744a58d41e91b6e711978954b36618f43bcd8c9f7`

## Semantic parser checks

Synthetic parser validation must include at least:

- Correct merchant: `TAHU TEK DAN GADO GADO QR` matches `Tahu Tek dan Gado-Gado`.
- Wrong merchant: an unrelated merchant must remain below the acceptance threshold.
- OCR-confused date such as `13/09/2O26` normalizes to `2026-09-13`.
- OCR-confused time such as `I4:3O` normalizes to `14:30`.
- OCR-confused nominal such as `Rp 5.OOO` normalizes to `Rp 5.000`.
- RRN/reference numbers must not outrank a context-labelled payment total.

## Final freeze gate

Before Master Clone v1.0 is tagged, verify with multiple real proof images from different bank/e-wallet interfaces:

1. Typical successful verification completes in **3–5 seconds** where device/network conditions permit.
2. No verification remains pending beyond **5 seconds**.
3. Merchant recognition target: **>=97%** on clear samples.
4. Date recognition target: **>=95%** on clear samples.
5. Time recognition target: **>=93–95%** on clear samples.
6. Nominal recognition target: **>=95%** when the nominal is visibly present.
7. False merchant acceptance must be effectively zero in the validation set.
8. Timeout/failure state is explicit and recoverable.
9. Payment/order submission contracts remain unchanged.
