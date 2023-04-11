def secrets = [
    [path: params.VAULT_PATH_SVC_ACCOUNT_EPHEMERAL, engineVersion: 1, secretValues: [
        [envVar: 'OC_LOGIN_TOKEN_DEV', vaultKey: 'oc-login-token-dev'],
        [envVar: 'OC_LOGIN_SERVER_DEV', vaultKey: 'oc-login-server-dev']]],
    [path: params.VAULT_PATH_QUAY_PUSH, engineVersion: 1, secretValues: [
        [envVar: 'QUAY_USER', vaultKey: 'user'],
        [envVar: 'QUAY_TOKEN', vaultKey: 'token']]],
    [path: params.VAULT_PATH_RHR_PULL, engineVersion: 1, secretValues: [
        [envVar: 'RH_REGISTRY_USER', vaultKey: 'user'],
        [envVar: 'RH_REGISTRY_TOKEN', vaultKey: 'token']]],
    [path: params.VAULT_PATH_MINIKUBE, engineVersion: 1, secretValues: [
        [envVar: 'MINIKUBE_HOST', vaultKey: 'hostname'],
        [envVar: 'MINIKUBE_USER', vaultKey: 'user'],
        [envVar: 'MINIKUBE_ROOTDIR', vaultKey: 'rootdir']]]
]

def configuration = [vaultUrl: params.VAULT_ADDRESS, vaultCredentialId: params.VAULT_CREDS_ID, engineVersion: 1]

def changes_excluding_docs() {
    target_branch="${ghprbTargetBranch}"
    docs_regex = ~"(^docs.*|^.*.adoc)"

    check_git_diff = sh("git --no-pager diff --name-only origin/${target_branch} | grep -v ${docs_regex} | grep -q '.'")
}

def create_junit_dummy_result() {
    sh '''
    mkdir -p 'artifacts'

    cat <<- EOF > 'artifacts/junit-dummy.xml'
	<?xml version="1.0" encoding="UTF-8"?>
	<testsuite tests="1">
	    <testcase classname="dummy" name="dummy-empty-test"/>
	</testsuite>
	EOF
    '''
}

pipeline {
    agent { label 'insights' }
    options {
        timestamps()
    }
    environment {
        CLOWDER_VERSION=sh(script: "git describe --tags", returnStdout: true).trim()

        BASE_TAG=sh(script:"cat go.mod go.sum Dockerfile.base | sha256sum  | head -c 8", returnStdout: true)
        BASE_IMG="quay.io/cloudservices/clowder-base:${BASE_TAG}"

        IMAGE_TAG=sh(script:"git rev-parse --short=8 HEAD", returnStdout: true).trim()
        IMAGE_NAME="quay.io/cloudservices/clowder"

        MINIKUBE_SSH_IDENT=sh("echo $MINIKUBE_SSH_KEY > minikube-ssh-ident", returnStdout: true).trim()

        CICD_URL="https://raw.githubusercontent.com/RedHatInsights/cicd-tools/main"
    }

    stages {
        // stage('Check For Changes') {
        //     steps {
        //         script {
        //             def hasChange = changes_excluding_docs()

        //             sh '''
        //             if [ ! ${hasChange} ]; then
        //                 echo "No code changes detected, exiting"
        //                 ${create_junit_dummy_result()}
        //                 exit 0
        //             fi
        //             '''
                    


        //         }
        //     }
        // }

        stage('Build and Push Base Image') {
            steps {
                withVault([configuration: configuration, vaultSecrets: secrets]) {
                    sh '''
                    ./ci/build_push_base_img.sh
                    '''
                }
            }
        }

        stage('Run Tests') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        withVault([configuration: configuration, vaultSecrets: secrets]) {
                            sh '''
                            TEST_CONTAINER="clowder-ci-unit-tests-${IMAGE_TAG}"

                            make envtest
                            make update-version

                            docker login -u="$QUAY_USER" -p="$QUAY_TOKEN" quay.io
                            
                            docker build -f ci/Dockerfile.unit_tests --build-arg BASE_IMAGE=${BASE_IMG} -t $TEST_CONTAINER .

                            docker run -i \
                                -v `$PWD/bin/setup-envtest use -p path`:/bins:ro \
                                -e IMAGE_NAME=${IMAGE_NAME} \
                                -e IMAGE_TAG=${IMAGE_TAG} \
                                -e QUAY_USER=$QUAY_USER \
                                -e QUAY_TOKEN=$QUAY_TOKEN \
                                -e MINIKUBE_HOST=$MINIKUBE_HOST \
                                -e MINIKUBE_ROOTDIR=$MINIKUBE_ROOTDIR \
                                -e MINIKUBE_USER=$MINIKUBE_USER \
                                -e CLOWDER_VERSION=$CLOWDER_VERSION \
                                $TEST_CONTAINER \
                                make test
                            UNIT_TEST_RESULT=$?

                            if [[ $UNIT_TEST_RESULT -ne 0 ]]; then
                                exit $UNIT_TEST_RESULT
                            fi
                            '''
                        }
                    }
                }

                stage('Minikube E2E Tests') {
                    steps {
                        withVault([configuration: configuration, vaultSecrets: secrets]) {
                            sh '''
                            set -exv

                            CONTAINER_NAME="clowder-ci-minikube-e2e-tests-$IMAGE_TAG"

                            docker login -u="$QUAY_USER" -p="$QUAY_TOKEN" quay.io

                            docker build -f Dockerfile --build-arg BASE_IMAGE=${BASE_IMG} -t $CONTAINER_NAME .
                            
                            docker run -i \
                                --name $CONTAINER_NAME \
                                -v $PWD:/workspace:ro \
                                -v `$PWD/bin/setup-envtest use -p path`:/bins:ro \
                                -e IMAGE_NAME=$IMAGE_NAME \
                                -e IMAGE_TAG=$IMAGE_TAG \
                                -e QUAY_USER=$QUAY_USER \
                                -e QUAY_TOKEN=$QUAY_TOKEN \
                                -e MINIKUBE_HOST=$MINIKUBE_HOST \
                                -e MINIKUBE_ROOTDIR=$MINIKUBE_ROOTDIR \
                                -e MINIKUBE_USER=$MINIKUBE_USER \
                                -e CLOWDER_VERSION=$CLOWDER_VERSION \
                                $BASE_IMG \
                                ./ci/minikube_e2e_tests.sh
                            TEST_RESULT=$?

                            mkdir artifacts

                            docker rm -f $CONTAINER_NAME
                            set -e

                            exit $TEST_RESULT
                            '''
                        }
                    }
                }
            }
        }  
    }
}
