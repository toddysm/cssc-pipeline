#!/usr/bin/env bash

#################################
# include the -=magic=-
# you can pass command line args
#
# example:
# to disable simulated typing
# . ../demo-magic.sh -d
#
# pass -h to see all options
#################################
. ../demo-magic.sh -n


########################
# Configure the options
########################

#
# speed at which to simulate typing. bigger num = faster
#
TYPE_SPEED=100

#
# custom prompt
#
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
#DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"
DEMO_PROMPT="${GREEN}$ ${COLOR_RESET}"

# text color
# DEMO_CMD_COLOR=$BLACK

# Log in to Azure
echo "[INFO] Logging out of Azure CLI to ensure a clean session..."
az logout --verbose 2>/dev/null || true

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

# clean up any previous runs
SIGNING_TRUST_STORE=kubeconDemoSigningRootCerts
TSA_TRUST_STORE=kubeconDemoTsaRootCerts
notation plugin uninstall azure-artifactsigning --yes
notation cert delete --type ca --store $SIGNING_TRUST_STORE --all --yes
notation cert delete --type tsa --store $TSA_TRUST_STORE --all --yes
rm -f ~/.config/notation/trustpolicy.json
rm -f ~/Library/Application\ Support/notation/trustpolicy.json
rm -f msft-root-certificate-authority-2020.crt msft-tsa-root-certificate-authority-2020.crt
kubectl delete -f nginx-signed-demo.yaml --ignore-not-found
kubectl delete -f nginx-unsigned-demo.yaml --ignore-not-found

# Delete all referrers (signatures) attached to the signed image
_signed_image="acrtsmkubeconeu2026demo.azurecr.io/nginx:1.29-alpine-signed"
echo "[INFO] Deleting referrers for $_signed_image..."
az acr login --name acrtsmkubeconeu2026demo 2>/dev/null || true
_digests=$(oras discover --format json "$_signed_image" 2>/dev/null \
    | python3 -c "import json,sys; [print(m['digest']) for m in json.load(sys.stdin).get('manifests',[])]" 2>/dev/null)
if [[ -z "$_digests" ]]; then
    echo "[INFO] No referrers found for $_signed_image."
else
    while IFS= read -r _digest; do
        [[ -z "$_digest" ]] && continue
        echo "[INFO]   Deleting referrer: $_digest"
        az acr manifest delete \
            --name "nginx@${_digest}" \
            --registry "acrtsmkubeconeu2026demo" \
            --yes || true
    done <<< "$_digests"
    echo "[INFO] Referrer cleanup complete."
fi


# hide the evidence
clear

# enters interactive mode and allows newly typed command to be executed
cmd

# print and execute immediately: ls -l

# Set up env variables

pe "# Set up variables for Trusted Signing"
pe "TS_ACCT_NAME=sig-tsm-kueu26-demo"
pe "TS_ACCT_URL=https://wus2.codesigning.azure.net/"
pe "TS_CERT_PROFILE=cert-tsm-kueu26-demo"
pe "TS_TSA_URL=http://timestamp.acs.microsoft.com/"
pe "TS_SIGNING_ROOT_CERT=\"https://www.microsoft.com/pkiops/certs/Microsoft%20Enterprise%20Identity%20Verification%20Root%20Certificate%20Authority%202020.crt\""

echo
wait

pe "# Set up variables for ACR and image"
pe "ACR_LOGIN_SERVER=acrtsmkubeconeu2026demo.azurecr.io"
pe "REPOSITORY=nginx"
pe "SIGNED_IMAGE=acrtsmkubeconeu2026demo.azurecr.io/nginx:1.29-alpine-signed"

echo
wait

pe "# Set up variables for signature verification"
pe "TS_TSA_ROOT_CERT=\"http://www.microsoft.com/pkiops/certs/microsoft%20identity%20verification%20root%20certificate%20authority%202020.crt\""
pe "SIGNING_TRUST_STORE=kubeconDemoSigningRootCerts"
pe "TSA_TRUST_STORE=kubeconDemoTsaRootCerts"
pe "TS_CERT_SUBJECT=\"CN=toddysmlive.onmicrosoft.com,OU=Cloud Native Security and Registries,O=toddysmlive.onmicrosoft.com,L=Redmond,ST=Washington,C=US\""

echo
wait

pe "# Log in to ACR"
pe "az login"
pe "az acr login --name $ACR_LOGIN_SERVER"

echo
pe "# Confirm notation is installed"
pe "notation version"

echo
pe "# Check the plugin"
pe "notation plugin ls"

echo
wait

pe "# Install the plugin"
pe "notation plugin install --url https://github.com/Azure/artifact-signing-notation-plugin/releases/download/v1.1.0/notation-azure-artifactsigning_1.1.0_darwin_arm64.tar.gz --sha256sum f9ff085c86474b2371cf3acd70e24f067df2f5c2c3240e101957d99b55d480f0"

echo
pe "# List the plugin"
pe "notation plugin ls"

echo
wait

pe "# Download the TSA root certificate"
pe "curl -o msft-tsa-root-certificate-authority-2020.crt $TS_TSA_ROOT_CERT"

echo
pe "# Sign the container image"
pe "notation sign --signature-format cose --timestamp-url $TS_TSA_URL --timestamp-root-cert "msft-tsa-root-certificate-authority-2020.crt" --id $TS_CERT_PROFILE --plugin azure-artifactsigning --plugin-config accountName=$TS_ACCT_NAME --plugin-config baseUrl=$TS_ACCT_URL --plugin-config certProfile=$TS_CERT_PROFILE $SIGNED_IMAGE"

echo
wait

pe "# List the signature"
pe "notation ls $SIGNED_IMAGE"

echo
wait

pe "# Inpsect the signature"
pe "notation inspect $SIGNED_IMAGE"

echo
wait

pe "# Set up trust store"
pe "curl -o msft-root-certificate-authority-2020.crt $TS_SIGNING_ROOT_CERT"
pe "notation cert add --type ca --store $SIGNING_TRUST_STORE msft-root-certificate-authority-2020.crt"
pe "notation cert add -t tsa -s $TSA_TRUST_STORE msft-tsa-root-certificate-authority-2020.crt"

echo
pe "# List the trust stores"
pe "notation cert ls"

echo
wait

pe "# Set up trust policy"
pe "notation policy import trustpolicy.json"

echo
pe "# Show trust policy"
pe "notation policy show"

echo
wait

pe "# Verify the image"
pe "notation verify $SIGNED_IMAGE"

echo
wait 

pe "# Let's deploy a demo application using the signed image"
pe "kubectl get all --namespace default"
pe "kubectl apply -f nginx-signed-demo.yaml"
pe "kubectl get svc nginx-signed-demo -w"

echo
wait

pe "# Now let's try to deploy an unsigned image and see it get blocked by the policy"
pe "kubectl apply -f nginx-unsigned-demo.yaml"

# show a prompt so as not to reveal our true nature after
# the demo has concluded
p ""
wait