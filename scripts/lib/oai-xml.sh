#!/usr/bin/env bash
# OAI-PMH XML helpers — prefer xmllint; fall back to python3 on agent pods.

set -euo pipefail

oai_count_records() {
  local file="$1"
  if command -v xmllint >/dev/null 2>&1; then
    xmllint --xpath 'count(//*[local-name()="record"])' "$file" 2>/dev/null || echo 0
    return
  fi
  python3 - "$file" <<'PY'
import sys
import xml.etree.ElementTree as ET

def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag

root = ET.parse(sys.argv[1]).getroot()
print(sum(1 for el in root.iter() if local(el.tag) == "record"))
PY
}

oai_append_records() {
  local src="$1"
  local dest="$2"
  if command -v xmllint >/dev/null 2>&1; then
    xmllint --xpath '//*[local-name()="ListRecords"]/*[local-name()="record"]' "$src" >>"$dest" 2>/dev/null \
      || cat "$src" >>"$dest"
    return
  fi
  python3 - "$src" "$dest" <<'PY'
import sys
import xml.etree.ElementTree as ET

def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag

root = ET.parse(sys.argv[1]).getroot()
records = []
for el in root.iter():
    if local(el.tag) == "ListRecords":
        for child in el:
            if local(child.tag) == "record":
                records.append(child)
        break

if not records:
    with open(sys.argv[2], "a", encoding="utf-8") as out:
        out.write(open(sys.argv[1], encoding="utf-8").read())
else:
    with open(sys.argv[2], "a", encoding="utf-8") as out:
        for rec in records:
            out.write(ET.tostring(rec, encoding="unicode"))
PY
}

oai_resumption_token() {
  local file="$1"
  if command -v xmllint >/dev/null 2>&1; then
    xmllint --xpath 'string(//*[local-name()="resumptionToken")' "$file" 2>/dev/null || true
    return
  fi
  python3 - "$file" <<'PY'
import sys
import xml.etree.ElementTree as ET

def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag

root = ET.parse(sys.argv[1]).getroot()
for el in root.iter():
    if local(el.tag) == "resumptionToken" and el.text:
        print(el.text.strip())
        break
PY
}

arxiv_full_harvest_complete() {
  [[ -f "$ARXIV_OUTPUT_DIR/full/.full.ok" ]]
}

arxiv_harvest_complete() {
  if [[ "${ARXIV_FULL_CORPUS:-0}" == "1" ]]; then
    arxiv_full_harvest_complete
    return
  fi
  arxiv_sets_all_complete "$@"
}

arxiv_sets_all_complete() {
  local sets_ref_name="$1"
  local -n sets_ref="$sets_ref_name"
  local set_spec safe_name marker
  local pending=0

  for set_spec in "${sets_ref[@]}"; do
    set_spec="$(printf '%s' "$set_spec" | xargs)"
    [[ -z "$set_spec" ]] && continue
    safe_name="$(printf '%s' "$set_spec" | tr ':/' '__')"
    marker="$ARXIV_OUTPUT_DIR/.${safe_name}.ok"
    if [[ ! -f "$marker" ]]; then
      pending=$((pending + 1))
    fi
  done

  [[ "$pending" -eq 0 ]]
}
