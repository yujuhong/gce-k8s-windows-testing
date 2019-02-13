#!/bin/bash

set -o nounset
set -o pipefail
set -o xtrace

# When running in prow, the working directory is the root of the test-infra
# repository.

# Wait 5 minutes for the test images to be pulled onto the nodes
sleep 5m

# Taint the Linux nodes to prevent the test workloads from landing on them.
# TODO: remove this once the issue is resolved:
# https://github.com/kubernetes/kubernetes/issues/69892
LINUX_NODES=$(kubectl get nodes -l beta.kubernetes.io/os=linux -o name)
LINUX_NODE_COUNT=$(echo ${LINUX_NODES} | wc -w)
for node in $LINUX_NODES; do
  kubectl taint node $node node-under-test=false:NoSchedule
done

# Untaint the windows nodes to allow test workloads without tolerations to be
# scheduled onto them.
WINDOWS_NODES=$(kubectl get nodes -l beta.kubernetes.io/os=windows -o name)
for node in $WINDOWS_NODES; do
  kubectl taint node $node node.kubernetes.io/os:NoSchedule-
done

# Download and set the list of test image repositories to use.

# curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list-ws1803 -o ${WORKSPACE}/repo-list.yaml
# Temporarily switching to use the claudiubelu repos to test the new images.
cat >> ${WORKSPACE}/repo-list.yaml <<EOF
dockerLibraryRegistry: claudiubelu
e2eRegistry: claudiubelu
gcRegistry: claudiubelu
hazelcastRegistry: claudiubelu
PrivateRegistry: claudiubelu
sampleRegistry: claudiubelu
stormRegistry: claudiubelu
zookeeperRegistry: claudiubelu
EOF

export KUBE_TEST_REPO_LIST=${WORKSPACE}/repo-list.yaml

# Download the list of tests to exclude.
curl https://raw.githubusercontent.com/e2e-win/e2e-win-prow-deployment/master/exclude_conformance_test.txt -o ${WORKSPACE}/exclude_conformance_test.txt
# Ignore lines starting with "#"
EXCLUDED_TESTS=$(cat ${WORKSPACE}/exclude_conformance_test.txt |
  tr -d '\r' |                # remove Windows carriage returns
  grep -v '^#' |              # ignore comment lines
  grep -v '^$' |              # ignore blank lines
  tr -s '\n' '|' |            # coalesce newlines into |
  tr -s ' ' '.' |             # coalesce spaces into .
  sed -e 's/[]\[()]/\\&/g' |  # escape brackets and parentheses
  sed -e 's/.$//g')           # remove final | added by tr

# When using customized test command (which we are now), report-dir is not set
# by default, so set it here.
# The test framework will not proceed to run tests unless all nodes are ready
# AND schedulable. Allow not-ready nodes since we make Linux nodes
# unschedulable.
# Do not set --disable-log-dump because upstream cannot handle dumping logs
# from windows nodes yet.
./hack/ginkgo-e2e.sh $@ --report-dir=${ARTIFACTS} --allowed-not-ready-nodes=${LINUX_NODE_COUNT} --ginkgo.skip=${EXCLUDED_TESTS}
