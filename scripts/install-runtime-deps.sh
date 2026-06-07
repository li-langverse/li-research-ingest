#!/usr/bin/env bash
# Bootstrap ingest runtime tools when apt packages are unavailable (agent pods).
# Idempotent — safe to source or exec before warm ingest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${LI_RESEARCH_INGEST_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DEPS_BIN="${LI_RESEARCH_DEPS_BIN:-$REPO_ROOT/.deps/bin}"
JQ_VERSION="${LI_JQ_VERSION:-1.7.1}"

_log() {
  printf '[li-research-ingest] %s\n' "$*" >&2
}

_ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "$DEPS_BIN/jq" ]]; then
    export PATH="$DEPS_BIN:$PATH"
    return 0
  fi

  require_curl() {
    command -v curl >/dev/null 2>&1 || {
      echo "install-runtime-deps: curl required to bootstrap jq" >&2
      exit 1
    }
  }

  require_curl
  mkdir -p "$DEPS_BIN"

  local lock="$DEPS_BIN/.jq-bootstrap.lock"
  (
    flock -x 200
    if [[ -x "$DEPS_BIN/jq" ]]; then
      exit 0
    fi

    local arch url
    arch="$(uname -m)"
    case "$arch" in
      x86_64 | amd64) url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" ;;
      aarch64 | arm64) url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-arm64" ;;
      *)
        echo "install-runtime-deps: unsupported arch for jq bootstrap: $arch" >&2
        exit 1
        ;;
    esac

    _log "bootstrapping jq ${JQ_VERSION} → $DEPS_BIN/jq"
    curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$DEPS_BIN/jq.part"
    chmod +x "$DEPS_BIN/jq.part"
    mv "$DEPS_BIN/jq.part" "$DEPS_BIN/jq"
  ) 200>"$lock"

  if [[ ! -x "$DEPS_BIN/jq" ]]; then
    echo "install-runtime-deps: jq bootstrap failed" >&2
    return 1
  fi
  export PATH="$DEPS_BIN:$PATH"
}

_ensure_jq
