#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

# Prep steps
cd /Users/toddysm/Documents/Development/cssc-pipeline
rm -rf temp
export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation
rm ${TRUST_POLICY_LOCATION}/*policy*

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
echo '| | Build the container image... | |'
echo '| |______________________________| |'
echo '|__________________________________|'

# Set the environment variables and build the image
slow 'export TEMP_LOCATION=temp
$ export OCI_LAYOUT_LOCATION=$TEMP_LOCATION/oci-layout
$ export BUILD_METADATA_FILE=build-metadata.json
$ export ARCHIVE_NAME=flasksample.tar
$ mkdir -p OCI_LAYOUT_LOCATION
$ docker buildx build . -f Dockerfile -o type=oci,dest=${ARCHIVE_NAME} --metadata-file ${TEMP_LOCATION}/${BUILD_METADATA_FILE}'
export TEMP_LOCATION=temp
export OCI_LAYOUT_LOCATION=$TEMP_LOCATION/oci-layout
export BUILD_METADATA_FILE=build-metadata.json
export ARCHIVE_NAME=flasksample.tar
mkdir -p $OCI_LAYOUT_LOCATION
docker buildx build . -f Dockerfile -o type=oci,dest=${TEMP_LOCATION}/${ARCHIVE_NAME} --metadata-file ${TEMP_LOCATION}/${BUILD_METADATA_FILE}

slow

slow 'tar -xvf ${TEMP_LOCATION}/${ARCHIVE_NAME} -C $OCI_LAYOUT_LOCATION'
tar -xvf ${TEMP_LOCATION}/${ARCHIVE_NAME} -C $OCI_LAYOUT_LOCATION

slow

slow 'tree $OCI_LAYOUT_LOCATION'
tree $OCI_LAYOUT_LOCATION

slow
clear

echo ' ______________________________ '
echo '|  ___________________________  |'
echo '| | Signing local artifact... | |'
echo '| |___________________________| |'
echo '|_______________________________|'

# Get the manifest digest and sign the image
slow 'export TEST_KEY_NAME=wabbit-networks.io
$ export IMAGE_DIGEST=`cat ${TEMP_LOCATION}/${BUILD_METADATA_FILE} | jq -r '."containerimage.descriptor".digest'`
$ notation sign --oci-layout --key $TEST_KEY_NAME ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}'
export TEST_KEY_NAME=wabbit-networks.io
export IMAGE_DIGEST=`cat ${TEMP_LOCATION}/${BUILD_METADATA_FILE} | jq -r '."containerimage.descriptor".digest'`
notation sign --oci-layout --key $TEST_KEY_NAME ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}

slow 'notation list --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}'
notation list --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}

slow
clear

echo ' _________________________________ '
echo '|  _____________________________  |'
echo '| | Verifying local artifact... | |'
echo '| |_____________________________| |'
echo '|_________________________________|'

slow 'export CERT_STORE_NAME=wabbit-networks.io
$ export REGISTRY_SCOPE=localhost:5000/${OCI_LAYOUT_LOCATION}
$ export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation'
export CERT_STORE_NAME=wabbit-networks.io
export REGISTRY_SCOPE=localhost:5000/${OCI_LAYOUT_LOCATION}
export TRUST_POLICY_LOCATION=~/Library/Application\ Support/notation

slow 'cat <<EOF > ${TRUST_POLICY_LOCATION}/trustpolicy.json
{
 "version": "1.0",
 "trustPolicies": [
    {
         "name": "local-images-policy",
         "registryScopes": [ "$REGISTRY_SCOPE" ],
         "signatureVerification": {
             "level" : "strict"
         },
         "trustStores": [ "ca:${CERT_STORE_NAME}" ],
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
         "name": "local-images-policy",
         "registryScopes": [ "$REGISTRY_SCOPE" ],
         "signatureVerification": {
             "level" : "strict"
         },
         "trustStores": [ "ca:${CERT_STORE_NAME}" ],
         "trustedIdentities": [
             "*"
         ]
     }
 ]
}
EOF

slow 'notation verify --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST} --scope $REGISTRY_SCOPE'
notation verify --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST} --scope $REGISTRY_SCOPE

slow
