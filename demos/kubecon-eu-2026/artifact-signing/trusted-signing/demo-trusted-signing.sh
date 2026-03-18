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
. ../demo-magic.sh -d


########################
# Configure the options
########################

#
# speed at which to simulate typing. bigger num = faster
#
TYPE_SPEED=20

#
# custom prompt
#
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
#DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"
DEMO_PROMPT="${GREEN}$ ${COLOR_RESET}"

# text color
# DEMO_CMD_COLOR=$BLACK

# clean up any previous runs
notation plugin uninstall azure-artifactsigning --yes
notation cert delete --type ca --store $SIGNING_TRUST_STORE --all --yes
notation cert delete --type tsa --store $TSA_TRUST_STORE --all --yes
rm -f ~/.config/notation/trustpolicy.json
rm -f msft-root-certificate-authority-2020.crt msft-tsa-root-certificate-authority-2020.crt
rm -fr ~/.config/notation

# hide the evidence
clear

# enters interactive mode and allows newly typed command to be executed
cmd

# print and execute immediately: ls -l

# Set up env variables

pe "# Set up variables for Trusted Signing"
pe "TS_ACCT_NAME=sig-tsm-demo"
pe "TS_ACCT_URL=https://wus2.codesigning.azure.net/"
pe "TS_CERT_PROFILE=cert-tsm-demo"
pe "TS_TSA_URL=http://timestamp.acs.microsoft.com/"
pe "TS_SIGNING_ROOT_CERT=\"https://www.microsoft.com/pkiops/certs/Microsoft%20Enterprise%20Identity%20Verification%20Root%20Certificate%20Authority%202020.crt\""

echo
pe "# Set up variables for ACR and image"
pe "ACR_LOGIN_SERVER=acrtsmpremiumsku.azurecr.io"
pe "REPOSITORY=python"
pe "IMAGE=acrtsmpremiumsku.azurecr.io/python:3.13"

echo
pe "# Set up variables for signature verification"
pe "TS_TSA_ROOT_CERT=\"http://www.microsoft.com/pkiops/certs/microsoft%20identity%20verification%20root%20certificate%20authority%202020.crt\""
pe "SIGNING_TRUST_STORE=kubeconDemoSigningRootCerts"
pe "TSA_TRUST_STORE=kubeconDemoTsaRootCerts"
pe "TS_CERT_SUBJECT=\"CN=microsoft.onmicrosoft.com, O=microsoft.onmicrosoft.com, OU=Cloud Native Security and Registries, L=Redmond, S=Washington, C=US\""

echo
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
pe "# Install the plugin"
pe "notation plugin install --url https://github.com/Azure/artifact-signing-notation-plugin/releases/download/v1.1.0/notation-azure-artifactsigning_1.1.0_darwin_arm64.tar.gz --sha256sum f9ff085c86474b2371cf3acd70e24f067df2f5c2c3240e101957d99b55d480f0"

echo
pe "# List the plugin"
pe "notation plugin ls"

echo
pe "# Download the TSA root certificate"
pe "curl -o msft-tsa-root-certificate-authority-2020.crt $TS_TSA_ROOT_CERT"

echo
pe "# Sign the container image"
pe "notation sign --signature-format cose --timestamp-url $TS_TSA_URL --timestamp-root-cert "msft-tsa-root-certificate-authority-2020.crt" --id $TS_CERT_PROFILE --plugin azure-artifactsigning --plugin-config accountName=$TS_ACCT_NAME --plugin-config baseUrl=$TS_ACCT_URL --plugin-config certProfile=$TS_CERT_PROFILE $IMAGE"

echo
pe "# List the signature"
pe "notation ls $IMAGE"

echo
pe "# Inpsect the signature"
pe "notation inspect $IMAGE"

echo
pe "# Set up trust store"
pe "curl -o msft-root-certificate-authority-2020.crt $TS_SIGNING_ROOT_CERT"
pe "notation cert add --type ca --store $SIGNING_TRUST_STORE msft-root-certificate-authority-2020.crt"
pe "notation cert add -t tsa -s $TSA_TRUST_STORE msft-tsa-root-certificate-authority-2020.crt"

echo
pe "# List the trust store"
pe "notation cert ls"

echo
pe "# Set up trust policy"
pe "notation policy import trustpolicy.json"

echo
pe "# Show trust policy"
pe "notation policy show"

echo
pe "# Verify the image"
pe "notation verify $IMAGE"

# run command behind

# enters interactive mode and allows newly typed command to be executed

# show a prompt so as not to reveal our true nature after
# the demo has concluded
p ""
