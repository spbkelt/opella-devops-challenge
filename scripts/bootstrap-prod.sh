#!/usr/bin/env bash
set -euo pipefail

# Idempotent Terraform backend bootstrap for PROD.
# Minimal required input: SUBSCRIPTION_ID (or --subscription).
# Optional: TENANT_ID, LOCATION, TFSTATE_SA, RUN_TF_INIT, TF_SERVICE_PRINCIPAL_APP_ID.
# Behavior:
# - creates or reuses RG / storage account / container
# - writes environments/prod/backend.tfbackend
# - optionally runs terraform init

ENVIRONMENT="prod"
LOCATION="${LOCATION:-eastus}"
TF_DIR="${TF_DIR:-environments/prod}"
TFSTATE_RG="${TFSTATE_RG:-tfstate-prod-rg}"
TFSTATE_CONTAINER="${TFSTATE_CONTAINER:-tfstate}"
BACKEND_FILE="${BACKEND_FILE:-${TF_DIR}/backend.tfbackend}"
RUN_TF_INIT="${RUN_TF_INIT:-true}"
USE_AZUREAD_AUTH="${USE_AZUREAD_AUTH:-true}"
TENANT_ID="${TENANT_ID:-}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
TFSTATE_SA="${TFSTATE_SA:-}"
SP_APP_ID="${TF_SERVICE_PRINCIPAL_APP_ID:-${ARM_CLIENT_ID:-}}"

usage() {
  cat <<USAGE
Usage: $0 [--subscription <id>] [--tenant <id>] [--storage-account <name>] [--location <region>] [--no-init]

Defaults:
  TF_DIR=environments/prod
  TFSTATE_RG=tfstate-prod-rg
  TFSTATE_CONTAINER=tfstate
  LOCATION=eastus

Only crucial input is the subscription id. If no storage account name is provided,
a stable one is derived from the subscription id.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --tenant) TENANT_ID="$2"; shift 2 ;;
    --storage-account) TFSTATE_SA="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --no-init) RUN_TF_INIT="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

command -v az >/dev/null 2>&1 || { echo "ERROR: az CLI is required." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform is required." >&2; exit 1; }

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "ERROR: SUBSCRIPTION_ID is required (env var or --subscription)." >&2
  exit 1
fi

if [[ -z "$TFSTATE_SA" ]]; then
  SUB_SHORT="$(echo "$SUBSCRIPTION_ID" | tr -d '-' | cut -c1-10 | tr '[:upper:]' '[:lower:]')"
  TFSTATE_SA="tfstate${ENVIRONMENT}${SUB_SHORT}"
fi

TFSTATE_SA="$(echo "$TFSTATE_SA" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)"
if [[ ${#TFSTATE_SA} -lt 3 ]]; then
  echo "ERROR: Derived storage account name '$TFSTATE_SA' is invalid." >&2
  exit 1
fi

ensure_login() {
  if ! az account show >/dev/null 2>&1; then
    if [[ -n "$TENANT_ID" ]]; then
      az login --tenant "$TENANT_ID" >/dev/null
    else
      az login >/dev/null
    fi
  fi

  if ! az account list --query "[?id=='${SUBSCRIPTION_ID}'] | length(@)" -o tsv | grep -qx '1'; then
    if [[ -n "$TENANT_ID" ]]; then
      az login --tenant "$TENANT_ID" >/dev/null
    else
      az login >/dev/null
    fi
  fi

  az account set --subscription "$SUBSCRIPTION_ID"
}

ensure_login

echo "Using subscription: $SUBSCRIPTION_ID"
az account show --output table

az provider register --namespace Microsoft.Storage >/dev/null
while [[ "$(az provider show --namespace Microsoft.Storage --query registrationState -o tsv)" != "Registered" ]]; do
  echo "Waiting for Microsoft.Storage registration..."
  sleep 5
done

az group create \
  --name "$TFSTATE_RG" \
  --location "$LOCATION" \
  --subscription "$SUBSCRIPTION_ID" \
  --output none

if ! az storage account show --name "$TFSTATE_SA" --resource-group "$TFSTATE_RG" >/dev/null 2>&1; then
  az storage account create \
    --name "$TFSTATE_SA" \
    --resource-group "$TFSTATE_RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --allow-shared-key-access true \
    --output none
else
  az storage account update \
    --name "$TFSTATE_SA" \
    --resource-group "$TFSTATE_RG" \
    --allow-shared-key-access true \
    --min-tls-version TLS1_2 \
    --output none >/dev/null 2>&1 || true
fi

ACCOUNT_KEY="$(az storage account keys list \
  --resource-group "$TFSTATE_RG" \
  --account-name "$TFSTATE_SA" \
  --query '[0].value' -o tsv)"

az storage container create \
  --name "$TFSTATE_CONTAINER" \
  --account-name "$TFSTATE_SA" \
  --account-key "$ACCOUNT_KEY" \
  --output none

if [[ -n "$SP_APP_ID" ]]; then
  SP_OBJECT_ID="$(az ad sp show --id "$SP_APP_ID" --query id -o tsv)"
  SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TFSTATE_RG}/providers/Microsoft.Storage/storageAccounts/${TFSTATE_SA}"
  HAS_ROLE="$(az role assignment list --assignee-object-id "$SP_OBJECT_ID" --scope "$SCOPE" --query "[?roleDefinitionName=='Storage Blob Data Contributor'] | length(@)" -o tsv 2>/dev/null || echo 0)"
  if [[ "$HAS_ROLE" != "1" ]]; then
    az role assignment create \
      --assignee-object-id "$SP_OBJECT_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Contributor" \
      --scope "$SCOPE" \
      --output none || true
  fi
fi

mkdir -p "$TF_DIR"
cat > "$BACKEND_FILE" <<BACKEND
resource_group_name  = "$TFSTATE_RG"
storage_account_name = "$TFSTATE_SA"
container_name       = "$TFSTATE_CONTAINER"
key                  = "terraform.tfstate"
use_azuread_auth     = ${USE_AZUREAD_AUTH}
BACKEND

echo
printf 'Reused/created backend resources for %s\n' "$ENVIRONMENT"
printf 'backend file         : %s\n' "$BACKEND_FILE"
printf 'resource group       : %s\n' "$TFSTATE_RG"
printf 'storage account      : %s\n' "$TFSTATE_SA"
printf 'container            : %s\n' "$TFSTATE_CONTAINER"
printf 'state key            : terraform.tfstate\n'

if [[ "$RUN_TF_INIT" == "true" ]]; then
  (
    cd "$TF_DIR"
    terraform init -reconfigure -backend-config="$(basename "$BACKEND_FILE")"
  )
fi
