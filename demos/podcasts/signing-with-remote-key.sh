#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

# NOTE: Prep steps and cleanup
# - Binaries are added to the path
# - Singed into Azure for AKV access
# - Images are uploaded to GHCR
# - Notation keys are removed
# - Notation certs are removed
export PATH=$PATH:${HOME}/Library/Application\ Support/notation/bin
export NOTATION_PATH="${HOME}/Library/Application Support/notation"
export TRUST_STORE_NAME=ghcr.io
export REMOTE_KEY_NAME=ghcr-io-toddysm-signing-key
az login
notation key delete $REMOTE_KEY_NAME
notation key ls
notation cert delete --type ca --store $REMOTE_KEY_NAME --all
notation cert ls

skopeo copy --format=oci docker://toddysm/flasksample:kubeconeu-demo-v1 docker://ghcr.io/toddysm/flasksample:demo-v1

opt_a=0
opt_s=25

while getopts 'ahs:' option; do
  case $option in
    a) opt_a=1;;
    h) opt_h=1;;
    s) opt_s="$OPTARG";;
  esac
done
set +e
shift `expr $OPTIND - 1`

if [ $# -gt 0 -o "$opt_h" = "1" ]; then
  echo "Usage: $0 [opts]"
  echo " -h: this help message"
  echo " -s bps: speed (default $opt_s)"
  exit 1
fi

slow() {
  echo -n "\$ $@" | pv -qL $opt_s
  if [ "$opt_a" = "0" ]; then
    read lf
  else
    echo
  fi
}

clear
slow

echo ' _______________________________ '
echo '|  ___________________________  |'
echo '| | Set up the environment... | |'
echo '| |___________________________| |'
echo '|_______________________________|'

slow 'export TEMP_DIR=${HOME}/Temp
$ export APPLICATION_REPO='ghcr.io/toddysm/flasksample'
$ export APPLICATION_IMAGE="${APPLICATION_REPO}:demo-v1"
$ export TEST_REPO="ghcr.io/toddysm/net-monitor"
$ export TEST_IMAGE="${TEST_REPO}:demo-v1"
$ export NOTATION_PATH="${HOME}/Library/Application Support/notation"'
export TEMP_DIR=${HOME}/Temp
export APPLICATION_REPO='ghcr.io/toddysm/flasksample'
export APPLICATION_IMAGE="${APPLICATION_REPO}:demo-v1"
export TEST_REPO="ghcr.io/toddysm/net-monitor"
export TEST_IMAGE="${TEST_REPO}:demo-v1"
export NOTATION_PATH="${HOME}/Library/Application Support/notation"

# Show notation version
slow 'notation version'
notation version

# Show the available plugins
slow 'notation plugin list'
notation plugin list

# List the tags for the app image (trusted)
slow 'oras repo tags $APPLICATION_IMAGE'
oras repo tags $APPLICATION_REPO

# List the tags for the netmonitor image (un-trusted)
# NOTE: Make sure the image is available
slow 'oras repo tags $TEST_IMAGE'
oras repo tags $TEST_REPO

# Show the keys (there shouldn't be any)
slow 'notation key list'
notation key list

slow
clear

echo ' _______________________________ '
echo '|  ___________________________  |'
echo '| | Set up the signing key... | |'
echo '| |___________________________| |'
echo '|_______________________________|'

slow 'export AKV_NAME=tsm-kv-usw2-testsigning
$ export REMOTE_KEY_NAME=ghcr-io-toddysm-signing-key
$ export CERT_SUBJECT="CN=toddysm.com,O=ToddySM,L=Seattle,ST=WA,C=US"
$ cat <<EOF > $TEMP_DIR/signing-key-policy.json
{
    "issuerParameters": {
    "certificateTransparency": null,
    "name": "Self"
    },
    "x509CertificateProperties": {
    "ekus": [
        "1.3.6.1.5.5.7.3.3"
    ],
    "keyUsage": [
        "digitalSignature"
    ],
    "subject": "$CERT_SUBJECT",
    "validityInMonths": 12
    }
}
EOF'

export AKV_NAME=tsm-kv-usw2-testsigning
export REMOTE_KEY_NAME=ghcr-io-toddysm-signing-key
export CERT_SUBJECT="CN=toddysm.com,O=ToddySM,L=Seattle,ST=WA,C=US"

cat <<EOF > $TEMP_DIR/signing-key-policy.json
{
    "issuerParameters": {
    "certificateTransparency": null,
    "name": "Self"
    },
    "x509CertificateProperties": {
    "ekus": [
        "1.3.6.1.5.5.7.3.3"
    ],
    "keyUsage": [
        "digitalSignature"
    ],
    "subject": "$CERT_SUBJECT",
    "validityInMonths": 12
    }
}
EOF

slow 'az keyvault certificate create -n $REMOTE_KEY_NAME --vault-name $AKV_NAME -p @$TEMP_DIR/signing-key-policy.json'
az keyvault certificate create -n $REMOTE_KEY_NAME --vault-name $AKV_NAME -p @$TEMP_DIR/signing-key-policy.json

slow 'export REMOTE_KEY_ID=$(az keyvault certificate show -n $REMOTE_KEY_NAME --vault-name $AKV_NAME --query 'kid' -o tsv)
$ echo $REMOTE_KEY_ID'
export REMOTE_KEY_ID=$(az keyvault certificate show -n $REMOTE_KEY_NAME --vault-name $AKV_NAME --query 'kid' -o tsv)
echo $REMOTE_KEY_ID

slow
clear

echo ' ____________________________________________________________ '
echo '|  _________________________________________________________  |'
echo '| | Add the signing key to the list of keys for notation... | |'
echo '| |_________________________________________________________| |'
echo '|_____________________________________________________________|'

slow 'notation key add $REMOTE_KEY_NAME --plugin azure-kv --id $REMOTE_KEY_ID'
notation key add $REMOTE_KEY_NAME --plugin azure-kv --id $REMOTE_KEY_ID
slow 'notation key list'
notation key list

echo ' _______________________________________________________ '
echo '|  ___________________________________________________  |'
echo '| | Sign the application image with the remote key... | |'
echo '| |___________________________________________________| |'
echo '|_______________________________________________________|'

slow 'notation sign --signature-format cose --key $REMOTE_KEY_NAME $APPLICATION_IMAGE'
notation sign --signature-format cose --key $REMOTE_KEY_NAME $APPLICATION_IMAGE
slow 'notation ls $APPLICATION_IMAGE'
notation ls $APPLICATION_IMAGE

slow
clear

echo ' _______________________________________________________ '
echo '|  ___________________________________________________  |'
echo '| | Download the certificate used for verification... | |'
echo '| |___________________________________________________| |'
echo '|_______________________________________________________|'

slow 'export STORE_TYPE="ca"
$ export TRUST_STORE_NAME=ghcr.io
$ export CERT_PATH="${TEMP_DIR}/validation-cert.pem"
$ export CERT_ID=$(az keyvault certificate show -n $REMOTE_KEY_NAME --vault-name $AKV_NAME --query 'id' -o tsv)
$ az keyvault certificate download --file $CERT_PATH --id $CERT_ID --encoding PEM'

export STORE_TYPE="ca"
export TRUST_STORE_NAME=ghcr.io
export CERT_PATH="${TEMP_DIR}/validation-cert.pem"
export CERT_ID=$(az keyvault certificate show -n $REMOTE_KEY_NAME --vault-name $AKV_NAME --query 'id' -o tsv)
az keyvault certificate download --file $CERT_PATH --id $CERT_ID --encoding PEM

slow 'notation cert add --type $STORE_TYPE --store $TRUST_STORE_NAME $CERT_PATH'
notation cert add --type $STORE_TYPE --store $TRUST_STORE_NAME $CERT_PATH

slow
clear

echo ' __________________________________________________ '
echo '|  ______________________________________________  |'
echo '| | Configure trust policy for the remote key... | |'
echo '| |______________________________________________| |'
echo '|__________________________________________________|'

slow 'rm ${NOTATION_PATH}/trustpolicy.json'
rm ${NOTATION_PATH}/trustpolicy.json

slow 'export TRUST_POLICY_NAME=toddysm-application
$ export TRUST_STORE_NAME=ghcr.io'

export TRUST_POLICY_NAME=toddysm-application

slow 'cat <<EOF > ${NOTATION_PATH}/trustpolicy.json
{
    "version": "1.0",
    "trustPolicies": [
        {
            "name": "$TRUST_POLICY_NAME",
            "registryScopes": [ "$APPLICATION_REPO" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:$TRUST_STORE_NAME" ],
            "trustedIdentities": [
                "*"
            ]
        }
    ]
}
EOF'
cat <<EOF > ${NOTATION_PATH}/trustpolicy.json
{
    "version": "1.0",
    "trustPolicies": [
        {
            "name": "$TRUST_POLICY_NAME",
            "registryScopes": [ "$APPLICATION_REPO" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:$TRUST_STORE_NAME" ],
            "trustedIdentities": [
                "*"
            ]
        }
    ]
}
EOF

echo ' ___________________________________________________________ '
echo '|  _______________________________________________________  |'
echo '| | Verify the application image... and the test image... | |'
echo '| |_______________________________________________________| |'
echo '|___________________________________________________________|'

slow 'notation verify $APPLICATION_IMAGE'
notation verify $APPLICATION_IMAGE

slow 'notation verify $TEST_IMAGE'
notation verify $TEST_IMAGE

slow
slow

# The END