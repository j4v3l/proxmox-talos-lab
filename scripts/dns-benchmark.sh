#!/usr/bin/env bash
set -euo pipefail

for required_command in dnsperf awk mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "ERROR: missing $required_command" >&2
    exit 1
  fi
done

duration=${DNSPERF_DURATION:-60}
qps=${DNSPERF_QPS:-100}
max_p95_ms=${DNSPERF_MAX_P95_MS:-10}
query_file=$(mktemp)
trap 'rm -f "$query_file"' EXIT

for domain in github.com forgejo.org pihole.net kubernetes.io cilium.io; do
  printf '%s A\n%s AAAA\n' "$domain" "$domain" >>"$query_file"
done

for server in 192.168.80.31 192.168.80.32; do
  output=$(dnsperf -s "$server" -d "$query_file" -l "$duration" -Q "$qps" 2>&1)
  lost=$(printf '%s\n' "$output" | awk '/Queries lost:/ {gsub(/[()%]/, "", $3); print $3}')
  p95_seconds=$(printf '%s\n' "$output" | awk '/Latency:/ {print $7}')
  p95_ms=$(awk -v value="${p95_seconds:-999}" 'BEGIN { printf "%.3f", value * 1000 }')

  if [[ ${lost:-1} != "0.000" && ${lost:-1} != "0" ]]; then
    echo "ERROR: $server lost DNS queries: ${lost:-unknown}%" >&2
    exit 1
  fi
  if ! awk -v actual="$p95_ms" -v maximum="$max_p95_ms" 'BEGIN { exit !(actual < maximum) }'; then
    echo "ERROR: $server p95 ${p95_ms}ms exceeds ${max_p95_ms}ms" >&2
    exit 1
  fi
  echo "OK: $server sustained ${qps} qps with p95 ${p95_ms}ms and zero loss"
done
