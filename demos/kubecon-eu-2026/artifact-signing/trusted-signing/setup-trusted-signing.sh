#!/usr/bin/env bash
# setup-trusted-signing.sh
#
# Creates an Azure Trusted Signing account, a Private Trust certificate profile,
# and assigns the required RBAC roles to the current user.
#
# What this script does:
#   1. Verify Azure login
#   2. Install the trustedsigning CLI extension if missing
#   3. Create resource group (if it doesn't exist)
#   4. Create Trusted Signing account
#   5. Create a Private Trust certificate profile (signing identity)
#   6. Assign RBAC roles to the current signed-in user:
#        - Artifact Signing Certificate Profile Signer  (for signing)
#        - Artifact Signing Identity Verifier           (for verification)
#
# Usage:
#   chmod +x setup-trusted-signing.sh
#   ./setup-trusted-signing.sh
#
# Required environment variables:
#   TS_ACCOUNT_NAME  - Trusted Signing account name (e.g. sig-tsm-demo)
#   TS_RG            - Resource group for the account
#   TS_LOCATION      - Azure region (e.g. westus2)
#   TS_CERT_PROFILE  - Certificate profile name (e.g. cert-tsm-demo)
#
# Optional environment variables (subject DN fields):
#   TS_COMMON_NAME   - CN field (default: microsoft.onmicrosoft.com)
#   TS_ORGANIZATION  - O field  (default: microsoft.onmicrosoft.com)
#   TS_ORG_UNIT      - OU field (default: Cloud Native Security and Registries)
#   TS_CITY          - L field  (default: Redmond)
#   TS_STATE         - S field  (default: Washington)
#   TS_COUNTRY       - C field  (default: US)

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
REQUIRED_VARS=(TS_ACCOUNT_NAME TS_RG TS_LOCATION TS_CERT_PROFILE)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Required environment variable \$$var is not set."
        exit 1
    fi
done

###############################################################################
# Step 1 — Verify Azure login
###############################################################################
info "Step 1: Verifying Azure login..."
if ! az account show --query id -o tsv &>/dev/null; then
    warn "Not logged in. Running az login..."
    run az login
fi
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION=$(az account show --query name -o tsv)
info "Using subscription: $SUBSCRIPTION ($SUBSCRIPTION_ID)"

###############################################################################
# Step 2 — Install trustedsigning CLI extension
###############################################################################
info "Step 2: Checking trustedsigning CLI extension..."
if az extension show --name trustedsigning &>/dev/null; then
    info "trustedsigning extension already installed."
else
    info "Installing trustedsigning extension..."
    run az extension add --name trustedsigning
fi

###############################################################################
# Step 3 — Create resource group
###############################################################################
info "Step 3: Ensuring resource group '$TS_RG' exists..."
if az group show --name "$TS_RG" &>/dev/null; then
    info "Resource group '$TS_RG' already exists — skipping."
else
    run az group create \
        --name "$TS_RG" \
        --location "$TS_LOCATION"
    info "Resource group '$TS_RG' created."
fi

###############################################################################
# Step 4 — Create Trusted Signing account
###############################################################################
info "Step 4: Creating Trusted Signing account '$TS_ACCOUNT_NAME'..."
if az trustedsigning show \
    --name "$TS_ACCOUNT_NAME" \
    --resource-group "$TS_RG" &>/dev/null; then
    info "Trusted Signing account '$TS_ACCOUNT_NAME' already exists — skipping."
else
    run az trustedsigning create \
        --name "$TS_ACCOUNT_NAME" \
        --resource-group "$TS_RG" \
        --location "$TS_LOCATION" \
        --sku "$TS_SKU"
    info "Trusted Signing account '$TS_ACCOUNT_NAME' created."
fi

TS_ACCOUNT_ID=$(az trustedsigning show \
    --name "$TS_ACCOUNT_NAME" \
    --resource-group "$TS_RG" \
    --query id -o tsv)

###############################################################################
# Step 5 — Create Private Trust certificate profile (signing identity)
###############################################################################
info "Step 5: Creating certificate profile '$TS_CERT_PROFILE' (PrivateTrust)..."
if az trustedsigning certificate-profile show \
    --account-name "$TS_ACCOUNT_NAME" \
    --resource-group "$TS_RG" \
    --profile-name "$TS_CERT_PROFILE" &>/dev/null; then
    info "Certificate profile '$TS_CERT_PROFILE' already exists — skipping."
else
    run az trustedsigning certificate-profile create \
        --account-name "$TS_ACCOUNT_NAME" \
        --resource-group "$TS_RG" \
        --profile-name "$TS_CERT_PROFILE" \
        --profile-type PrivateTrust \
        --common-name "$TS_COMMON_NAME" \
        --organization "$TS_ORGANIZATION" \
        --organization-unit "$TS_ORG_UNIT" \
        --city "$TS_CITY" \
        --state "$TS_STATE" \
        --country "$TS_COUNTRY" \
        --include-street-address false
    info "Certificate profile '$TS_CERT_PROFILE' created."
fi

###############################################################################
# Step 6 — Assign RBAC roles to the current signed-in user
###############################################################################
info "Step 6: Assigning RBAC roles to current user..."

CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv)
info "Current user object ID: $CURRENT_USER_ID"

_assign_role() {
    local role="$1"
    local scope="$2"
    local existing
    existing=$(az role assignment list \
        --assignee "$CURRENT_USER_ID" \
        --role "$role" \
        --scope "$scope" \
        --query "[0].id" -o tsv 2>/dev/null || true)
    if [[ -n "$existing" ]]; then
        info "  Role '$role' already assigned — skipping."
    else
        run az role assignment create \
            --assignee "$CURRENT_USER_ID" \
            --role "$role" \
            --scope "$scope"
        info "  Role '$role' assigned."
    fi
}

# Signing: allows the user to sign artifacts using this certificate profile
_assign_role \
    "Artifact Signing Certificate Profile Signer" \
    "$TS_ACCOUNT_ID"

# Verification: allows the user (and Ratify) to verify signatures
_assign_role \
    "Artifact Signing Identity Verifier" \
    "$TS_ACCOUNT_ID"

###############################################################################
# Summary
###############################################################################
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Trusted Signing setup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "  Account:         $TS_ACCOUNT_NAME ($TS_RG)"
echo "  Endpoint:        https://${TS_LOCATION}.codesigning.azure.net/"
echo "  Cert Profile:    $TS_CERT_PROFILE (PrivateTrust)"
echo "  Subject DN:"
echo "    CN=$TS_COMMON_NAME"
echo "    O=$TS_ORGANIZATION"
echo "    OU=$TS_ORG_UNIT"
echo "    L=$TS_CITY, S=$TS_STATE, C=$TS_COUNTRY"
echo
echo "Next steps:"
echo "  1. Copy images to ACR:  ./setup-acr.sh"
echo "  2. Sign the image:      notation sign --plugin azure-artifactsigning \\"
echo "       --plugin-config accountName=$TS_ACCOUNT_NAME \\"
echo "       --plugin-config baseUrl=https://${TS_LOCATION}.codesigning.azure.net/ \\"
echo "       --plugin-config certProfile=$TS_CERT_PROFILE \\"
echo "       --id $TS_CERT_PROFILE \\"
echo "       <acr>/nginx:1.29-alpine-signed"
echo "  3. Set up AKS cluster:  ./setup-aks.sh"
echo
