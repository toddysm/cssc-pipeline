#!/bin/bash

export TEMP_LOCATION=temp
export OCI_LAYOUT_LOCATION=$TEMP_LOCATION/oci-layout
export BUILD_METADATA_FILE=build-metadata.json
export ARCHIVE_NAME=flasksample.tar

echo "Printing the environment variables..."
echo "TEMP_LOCATION: $TEMP_LOCATION"
echo "OCI_LAYOUT_LOCATION: $OCI_LAYOUT_LOCATION"
echo "BUILD_METADATA_FILE: $BUILD_METADATA_FILE"
echo "ARCHIVE_NAME: $ARCHIVE_NAME"

notation version

# Generate a test key for the demo
echo "Generating a test key for the demo..."
notation cert generate-test --default "wabbit-networks.io"
notation key ls

echo
echo

# Create the OCI layout directory
mkdir -p $OCI_LAYOUT_LOCATION

# Build the image in OCI layout and save locally
echo "Building the image in OCI layout and saving locally..."
docker buildx build . \
    -f Dockerfile \
    -o type=oci,dest=${TEMP_LOCATION}/${ARCHIVE_NAME} \
    --metadata-file ${TEMP_LOCATION}/${BUILD_METADATA_FILE}

echo
echo

# Extract the OCI layout
echo
tar -xvf ${TEMP_LOCATION}/${ARCHIVE_NAME} -C ${OCI_LAYOUT_LOCATION}

echo
echo

# Show the tree of the OCI layout
echo "Printing the tree of the OCI layout..."
tree ${TEMP_LOCATION}

echo
echo

# Get the manifest digest
echo "Getting the manifest digest..."
export IMAGE_DIGEST=`cat ${TEMP_LOCATION}/${BUILD_METADATA_FILE} | jq -r '."containerimage.descriptor".digest'`

echo
echo

echo "Signing image with digest ${IMAGE_DIGEST}..."
notation sign --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}

echo
echo

# Show the list of signatures
echo "Listing the signatures for image with digest ${IMAGE_DIGEST}..."
notation list --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}

echo
echo

# Verify the signature
export CERT_STORE_NAME=wabbit-networks.io
export REGISTRY_SCOPE=localhost:5000/${OCI_LAYOUT_LOCATION}
export TRUST_POLICY_LOCATION=$XDG_CONFIG_HOME/notation

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

echo "Verifying the signature for image with digest ${IMAGE_DIGEST}..."
notation verify --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST} --scope $REGISTRY_SCOPE
