#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

# Prep steps
export PATH=$PATH:${HOME}/Library/Application\ Support/notation/bin

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
$ export VERSION=1.0.0-rc.2
$ export ARCH=arm64
$ export NOTATION_PATH="${HOME}/Library/Application Support/notation"
$ export INSTALL_PATH="${HOME}/Library/Application Support/notation/plugins/azure-kv"
$ mkdir -p $TEMP_DIR
$ cd $TEMP_DIR'

export TEMP_DIR=${HOME}/Temp
export VERSION=1.0.0-rc.2
export ARCH=arm64
export NOTATION_PATH="${HOME}/Library/Application Support/notation"
export INSTALL_PATH="${HOME}/Library/Application Support/notation/plugins/azure-kv"
mkdir -p $TEMP_DIR
cd $TEMP_DIR

echo ' ______________________________________ '
echo '|  __________________________________  |'
echo '| | Download tarball and checksum... | |'
echo '| |__________________________________| |'
echo '|______________________________________|'

slow 'export CHECKSUM_FILE="notation-azure-kv_${VERSION}_checksums.txt"
$ export TAR_FILE="notation-azure-kv_${VERSION}_darwin_${ARCH}.tar.gz"
$ curl -Lo ${CHECKSUM_FILE} "https://github.com/Azure/notation-azure-kv/releases/download/v${VERSION}/${CHECKSUM_FILE}"'

export CHECKSUM_FILE="notation-azure-kv_${VERSION}_checksums.txt"
export TAR_FILE="notation-azure-kv_${VERSION}_darwin_${ARCH}.tar.gz"
curl -Lo ${CHECKSUM_FILE} "https://github.com/Azure/notation-azure-kv/releases/download/v${VERSION}/${CHECKSUM_FILE}"

slow 'curl -Lo ${TAR_FILE} "https://github.com/Azure/notation-azure-kv/releases/download/v${VERSION}/${TAR_FILE}"'

curl -Lo ${TAR_FILE} "https://github.com/Azure/notation-azure-kv/releases/download/v${VERSION}/${TAR_FILE}"

echo ' _________________________________________________________ '
echo '|  _____________________________________________________  |'
echo '| | Validate the checksum for the downloaded tarball... | |'
echo '| |_____________________________________________________| |'
echo '|_________________________________________________________|'

slow 'grep ${TAR_FILE} ${CHECKSUM_FILE} | shasum -a 256 -c'
grep ${TAR_FILE} ${CHECKSUM_FILE} | shasum -a 256 -c

echo ' __________________________________________________ '
echo '|  ______________________________________________  |'
echo '| | Install the plugin in the relevant folder... | |'
echo '| |______________________________________________| |'
echo '|__________________________________________________|'

slow 'mkdir -p ${INSTALL_PATH}
$ tar xvzf ${TAR_FILE} -C ${INSTALL_PATH} notation-azure-kv'

mkdir -p ${INSTALL_PATH}
tar xvzf ${TAR_FILE} -C ${INSTALL_PATH} notation-azure-kv

slow 'tree $NOTATION_PATH'
tree $NOTATION_PATH

slow 'notation plugin ls'
notation plugin ls