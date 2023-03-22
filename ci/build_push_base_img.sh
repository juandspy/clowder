#!/bin/bash

echo "$MINIKUBE_SSH_KEY" > minikube-ssh-ident

while read line; do
    if [ ${#line} -ge 100 ]; then
        echo "Commit messages are limited to 100 characters."
        echo "The following commit message has ${#line} characters."
        echo "${line}"
        exit 1
    fi
done <<< "$(git log --pretty=format:%s $(git merge-base master HEAD)..HEAD)"

set -exv

# BASE_TAG=`cat go.mod go.sum Dockerfile.base | sha256sum  | head -c 8`
# BASE_IMG=quay.io/cloudservices/clowder-base:$BASE_TAG

DOCKER_CONF="$PWD/.docker"
mkdir -p "$DOCKER_CONF"
docker login -u="$QUAY_USER" -p="$QUAY_TOKEN" quay.io


RESPONSE=$( \
    curl -Ls -H "Authorization: Bearer $QUAY_API_TOKEN" \
    "https://quay.io/api/v1/repository/cloudservices/clowder-base/tag/?specificTag=$BASE_TAG" \
)

echo "received HTTP response: $RESPONSE"

# find all non-expired tags
VALID_TAGS_LENGTH=$(echo $RESPONSE | jq '[ .tags[] | select(.end_ts == null) ] | length')

# Check if Clowder's base image tag already exists
if [[ "$VALID_TAGS_LENGTH" -eq 0 ]]; then
    BASE_IMG=$BASE_IMG make docker-build-and-push-base
fi