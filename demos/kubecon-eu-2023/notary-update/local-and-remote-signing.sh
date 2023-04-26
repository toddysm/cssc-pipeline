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
export TRUST_STORE_NAME=ghcr.io
export TEST_KEY_NAME=wabbit-networks.io
export REMOTE_KEY_NAME=tsmacrusw3kubeconeu23-azurecr-io
az login
notation key delete $TEST_KEY_NAME
notation key delete $REMOTE_KEY_NAME
notation key ls
rm /Users/toddysm/Library/Application\ Support/notation/localkeys/wabbit-networks.io.key
rm /Users/toddysm/Library/Application\ Support/notation/localkeys/wabbit-networks.io.crt
notation cert delete --type ca --store $TEST_KEY_NAME --all
notation cert delete --type ca --store $TRUST_STORE_NAME --all
notation cert delete --type ca --store $REMOTE_KEY_NAME --all
notation cert ls

skopeo copy --format=oci docker://toddysm/flasksample:kubeconeu-demo-v1 docker://ghcr.io/toddysm/flasksample:kubeconeu-demo-v1
skopeo copy --format=oci docker://toddysm/net-monitor:kubeconeu-demo-v1 docker://ghcr.io/toddysm/net-monitor:kubeconeu-demo-v1

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

# Set the env variables for the images
slow 'export APPLICATION_REPO='ghcr.io/toddysm/flasksample'
$ export TEST_REPO='ghcr.io/toddysm/net-monitor'
$ export APPLICATION_IMAGE='ghcr.io/toddysm/flasksample:kubeconeu-demo-v1'
$ export TEST_IMAGE='ghcr.io/toddysm/net-monitor:kubeconeu-demo-v1''
export APPLICATION_REPO='ghcr.io/toddysm/flasksample'
export TEST_REPO='ghcr.io/toddysm/net-monitor'
export APPLICATION_IMAGE='ghcr.io/toddysm/flasksample:kubeconeu-demo-v1'
export TEST_IMAGE='ghcr.io/toddysm/net-monitor:kubeconeu-demo-v1'

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

# Sign the net-monitor image
slow 'notation sign --signature-format cose --key $TEST_KEY_NAME $TEST_IMAGE'
notation sign --signature-format cose --key $TEST_KEY_NAME $TEST_IMAGE
slow 'notation ls $TEST_IMAGE'
notation ls $TEST_IMAGE

slow
clear

echo ' ________________________________ '
echo '|  ____________________________  |'
echo '| | Signing with remote key... | |'
echo '| |____________________________| |'
echo '|________________________________|'

# Set up the environment
slow 'export AKV_NAME=tsm-kv-usw3-kubeconeu23
$ export REMOTE_KEY_NAME=tsmacrusw3kubeconeu23-azurecr-io
$ export REMOTE_KEY_ID=$(az keyvault certificate show -n $REMOTE_KEY_NAME --vault-name $AKV_NAME --query 'kid' -o tsv)'
export AKV_NAME=tsm-kv-usw3-kubeconeu23
export REMOTE_KEY_NAME=tsmacrusw3kubeconeu23-azurecr-io
export REMOTE_KEY_ID=$(az keyvault certificate show -n $REMOTE_KEY_NAME --vault-name $AKV_NAME --query 'kid' -o tsv)
echo $REMOTE_KEY_ID

# Add the remote key to the key list
slow 'notation key add $REMOTE_KEY_NAME --plugin azure-kv --id $REMOTE_KEY_ID'
notation key add $REMOTE_KEY_NAME --plugin azure-kv --id $REMOTE_KEY_ID
slow 'notation key list'
notation key list

# Sign the application image with the remote key
slow 'notation sign --signature-format cose --key $REMOTE_KEY_NAME $APPLICATION_IMAGE'
notation sign --signature-format cose --key $REMOTE_KEY_NAME $APPLICATION_IMAGE
slow 'notation ls $APPLICATION_IMAGE'
notation ls $APPLICATION_IMAGE

slow
slow
# The END