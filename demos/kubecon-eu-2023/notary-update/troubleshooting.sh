#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

# Prep steps - set up
export TEST_KEY_NAME=wabbit-networks.io
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

echo ' _____________________________________ '
echo '|  _________________________________  |'
echo '| | Troubleshooting signing flow... | |'
echo '| |_________________________________| |'
echo '|_____________________________________|'

slow 'notation sign --signature-format cose --key $TEST_KEY_NAME --debug $TEST_IMAGE'
notation sign --signature-format cose --key $TEST_KEY_NAME --debug $TEST_IMAGE

slow
clear

echo ' ______________________________ '
echo '|  __________________________  |'
echo '| | Inspecting signatures... | |'
echo '| |__________________________| |'
echo '|______________________________|'

slow 'notation inspect ghcr.io/toddysm/flasksample:kubeconeu-demo-v1'
notation inspect ghcr.io/toddysm/flasksample:kubeconeu-demo-v1

echo
slow

slow 'notation inspect ghcr.io/toddysm/net-monitor:kubeconeu-demo-v1'
notation inspect ghcr.io/toddysm/net-monitor:kubeconeu-demo-v1

slow