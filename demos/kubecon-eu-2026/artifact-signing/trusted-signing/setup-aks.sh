#!/usr/bin/env bash
# setup-aks.sh
#
# Creates and configures an AKS cluster for the KubeCon EU 2026 artifact-signing demo.
#
# What this script does:
#   1. Verify Azure login
#   2. Create AKS cluster (OIDC + workload identity enabled)
#   3. Grant kubelet identity AcrPull on the ACR
#   4. Get credentials (kubectl)
#   5. Install OPA Gatekeeper via Helm
#   6. Install Ratify via Helm
#   7. Configure Ratify: CertificateStore (CA + TSA) and Notation Verifier
#   8. Apply Gatekeeper ConstraintTemplate + RatifyVerification constraint
#
# Usage:
#   Export the required environment variables (see below), then run:
#     chmod +x setup-aks.sh
#     ./setup-aks.sh
#
# Required environment variables:
#   AKS_CLUSTER        - Name of the AKS cluster to create
#   AKS_RG             - Resource group for the AKS cluster
#   AKS_LOCATION       - Azure region for the AKS cluster (e.g. westus2)
#   ACR_LOGIN_SERVER   - ACR login server (e.g. acrtsmkubeconeu2026demo.azurecr.io)
#   TS_CERT_SUBJECT    - Expected certificate subject for Notation trust policy
#                        e.g. "CN=..., O=..., OU=..., L=..., S=..., C=US"
#   TS_SIGNING_ROOT_CERT - URL of the Artifact Signing root CA certificate
#   TS_TSA_ROOT_CERT     - URL of the Artifact Signing TSA root CA certificate

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
REQUIRED_VARS=(
    AKS_CLUSTER AKS_RG AKS_LOCATION
    ACR_LOGIN_SERVER
    TS_CERT_SUBJECT TS_SIGNING_ROOT_CERT TS_TSA_ROOT_CERT
)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Required environment variable \$$var is not set."
        exit 1
    fi
done

###############################################################################
# Step 1 — Register required resource providers
###############################################################################
info "Step 1: Registering required Azure resource providers..."
for _rp in Microsoft.ContainerService Microsoft.ContainerRegistry; do
    _state=$(az provider show --namespace "$_rp" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
    if [[ "$_state" == "Registered" ]]; then
        info "  $_rp is already registered."
    else
        info "  Registering $_rp..."
        run az provider register --namespace "$_rp" --wait
        info "  $_rp registered."
    fi
done

###############################################################################
# Step 2 — Create the AKS cluster
###############################################################################
info "Step 2: Creating AKS cluster '$AKS_CLUSTER' in resource group '$AKS_RG'..."

if az aks show --name "$AKS_CLUSTER" --resource-group "$AKS_RG" &>/dev/null; then
    info "Cluster '$AKS_CLUSTER' already exists — skipping creation."
else
    run az group create \
        --name "$AKS_RG" \
        --location "$AKS_LOCATION"

    run az aks create \
        --name "$AKS_CLUSTER" \
        --resource-group "$AKS_RG" \
        --location "$AKS_LOCATION" \
        --node-count 2 \
        --node-vm-size Standard_DS2_v2 \
        --enable-oidc-issuer \
        --enable-workload-identity \
        --generate-ssh-keys

    info "Cluster '$AKS_CLUSTER' created."
fi

# Disable Azure Policy add-on if enabled — it takes over Gatekeeper and blocks
# custom ConstraintTemplates via the byovalidation.policy.azure.com webhook.
_az_policy=$(az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$AKS_RG" \
    --query "addonProfiles.azurepolicy.enabled" -o tsv 2>/dev/null || echo "false")
if [[ "$_az_policy" == "true" ]]; then
    warn "Azure Policy add-on is enabled — disabling to allow custom Gatekeeper policies..."
    run az aks disable-addons \
        --addons azure-policy \
        --name "$AKS_CLUSTER" \
        --resource-group "$AKS_RG"
    info "Azure Policy add-on disabled."
fi

###############################################################################
# Step 3 — Grant kubelet identity AcrPull on the ACR
###############################################################################
info "Step 3: Granting kubelet identity AcrPull on ACR '$ACR_LOGIN_SERVER'..."

KUBELET_CLIENT_ID=$(az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$AKS_RG" \
    --query "identityProfile.kubeletidentity.clientId" -o tsv)

ACR_ID=$(az acr show \
    --name "${ACR_LOGIN_SERVER%%.*}" \
    --query id -o tsv)

EXISTING_ASSIGNMENT=$(az role assignment list \
    --assignee "$KUBELET_CLIENT_ID" \
    --role AcrPull \
    --scope "$ACR_ID" \
    --query "[0].id" -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING_ASSIGNMENT" ]]; then
    info "AcrPull role already assigned — skipping."
else
    run az role assignment create \
        --role AcrPull \
        --assignee "$KUBELET_CLIENT_ID" \
        --scope "$ACR_ID"
    info "AcrPull role assigned to kubelet identity."
fi

###############################################################################
# Step 4 — Get credentials
###############################################################################
info "Step 4: Fetching kubeconfig for cluster '$AKS_CLUSTER'..."
run az aks get-credentials \
    --name "$AKS_CLUSTER" \
    --resource-group "$AKS_RG" \
    --overwrite-existing

info "Current kubectl context: $(kubectl config current-context)"

###############################################################################
# Step 5 — Install OPA Gatekeeper
###############################################################################
info "Step 5: Installing OPA Gatekeeper..."

helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update
helm repo update

if helm status gatekeeper --namespace gatekeeper-system &>/dev/null; then
    info "Gatekeeper already installed — skipping."
else
    run helm install gatekeeper gatekeeper/gatekeeper \
        --namespace gatekeeper-system \
        --create-namespace \
        --set enableExternalData=true \
        --set validatingWebhookTimeoutSeconds=5 \
        --set mutatingWebhookTimeoutSeconds=2 \
        --wait
    info "Gatekeeper installed."
fi

###############################################################################
# Step 6 — Install Ratify
###############################################################################
info "Step 6: Installing Ratify..."

helm repo add ratify https://notaryproject.github.io/ratify --force-update
helm repo update

if helm status ratify --namespace gatekeeper-system &>/dev/null; then
    info "Ratify already installed — skipping."
else
    run helm install ratify ratify/ratify \
        --namespace gatekeeper-system \
        --set featureFlags.RATIFY_CERT_ROTATION=true \
        --set akvCertConfig.enabled=false \
        --set mutationProvider.enable=false \
        --wait
    info "Ratify installed."
fi

# The Helm chart creates a default verifier-notation CR with the legacy
# verificationCerts path set. Remove it so our Step 7 CR (which uses only
# the new verificationCertStores format) does not conflict with it.
if kubectl get verifier verifier-notation -n gatekeeper-system &>/dev/null; then
    info "Removing default Ratify verifier-notation CR (will be replaced in Step 7)..."
    kubectl delete verifier verifier-notation -n gatekeeper-system
fi

###############################################################################
# Step 7 — Download root certificates and configure Ratify
###############################################################################
info "Step 7: Configuring Ratify with ORAS store, Artifact Signing trust store, and Notation Verifier..."

info "Configuring Ratify ORAS store with workload identity auth..."
# The Helm chart creates a default store-oras CR without the last-applied-configuration
# annotation; delete it first so kubectl apply creates a clean resource.
if kubectl get store store-oras -n gatekeeper-system &>/dev/null; then
    kubectl delete store store-oras -n gatekeeper-system
fi
kubectl apply -f - <<EOF
apiVersion: config.ratify.deislabs.io/v1beta1
kind: Store
metadata:
  name: store-oras
  namespace: gatekeeper-system
spec:
  name: oras
  parameters:
    authProvider:
      name: azureManagedIdentity
      clientID: "${KUBELET_CLIENT_ID}"
EOF

SIGNING_CERT_FILE="msft-root-certificate-authority-2020.crt"
TSA_CERT_FILE="msft-tsa-root-certificate-authority-2020.crt"

info "Downloading Artifact Signing root CA..."
run curl -sLo "$SIGNING_CERT_FILE" "$TS_SIGNING_ROOT_CERT"
run openssl x509 -inform DER -in "$SIGNING_CERT_FILE" -out "$SIGNING_CERT_FILE"

info "Downloading Artifact Signing TSA root CA..."
run curl -sLo "$TSA_CERT_FILE" "$TS_TSA_ROOT_CERT"
run openssl x509 -inform DER -in "$TSA_CERT_FILE" -out "$TSA_CERT_FILE"

SIGNING_CERT_PEM=$(cat "$SIGNING_CERT_FILE")
TSA_CERT_PEM=$(cat "$TSA_CERT_FILE")

kubectl apply -f - <<EOF
apiVersion: config.ratify.deislabs.io/v1beta1
kind: CertificateStore
metadata:
  name: artifact-signing-root
  namespace: gatekeeper-system
spec:
  provider: inline
  parameters:
    value: |
$(echo "$SIGNING_CERT_PEM" | sed 's/^/      /')
---
apiVersion: config.ratify.deislabs.io/v1beta1
kind: CertificateStore
metadata:
  name: artifact-signing-tsa-root
  namespace: gatekeeper-system
spec:
  provider: inline
  parameters:
    value: |
$(echo "$TSA_CERT_PEM" | sed 's/^/      /')
---
apiVersion: config.ratify.deislabs.io/v1beta1
kind: Verifier
metadata:
  name: verifier-notation
  namespace: gatekeeper-system
spec:
  name: notation
  artifactTypes: application/vnd.cncf.notary.signature
  parameters:
    verificationCertStores:
      ca:
        caCerts:
          - artifact-signing-root
      tsa:
        tsaCerts:
          - artifact-signing-tsa-root
    trustPolicyDoc:
      version: "1.0"
      trustPolicies:
        - name: default
          registryScopes:
            - "${ACR_LOGIN_SERVER}/nginx"
          signatureVerification:
            level: strict
          trustStores:
            - "ca:caCerts"
            - "tsa:tsaCerts"
          trustedIdentities:
            - "x509.subject: ${TS_CERT_SUBJECT}"
EOF

info "Ratify CertificateStore and Verifier configured."

###############################################################################
# Step 8 — Apply Gatekeeper ConstraintTemplate and constraint
###############################################################################
info "Step 8: Applying Gatekeeper ConstraintTemplate and RatifyVerification constraint..."

kubectl apply -f - <<'EOF'
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: ratifyverification
spec:
  crd:
    spec:
      names:
        kind: RatifyVerification
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package ratifyverification
        violation[{"msg": msg}] {
          subject := input.review.object.spec.containers[_].image
          response := external_data({"provider": "ratify", "keys": [subject]})
          result := response.responses[_]
          result[0] == subject
          result[1].isSuccess == false
          msg := sprintf("Signature verification failed for image %v: %v", [subject, result[1].verifierReports])
        }
EOF

info "Waiting for RatifyVerification CRD to be established..."
# Gatekeeper names constraint CRDs after the lowercase ConstraintTemplate name
# (non-pluralized): ratifyverification.constraints.gatekeeper.sh
_crd="ratifyverification.constraints.gatekeeper.sh"
for _i in $(seq 1 30); do
    if kubectl get crd "$_crd" &>/dev/null; then
        kubectl wait --for=condition=established "crd/$_crd" --timeout=60s
        break
    fi
    [[ $_i -eq 30 ]] && { error "Timed out waiting for CRD $_crd"; exit 1; }
    sleep 4
done

kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RatifyVerification
metadata:
  name: require-notation-signature
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - default
EOF

info "Gatekeeper constraint applied."

###############################################################################
# Summary
###############################################################################
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  AKS cluster setup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "  Cluster:       $AKS_CLUSTER ($AKS_RG)"
echo "  ACR:           $ACR_LOGIN_SERVER"
echo "  Gatekeeper:    $(helm status gatekeeper -n gatekeeper-system --short 2>/dev/null || echo 'installed')"
echo "  Ratify:        $(helm status ratify -n gatekeeper-system --short 2>/dev/null || echo 'installed')"
echo
echo "Next steps:"
echo "  1. Sign your image:   notation sign ... <image>"
echo "  2. Test admission:    kubectl run signed --image=<signed-image>"
echo "  3. Test rejection:    kubectl run unsigned --image=nginx:latest"
echo
