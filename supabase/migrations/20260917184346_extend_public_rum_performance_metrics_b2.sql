alter table public.public_rum_samples
  drop constraint if exists public_rum_samples_metric_check;

alter table public.public_rum_samples
  drop constraint if exists public_rum_samples_metric_v2_chk;

alter table public.public_rum_samples
  add constraint public_rum_samples_metric_v3_chk
  check (
    metric = any (
      array['VIEW','LCP','CLS','INP','FCP','TTFB','JSERR','LONGTASK','OCRMS','OCRFAIL']::text[]
    )
  );
