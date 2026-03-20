# defaults.sh
#
# Shared default configuration for the KubeCon EU 2026 artifact-signing demo.
# This file is meant to be sourced by the setup scripts — do not run directly.
#
# All values can be overridden by exporting environment variables before
# running any setup script. Example:
#
#   export ACR_NAME=myacr
#   ./setup-acr.sh
#
# To skip the interactive tenant/subscription prompts, export them upfront:
#   export DEMO_TENANT_ID=<tenant-id>
#   export DEMO_SUBSCRIPTION_ID=<subscription-id>
#   ./setup-acr.sh
#
# Source from a setup script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/defaults.sh"

###############################################################################
# Shared resource group and location
# All services (ACR, AKS, Trusted Signing) are deployed into the same resource
# group and region. Change DEMO_RG / DEMO_LOCATION here to move everything.
# Individual service variables (ACR_RG, AKS_RG, TS_RG, …) inherit these values
# but can still be overridden independently if needed.
###############################################################################
export DEMO_RG="${DEMO_RG:-rg-tsm-kubeconeu2026-demo}"
export DEMO_LOCATION="${DEMO_LOCATION:-westus2}"
export DEMO_TENANT_ID="${DEMO_TENANT_ID:-}"
export DEMO_SUBSCRIPTION_ID="${DEMO_SUBSCRIPTION_ID:-}"

###############################################################################
# Azure Container Registry
###############################################################################
export ACR_NAME="${ACR_NAME:-acrtsmkubeconeu2026demo}"
export ACR_RG="${ACR_RG:-${DEMO_RG}}"
export ACR_SKU="${ACR_SKU:-Premium}"
export ACR_LOCATION="${ACR_LOCATION:-${DEMO_LOCATION}}"
# Derived from ACR_NAME — override explicitly if using a custom login server
export ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}"

###############################################################################
# Azure Kubernetes Service
###############################################################################
export AKS_CLUSTER="${AKS_CLUSTER:-aks-tsm-kubecon-eu-2026-demo}"
export AKS_RG="${AKS_RG:-${DEMO_RG}}"
export AKS_LOCATION="${AKS_LOCATION:-${DEMO_LOCATION}}"

###############################################################################
# Azure Trusted Signing
###############################################################################
export TS_ACCOUNT_NAME="${TS_ACCOUNT_NAME:-sig-tsm-kueu26-demo}"
export TS_RG="${TS_RG:-${DEMO_RG}}"
export TS_LOCATION="${TS_LOCATION:-${DEMO_LOCATION}}"
export TS_SKU="${TS_SKU:-Basic}"
export TS_CERT_PROFILE="${TS_CERT_PROFILE:-cert-tsm-kueu26-demo}"

# Identity validation ID — required for certificate profile creation.
# Find it in the Portal: Trusted Signing → <account> → Identity validation
# The GUID is shown in the identity validation details.
export TS_IDENTITY_VALIDATION_ID="${TS_IDENTITY_VALIDATION_ID:-a768ae25-6256-4366-b38d-67daf7b1dee4}"

# Certificate subject DN — used for display / Ratify policy only (not passed
# to the CLI; the subject is derived from the identity validation at signing time).
export TS_CERT_SUBJECT="${TS_CERT_SUBJECT:-CN=toddysmlive.onmicrosoft.com,OU=Cloud Native Security and Registries,O=toddysmlive.onmicrosoft.com,L=Redmond,ST=Washington,C=US}"

# Microsoft PKI certificate URLs (used by Ratify CertificateStore)
export TS_SIGNING_ROOT_CERT="${TS_SIGNING_ROOT_CERT:-https://www.microsoft.com/pkiops/certs/Microsoft%20Enterprise%20Identity%20Verification%20Root%20Certificate%20Authority%202020.crt}"
export TS_TSA_ROOT_CERT="${TS_TSA_ROOT_CERT:-http://www.microsoft.com/pkiops/certs/microsoft%20identity%20verification%20root%20certificate%20authority%202020.crt}"

###############################################################################
# Log out and log back in to ensure a clean session on the correct subscription
###############################################################################
echo "[INFO] Logging out of Azure CLI to ensure a clean session..."
az logout --verbose 2>/dev/null || true

# Prompt for tenant and subscription if not already set
if [[ -z "$DEMO_TENANT_ID" ]]; then
    read -rp "Enter Azure Tenant ID: " DEMO_TENANT_ID
fi
if [[ -z "$DEMO_SUBSCRIPTION_ID" ]]; then
    read -rp "Enter Azure Subscription ID: " DEMO_SUBSCRIPTION_ID
fi

echo "[INFO] Logging in to Azure CLI (tenant: $DEMO_TENANT_ID)..."
az login --tenant "$DEMO_TENANT_ID"
if ! az account show --query id -o tsv &>/dev/null; then
    echo "[ERROR] No active Azure CLI session after login. Exiting." >&2
    exit 1
fi

echo "[INFO] Setting active subscription to '$DEMO_SUBSCRIPTION_ID'..."
az account set --subscription "$DEMO_SUBSCRIPTION_ID"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION=$(az account show --query name -o tsv)
echo "[INFO] Using subscription: $SUBSCRIPTION ($SUBSCRIPTION_ID)"

###############################################################################
# Ensure the shared resource group exists
# This runs automatically when defaults.sh is sourced, so each setup script
# doesn't need its own resource group creation step.
###############################################################################
if ! az group show --name "$DEMO_RG" &>/dev/null; then
    echo "[INFO] Resource group '$DEMO_RG' not found — creating in '$DEMO_LOCATION'..."
    az group create --name "$DEMO_RG" --location "$DEMO_LOCATION" --output none
    echo "[INFO] Resource group '$DEMO_RG' created."
fi
