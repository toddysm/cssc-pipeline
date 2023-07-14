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
export TEST_KEY_NAME=wabbit-networks.io
export REMOTE_KEY_NAME=ghcr-io-toddysm-signing-key
notation key delete $TEST_KEY_NAME
notation key delete $REMOTE_KEY_NAME
notation key ls
rm ${NOTATION_PATH}/signingkeys.json
rm ${NOTATION_PATH}/trustpolicy.json
rm -r ${NOTATION_PATH}/localkeys
rm -r ${NOTATION_PATH}/truststore
notation cert delete --type ca --store $TEST_KEY_NAME --all
notation cert delete --type ca --store $REMOTE_KEY_NAME --all
notation cert ls

skopeo copy --format=oci docker://toddysm/net-monitor:kubeconeu-demo-v1 docker://ghcr.io/toddysm/net-monitor:demo-v1

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

slow 'export TEST_REPO="ghcr.io/toddysm/net-monitor"
$ export TEST_IMAGE="${TEST_REPO}:demo-v1"
$ export NOTATION_PATH="${HOME}/Library/Application Support/notation"'

export TEST_REPO="ghcr.io/toddysm/net-monitor"
export TEST_IMAGE="${TEST_REPO}:demo-v1"
export NOTATION_PATH="${HOME}/Library/Application Support/notation"

echo ' __________________________________ '
echo '|  ______________________________  |'
echo '| | What do we have available... | |'
echo '| |______________________________| |'
echo '|__________________________________|'

slow 'oras repo tags $TEST_IMAGE'
oras repo tags $TEST_REPO

# Show the notation version
slow 'notation version'
notation version

# Show the keys (there shouldn't be any)
slow 'notation key list'
notation key list

slow
clear

echo ' ______________________________ '
echo '|  __________________________  |'
echo '| | Generate the test key... | |'
echo '| |__________________________| |'
echo '|______________________________|'

# Set the test key name in env variable
slow 'export TEST_KEY_NAME=wabbit-networks.io'
slow 'notation cert generate-test --default $TEST_KEY_NAME'
export TEST_KEY_NAME=wabbit-networks.io
notation cert generate-test --default $TEST_KEY_NAME

slow 'notation key list'
notation key list

slow 'notation cert list'
notation cert list

echo ' ______________________________ '
echo '|  __________________________  |'
echo '| | Signing with test key... | |'
echo '| |__________________________| |'
echo '|______________________________|'
slow 'notation sign --signature-format cose --key $TEST_KEY_NAME $TEST_IMAGE'
notation sign --signature-format cose --key $TEST_KEY_NAME $TEST_IMAGE
slow 'notation ls $TEST_IMAGE'
notation ls $TEST_IMAGE

slow
clear

echo ' ___________________________________ '
echo '|  _______________________________  |'
echo '| | Trust policy configuration... | |'
echo '| |_______________________________| |'
echo '|___________________________________|'

slow 'export TEST_TRUST_POLICY_NAME=net-monitor-application
$ export TEST_CA_NAME=net-monitor-ca'

export TEST_TRUST_POLICY_NAME=net-monitor-application
export TEST_CA_NAME=wabbit-networks.io

slow 'cat <<EOF > ${NOTATION_PATH}/trustpolicy.json
{
    "version": "1.0",
    "trustPolicies": [
        {
            "name": "$TEST_TRUST_POLICY_NAME",
            "registryScopes": [ "$TEST_REPO" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:$TEST_CA_NAME" ],
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
            "name": "$TEST_TRUST_POLICY_NAME",
            "registryScopes": [ "$TEST_REPO" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:$TEST_CA_NAME" ],
            "trustedIdentities": [
                "*"
            ]
        }
    ]
}
EOF

echo ' ______________________________ '
echo '|  __________________________  |'
echo '| | Verify the test image... | |'
echo '| |__________________________| |'
echo '|______________________________|'

slow 'notation verify $TEST_IMAGE'
notation verify $TEST_IMAGE

slow
slow
# The END