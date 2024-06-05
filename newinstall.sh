: ${OSH_HELM_REPO:="../openstack-helm"}
: ${OSH_PATH:="../openstack-helm"}
helm plugin install https://opendev.org/openstack/openstack-helm-plugin
tee > /tmp/openstack_namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openstack
EOF
kubectl apply -f /tmp/openstack_namespace.yaml
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --version="4.8.3" \
    --namespace=openstack \
    --set controller.kind=Deployment \
    --set controller.admissionWebhooks.enabled="false" \
    --set controller.scope.enabled="true" \
    --set controller.service.enabled="false" \
    --set controller.ingressClassResource.name=nginx \
    --set controller.ingressClassResource.controllerValue="k8s.io/ingress-nginx" \
    --set controller.ingressClassResource.default="false" \
    --set controller.ingressClass=nginx \
    --set controller.labels.app=ingress-api
export OPENSTACK_RELEASE=2023.2
# Features enabled for the deployment. This is used to look up values overrides.
export FEATURES="${OPENSTACK_RELEASE} ubuntu_jammy"


kubectl label --overwrite nodes --all openstack-control-plane=enabled
kubectl label --overwrite nodes --all openstack-compute-node=enabled
kubectl label --overwrite nodes --all openvswitch=enabled
#会在有node-role.kubernetes.io/control-plane标签的node创建ovs
kubectl label --overwrite nodes --all l3-agent=enabled 
kubectl label --overwrite nodes --all openstack-network-node=enabled

apt install jq -y
OSH_INFRA_HELM_REPO=$(pwd)
helm upgrade --install rabbitmq ${OSH_INFRA_HELM_REPO}/rabbitmq --namespace=openstack \
    --set pod.replicas.server=1 \
    --set volume.enabled=false    \
    --timeout=600s     \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c rabbitmq ${FEATURES})
helm osh wait-for-pods openstack

helm upgrade --install mariadb ${OSH_INFRA_HELM_REPO}/mariadb \
    --namespace=openstack \
    --set volume.use_local_path_for_single_pod_cluster.enabled=false \
    --set volume.enabled=true \
    --set volume.class_name=csi-cephfs-sc \
    --set volume.backup.class_name=csi-cephfs-sc \
    --set pod.replicas.server=1 \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c mariadb ${FEATURES})
helm osh wait-for-pods openstack

helm upgrade --install memcached ${OSH_INFRA_HELM_REPO}/memcached \
    --namespace=openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c memcached ${FEATURES})
helm osh wait-for-pods openstack

helm upgrade --install keystone ${OSH_INFRA_HELM_REPO}/keystone \
    --namespace=openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c keystone ${FEATURES})
helm osh wait-for-pods openstack

helm upgrade --install openvswitch ${OSH_INFRA_HELM_REPO}/openvswitch \
  --namespace=openstack \
  --set conf.ovs_hw_offload.enabled=true \
  $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c openvswitch ${FEATURES}) 
helm osh wait-for-pods openstack


tee /tmp/ovn.yaml << EOF
volume:
  ovn_ovsdb_nb:
    enabled: true
  ovn_ovsdb_sb:
    enabled: true
network:
  interface:
    tunnel: null
conf:
  ovn_bridge_mappings: publicnet:br-ex
  auto_bridge_add:
    br-ex: provider1
    br-ex: bond2.2125
EOF

#NOTE: Deploy command
helm upgrade --install ovn ${OSH_INFRA_HELM_REPO}/ovn \
  --namespace=openstack \
  --values=/tmp/ovn.yaml \
  --set volume.ovn_ovsdb_nb.class_name=csi-cephfs-sc \
  --set volume.ovn_ovsdb_sb.class_name=csi-cephfs-sc \
  --set conf.onv_cms_options_gw_enabled=enable-chassis-as-gw \
  $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c ovn ${FEATURES}) 

#NOTE: Wait for deploy
helm osh wait-for-pods openstack

helm upgrade --install neutron ./neutron \
    --namespace=openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c neutron ovn)

helm upgrade --install horizon $(pwd)/horizon \
    --namespace=openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c horizon ${FEATURES})
helm osh wait-for-pods openstack   





apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-cephfs-sc
provisioner: cephfs.csi.ceph.com
parameters:
  clusterID: 6244bed2-1ef9-11ef-89e7-79ea293d4d88
  fsName: diylink-fs  ## cephfs的名称
  pool: cephfs_data
  #  mounter: fuse       挂载方式
  csi.storage.k8s.io/provisioner-secret-name: csi-ceph-secret
  csi.storage.k8s.io/provisioner-secret-namespace: default
  csi.storage.k8s.io/controller-expand-secret-name: csi-ceph-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: default
  csi.storage.k8s.io/node-stage-secret-name: csi-ceph-secret
  csi.storage.k8s.io/node-stage-secret-namespace: default
reclaimPolicy: Delete
allowVolumeExpansion: true