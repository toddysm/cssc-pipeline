# End-to-End Container Image Signing with Azure Artifact Signing

## Overview

This demo shows a complete end-to-end container image signing and verification
workflow using **Azure Artifact Signing** (formerly Azure Trusted Signing) and
the **Notation CLI** with the `azure-artifactsigning` plugin. Signed images are
then verified at deployment time on **AKS** using **Ratify** and **Gatekeeper**
to enforce a policy that rejects any unsigned or improperly signed workload.

### What is Azure Artifact Signing?

Azure Artifact Signing is a Microsoft fully managed, end-to-end signing solution
that simplifies certificate signing for organizations and developers. Key
characteristics:

- **Zero-touch certificate lifecycle management** inside FIPS 140-2 Level 3
  certified HSMs.
- **Short-lived certificates** (3-day validity) — timestamps are therefore
  critical for long-term signature validation.
- **Content-confidential signing** — only the digest of the artifact leaves the
  endpoint; the artifact itself never leaves your environment.
- **Timestamping service** at `http://timestamp.acs.microsoft.com/`.
- Integrates with Notation, SignTool, GitHub Actions, Azure DevOps, and more.

Service documentation: <https://learn.microsoft.com/en-us/azure/artifact-signing/>  
Notation plugin repo: <https://github.com/Azure/artifact-signing-notation-plugin>

---

## Architecture

```
Developer workstation
  └─ notation sign  ──────────────────────────────────────────────────────────┐
       │  azure-artifactsigning plugin                                        │
       ├─ digest sent to Azure Artifact Signing ──► HSM signs ──► signature  │
       └─ signature pushed to ACR                                             │
                                                                              ▼
AKS cluster                                                            ACR registry
  ├─ OPA Gatekeeper  (policy enforcement)                      wabbitregistry.azurecr.io
  └─ Ratify           (signature verification)       net-monitor:v1 + attached signature
       └─ notation verify (azure-artifactsigning plugin)
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Azure CLI | ≥ 2.60 | `brew install azure-cli` |
| Notation CLI | ≥ 1.1 | <https://notaryproject.dev/docs/installation/notation/> |
| `azure-artifactsigning` plugin | ≥ 1.1.0 | see Step 5 below |
| Docker | any | `brew install docker` |
| `kubectl` | any | `brew install kubectl` |
| `helm` | ≥ 3 | `brew install helm` |

You also need:
- An Azure subscription with an ACR instance (Premium SKU for OCI artifact support).
- An AKS cluster with OIDC issuer and workload identity enabled.

---

## Environment Variables

Set these before running any step:

```bash
# Azure Artifact Signing
export TS_ACCT_NAME=tsdemo
export TS_ACCT_URL=https://eus.codesigning.azure.net/   # matches the region of your account
export TS_CERT_PROFILE=tsdemoprofile
export TS_TSA_URL=http://timestamp.acs.microsoft.com/
export TS_SIGNING_ROOT_CERT="https://www.microsoft.com/pkiops/certs/Microsoft%20Enterprise%20Identity%20Verification%20Root%20Certificate%20Authority%202020.crt"
export TS_TSA_ROOT_CERT="http://www.microsoft.com/pkiops/certs/microsoft%20identity%20verification%20root%20certificate%20authority%202020.crt"

# ACR and image
export ACR_LOGIN_SERVER=wabbitregistry.azurecr.io
export REPOSITORY=net-monitor
export IMAGE=wabbitregistry.azurecr.io/net-monitor:v1

# Notation trust stores
export SIGNING_TRUST_STORE=myRootCerts
export TSA_TRUST_STORE=myTsaRootCerts
export TS_CERT_SUBJECT="CN=microsoft.onmicrosoft.com, O=microsoft.onmicrosoft.com, OU=tsdemo, S=Washington, C=US"

# AKS
export AKS_CLUSTER=<your-aks-cluster-name>
export AKS_RG=<your-aks-resource-group>
export ACR_RG=<your-acr-resource-group>
```

---

## Step 1 — Create the Artifact Signing Account

### 1.1 Register the resource provider

The Artifact Signing resource provider (`Microsoft.CodeSigning`) must be
registered in your Azure subscription before any resources can be created.

```bash
az provider register --namespace Microsoft.CodeSigning

# Wait until RegistrationState is "Registered"
az provider show --namespace Microsoft.CodeSigning --query "registrationState" -o tsv
```

> **Tip:** Registration can take a few minutes. Re-run the `show` command
> until the output is `Registered`.

### 1.2 Create the account

Artifact Signing accounts are available in the following regions (partial list):

| Region | Endpoint |
|--------|----------|
| East US | `https://eus.codesigning.azure.net` |
| West Europe | `https://weu.codesigning.azure.net` |
| North Europe | `https://neu.codesigning.azure.net` |
| West US 2 | `https://wus2.codesigning.azure.net` |

Account naming constraints: 3–24 alphanumeric characters, globally unique,
starts with a letter, ends with a letter or digit, no consecutive hyphens.

```bash
export TS_RG=artifact-signing-rg
export TS_LOCATION=eastus

az group create --name $TS_RG --location $TS_LOCATION

az codesigning account create \
  --name $TS_ACCT_NAME \
  --resource-group $TS_RG \
  --location $TS_LOCATION \
  --sku Basic
```

> **Note:** The `Basic` SKU is sufficient for Private Trust certificates used
> in this demo. Use `Premium` for Public Trust certificates.

### 1.3 Create an identity validation

Identity validation must be completed in the **Azure portal**; it cannot be
done via the CLI.

1. Go to the Azure portal and open your new Artifact Signing account.
2. Confirm you are assigned the **Artifact Signing Identity Verifier** role.
3. Select **Identity validations → New identity → Private**.
4. Fill in the organization details (name, email, address, etc.).
5. Select **Create** and wait for the status to change to **Completed**.
   Processing takes 1–7 business days for Public Trust; Private Trust is
   usually instant.

> **Demo shortcut:** For a demo with a private trust certificate, use
> **Private** validation. This skips the external identity verification step
> and completes immediately within your Entra tenant.

### 1.4 Create a certificate profile

```bash
az codesigning certificate-profile create \
  --account-name $TS_ACCT_NAME \
  --resource-group $TS_RG \
  --profile-name $TS_CERT_PROFILE \
  --profile-type PrivateTrust \
  --identity-validation-id <identity-validation-resource-id>
```

Retrieve the identity validation resource ID from the portal or:

```bash
az codesigning account show \
  --name $TS_ACCT_NAME \
  --resource-group $TS_RG \
  --query "id" -o tsv
```

### 1.5 Assign the signer role

The principal that will sign (typically your user or a service principal) must
be assigned the **Artifact Signing Certificate Profile Signer** role on the
certificate profile resource.

```bash
export SIGNER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
export CERT_PROFILE_ID=$(az codesigning certificate-profile show \
  --account-name $TS_ACCT_NAME \
  --resource-group $TS_RG \
  --profile-name $TS_CERT_PROFILE \
  --query id -o tsv)

az role assignment create \
  --role "Artifact Signing Certificate Profile Signer" \
  --assignee $SIGNER_PRINCIPAL_ID \
  --scope $CERT_PROFILE_ID
```

---

## Step 2 — Install Notation and the Plugin

### 2.1 Install the Notation CLI

```bash
# macOS (Homebrew)
brew install notation

# verify
notation version
```

### 2.2 Install the `azure-artifactsigning` plugin

```bash
# Linux amd64
notation plugin install \
  --url https://github.com/Azure/artifact-signing-notation-plugin/releases/download/v1.1.0/notation-azure-artifactsigning_1.1.0_linux_amd64.tar.gz \
  --sha256sum 459075a5cdadcdba334b728838d617fa330f19b45848ba993a4d2a061f49d4ac

# macOS arm64
notation plugin install \
  --url https://github.com/Azure/artifact-signing-notation-plugin/releases/download/v1.1.0/notation-azure-artifactsigning_1.1.0_darwin_arm64.tar.gz \
  --sha256sum f9ff085c86474b2371cf3acd70e24f067df2f5c2c3240e101957d99b55d480f0

# confirm
notation plugin ls
```

The plugin name shown by `notation plugin ls` must be `azure-artifactsigning`.

---

## Step 3 — Sign the Container Image

Authenticate to ACR and Azure, then sign:

```bash
az login
az acr login --name $ACR_LOGIN_SERVER

# Download the TSA root certificate (needed for timestamping)
curl -o msft-tsa-root-certificate-authority-2020.crt "$TS_TSA_ROOT_CERT"

# Sign
notation sign \
  --signature-format cose \
  --timestamp-url "$TS_TSA_URL" \
  --timestamp-root-cert msft-tsa-root-certificate-authority-2020.crt \
  --id "$TS_CERT_PROFILE" \
  --plugin azure-artifactsigning \
  --plugin-config accountName="$TS_ACCT_NAME" \
  --plugin-config baseUrl="$TS_ACCT_URL" \
  --plugin-config certProfile="$TS_CERT_PROFILE" \
  "$IMAGE"
```

> **How it works:** The plugin sends only the image digest to the Artifact
> Signing HSM. The HSM signs the digest and returns a signature. The signature
> is timestamped by the Azure TSA so it remains valid after the certificate
> expires (3-day validity window).

### 3.1 Inspect the signature

```bash
# List attached signatures
notation ls "$IMAGE"

# Inspect the full signature envelope
notation inspect "$IMAGE"
```

---

## Step 4 — Verify the Image Locally

### 4.1 Set up the trust store

Download the signing root CA and add it together with the TSA root:

```bash
curl -o msft-root-certificate-authority-2020.crt "$TS_SIGNING_ROOT_CERT"

# Add signing root CA
notation cert add \
  --type ca \
  --store "$SIGNING_TRUST_STORE" \
  msft-root-certificate-authority-2020.crt

# Add TSA root CA
notation cert add \
  --type tsa \
  --store "$TSA_TRUST_STORE" \
  msft-tsa-root-certificate-authority-2020.crt

# Confirm both are present
notation cert ls
```

### 4.2 Configure the trust policy

Import `trusted-signing/trustpolicy.json`:

```bash
notation policy import trusted-signing/trustpolicy.json
notation policy show
```

The trust policy (`trustpolicy.json`) ties the registry scope to the trust
stores and restricts signatures to the expected certificate subject:

```json
{
    "version": "1.0",
    "trustPolicies": [
        {
            "name": "myPolicy",
            "registryScopes": [ "wabbitregistry.azurecr.io/net-monitor" ],
            "signatureVerification": { "level": "strict" },
            "trustStores": [ "ca:myRootCerts", "tsa:myTsaRootCerts" ],
            "trustedIdentities": [
                "x509.subject: CN=microsoft.onmicrosoft.com, O=microsoft.onmicrosoft.com, OU=tsdemo, S=Washington, C=US"
            ]
        }
    ]
}
```

### 4.3 Verify

```bash
notation verify "$IMAGE"
```

A successful verification prints:
```
Successfully verified signature for wabbitregistry.azurecr.io/net-monitor@sha256:<digest>
```

---

## Step 5 — Enforce Signatures on AKS with Ratify and Gatekeeper

This section shows how to enforce a policy on an AKS cluster so that only
images with a valid Artifact Signing signature can be deployed.

### 5.1 Connect to the AKS cluster

```bash
az aks get-credentials \
  --name "$AKS_CLUSTER" \
  --resource-group "$AKS_RG"
```

### 5.2 Install OPA Gatekeeper

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set enableExternalData=true \
  --set validatingWebhookTimeoutSeconds=5 \
  --set mutatingWebhookTimeoutSeconds=2
```

### 5.3 Install Ratify

```bash
helm repo add ratify https://ratify-project.github.io/ratify
helm repo update

# Grant AKS kubelet identity pull access to ACR
export KUBELET_CLIENT_ID=$(az aks show \
  --name "$AKS_CLUSTER" \
  --resource-group "$AKS_RG" \
  --query "identityProfile.kubeletidentity.clientId" -o tsv)

az role assignment create \
  --role AcrPull \
  --assignee "$KUBELET_CLIENT_ID" \
  --scope "$(az acr show --name $ACR_LOGIN_SERVER --resource-group $ACR_RG --query id -o tsv)"

helm install ratify ratify/ratify \
  --namespace gatekeeper-system \
  --set featureFlags.RATIFY_CERT_ROTATION=true \
  --set akvCertConfig.enabled=false
```

### 5.4 Configure Ratify with the Artifact Signing trust store

Create a `VerifyConfig` that points Ratify at the Artifact Signing root CA:

```bash
# Base64-encode the root certificate
ROOT_CERT_B64=$(base64 -w0 msft-root-certificate-authority-2020.crt)
TSA_CERT_B64=$(base64 -w0 msft-tsa-root-certificate-authority-2020.crt)

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
      $(cat msft-root-certificate-authority-2020.crt)
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
      $(cat msft-tsa-root-certificate-authority-2020.crt)
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
            - "*"
          signatureVerification:
            level: strict
          trustStores:
            - "ca:caCerts"
            - "tsa:tsaCerts"
          trustedIdentities:
            - "x509.subject: $TS_CERT_SUBJECT"
EOF
```

### 5.5 Apply the Gatekeeper constraint

```bash
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
        import future.keywords.if
        violation[{"msg": msg}] if {
          subject := input.review.object.spec.containers[_].image
          response := external_data({"provider": "ratify", "keys": [subject]})
          result := response.responses[_]
          result[0] == subject
          result[1].isSuccess == false
          msg := sprintf("Signature verification failed for image %v: %v", [subject, result[1].verifierReports])
        }
---
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
```

### 5.6 Test the policy

**Deploy a signed image (should succeed):**

```bash
kubectl run signed-demo \
  --image="$IMAGE" \
  --restart=Never

kubectl get pod signed-demo
```

**Deploy an unsigned image (should be rejected):**

```bash
kubectl run unsigned-demo \
  --image=nginx:latest \
  --restart=Never
```

Expected output:
```
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
  Signature verification failed for image nginx:latest: ...
```

---

## Troubleshooting

| Symptom | Likely cause | Remedy |
|---------|-------------|--------|
| `notation sign` fails with `403 Forbidden` | Endpoint region mismatch or missing signer role | Verify `TS_ACCT_URL` matches the account region; check role assignment |
| `notation verify` fails with `certificate expired` | TSA timestamp not applied | Re-sign with `--timestamp-url` and `--timestamp-root-cert` |
| Ratify rejects all images including signed ones | Wrong certificate subject in `trustedIdentities` | Run `notation inspect $IMAGE` and copy the exact subject string |
| Gatekeeper webhook times out | Ratify pod not ready | Check `kubectl get pods -n gatekeeper-system` and Ratify logs |
| `az provider register` stuck | Normal; can take a few minutes | Retry `az provider show --namespace Microsoft.CodeSigning --query registrationState` |

---

## References

- [Azure Artifact Signing overview](https://learn.microsoft.com/en-us/azure/artifact-signing/overview)
- [Quickstart: Set up Artifact Signing](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart)
- [Artifact Signing Notation Plugin (GitHub)](https://github.com/Azure/artifact-signing-notation-plugin)
- [Notary Project / Notation](https://notaryproject.dev/)
- [Ratify](https://ratify.dev/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [Demo script](trusted-signing/demo-trusted-signing.sh)
