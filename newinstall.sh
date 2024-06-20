: ${OSH_HELM_REPO:="../openstack-helm"}
: ${OSH_PATH:="../openstack-helm"}

OSH_INFRA_HELM_REPO=$(pwd)
# export OPENSTACK_RELEASE=2023.2
# export FEATURES="${OPENSTACK_RELEASE} ubuntu_jammy"
helm plugin install https://opendev.org/openstack/openstack-helm-plugin
tee > /tmp/openstack_namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: diylink-openstack
EOF
kubectl apply -f /tmp/openstack_namespace.yaml
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --version="4.8.3" \
    --namespace=diylink-openstack \
    --set controller.kind=Deployment \
    --set controller.admissionWebhooks.enabled="false" \
    --set controller.scope.enabled="true" \
    --set controller.service.enabled="false" \
    --set controller.ingressClassResource.name=nginx \
    --set controller.ingressClassResource.controllerValue="k8s.io/ingress-nginx" \
    --set controller.ingressClassResource.default="false" \
    --set controller.ingressClass=nginx \
    --set controller.labels.app=ingress-api



kubectl label --overwrite nodes --all openstack-control-plane=enabled
kubectl label --overwrite nodes --all openstack-compute-node=enabled
kubectl label --overwrite nodes --all openvswitch=enabled
#会在有node-role.kubernetes.io/control-plane标签的node创建ovs
kubectl label --overwrite nodes --all l3-agent=enabled 
kubectl label --overwrite nodes --all openstack-network-node=enabled


helm dependency build rabbitmq
helm upgrade --install rabbitmq ${OSH_INFRA_HELM_REPO}/rabbitmq --namespace=diylink-openstack \
    --set pod.replicas.server=1 \
    --set volume.enabled=true    \
    --set volume.class_name=csi-cephfs-sc    \
    --timeout=600s     \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c rabbitmq ${FEATURES})
helm osh wait-for-pods openstack

helm dependency build mariadb
helm upgrade --install mariadb ${OSH_INFRA_HELM_REPO}/mariadb \
    --namespace=diylink-openstack \
    --set volume.use_local_path_for_single_pod_cluster.enabled=false \
    --set volume.enabled=true \
    --set volume.class_name=csi-cephfs-sc \
    --set volume.backup.class_name=csi-cephfs-sc \
    --set pod.replicas.server=1 \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c mariadb ${FEATURES})
helm osh wait-for-pods openstack

helm dependency build memcached
helm upgrade --install memcached ${OSH_INFRA_HELM_REPO}/memcached \
    --namespace=diylink-openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c memcached ${FEATURES})
helm osh wait-for-pods openstack

helm dependency build keystone
helm upgrade --install keystone ${OSH_INFRA_HELM_REPO}/keystone \
    --namespace=diylink-openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c keystone ${FEATURES})
helm osh wait-for-pods openstack

helm dependency build openvswitch
helm upgrade --install openvswitch ${OSH_INFRA_HELM_REPO}/openvswitch \
  --namespace=diylink-openstack \
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

helm dependency build ovn
helm upgrade --install ovn ${OSH_INFRA_HELM_REPO}/ovn \
  --namespace=diylink-openstack \
  --values=/tmp/ovn.yaml \
  --set pod.replicas.ovn_ovsdb_nb=1 \
  --set pod.replicas.ovn_ovsdb_sb=1 \
  --set pod.replicas.ovn_northd=1 \
  --set volume.ovn_ovsdb_nb.class_name=csi-cephfs-sc \
  --set volume.ovn_ovsdb_sb.class_name=csi-cephfs-sc \
  --set conf.onv_cms_options_gw_enabled=enable-chassis-as-gw \
  $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c ovn ${FEATURES}) 

#NOTE: Wait for deploy
helm osh wait-for-pods openstack

helm dependency build neutron
helm upgrade --install neutron ${OSH_INFRA_HELM_REPO}/neutron \
    --namespace=openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c neutron ovn)

helm dependency build horizon
helm upgrade --install horizon ${OSH_INFRA_HELM_REPO}/horizon \
    --namespace=diylink-openstack \
    $(helm osh get-values-overrides -p ${OSH_HELM_REPO} -c horizon ${FEATURES})
helm osh wait-for-pods openstack   

