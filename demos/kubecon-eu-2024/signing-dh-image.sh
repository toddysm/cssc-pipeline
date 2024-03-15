#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

# NOTE: Prep steps and cleanup
# - Notation keys are removed
# - Notation certs are removed
export TRUST_STORE_NAME=docker.io
export TEST_KEY_NAME=wabbit-networks.io
notation key delete $TEST_KEY_NAME
notation key ls
rm /Users/toddysm/Library/Application\ Support/notation/localkeys/wabbit-networks.io.key
rm /Users/toddysm/Library/Application\ Support/notation/localkeys/wabbit-networks.io.crt
notation cert delete --type ca --store $TEST_KEY_NAME --all
notation cert delete --type ca --store $TRUST_STORE_NAME --all
notation cert ls

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

echo ' ______________________________ '
echo '|  __________________________  |'
echo '| | Prep the environment...  | |'
echo '| |__________________________| |'
echo '|______________________________|'

# Set the env variables for the images
slow 'export TEST_REPO='docker.io/toddysm/python'
$ export TEST_IMAGE="${TEST_REPO}:3.12"'
export TEST_REPO='docker.io/toddysm/python'
export TEST_IMAGE="${TEST_REPO}:3.12"

# Show notation version
slow 'notation version'
notation version

# List the tags for the netmonitor image (un-trusted)
# NOTE: Make sure the image is available
slow 'oras repo tags $TEST_IMAGE'
oras repo tags $TEST_REPO

# Show the keys (there shouldn't be any)
slow 'notation key list'
notation key list

slow
clear

echo ' ______________________________ '
echo '|  __________________________  |'
echo '| | Signing with test key... | |'
echo '| |__________________________| |'
echo '|______________________________|'

# Set the test key name in env variable
slow 'export TEST_KEY_NAME=wabbit-networks.io'
export TEST_KEY_NAME=wabbit-networks.io

# Set up the TEST_KEY
slow 'notation cert generate-test --default $TEST_KEY_NAME'
notation cert generate-test --default $TEST_KEY_NAME

slow 'notation key list'
notation key list

slow 'notation cert list'
notation cert list

slow
clear

# Sign into Docker Hub
slow 'docker login'
docker login

# Sign the net-monitor image
slow 'notation sign --signature-format cose --key $TEST_KEY_NAME $TEST_IMAGE'
notation sign --signature-format cose --key $TEST_KEY_NAME $TEST_IMAGE
slow 'notation ls $TEST_IMAGE'
notation ls $TEST_IMAGE

slow
clear

echo ' ___________________________________ '
echo '|  _______________________________  |'
echo '| | Validating the signature...   | |'
echo '| |_______________________________| |'
echo '|___________________________________|'

slow 'export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation/'
export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation

slow
slow 'cat <<EOF > ${TRUST_POLICY_LOCATION}/trustpolicy.json
{
    "version": "1.0",
    "trustPolicies": [
        {
            "name": "python-images",
            "registryScopes": [ "${TEST_REPO}" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:wabbit-networks.io" ],
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
            "registryScopes": [ "${TEST_REPO}" ],
            "signatureVerification": {
                "level" : "strict"
            },
            "trustStores": [ "ca:wabbit-networks.io" ],
            "trustedIdentities": [
                "*"
            ]
        }
    ]
}
EOF

slow 'notation verify $TEST_IMAGE'
notation verify $TEST_IMAGE

slow
slow
# The END