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
# bash -x build/pr_check_inner.sh

# copy the workspace from the Jenkins job off the ro volume into this container
mkdir /container_workspace
cp -r /workspace/. /container_workspace
cd /container_workspace

mkdir -p /container_workspace/bin
cp /opt/app-root/src/go/bin/* /container_workspace/bin

export KUBEBUILDER_ASSETS=/container_workspace/testbin/bin

(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

source build/template_check.sh

export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH="/bins:$PATH"

chmod 600 minikube-ssh-ident

ssh -o StrictHostKeyChecking=no $MINIKUBE_USER@$MINIKUBE_HOST -i minikube-ssh-ident "minikube delete"
ssh -o StrictHostKeyChecking=no $MINIKUBE_USER@$MINIKUBE_HOST -i minikube-ssh-ident "minikube start --cpus 6 --disk-size 10GB --memory 16000MB --kubernetes-version=1.23.5 --addons=metrics-server --disable-optimizations"

export MINIKUBE_IP=`ssh -o StrictHostKeyChecking=no $MINIKUBE_USER@$MINIKUBE_HOST -i minikube-ssh-ident "minikube ip"`

scp -o StrictHostKeyChecking=no -i minikube-ssh-ident $MINIKUBE_USER@$MINIKUBE_HOST:$MINIKUBE_ROOTDIR/.minikube/profiles/minikube/client.key ./
scp -i minikube-ssh-ident $MINIKUBE_USER@$MINIKUBE_HOST:$MINIKUBE_ROOTDIR/.minikube/profiles/minikube/client.crt ./
scp -i minikube-ssh-ident $MINIKUBE_USER@$MINIKUBE_HOST:$MINIKUBE_ROOTDIR/.minikube/ca.crt ./

ssh -o ExitOnForwardFailure=yes -f -N -L 127.0.0.1:8444:$MINIKUBE_IP:8443 -i minikube-ssh-ident $MINIKUBE_USER@$MINIKUBE_HOST

cat > kube-config <<- EOM
apiVersion: v1
clusters:
- cluster:
    certificate-authority: $PWD/ca.crt
    server: https://127.0.0.1:8444
  name: 127-0-0-1:8444
contexts:
- context:
    cluster: 127-0-0-1:8444
    user: remote-minikube
  name: remote-minikube
users:
- name: remote-minikube
  user:
    client-certificate: $PWD/client.crt
    client-key: $PWD/client.key
current-context: remote-minikube
kind: Config
preferences: {}
EOM

export PATH="$KUBEBUILDER_ASSETS:$PATH"
export PATH="/root/go/bin:$PATH"

export KUBECONFIG=$PWD/kube-config
export KUBECTL_CMD="kubectl "
$KUBECTL_CMD config use-context remote-minikube
$KUBECTL_CMD get pods --all-namespaces=true

source build/kube_setup.sh

export IMAGE_TAG=`git rev-parse --short=8 HEAD`

$KUBECTL_CMD create namespace clowder-system

mkdir artifacts

cat manifest.yaml > artifacts/manifest.yaml

sed -i "s/clowder:latest/clowder:$IMAGE_TAG/g" manifest.yaml

$KUBECTL_CMD apply -f manifest.yaml --validate=false

## The default generated config isn't quite right for our tests - so we'll create a new one and restart clowder
$KUBECTL_CMD apply -f clowder-config.yaml -n clowder-system
$KUBECTL_CMD delete pod -n clowder-system -l operator-name=clowder

# Wait for operator deployment...
$KUBECTL_CMD rollout status deployment clowder-controller-manager -n clowder-system

$KUBECTL_CMD krew install kuttl

set +e

$KUBECTL_CMD get env
$KUBECTL_CMD get env

source build/run_kuttl.sh --report xml
# KUTTL_RESULT=$?
mv kuttl-report.xml artifacts/junit-kuttl.xml

CLOWDER_PODS=$($KUBECTL_CMD get pod -n clowder-system -o jsonpath='{.items[*].metadata.name}')
for pod in $CLOWDER_PODS; do
    $KUBECTL_CMD logs $pod -n clowder-system > artifacts/$pod.log
    $KUBECTL_CMD logs $pod -n clowder-system | ./parse-controller-logs > artifacts/$pod-parsed-controller-logs.log
done

# Grab the metrics
$KUBECTL_CMD port-forward svc/clowder-controller-manager-metrics-service-non-auth -n clowder-system 8080 &
sleep 5
curl 127.0.0.1:8080/metrics > artifacts/clowder-metrics

STRIMZI_PODS=$($KUBECTL_CMD get pod -n strimzi -o jsonpath='{.items[*].metadata.name}')
for pod in $STRIMZI_PODS; do
    $KUBECTL_CMD logs $pod -n strimzi > artifacts/$pod.log
done
set -e

# exit $KUTTL_RESULT


TEST_RESULT=$?

mkdir artifacts

# docker cp $CONTAINER_NAME:/container_workspace/artifacts/ $PWD

# docker rm -f $CONTAINER_NAME
set -e

exit $TEST_RESULT
