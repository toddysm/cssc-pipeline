#!/bin/bash

export TEMP_LOCATION=/tmp
export OCI_LAYOUT_LOCATION=$TEMP_LOCATION/oci-layout
export BUILD_METADATA_FILE=build-metadata.json
export ARCHIVE_NAME=flasksample.tar

notation version

# Generate a test key for the demo
notation cert generate-test --default "wabbit-networks.io"
notation key ls

# Build the image in OCI layout and save locally
docker buildx build . \
    -f Dockerfile \
    -o type=oci,dest=${TEMP_LOCATION}/${ARCHIVE_NAME} \
    --metadata-file ${TEMP_LOCATION}/${BUILD_METADATA_FILE}

mkdir -p $OCI_LAYOUT_LOCATION

# Extract the OCI layout
tar -xvf ${TEMP_LOCATION}/${ARCHIVE_NAME} -C ${OCI_LAYOUT_LOCATION}

# Show the tree of the OCI layout
tree ${OCI_LAYOUT_LOCATION}

# Get the manifest digest
export IMAGE_DIGEST=`cat ${TEMP_LOCATION}/${BUILD_METADATA_FILE} | jq -r '."containerimage.descriptor".digest'`
notation sign --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}

# Show the list of signatures
notation list --oci-layout ${OCI_LAYOUT_LOCATION}@${IMAGE_DIGEST}