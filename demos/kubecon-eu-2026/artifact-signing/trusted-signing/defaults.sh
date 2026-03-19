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
export DEMO_RG="${DEMO_RG:-rg-tsm-signing}"
export DEMO_LOCATION="${DEMO_LOCATION:-westus2}"

###############################################################################
# Azure Container Registry
###############################################################################
export ACR_NAME="${ACR_NAME:-acrtsmpremiumsku}"
export ACR_RG="${ACR_RG:-${DEMO_RG}}"
export ACR_SKU="${ACR_SKU:-Premium}"
export ACR_LOCATION="${ACR_LOCATION:-${DEMO_LOCATION}}"
# Derived from ACR_NAME — override explicitly if using a custom login server
export ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-${ACR_NAME}.azurecr.io}"

###############################################################################
# Azure Kubernetes Service
###############################################################################
export AKS_CLUSTER="${AKS_CLUSTER:-aks-tsm-signing-demo}"
export AKS_RG="${AKS_RG:-${DEMO_RG}}"
export AKS_LOCATION="${AKS_LOCATION:-${DEMO_LOCATION}}"

###############################################################################
# Azure Trusted Signing
###############################################################################
export TS_ACCOUNT_NAME="${TS_ACCOUNT_NAME:-sig-tsm-demo}"
export TS_RG="${TS_RG:-${DEMO_RG}}"
export TS_LOCATION="${TS_LOCATION:-${DEMO_LOCATION}}"
export TS_SKU="${TS_SKU:-Basic}"
export TS_CERT_PROFILE="${TS_CERT_PROFILE:-cert-tsm-demo}"

# Certificate profile subject DN fields
export TS_COMMON_NAME="${TS_COMMON_NAME:-microsoft.onmicrosoft.com}"
export TS_ORGANIZATION="${TS_ORGANIZATION:-microsoft.onmicrosoft.com}"
export TS_ORG_UNIT="${TS_ORG_UNIT:-Cloud Native Security and Registries}"
export TS_CITY="${TS_CITY:-Redmond}"
export TS_STATE="${TS_STATE:-Washington}"
export TS_COUNTRY="${TS_COUNTRY:-US}"

# Assembled certificate subject DN — derived from DN fields above.
# Override explicitly if you need a different format.
export TS_CERT_SUBJECT="${TS_CERT_SUBJECT:-CN=${TS_COMMON_NAME}, O=${TS_ORGANIZATION}, OU=${TS_ORG_UNIT}, L=${TS_CITY}, S=${TS_STATE}, C=${TS_COUNTRY}}"

# Microsoft PKI certificate URLs (used by Ratify CertificateStore)
export TS_SIGNING_ROOT_CERT="${TS_SIGNING_ROOT_CERT:-https://www.microsoft.com/pkiops/certs/Microsoft%20Enterprise%20Identity%20Verification%20Root%20Certificate%20Authority%202020.crt}"
export TS_TSA_ROOT_CERT="${TS_TSA_ROOT_CERT:-http://www.microsoft.com/pkiops/certs/microsoft%20identity%20verification%20root%20certificate%20authority%202020.crt}"
