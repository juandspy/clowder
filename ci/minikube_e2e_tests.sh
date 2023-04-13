#!/bin/bash

# DOCKER_CONF="$PWD/.docker"
# mkdir -p "$DOCKER_CONF"

make envtest
make update-version

CLOWDER_VERSION=`git describe --tags`

# IMG=$IMAGE_NAME:$IMAGE_TAG BASE_IMG=$BASE_IMG make docker-build
# IMG=$IMAGE_NAME:$IMAGE_TAG make docker-push

# docker rm clowdercopy || true
# docker create --name clowdercopy $IMAGE_NAME:$IMAGE_TAG
# docker cp clowdercopy:/manifest.yaml .
# docker rm clowdercopy || true

# CONTAINER_NAME="clowder-pr-check-pipeline-$ghprbPullId"
# docker rm -f $CONTAINER_NAME || true
# NOTE: Make sure this volume is mounted 'ro', otherwise Jenkins cannot clean up the workspace due to file permission errors
set +e
# docker run -i \
#     --name $CONTAINER_NAME \
#     -v $PWD:/workspace:ro \
#     -v `$PWD/bin/setup-envtest use -p path`:/bins:ro \
#     -e IMAGE_NAME=$IMAGE_NAME \
#     -e IMAGE_TAG=$IMAGE_TAG \
#     -e QUAY_USER=$QUAY_USER \
#     -e QUAY_TOKEN=$QUAY_TOKEN \
#     -e MINIKUBE_HOST=$MINIKUBE_HOST \
#     -e MINIKUBE_ROOTDIR=$MINIKUBE_ROOTDIR \
#     -e MINIKUBE_USER=$MINIKUBE_USER \
#     -e CLOWDER_VERSION=$CLOWDER_VERSION \
#     $BASE_IMG \
#     /workspace/build/pr_check_inner.sh
# TEST_RESULT=$?

#./workspace/build/pr_check_inner.sh
bash -x build/pr_check_inner.sh

TEST_RESULT=$?

mkdir artifacts

# docker cp $CONTAINER_NAME:/container_workspace/artifacts/ $PWD

# docker rm -f $CONTAINER_NAME
set -e

exit $TEST_RESULT
