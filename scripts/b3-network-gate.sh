#!/usr/bin/env bash
set -euo pipefail
BASE="${B3_BASE_URL:-https://smart-order-sdb.vercel.app}"

check_route(){
  local path="$1" max_transfer="$2" label="$3"
  local tmp
  tmp="$(mktemp)"
  for i in 1 2 3 4 5; do
    curl -L -sS --compressed -o /dev/null \
      -w '%{http_code} %{time_starttransfer} %{time_total} %{size_download}\n' \
      "$BASE$path" >>"$tmp"
  done
  awk -v label="$label" -v max="$max_transfer" '
    $1!=200 {print label ": http status " $1 > "/dev/stderr"; exit 10}
    $4>max {print label ": compressed transfer " $4 " > " max > "/dev/stderr"; exit 11}
    NR==1 && $3>4.0 {print label ": cold total " $3 "s > 4.0s" > "/dev/stderr"; exit 12}
    NR>1 {warm[++n]=$2}
    END {
      if(n<4) exit 13;
      for(i=1;i<=n;i++) for(j=i+1;j<=n;j++) if(warm[j]<warm[i]){t=warm[i];warm[i]=warm[j];warm[j]=t}
      med=(warm[2]+warm[3])/2;
      if(med>1.5){print label ": warm median TTFB " med "s > 1.5s" > "/dev/stderr"; exit 14}
      print label ": PASS warm_median_ttfb=" med "s max_transfer=" max
    }' "$tmp"
  rm -f "$tmp"
}

check_route "/" 40000 public
check_route "/admin" 35000 admin
check_route "/kds" 5000 kds
check_route "/database" 35000 database
echo "B3_NETWORK_PERFORMANCE_GATE_PASS=1"
