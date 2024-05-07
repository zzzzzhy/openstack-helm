#!/bin/bash

#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -xe

tee /tmp/nfs-ns.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: nfs
    name: nfs
  name: nfs
EOF

kubectl create -f /tmp/nfs-ns.yaml

#NOTE: Deploy command
: ${OSH_INFRA_PATH:="../openstack-helm-infra"}
helm upgrade --install nfs-provisioner ${OSH_INFRA_PATH}/nfs-provisioner \
    --namespace=nfs \
    --set storageclass.name=general \
    ${OSH_EXTRA_HELM_ARGS_NFS_PROVISIONER}

#NOTE: Wait for deploy
helm osh wait-for-pods nfs
