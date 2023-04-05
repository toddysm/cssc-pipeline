#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

opt_a=0
opt_s=10

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

# Prepare the environment 
# NOTE: Already done in the previous demo. Setting the env vars for this script
# NOTE: Cosign and Notation must be installed and configured on the machine
export SOURCE_REGISTRY=ghcr.io
export DEST_REGISTRY=registry.twnt.co
# export SOURCE_REPO=ghcr.io/toddysm/cssc-pipeline/flasksample
# export DEST_REPO=registry.twnt.co/flasksample
# export SOURCE_IMAGE=ghcr.io/toddysm/cssc-pipeline/flasksample:kubeconeu-demo-v1
# export DEST_IMAGE=registry.twnt.co/flasksample:kubeconeu-demo-v1
export SOURCE_REPO=ghcr.io/toddysm/cssc-pipeline/flasksample-test
export DEST_REPO=registry.twnt.co/flasksample-test
export SOURCE_IMAGE=ghcr.io/toddysm/cssc-pipeline/flasksample-test:kubeconeu-demo-v1
export DEST_IMAGE=registry.twnt.co/flasksample-test:kubeconeu-demo-v1
# This is password for the Cosign signing key
export COSIGN_PASSWORD='P4ssW0rd1!'

clear
slow

# Recap the status
slow 'regctl artifact tree $SOURCE_IMAGE'
regctl artifact tree $SOURCE_IMAGE

# Set up the Cosign key
slow 'export COSIGN_KEY=./kubecon-eu-2023-talks/sigstore/cosign.key'
export COSIGN_KEY=./kubecon-eu-2023-talks/sigstore/cosign.key

# Sign the image
slow 'cosign sign -y --key $COSIGN_KEY --registry-referrers-mode oci-1-1 $SOURCE_IMAGE'
cosign sign -y --key $COSIGN_KEY --registry-referrers-mode oci-1-1 $SOURCE_IMAGE