#!/usr/bin/env bash
set -euo pipefail

log()  { printf '%s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_cmd az
require_cmd python3

OWNER="${OWNER:-}"
REPO="${REPO:-}"
APP_NAME="${APP_NAME:-opella-devops-challenge-github-actions}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
TENANT_ID="${TENANT_ID:-}"
DEV_RG="${DEV_RG:-}"
PROD_RG="${PROD_RG:-}"
TFSTATE_RG="${TFSTATE_RG:-}"
TFSTATE_SA="${TFSTATE_SA:-}"
ALLOW_SUBSCRIPTION_SCOPE="${ALLOW_SUBSCRIPTION_SCOPE:-false}"

[[ -n "$OWNER" ]] || die "OWNER is required"
[[ -n "$REPO"  ]] || die "REPO is required"

ensure_login() {
  if ! az account show >/dev/null 2>&1; then
    log "No Azure CLI session detected. Running az login..."
    az login >/dev/null
  fi
}

ensure_login

if [[ -n "$SUBSCRIPTION_ID" ]]; then
  az account set --subscription "$SUBSCRIPTION_ID"
fi

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="${TENANT_ID:-$(az account show --query tenantId -o tsv)}"

find_or_create_app() {
  local app_name="$1"
  local app_id

  app_id="$(az ad app list --display-name "$app_name" --query "[0].appId" -o tsv 2>/dev/null || true)"
  if [[ -n "$app_id" ]]; then
    log "Reusing existing Entra app: ${app_name} (${app_id})"
    printf '%s\n' "$app_id"
    return 0
  fi

  app_id="$(az ad app create --display-name "$app_name" --query appId -o tsv)"
  [[ -n "$app_id" ]] || die "Failed to create Entra app ${app_name}"
  log "Created Entra app: ${app_name} (${app_id})"
  printf '%s\n' "$app_id"
}

find_or_create_sp() {
  local app_id="$1"
  local sp_id

  sp_id="$(az ad sp show --id "$app_id" --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$sp_id" ]]; then
    log "Reusing existing service principal: ${sp_id}"
    printf '%s\n' "$sp_id"
    return 0
  fi

  az ad sp create --id "$app_id" >/dev/null
  sp_id="$(az ad sp show --id "$app_id" --query id -o tsv)"
  [[ -n "$sp_id" ]] || die "Failed to create service principal for app ${app_id}"
  log "Created service principal: ${sp_id}"
  printf '%s\n' "$sp_id"
}

upsert_federated_credential() {
  local app_id="$1"
  local cred_name="$2"
  local subject="$3"
  local tmp_json
  tmp_json="$(mktemp)"

  python3 - <<PY > "$tmp_json"
import json
print(json.dumps({
  "name": "$cred_name",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$subject",
  "audiences": ["api://AzureADTokenExchange"]
}))
PY

  if az ad app federated-credential show --id "$app_id" --federated-credential-id "$cred_name" >/dev/null 2>&1; then
    az ad app federated-credential update \
      --id "$app_id" \
      --federated-credential-id "$cred_name" \
      --parameters @"$tmp_json" >/dev/null
    log "Updated federated credential: ${cred_name} (${subject})"
  else
    az ad app federated-credential create \
      --id "$app_id" \
      --parameters @"$tmp_json" >/dev/null
    log "Created federated credential: ${cred_name} (${subject})"
  fi

  rm -f "$tmp_json"
}

supports_assignee_object_id() {
  az role assignment create -h 2>/dev/null | grep -q -- '--assignee-object-id'
}

role_assignment_exists() {
  local assignee="$1"
  local role="$2"
  local scope="$3"
  local count
  count="$(az role assignment list \
    --assignee "$assignee" \
    --role "$role" \
    --scope "$scope" \
    --query 'length(@)' -o tsv 2>/dev/null || printf '0')"
  [[ "$count" != "0" ]]
}

create_role_assignment() {
  local assignee_object_id="$1"
  local role="$2"
  local scope="$3"

  if role_assignment_exists "$assignee_object_id" "$role" "$scope"; then
    log "Reusing role assignment: ${role} on ${scope}"
    return 0
  fi

  if supports_assignee_object_id; then
    az role assignment create \
      --assignee-object-id "$assignee_object_id" \
      --assignee-principal-type ServicePrincipal \
      --role "$role" \
      --scope "$scope" >/dev/null
  else
    warn "Azure CLI does not support --assignee-object-id on this machine; using --assignee fallback."
    az role assignment create \
      --assignee "$assignee_object_id" \
      --role "$role" \
      --scope "$scope" >/dev/null
  fi

  log "Created role assignment: ${role} on ${scope}"
}

APP_ID="$(find_or_create_app "$APP_NAME")"
SP_OBJECT_ID="$(find_or_create_sp "$APP_ID")"

PR_SUBJECT="repo:${OWNER}/${REPO}:pull_request"
DEV_SUBJECT="repo:${OWNER}/${REPO}:environment:dev"
PROD_SUBJECT="repo:${OWNER}/${REPO}:environment:production"

upsert_federated_credential "$APP_ID" "github-pull-request" "$PR_SUBJECT"
upsert_federated_credential "$APP_ID" "github-dev" "$DEV_SUBJECT"
upsert_federated_credential "$APP_ID" "github-production" "$PROD_SUBJECT"

if [[ -n "$DEV_RG" ]]; then
  create_role_assignment "$SP_OBJECT_ID" "Contributor" "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${DEV_RG}"
fi

if [[ -n "$PROD_RG" ]]; then
  create_role_assignment "$SP_OBJECT_ID" "Contributor" "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${PROD_RG}"
fi

if [[ -z "$DEV_RG" || -z "$PROD_RG" ]]; then
  if [[ "$ALLOW_SUBSCRIPTION_SCOPE" == "true" ]]; then
    warn "DEV_RG / PROD_RG not fully set; assigning Contributor at subscription scope because ALLOW_SUBSCRIPTION_SCOPE=true."
    create_role_assignment "$SP_OBJECT_ID" "Contributor" "/subscriptions/${SUBSCRIPTION_ID}"
  else
    warn "DEV_RG / PROD_RG not fully set; skipped Contributor assignment to avoid broad subscription-wide access."
    warn "Provide DEV_RG and PROD_RG, or set ALLOW_SUBSCRIPTION_SCOPE=true if you explicitly want that behavior."
  fi
fi

if [[ -n "$TFSTATE_RG" && -n "$TFSTATE_SA" ]]; then
  create_role_assignment \
    "$SP_OBJECT_ID" \
    "Storage Blob Data Contributor" \
    "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TFSTATE_RG}/providers/Microsoft.Storage/storageAccounts/${TFSTATE_SA}"
else
  warn "TFSTATE_RG / TFSTATE_SA not set; Storage Blob Data Contributor was NOT assigned."
  warn "Terraform init against the AzureRM backend may fail until this role is added."
  warn "Rerun with: TFSTATE_RG=<rg> TFSTATE_SA=<storage-account> ./scripts/setup-github-oidc.sh"
fi

cat <<EOF

Done.

GitHub Environments to create:
  - dev
  - production

Add these GitHub REPOSITORY secrets:
  AZURE_CLIENT_ID=${APP_ID}
  AZURE_TENANT_ID=${TENANT_ID}
  AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}

Federated subject claims configured:
  ${PR_SUBJECT}
  ${DEV_SUBJECT}
  ${PROD_SUBJECT}

Use these in workflow jobs:
  ARM_CLIENT_ID: \${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: \${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: \${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_USE_OIDC: true
  ARM_USE_AZUREAD: true
  TF_IN_AUTOMATION: true
  TF_INPUT: 0

Notes:
  - GitHub Environments are used for deployment protection rules and production approval.
  - Plan jobs in the current workflow use REPOSITORY secrets, not environment secrets.
  - OIDC does not require an Azure client secret for GitHub Actions.
EOF
