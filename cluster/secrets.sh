#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAYS_DIR="$SCRIPT_DIR/overlays"

usage() {
  echo "Usage: $(basename "$0") <overlay>"
  echo ""
  echo "Creates Kubernetes secrets from the .env file in the specified overlay."
  echo "The .env file uses the format: secret-name/key:value"
  echo "Secrets are grouped by name and created in namespaces matching"
  echo "the service directories where they are referenced."
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") zahariev.com"
  exit 1
}

[[ $# -eq 1 ]] || usage

OVERLAY="$1"
OVERLAY_DIR="$OVERLAYS_DIR/$OVERLAY"
ENV_FILE="$OVERLAY_DIR/.env"

if [[ ! -d "$OVERLAY_DIR" ]]; then
  echo "Error: overlay '$OVERLAY' not found in $OVERLAYS_DIR" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env file not found at $ENV_FILE" >&2
  exit 1
fi

# Map of secret names to their namespaces
declare -A SECRET_NS
SECRET_NS[calibre-secrets]="calibre"
SECRET_NS[keycloak-db-secrets]="keycloak"
SECRET_NS[mealie-db-secrets]="mealie"
SECRET_NS[mattermost-db-secrets]="mattermost"
SECRET_NS[taskboard-secrets]="taskboard"
SECRET_NS[invval-secrets]="invval"
SECRET_NS[plex-secrets]="plex"
SECRET_NS[grafana-secrets]="monitoring"

# Collect all keys per secret
declare -A SECRET_ARGS

while IFS= read -r line; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" == \#* ]] && continue

  # Parse secret-name/key:value
  secret_name="${line%%/*}"
  rest="${line#*/}"
  key="${rest%%:*}"
  value="${rest#*:}"

  if [[ -z "$secret_name" || -z "$key" ]]; then
    echo "Warning: skipping malformed line: $line" >&2
    continue
  fi

  # Append --from-literal argument
  if [[ -n "${SECRET_ARGS[$secret_name]:-}" ]]; then
    SECRET_ARGS[$secret_name]+=" --from-literal=${key}=${value}"
  else
    SECRET_ARGS[$secret_name]="--from-literal=${key}=${value}"
  fi
done < "$ENV_FILE"

# Create each secret
errors=0
for secret_name in $(echo "${!SECRET_ARGS[@]}" | tr ' ' '\n' | sort); do
  ns="${SECRET_NS[$secret_name]:-}"
  if [[ -z "$ns" ]]; then
    echo "Error: unknown secret '$secret_name' — add its namespace to the script" >&2
    errors=$((errors + 1))
    continue
  fi

  args="${SECRET_ARGS[$secret_name]}"
  if kubectl create secret generic "$secret_name" \
    --namespace="$ns" \
    $args \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null; then
    echo "  OK: $secret_name (namespace: $ns)"
  else
    echo "  FAIL: $secret_name (namespace: $ns)" >&2
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  echo ""
  echo "$errors secret(s) failed" >&2
  exit 1
fi

echo ""
echo "All secrets applied successfully"
