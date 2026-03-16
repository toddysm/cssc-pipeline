az login
az acr login --name tsmacrtestmis
docker login -u toddysm ghcr.io
export PATH=$PATH:~/Documents/Development/cssc-pipeline/temp

export TEMP_LOCATION=temp
export IMAGE_VERSION=1.0
export REVISION=20230808
export ACR_REGISTRY=tsmacrtestmis.azurecr.io
export GHCR_REGISTRY=ghcr.io
export REPOSITORY=flasksample
export NAMESPACE=toddysm
export TXT_FILE_TAG=hello.txt
export MUTLI_FILE_TAG=multiple-files
export PATH=$PATH:~/Documents/Development/cssc-pipeline/temp
export TEST_SIGN_KEY=wabbit-networks.io
mkdir -p $TEMP_LOCATION

# Build a simple Docker image and push to the ACR_REGISTRY
docker build . -f Dockerfile \
  -t ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}

docker push ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}

# Fetch the manifest and inspect it
oras manifest fetch ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .

# Lets push a simple file to the ACR_REGISTRY
echo "Hello World" > ${TEMP_LOCATION}/hello.txt
oras push ${ACR_REGISTRY}/${REPOSITORY}:${TXT_FILE_TAG} ${TEMP_LOCATION}/hello.txt

# Pull the file back down
rm ./temp/hello.txt
tree ./temp
oras pull ${ACR_REGISTRY}/${REPOSITORY}:${TXT_FILE_TAG}
more ./temp/hello.txt

# Let's take a look at the manifest
oras manifest fetch ${ACR_REGISTRY}/${REPOSITORY}:${TXT_FILE_TAG} | jq .
# NOTE: The config media type is unknown

# Push with a specific media type
oras push --artifact-type text/example ${ACR_REGISTRY}/${REPOSITORY}:${TXT_FILE_TAG} ${TEMP_LOCATION}/hello.txt
oras manifest fetch ${ACR_REGISTRY}/${REPOSITORY}:${TXT_FILE_TAG} | jq .

# Push multiple files
echo "{'foo':'bar'}" > ${TEMP_LOCATION}/hello.json
oras push ${ACR_REGISTRY}/${REPOSITORY}:${MUTLI_FILE_TAG} ${TEMP_LOCATION}/hello.txt:text/example ${TEMP_LOCATION}/hello.json:application/json
oras manifest fetch ${ACR_REGISTRY}/${REPOSITORY}:${MUTLI_FILE_TAG} | jq .

# Create an SBOM
trivy image --format spdx-json --output ${TEMP_LOCATION}/${REPOSITORY}_${IMAGE_VERSION}.json ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}
cat ${TEMP_LOCATION}/${REPOSITORY}_${IMAGE_VERSION}.json | jq .

# Attach the SBOM to the image
oras attach --artifact-type=application/spdx+json ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} ${TEMP_LOCATION}/${REPOSITORY}_${IMAGE_VERSION}.json
oras discover ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} -o tree

# Filter by artifact type and get the digest of the SBOM
export SBOM_ARTIFACT_DIGEST=`oras discover --artifact-type "application/spdx+json" \
  ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} -o json \
  | jq '.manifests[0].digest' \
  | tr -d '"'`
echo $SBOM_ARTIFACT_DIGEST
oras manifest fetch ${ACR_REGISTRY}/${REPOSITORY}@${SBOM_ARTIFACT_DIGEST} | jq .

# Sign the image and the SBOM
notation sign --signature-format cose --key $TEST_SIGN_KEY ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}
oras discover ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} -o tree
notation sign --signature-format cose --key $TEST_SIGN_KEY ${ACR_REGISTRY}/${REPOSITORY}@${SBOM_ARTIFACT_DIGEST}
oras discover ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} -o tree

# DO THE DEMO WITH GHCR (1.0)
# Build a simple Docker image and push to the ACR_REGISTRY
docker build . -f Dockerfile \
  -t ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}:${IMAGE_VERSION}

docker push ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}:${IMAGE_VERSION}

oras attach --artifact-type=application/spdx+json ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}:${IMAGE_VERSION} ${TEMP_LOCATION}/${REPOSITORY}_${IMAGE_VERSION}.json
oras discover ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}:${IMAGE_VERSION} -o tree
export SBOM_ARTIFACT_DIGEST=`oras discover --artifact-type "application/spdx+json" \
  ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}:${IMAGE_VERSION} -o json \
  | jq '.manifests[0].digest' \
  | tr -d '"'`
echo $SBOM_ARTIFACT_DIGEST
oras manifest fetch ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}@${SBOM_ARTIFACT_DIGEST} | jq .
oras repo tags ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}
# crane ls ${GHCR_REGISTRY}/${NAMESPACE}/${REPOSITORY}

# SHOW THAT DOCKER CAN ALSO BUILD OCI ARTIFACTS
docker buildx build . -f Dockerfile \
  -t ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}-${REVISION} \
  -o "type=oci,dest=${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${REVISION}.tar,annotation.org.opencontainers.image.created=2023-07-07T00:00:00-08:00,annotation.org.opencontainers.image.version=${IMAGE_VERSION},annotation.org.opencontainers.image.revision=${FIRST_REVISION}" \

oras cp --from-oci-layout ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${REVISION}.tar:${IMAGE_VERSION}-${REVISION} \
  ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}-${REVISION}

oras manifest fetch ${ACR_REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}-${REVISION} | jq .
