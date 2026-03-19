#!/usr/bin/env bash
# setup-acr.sh
#
# Creates an Azure Container Registry and copies the demo NGINX images into it
# from Docker Hub using ORAS, retagging them for the demo:
#
#   nginx:1.29-alpine  →  <acr>/nginx:1.29-alpine-signed
#   nginx:1.28-alpine  →  <acr>/nginx:1.28-alpine-unsigned
#
# Usage:
#   chmod +x setup-acr.sh
#   ./setup-acr.sh
#
# Required environment variables:
#   ACR_NAME   - Name of the ACR to create (e.g. acrtsmpremiumsku)
#   ACR_RG     - Resource group for the ACR
#   ACR_SKU    - ACR SKU (default: Premium)
#   ACR_LOCATION - Azure region (default: westus2)

set -euo pipefail

###############################################################################
# Colors / helpers
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
cmd_log() { echo -e "${CYAN}[CMD]${NC} $*"; }

run() {
    cmd_log "$*"
    local _err; _err=$(mktemp)
    if ! "$@" 2>"$_err"; then
        local _rc=$?
        [[ -s "$_err" ]] && error "$(cat "$_err")"
        rm -f "$_err"
        return $_rc
    fi
    rm -f "$_err"
}

###############################################################################
# Load shared defaults (override by exporting before running)
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=defaults.sh
source "${SCRIPT_DIR}/defaults.sh"

###############################################################################
# Validate required variables
###############################################################################
REQUIRED_VARS=(ACR_NAME ACR_RG ACR_SKU ACR_LOCATION)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Required environment variable \$$var is not set."
        exit 1
    fi
done

###############################################################################
# Step 1 — Log out and log back in to ensure the correct subscription
###############################################################################
info "Step 1: Logging out of Azure CLI to ensure a clean session..."
az logout --verbose 2>/dev/null || true
info "Logging in to Azure CLI..."
az login
if ! az account show --query id -o tsv &>/dev/null; then
    error "No active Azure CLI session. Authenticate first with one of:"
    error "  az login                                  (interactive)"
    error "  az login --service-principal ...          (service principal)"
    error "  az login --identity                       (managed identity)"
    exit 1
fi
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION=$(az account show --query name -o tsv)
info "Using subscription: $SUBSCRIPTION ($SUBSCRIPTION_ID)"

###############################################################################
# Step 2 — Create resource group
###############################################################################
info "Step 2: Ensuring resource group '$ACR_RG' exists..."
if az group show --name "$ACR_RG" &>/dev/null; then
    info "Resource group '$ACR_RG' already exists — skipping."
else
    run az group create \
        --name "$ACR_RG" \
        --location "$ACR_LOCATION"
    info "Resource group '$ACR_RG' created."
fi

###############################################################################
# Step 3 — Create Azure Container Registry
###############################################################################
info "Step 3: Creating ACR '$ACR_NAME' (SKU: $ACR_SKU)..."
if az acr show --name "$ACR_NAME" --resource-group "$ACR_RG" &>/dev/null; then
    info "ACR '$ACR_NAME' already exists — skipping."
else
    run az acr create \
        --name "$ACR_NAME" \
        --resource-group "$ACR_RG" \
        --location "$ACR_LOCATION" \
        --sku "$ACR_SKU"
    info "ACR '$ACR_NAME' created."
fi

###############################################################################
# Step 4 — Log in to ACR
###############################################################################
info "Step 4: Logging in to ACR '$ACR_LOGIN_SERVER'..."
run az acr login --name "$ACR_NAME"

###############################################################################
# Step 5 — Copy images using ORAS
###############################################################################
info "Step 5: Copying images from Docker Hub into '$ACR_LOGIN_SERVER'..."

# nginx:1.29-alpine → <acr>/nginx:1.29-alpine-signed (will be Notation-signed later)
info "  Copying nginx:1.29-alpine → ${ACR_LOGIN_SERVER}/nginx:1.29-alpine-signed"
run oras copy \
    registry-1.docker.io/library/nginx:1.29-alpine \
    "${ACR_LOGIN_SERVER}/nginx:1.29-alpine-signed"

# nginx:1.28-alpine → <acr>/nginx:1.28-alpine-unsigned (intentionally not signed)
info "  Copying nginx:1.28-alpine → ${ACR_LOGIN_SERVER}/nginx:1.28-alpine-unsigned"
run oras copy \
    registry-1.docker.io/library/nginx:1.28-alpine \
    "${ACR_LOGIN_SERVER}/nginx:1.28-alpine-unsigned"

###############################################################################
# Summary
###############################################################################
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ACR setup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "  ACR:      $ACR_LOGIN_SERVER"
echo "  Images:"
echo "    ${ACR_LOGIN_SERVER}/nginx:1.29-alpine-signed   (ready to sign with Notation)"
echo "    ${ACR_LOGIN_SERVER}/nginx:1.28-alpine-unsigned (intentionally unsigned)"
echo
echo "Next steps:"
echo "  1. Sign the image:  notation sign ${ACR_LOGIN_SERVER}/nginx:1.29-alpine-signed"
echo "  2. Run setup-aks.sh to configure the AKS cluster"
echo
