#!/usr/bin/env bash
# OpenAlex REST fetch helpers (polite pool — mailto required).

set -euo pipefail

openalex_api_url() {
  local cursor="${1:-*}"
  local base="${OPENALEX_API_BASE:-https://api.openalex.org}"
  local filter="${OPENALEX_WORKS_FILTER:-topics.field.id:17}"
  local per_page="${OPENALEX_PER_PAGE:-200}"
  local mailto="${OPENALEX_MAILTO:?OPENALEX_MAILTO required for polite pool — export mailto=you@example.com}"

  local url="${base}/works?filter=${filter}&per_page=${per_page}&cursor=${cursor}&mailto=${mailto}"
  printf '%s' "$url"
}

openalex_fetch_page() {
  local cursor="${1:-*}"
  local out_json="$2"
  local url
  url="$(openalex_api_url "$cursor")"

  local attempt=0
  local max_attempts=8
  local delay=2

  while [[ "$attempt" -lt "$max_attempts" ]]; do
    attempt=$((attempt + 1))
    local http_code
    http_code="$(curl -fsSL -w '%{http_code}' -o "$out_json.part" "$url" 2>/dev/null || true)"
    if [[ "$http_code" == "200" ]]; then
      mv "$out_json.part" "$out_json"
      return 0
    fi
    rm -f "$out_json.part"
    if [[ "$http_code" == "429" || "$http_code" == "503" ]]; then
      log "OpenAlex HTTP ${http_code} — backoff ${delay}s (attempt ${attempt}/${max_attempts})"
      sleep "$delay"
      delay=$((delay * 2))
      [[ "$delay" -gt 300 ]] && delay=300
      continue
    fi
    echo "OpenAlex fetch failed HTTP ${http_code}: $url" >&2
    return 1
  done
  echo "OpenAlex fetch exhausted retries: $url" >&2
  return 1
}

openalex_results_to_jsonl() {
  local in_json="$1"
  local out_jsonl="$2"
  jq -c '.results[]?' "$in_json" >>"$out_jsonl"
}
