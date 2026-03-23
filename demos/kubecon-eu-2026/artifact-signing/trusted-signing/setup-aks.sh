#!/usr/bin/env bash
# setup-aks.sh
#
# Creates and configures an AKS cluster for the KubeCon EU 2026 artifact-signing demo.
#
# What this script does:
#   1. Verify Azure login
#   2. Create AKS cluster (OIDC + workload identity enabled)
#   3. Grant kubelet identity AcrPull on the ACR (for node image pulls)
#   3b. Create Ratify User-Assigned Managed Identity with workload identity federation
#   4. Get credentials (kubectl)
#   5. Install OPA Gatekeeper via Helm
#   6. Install Ratify via Helm (with workload identity client ID)
#   7. Configure Ratify: store-oras (azureWorkloadIdentity), CertificateStore (CA + TSA), Notation Verifier
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
# Step 3b — Create Ratify Managed Identity and configure Workload Identity
###############################################################################
info "Step 3b: Setting up Ratify workload identity..."

if az identity show --name "$RATIFY_MI_NAME" --resource-group "$AKS_RG" &>/dev/null; then
    info "Managed identity '$RATIFY_MI_NAME' already exists — skipping creation."
else
    run az identity create \
        --name "$RATIFY_MI_NAME" \
        --resource-group "$AKS_RG" \
        --location "$AKS_LOCATION"
    info "Managed identity '$RATIFY_MI_NAME' created."
fi

RATIFY_MI_CLIENT_ID=$(az identity show \
    --name "$RATIFY_MI_NAME" \
    --resource-group "$AKS_RG" \
    --query clientId -o tsv)

RATIFY_MI_PRINCIPAL_ID=$(az identity show \
    --name "$RATIFY_MI_NAME" \
    --resource-group "$AKS_RG" \
    --query principalId -o tsv)

info "Granting AcrPull to Ratify managed identity on '$ACR_LOGIN_SERVER'..."
EXISTING_RATIFY_ASSIGNMENT=$(az role assignment list \
    --assignee "$RATIFY_MI_PRINCIPAL_ID" \
    --role AcrPull \
    --scope "$ACR_ID" \
    --query "[0].id" -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING_RATIFY_ASSIGNMENT" ]]; then
    info "AcrPull role already assigned to Ratify MI — skipping."
else
    run az role assignment create \
        --role AcrPull \
        --assignee-object-id "$RATIFY_MI_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --scope "$ACR_ID"
    info "AcrPull role assigned to Ratify managed identity."
fi

info "Getting AKS OIDC issuer URL..."
OIDC_ISSUER=$(az aks show \
    --name "$AKS_CLUSTER" \
    --resource-group "$AKS_RG" \
    --query "oidcIssuerProfile.issuerUrl" -o tsv)
info "OIDC issuer: $OIDC_ISSUER"

# The Ratify Helm chart creates the service account "ratify" in gatekeeper-system.
# The federated credential links the AKS OIDC issuer + that service account to
# the managed identity, so Ratify pods can obtain Azure tokens automatically.
FEDERATED_CRED_NAME="ratify-federated-cred"
if az identity federated-credential show \
    --name "$FEDERATED_CRED_NAME" \
    --identity-name "$RATIFY_MI_NAME" \
    --resource-group "$AKS_RG" &>/dev/null; then
    info "Federated credential '$FEDERATED_CRED_NAME' already exists — skipping."
else
    run az identity federated-credential create \
        --name "$FEDERATED_CRED_NAME" \
        --identity-name "$RATIFY_MI_NAME" \
        --resource-group "$AKS_RG" \
        --issuer "$OIDC_ISSUER" \
        --subject "system:serviceaccount:gatekeeper-system:ratify" \
        --audience "api://AzureADTokenExchange"
    info "Federated credential created for Ratify service account."
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
    info "Ratify already installed — skipping Helm install."
    info "Ensuring workload identity client ID is set on the Ratify service account..."
    kubectl annotate serviceaccount ratify \
        -n gatekeeper-system \
        azure.workload.identity/client-id="$RATIFY_MI_CLIENT_ID" \
        --overwrite
else
    run helm install ratify ratify/ratify \
        --namespace gatekeeper-system \
        --set featureFlags.RATIFY_CERT_ROTATION=true \
        --set akvCertConfig.enabled=false \
        --set mutationProvider.enable=false \
        --set azureWorkloadIdentity.clientId="$RATIFY_MI_CLIENT_ID" \
        --wait
    info "Ratify installed."
fi

# Always clean up mutation CRs — the Helm chart creates them regardless of the
# mutationProvider.enable flag, and helm upgrade recreates them. Purge them
# every run so the Gatekeeper mutation webhook never references a Ratify
# provider that isn't running.
info "Removing Ratify mutation CRs (mutation not used in this demo)..."
kubectl delete provider ratify-mutation-provider \
    -n gatekeeper-system --ignore-not-found
kubectl delete assignmetadata \
    -n gatekeeper-system -l app.kubernetes.io/name=ratify --ignore-not-found
kubectl delete assign \
    mutate-cronjob-image mutate-cronjob-image-ephemeral mutate-cronjob-image-init \
    mutate-pod-image mutate-pod-image-ephemeral mutate-pod-image-init \
    mutate-workload-image mutate-workload-image-ephemeral mutate-workload-image-init \
    --ignore-not-found

# Remove the default verifier-notation CR created by the Helm chart — it uses
# the legacy verificationCerts path; our Step 7 CR uses verificationCertStores.
if kubectl get verifier verifier-notation -n gatekeeper-system &>/dev/null; then
    info "Removing default Ratify verifier-notation CR (will be replaced in Step 7)..."
    kubectl delete verifier verifier-notation -n gatekeeper-system
fi

###############################################################################
# Step 7 — Download root certificates and configure Ratify
###############################################################################
info "Step 7: Configuring Ratify with ORAS store, Artifact Signing trust store, and Notation Verifier..."

info "Configuring Ratify ORAS store with workload identity auth..."
# The azureWorkloadIdentity auth provider uses the federated credential created
# in Step 3b to exchange the Ratify pod's service account token for an Azure
# access token, which is then used to authenticate to ACR. No secrets or
# short-lived ACR tokens need to be managed manually.

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
      name: azureWorkloadIdentity
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
EOF

info "Waiting for CertificateStore CRs to be reconciled..."
# CertificateStore CRs have no standard readiness condition; poll the
# isSuccess field in the status block that Ratify sets after reconciliation.
for _cr in artifact-signing-root artifact-signing-tsa-root; do
    for _i in $(seq 1 30); do
        _ok=$(kubectl get certificatestore "$_cr" \
            -n gatekeeper-system \
            -o jsonpath='{.status.error}' 2>/dev/null || echo "not-found")
        # An empty status.error means the controller reconciled successfully
        if [[ "$_ok" == "" ]]; then
            info "  CertificateStore '$_cr' reconciled successfully."
            break
        fi
        [[ $_i -eq 30 ]] && { error "Timed out waiting for CertificateStore '$_cr'"; exit 1; }
        sleep 4
    done
done

kubectl apply -f - <<EOF
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

        # Collect images from all container types (fail-closed: any unverified image blocks)
        _images[img] {
          img := input.review.object.spec.containers[_].image
        }
        _images[img] {
          img := input.review.object.spec.initContainers[_].image
        }
        _images[img] {
          img := input.review.object.spec.ephemeralContainers[_].image
        }

        # Case 1: Ratify explicitly reports verification failure
        violation[{"msg": msg}] {
          img := _images[_]
          response := external_data({"provider": "ratify-provider", "keys": [img]})
          result := response.responses[_]
          result[0] == img
          result[1].isSuccess == false
          msg := sprintf("Signature verification failed for image %v: %v", [img, result[1].verifierReports])
        }

        # Case 2: Ratify returned an error for the image (e.g., can't pull referrers,
        # registry auth failure). Treat as a denial to keep the policy fail-closed.
        violation[{"msg": msg}] {
          img := _images[_]
          response := external_data({"provider": "ratify-provider", "keys": [img]})
          err := response.errors[_]
          err[0] == img
          msg := sprintf("Ratify error verifying image %v: %v", [img, err[1]])
        }

        # Case 3: The ExternalData call itself failed (Gatekeeper can't reach Ratify).
        # Deny to keep the policy fail-closed.
        violation[{"msg": msg}] {
          img := _images[_]
          response := external_data({"provider": "ratify-provider", "keys": [img]})
          response.system_error != ""
          msg := sprintf("Ratify system error for image %v: %v", [img, response.system_error])
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
