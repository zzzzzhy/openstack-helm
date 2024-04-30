mkdir ~/osh
cd ~/osh
git clone https://github.com/zzzzzhy/openstack-helm.git
git clone https://opendev.org/openstack/openstack-helm-infra.git
export OPENSTACK_RELEASE=2023.2
export CONTAINER_DISTRO_NAME=ubuntu
export CONTAINER_DISTRO_VERSION=jammy
cd ~/osh/openstack-helm
./tools/deployment/common/prepare-charts.sh


kubectl label --overwrite nodes --all openstack-control-plane=enabled
kubectl label --overwrite nodes --all openstack-compute-node=enabled
kubectl label --overwrite nodes --all openvswitch=enabled
kubectl label --overwrite nodes -l "node-role.kubernetes.io/control-plane" l3-agent=enabled #会在有node-role.kubernetes.io/control-plane标签的node创建ovs
kubectl label --overwrite nodes -l "node-role.kubernetes.io/control-plane" openstack-network-node=enabled

apt install jq
helm plugin install https://opendev.org/openstack/openstack-helm-plugin.git

./tools/deployment/common/setup-client.sh
./tools/deployment/component/common/rabbitmq.sh
./tools/deployment/component/common/mariadb.sh
./tools/deployment/component/common/memcached.sh
./tools/deployment/component/keystone/keystone.sh
./tools/deployment/component/ovn/120-openvswitch.sh
./tools/deployment/component/ovn/ovn.sh
./tools/deployment/component/ovn/140-compute-kit.sh