#!/usr/bin/env bash
# Alias for run-warm-ingest.sh (R1b gate accepts either script name).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/run-warm-ingest.sh" "$@"
