#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

# Prep steps - cleanup
export TRUST_STORE_NAME=ghcr.io
export TEMP_LOCATION=./Temp
export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation
az login
notation cert delete --type ca --store $TRUST_STORE_NAME --all
rm ${TEMP_LOCATION}/*
rm ${TRUST_POLICY_LOCATION}/*policy*

# Prep steps setup
export APPLICATION_REPO='ghcr.io/toddysm/flasksample'
export TEST_REPO='ghcr.io/toddysm/net-monitor'
export APPLICATION_IMAGE='ghcr.io/toddysm/flasksample:kubeconeu-demo-v1'
export TEST_IMAGE='ghcr.io/toddysm/net-monitor:kubeconeu-demo-v1'

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

echo ' __________________________________ '
echo '|  ______________________________  |'
echo '| | Trust store configuration... | |'
echo '| |______________________________| |'
echo '|__________________________________|'

slow 'export TRUST_STORE_LOCATION=~/Library/Application\ Support/notation/truststore
$ tree $TRUST_STORE_LOCATION'
export TRUST_STORE_LOCATION=~/Library/Application\ Support/notation/truststore
tree $TRUST_STORE_LOCATION

slow

slow 'export AKV_NAME=tsm-kv-usw3-kubeconeu23
$ export CERT_NAME=tsmacrusw3kubeconeu23-azurecr-io
$ export TEMP_LOCATION=./Temp
$ export CERT_PATH=./Temp/${CERT_NAME}.pem
$ export CERT_ID=$(az keyvault certificate show -n $CERT_NAME --vault-name $AKV_NAME --query 'id' -o tsv)
$ az keyvault certificate download --file $CERT_PATH --id $CERT_ID --encoding PEM'
export AKV_NAME=tsm-kv-usw3-kubeconeu23
export CERT_NAME=tsmacrusw3kubeconeu23-azurecr-io
export TEMP_LOCATION=./Temp
export CERT_PATH=${TEMP_LOCATION}/${CERT_NAME}.pem
export CERT_ID=$(az keyvault certificate show -n $CERT_NAME --vault-name $AKV_NAME --query 'id' -o tsv)
az keyvault certificate download --file $CERT_PATH --id $CERT_ID --encoding PEM

slow 

slow 'ls -al $TEMP_LOCATION'
ls -al $TEMP_LOCATION

echo
echo

slow 'export TRUST_STORE_NAME=ghcr.io
$ notation cert add --type ca --store $TRUST_STORE_NAME $CERT_PATH'
export TRUST_STORE_NAME=ghcr.io
notation cert add --type ca --store $TRUST_STORE_NAME $CERT_PATH

slow 

slow 'tree $TRUST_STORE_LOCATION'
tree $TRUST_STORE_LOCATION

slow

slow 'notation verify $APPLICATION_IMAGE'
notation verify $APPLICATION_IMAGE

slow
clear

echo ' ___________________________________ '
echo '|  _______________________________  |'
echo '| | Trust policy configuration... | |'
echo '| |_______________________________| |'
echo '|___________________________________|'

slow 'export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation/
$ ls ${TRUST_POLICY_LOCATION}/*policy*'
export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation

slow
slow 'cat <<EOF > ${TRUST_POLICY_LOCATION}/trustpolicy.json
{
    "version": "1.0",
    "trustPolicies": [
        {
            "name": "flasksample-application",
            "registryScopes": [ "ghcr.io/toddysm/flasksample" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:ghcr.io" ],
            "trustedIdentities": [
                "*"
            ]
        }
    ]
}
EOF'
cat <<EOF > ${TRUST_POLICY_LOCATION}/trustpolicy.json
{
    "version": "1.0",
    "trustPolicies": [
        {
            "name": "flasksample-application",
            "registryScopes": [ "ghcr.io/toddysm/flasksample" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:ghcr.io" ],
            "trustedIdentities": [
                "*"
            ]
        }
    ]
}
EOF

slow 'notation verify $APPLICATION_IMAGE'
notation verify $APPLICATION_IMAGE

slow 

slow 'notation verify $TEST_IMAGE'
notation verify $TEST_IMAGE

slow
