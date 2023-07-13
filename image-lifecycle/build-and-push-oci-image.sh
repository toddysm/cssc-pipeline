#!/bin/zsh

# This script uses the slow() function from Brandon Mitchell available at 
# https://github.com/sudo-bmitch/presentations/blob/main/oci-referrers-2023/demo-script.sh#L23
# to simulate typing the commands

# Prep steps
cd /Users/toddysm/Documents/Development/cssc-pipeline
rm -rf ./image-lifecycle/temp

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

echo ' ____________________________ '
echo '|  ________________________  |'
echo '| | Set the environment... | |'
echo '| |________________________| |'
echo '|____________________________|'

slow 'export TEMP_LOCATION=temp
$ export IMAGE_VERSION=1.0
$ export FIRST_REVISION=20230707
$ export SECOND_REVISION=20230710
$ export REGISTRY=ghcr.io/toddysm/cssc-pipeline
$ export REPOSITORY=flasksample
$ mkdir -p $TEMP_LOCATION'

export TEMP_LOCATION=temp
export IMAGE_VERSION=1.0
export FIRST_REVISION=20230707
export SECOND_REVISION=20230710
export REGISTRY=ghcr.io/toddysm/cssc-pipeline
export REPOSITORY=flasksample
mkdir -p $TEMP_LOCATION

clear

echo ' _________________________________________________________________________ '
echo '|  _____________________________________________________________________  |'
echo '| | Build the first revision of the container image with annotations... | |'
echo '| |_____________________________________________________________________| |'
echo '|_________________________________________________________________________|'

slow 'docker buildx build . -f Dockerfile \
  -t ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} \
  -o "type=oci,dest=${TEMP_LOCATION}/flasksample-${IMAGE_VERSION}-${FIRST_REVISION}.tar,annotation.org.opencontainers.image.created=2023-07-07T00:00:00-08:00,annotation.org.opencontainers.image.version=${IMAGE_VERSION},annotation.org.opencontainers.image.revision=${FIRST_REVISION}" \
  --metadata-file ${TEMP_LOCATION}/flasksample-${IMAGE_VERSION}-${FIRST_REVISION}-metadata.json'
docker buildx build . -f Dockerfile \
  -t ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} \
  -o "type=oci,dest=${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${FIRST_REVISION}.tar,annotation.org.opencontainers.image.created=2023-07-07T00:00:00-08:00,annotation.org.opencontainers.image.version=${IMAGE_VERSION},annotation.org.opencontainers.image.revision=${FIRST_REVISION}" \
  --metadata-file ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${FIRST_REVISION}-metadata.json

echo ' ______________________________________________ '
echo '|  __________________________________________  |'
echo '| | Get the digest for the first revision... | |'
echo '| |__________________________________________| |'
echo '|______________________________________________|'

slow 'export FIRST_REVISION_DIGEST=`cat ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${FIRST_REVISION}-metadata.json | jq -r '."containerimage.descriptor".digest'`
$ echo $FIRST_REVISION_DIGEST'

export FIRST_REVISION_DIGEST=`cat ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${FIRST_REVISION}-metadata.json | jq -r '."containerimage.descriptor".digest'`
echo $FIRST_REVISION_DIGEST

slow
clear

echo ' ____________________________________________________________ '
echo '|  ________________________________________________________  |'
echo '| | Use ORAS to push the first revision to the registry... | |'
echo '| |________________________________________________________| |'
echo '|____________________________________________________________|'

slow 'oras cp --from-oci-layout ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${FIRST_REVISION}.tar:${IMAGE_VERSION} ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}'
oras cp --from-oci-layout ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${FIRST_REVISION}.tar:${IMAGE_VERSION} \
  ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}

echo ' ________________________________________________________________ '
echo '|  ____________________________________________________________  |'
echo '| | Use ORAS to verify the annotations are set on the image... | |'
echo '| |____________________________________________________________| |'
echo '|________________________________________________________________|'

slow 'oras manifest fetch ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .annotations'
oras manifest fetch ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .annotations

slow
clear

echo ' _________________________________________________________________________ '
echo '|  _____________________________________________________________________  |'
echo '| | Use ORAS to fetch the digest for the first revision of the image... | |'
echo '| |_____________________________________________________________________| |'
echo '|_________________________________________________________________________|'

slow 'export OLD_IMAGE_DIGEST=`oras manifest fetch --descriptor ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .digest | tr -d '\''"'\''`
$ echo $OLD_IMAGE_DIGEST'

export OLD_IMAGE_DIGEST=`oras manifest fetch --descriptor ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .digest | tr -d '"'`
echo $OLD_IMAGE_DIGEST

slow
clear

echo ' __________________________________________________________________________ '
echo '|  ______________________________________________________________________  |'
echo '| | Build the second revision of the container image with annotations... | |'
echo '| |______________________________________________________________________| |'
echo '|__________________________________________________________________________|'

slow 'docker buildx build . -f Dockerfile \
  -t ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} \
  -o "type=oci,dest=${TEMP_LOCATION}/flasksample-${IMAGE_VERSION}-${SECOND_REVISION}.tar,annotation.org.opencontainers.image.created=2023-07-10T00:00:00-08:00,annotation.org.opencontainers.image.version=${IMAGE_VERSION},annotation.org.opencontainers.image.revision=${FIRST_REVISION}" \
  --metadata-file ${TEMP_LOCATION}/flasksample-${IMAGE_VERSION}-${SECOND_REVISION}-metadata.json'
docker buildx build . -f Dockerfile \
  -t ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} \
  -o "type=oci,dest=${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${SECOND_REVISION}.tar,annotation.org.opencontainers.image.created=2023-07-10T00:00:00-08:00,annotation.org.opencontainers.image.version=${IMAGE_VERSION},annotation.org.opencontainers.image.revision=${SECOND_REVISION}" \
  --metadata-file ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${SECOND_REVISION}-metadata.json

echo ' _______________________________________________ '
echo '|  ___________________________________________  |'
echo '| | Get the digest for the second revision... | |'
echo '| |___________________________________________| |'
echo '|_______________________________________________|'

slow 'export SECOND_REVISION_DIGEST=`cat ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${SECOND_REVISION}-metadata.json | jq -r '."containerimage.descriptor".digest'`
$ echo $SECOND_REVISION_DIGEST'

export SECOND_REVISION_DIGEST=`cat ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${SECOND_REVISION}-metadata.json | jq -r '."containerimage.descriptor".digest'`
echo $SECOND_REVISION_DIGEST

slow
clear

echo ' _____________________________________________________________ '
echo '|  _________________________________________________________  |'
echo '| | Use ORAS to push the second revision to the registry... | |'
echo '| |_________________________________________________________| |'
echo '|_____________________________________________________________|'

slow 'oras cp --from-oci-layout ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${SECOND_REVISION}.tar:${IMAGE_VERSION} ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}'
oras cp --from-oci-layout ${TEMP_LOCATION}/${REPOSITORY}-${IMAGE_VERSION}-${SECOND_REVISION}.tar:${IMAGE_VERSION} \
  ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION}

echo ' ________________________________________________________________ '
echo '|  ____________________________________________________________  |'
echo '| | Use ORAS to verify the annotations are set on the image... | |'
echo '| |____________________________________________________________| |'
echo '|________________________________________________________________|'

slow 'oras manifest fetch ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .annotations'
oras manifest fetch ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .annotations

echo ' __________________________________________________________________________ '
echo '|  ______________________________________________________________________  |'
echo '| | Use ORAS to fetch the digest for the latest revision of the image... | |'
echo '| |______________________________________________________________________| |'
echo '|__________________________________________________________________________|'

slow 'export NEW_IMAGE_DIGEST=`oras manifest fetch --descriptor ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .digest | tr -d '\''"'\''`
$ echo $NEW_IMAGE_DIGEST'

export NEW_IMAGE_DIGEST=`oras manifest fetch --descriptor ${REGISTRY}/${REPOSITORY}:${IMAGE_VERSION} | jq .digest | tr -d '"'`
echo $NEW_IMAGE_DIGEST

slow
clear

echo ' ___________________________________________________________________________________________ '
echo '|  _______________________________________________________________________________________  |'
echo '| | Fetch the annotations of the first revision and update with end-of-life annotation... | |'
echo '| |_______________________________________________________________________________________| |'
echo '|___________________________________________________________________________________________|'

slow 'oras manifest fetch ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST} \
  | jq .annotations \
  | jq '. += {"vnd.myorganization.image.end-of-life":"2023-07-10T00:00:00-08:00"}' \
  | jq '{"\$manifest":.}' \
  > ${TEMP_LOCATION}/annotations.json'

oras manifest fetch ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST} \
  | jq .annotations \
  | jq '. += {"vnd.myorganization.image.end-of-life":"2023-07-10T00:00:00-08:00"}' \
  | jq '{"$manifest":.}' \
  > ${TEMP_LOCATION}/annotations.json

echo ' ____________________________________________________ '
echo '|  ________________________________________________  |'
echo '| | Here is how the annotations file looks like... | |'
echo '| |________________________________________________| |'
echo '|____________________________________________________|'

slow 'jq . ${TEMP_LOCATION}/annotations.json'

jq . ${TEMP_LOCATION}/annotations.json

echo ' _____________________________________________________________________________________ '
echo '|  _________________________________________________________________________________  |'
echo '| | Push the new lifecycle annotations and refer the first revision of the image... | |'
echo '| |_________________________________________________________________________________| |'
echo '|_____________________________________________________________________________________|'

slow 'oras attach --artifact-type application/vnd.myorganization.image.lifecycle.metadata \
  --annotation-file ${TEMP_LOCATION}/annotations.json \
  ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST}' 

oras attach --artifact-type application/vnd.myorganization.image.lifecycle.metadata \
  --annotation-file ${TEMP_LOCATION}/annotations.json \
  ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST} 

slow
clear

echo ' ____________________________________________________________ '
echo '|  ________________________________________________________  |'
echo '| | Show the annotations for each revision of the image... | |'
echo '| |________________________________________________________| |'
echo '|____________________________________________________________|'

slow 'oras manifest fetch ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST} | jq .annotations'
oras manifest fetch ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST} | jq .annotations

slow 'oras manifest fetch ${REGISTRY}/${REPOSITORY}@${NEW_IMAGE_DIGEST} | jq .annotations'
oras manifest fetch ${REGISTRY}/${REPOSITORY}@${NEW_IMAGE_DIGEST} | jq .annotations

echo ' _______________________________________________________________________________ '
echo '|  ___________________________________________________________________________  |'
echo '| | Oops... for the old revision we do not see the updated annotations...     | |'
echo '| | Because we need to pull the referrer artifact with updated annotations... | |'
echo '| | First, we need to get the referrer artifact from specified type...        | |'
echo '| |___________________________________________________________________________| |'
echo '|_______________________________________________________________________________|'

slow 'export ANNOTATIONS_ARTIFACT_DIGEST=`oras discover --artifact-type "application/vnd.myorganization.image.lifecycle.metadata" \
  ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST} -o json \
  | jq ''.manifests[0].digest'' \
  | tr -d '\''"'\''`
$ echo $ANNOTATIONS_ARTIFACT_DIGEST'

export ANNOTATIONS_ARTIFACT_DIGEST=`oras discover --artifact-type "application/vnd.myorganization.image.lifecycle.metadata" \
  ${REGISTRY}/${REPOSITORY}@${OLD_IMAGE_DIGEST} -o json \
  | jq '.manifests[0].digest' \
  | tr -d '"'`
echo $ANNOTATIONS_ARTIFACT_DIGEST

slow 'oras manifest fetch ${REGISTRY}/${REPOSITORY}@${ANNOTATIONS_ARTIFACT_DIGEST} | jq .annotations'
oras manifest fetch ${REGISTRY}/${REPOSITORY}@${ANNOTATIONS_ARTIFACT_DIGEST} | jq .annotations

slow