#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAYS_DIR="$SCRIPT_DIR/overlays"
OUTPUT_DIR="/tmp/home-server"

usage() {
  echo "Usage: $(basename "$0") <command> [overlay]"
  echo ""
  echo "Commands:"
  echo "  dump   Build all manifests and save to $OUTPUT_DIR"
  echo "  diff   Build manifests and show differences against last dump"
  echo "  clear  Remove generated manifests from $OUTPUT_DIR"
  echo ""
  echo "Options:"
  echo "  overlay  Name of the overlay folder (default: first found under overlays/)"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") dump zahariev.com"
  echo "  $(basename "$0") diff zahariev.com"
  echo "  $(basename "$0") clear"
  exit 1
}

resolve_overlay() {
  local overlay="${1:-}"
  if [[ -n "$overlay" ]]; then
    if [[ ! -d "$OVERLAYS_DIR/$overlay" ]]; then
      echo "Error: overlay '$overlay' not found in $OVERLAYS_DIR" >&2
      exit 1
    fi
    echo "$overlay"
  else
    # Auto-detect: use the first (or only) overlay directory
    local found
    found=$(ls -1 "$OVERLAYS_DIR" | head -1)
    if [[ -z "$found" ]]; then
      echo "Error: no overlays found in $OVERLAYS_DIR" >&2
      exit 1
    fi
    echo "$found"
  fi
}

build_manifests() {
  local overlay_dir="$1"
  local target_dir="$2"
  local errors=0

  for svc_dir in "$overlay_dir"/*/; do
    [[ -d "$svc_dir" ]] || continue
    local svc
    svc=$(basename "$svc_dir")
    local output_file="$target_dir/$svc.yaml"

    if kubectl kustomize "$svc_dir" > "$output_file" 2>/dev/null; then
      echo "  OK: $svc"
    else
      echo "  FAIL: $svc" >&2
      kubectl kustomize "$svc_dir" 2>&1 | head -3 >&2
      rm -f "$output_file"
      errors=$((errors + 1))
    fi
  done

  return $errors
}

cmd_dump() {
  local overlay
  overlay=$(resolve_overlay "${1:-}")
  local overlay_dir="$OVERLAYS_DIR/$overlay"
  local target_dir="$OUTPUT_DIR/$overlay"

  mkdir -p "$target_dir"
  echo "Building manifests from overlays/$overlay -> $target_dir"
  echo ""

  if build_manifests "$overlay_dir" "$target_dir"; then
    echo ""
    echo "All manifests saved to $target_dir"
  else
    echo ""
    echo "Some manifests failed to build" >&2
    exit 1
  fi
}

cmd_diff() {
  local overlay
  overlay=$(resolve_overlay "${1:-}")
  local overlay_dir="$OVERLAYS_DIR/$overlay"
  local saved_dir="$OUTPUT_DIR/$overlay"

  if [[ ! -d "$saved_dir" ]]; then
    echo "No previous dump found at $saved_dir"
    echo "Run 'dump' first to create a baseline."
    exit 1
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir'" EXIT

  echo "Building current manifests and comparing against $saved_dir"
  echo ""

  local has_diff=0
  for svc_dir in "$overlay_dir"/*/; do
    [[ -d "$svc_dir" ]] || continue
    local svc
    svc=$(basename "$svc_dir")
    local saved_file="$saved_dir/$svc.yaml"
    local current_file="$tmp_dir/$svc.yaml"

    if ! kubectl kustomize "$svc_dir" > "$current_file" 2>/dev/null; then
      echo "FAIL: $svc (build error)" >&2
      continue
    fi

    if [[ ! -f "$saved_file" ]]; then
      echo "NEW: $svc (no previous dump)"
      has_diff=1
      continue
    fi

    local result
    result=$(diff --unified=3 "$saved_file" "$current_file" 2>&1) || true
    if [[ -n "$result" ]]; then
      echo "=== $svc ==="
      echo "$result"
      echo ""
      has_diff=1
    fi
  done

  # Check for removed services
  for saved_file in "$saved_dir"/*.yaml; do
    [[ -f "$saved_file" ]] || continue
    local svc
    svc=$(basename "$saved_file" .yaml)
    if [[ ! -d "$overlay_dir/$svc" ]]; then
      echo "REMOVED: $svc"
      has_diff=1
    fi
  done

  if [[ $has_diff -eq 0 ]]; then
    echo "No differences found."
  fi
}

cmd_clear() {
  if [[ -d "$OUTPUT_DIR" ]]; then
    rm -rf "$OUTPUT_DIR"
    echo "Cleared $OUTPUT_DIR"
  else
    echo "Nothing to clear ($OUTPUT_DIR does not exist)"
  fi
}

# --- Main ---
[[ $# -lt 1 ]] && usage

command="$1"
shift

case "$command" in
  dump)  cmd_dump "$@" ;;
  diff)  cmd_diff "$@" ;;
  clear) cmd_clear ;;
  *)     usage ;;
esac
