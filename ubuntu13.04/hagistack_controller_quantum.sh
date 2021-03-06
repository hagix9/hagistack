#!/bin/bash
#description "OpenStack Deploy Script for Ubuntu 13.04"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm cinder-volumes and setting hosts
#Number of necessary NIC 2
#networking
#auto eth0
#iface eth0 inet static
#       address 192.168.10.50
#       netmask 255.255.255.0
#       network 192.168.10.0
#       broadcast 192.168.10.255
#       gateway 192.168.10.1
#       dns-nameservers 192.168.10.1

#auto  eth1
#iface eth1 inet manual
#        up   ifconfig $IFACE 0.0.0.0 up
#        up   ip link set $IFACE promisc on
#        down ip link set $IFACE promisc off
#        down ifconfig $IFACE down

### ENV ###
#For openstack admin user
STACK_USER=stack
STACK_PASS=stack

#For EXT NIC
EXT_NIC=eth1

#For nova.conf
NOVA_CONTROLLER_IP=192.168.10.50
NOVA_CONTROLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.50

#mysql(root) pass
MYSQL_PASS=nova 

#rabbitmq setting for common
RABBIT_PASS=password

#mysql pass
MYSQL_PASS_KEYSTONE=password
MYSQL_PASS_GLANCE=password
MYSQL_PASS_QUANTUM=password
MYSQL_PASS_CINDER=password
MYSQL_PASS_NOVA=password

#openstack env
export ADMIN_PASSWORD=secrete
export SERVICE_PASSWORD=secrete

#tenant settings
TENANT_NAME=tenant01
TENANT_ADMIN=admin01
TENANT_ADMIN_PASS=admin01
TENANT_USER=user01
TENANT_USER_PASS=user01
TENANT_NETWORK=private01
TENANT_SUBNET=10.10.10.0/24
TENANT_NAME_SERVER=8.8.8.8
GATEWAY=192.168.10.1
EXT_NETWORK=192.168.10.0/24
IP_POOL_START=192.168.10.200
IP_POOL_END=192.168.10.250

#read the configuration from external
if [ -f stack.env ] ; then
  . ./stack.env
fi

### Preparing Ubuntu ###
#os update
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y

#install ntp
sudo apt-get install ntp -y

#install network software
sudo apt-get install -y vlan bridge-utils

#kernel setting
cat << SYSCTL | sudo tee -a /etc/sysctl.conf > /dev/null
net.ipv4.ip_forward=1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
SYSCTL
sudo sysctl -p

### MySQL ###
#mysql setting
cat <<MYSQL_DEBCONF | sudo debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.5 mysql-server/start_on_boot boolean true
MYSQL_DEBCONF

#install mysql
sudo apt-get install -y mysql-server python-mysqldb

#mysql setting for contoller node
sudo sed -i 's#127.0.0.1#0.0.0.0#g' /etc/mysql/my.cnf
sudo restart mysql

#keystone db create
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists keystone;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database keystone character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'%' identified by '$MYSQL_PASS_KEYSTONE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'localhost' identified by '$MYSQL_PASS_KEYSTONE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'$NOVA_CONTROLLER_HOSTNAME' identified by '$MYSQL_PASS_KEYSTONE';"

#glance db create
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists glance;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database glance character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'%' identified by '$MYSQL_PASS_GLANCE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'localhost' identified by '$MYSQL_PASS_GLANCE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'$NOVA_CONTROLLER_HOSTNAME' identified by '$MYSQL_PASS_GLANCE';"

#quantum db create
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists ovs_quantum;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database ovs_quantum character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on ovs_quantum.* to 'quantum'@'%' identified by '$MYSQL_PASS_QUANTUM';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on ovs_quantum.* to 'quantum'@'localhost' identified by '$MYSQL_PASS_QUANTUM';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on ovs_quantum.* to 'quantum'@'$NOVA_CONTROLLER_HOSTNAME' identified by '$MYSQL_PASS_QUANTUM';"

#cinder db create
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists cinder;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database cinder character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'%' identified by '$MYSQL_PASS_CINDER';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'localhost' identified by '$MYSQL_PASS_CINDER';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'$NOVA_CONTROLLER_HOSTNAME' identified by '$MYSQL_PASS_CINDER';"

#nova db create
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists nova;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database nova;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on nova.* to 'nova'@'%' identified by '$MYSQL_PASS_NOVA';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on nova.* to 'nova'@'localhost' identified by '$MYSQL_PASS_NOVA';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on nova.* to 'nova'@'$NOVA_CONTROLLER_HOSTNAME' identified by '$MYSQL_PASS_NOVA';"

### RabbitMQ ###
#install rabbitmq
sudo apt-get install -y rabbitmq-server

#rabbitmq setting for controller node
sudo rabbitmqctl add_vhost /nova
sudo rabbitmqctl add_user nova $RABBIT_PASS
sudo rabbitmqctl set_permissions -p /nova nova ".*" ".*" ".*"
sudo rabbitmqctl delete_user guest

### Keystone ###
#keystone install
sudo apt-get install -y keystone

#keystone setting
sudo cp -a /etc/keystone /etc/keystone_bak
sudo sed -i "s#sqlite:////var/lib/keystone/keystone.db#mysql://keystone:$MYSQL_PASS_KEYSTONE@$NOVA_CONTROLLER_HOSTNAME/keystone?charset=utf8#" /etc/keystone/keystone.conf

#keystone service init
sudo stop keystone ; sudo start keystone

#keystone db sync
sudo keystone-manage db_sync

#keystone setting2
sudo \rm -rf /usr/local/src/*keystone_basic.sh*
sudo \rm -rf /usr/local/src/*keystone_endpoints_basic.sh*
sudo -E wget -P /usr/local/src https://raw.github.com/mseknibilel/OpenStack-Grizzly-Install-Guide/OVS_MultiNode/KeystoneScripts/keystone_basic.sh
sudo -E wget -P /usr/local/src https://raw.github.com/mseknibilel/OpenStack-Grizzly-Install-Guide/OVS_MultiNode/KeystoneScripts/keystone_endpoints_basic.sh
sudo sed -i "s@HOST_IP=10.10.10.51@HOST_IP=$NOVA_CONTROLLER_IP@" /usr/local/src/keystone_basic.sh
sudo sed -i "s@HOST_IP=10.10.10.51@HOST_IP=$NOVA_CONTROLLER_IP@" /usr/local/src/keystone_endpoints_basic.sh
sudo sed -i "s@EXT_HOST_IP=192.168.100.51@EXT_HOST_IP=$NOVA_CONTROLLER_IP@" /usr/local/src/keystone_endpoints_basic.sh
sudo sed -i "s@MYSQL_USER=keystoneUser@MYSQL_USER=keystone@" /usr/local/src/keystone_endpoints_basic.sh
sudo sed -i "s@MYSQL_PASSWORD=keystonePass@MYSQL_PASSWORD=$MYSQL_PASS_KEYSTONE@" /usr/local/src/keystone_endpoints_basic.sh
sudo chmod +x /usr/local/src/keystone_basic.sh
sudo chmod +x /usr/local/src/keystone_endpoints_basic.sh
sudo -E /usr/local/src/keystone_basic.sh
sudo -E /usr/local/src/keystone_endpoints_basic.sh

#credential file make
cd /home/$STACK_USER
cat << KEYSTONERC | sudo tee keystonerc > /dev/null
export OS_TENANT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_AUTH_URL=http://$NOVA_CONTROLLER_HOSTNAME:5000/v2.0/
KEYSTONERC
sudo chown $STACK_USER:$STACK_USER /home/$STACK_USER/keystonerc

### Glance ###
#glance install
sudo apt-get install -y glance

#glance setting
sudo cp -a /etc/glance /etc/glance_bak

cat << GLANCE_API_PASTE | sudo tee -a /etc/glance/glance-api-paste.ini > /dev/null
auth_host = $NOVA_CONTROLLER_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = glance
admin_password = $SERVICE_PASSWORD
GLANCE_API_PASTE

cat << GLANCE_REGISTRY_PASTE | sudo tee -a /etc/glance/glance-registry-paste.ini > /dev/null
auth_host = $NOVA_CONTROLLER_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = glance
admin_password = $SERVICE_PASSWORD
GLANCE_REGISTRY_PASTE

sudo sed -i "s#sqlite:////var/lib/glance/glance.sqlite#mysql://glance:$MYSQL_PASS_GLANCE@$NOVA_CONTROLLER_HOSTNAME/glance?charset=utf8#" /etc/glance/glance-api.conf
sudo sed -i "s/#flavor=/flavor = keystone/" /etc/glance/glance-api.conf
sudo sed -i "s/notifier_strategy = noop/notifier_strategy = rabbit/" /etc/glance/glance-api.conf
sudo sed -i "s/rabbit_host = localhost/rabbit_host=$NOVA_CONTROLLER_HOSTNAME/" /etc/glance/glance-api.conf
sudo sed -i "s/rabbit_userid = guest/rabbit_userid = nova/" /etc/glance/glance-api.conf
sudo sed -i "s/rabbit_password = guest/rabbit_password = $RABBIT_PASS/" /etc/glance/glance-api.conf
sudo sed -i "s@rabbit_virtual_host = /@rabbit_virtual_host = /nova@" /etc/glance/glance-api.conf

sudo sed -i "s#sqlite:////var/lib/glance/glance.sqlite#mysql://glance:$MYSQL_PASS_GLANCE@$NOVA_CONTROLLER_HOSTNAME/glance?charset=utf8#" /etc/glance/glance-registry.conf
sudo sed -i "s/#flavor=/flavor = keystone/" /etc/glance/glance-registry.conf

###warning workaround###
sudo -E wget -P /etc/glance https://raw.github.com/openstack/glance/master/etc/schema-image.json
########################

#glance service init
sudo \rm -rf /var/log/glance/*
for i in api registry
do
  sudo start glance-$i ; sudo restart glance-$i
done

#glance db sync
sudo glance-manage db_sync

### OpenVswitch ###
#openvswitch install
sudo apt-get install openvswitch-switch openvswitch-datapath-dkms -y

#create bridge
# br-int is vm integration
sudo ovs-vsctl --no-wait -- --may-exist add-br br-int
# br-ex is vm external network access
sudo ovs-vsctl --no-wait -- --may-exist add-br br-ex
sudo ovs-vsctl add-port br-ex $EXT_NIC

### QUANTUM ###
#quantum install
sudo apt-get install quantum-server quantum-plugin-openvswitch-agent quantum-dhcp-agent quantum-l3-agent quantum-metadata-agent -y

#quantum settings backup
sudo cp -a  /etc/quantum /etc/quantum_bak

#quantum plugin setting
cat << QUANTUM_OVS | sudo tee /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini > /dev/null
[DATABASE]
sql_connection = mysql://quantum:$MYSQL_PASS_QUANTUM@$NOVA_CONTROLLER_HOSTNAME/ovs_quantum?charset=utf8
[OVS]
tenant_network_type = gre
tunnel_id_ranges = 1:1000
integration_bridge = br-int
tunnel_bridge = br-tun
local_ip = $NOVA_COMPUTE_IP
enable_tunneling = True
[SECURITYGROUP]
firewall_driver = quantum.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
QUANTUM_OVS

#quantum paste.ini  setting
cat << QUANTUM_PASTE_INI | sudo tee /etc/quantum/api-paste.ini > /dev/null
[composite:quantum]
use = egg:Paste#urlmap
/: quantumversions
/v2.0: quantumapi_v2_0

[composite:quantumapi_v2_0]
use = call:quantum.auth:pipeline_factory
noauth = extensions quantumapiapp_v2_0
keystone = authtoken keystonecontext extensions quantumapiapp_v2_0

[filter:keystonecontext]
paste.filter_factory = quantum.auth:QuantumKeystoneContext.factory

[filter:authtoken]
paste.filter_factory = keystoneclient.middleware.auth_token:filter_factory
auth_host = $NOVA_CONTROLLER_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = quantum
admin_password = $SERVICE_PASSWORD

[filter:extensions]
paste.filter_factory = quantum.api.extensions:plugin_aware_extension_middleware_factory

[app:quantumversions]
paste.app_factory = quantum.api.versions:Versions.factory

[app:quantumapiapp_v2_0]
paste.app_factory = quantum.api.v2.router:APIRouter.factory
QUANTUM_PASTE_INI

#quantum server setting
cat << QUANTUM_SERVER | sudo tee /etc/quantum/quantum.conf > /dev/null
[DEFAULT]
lock_path = \$state_path/lock
bind_host = 0.0.0.0
bind_port = 9696
core_plugin = quantum.plugins.openvswitch.ovs_quantum_plugin.OVSQuantumPluginV2
api_paste_config = /etc/quantum/api-paste.ini
control_exchange = quantum
rpc_backend = quantum.openstack.common.rpc.impl_kombu
rabbit_host=$NOVA_CONTROLLER_IP
rabbit_userid=nova
rabbit_password=$RABBIT_PASS
rabbit_virtual_host=/nova
notification_driver = quantum.openstack.common.notifier.rpc_notifier
default_notification_level = INFO
notification_topics = notifications
[QUOTAS]
[DEFAULT_SERVICETYPE]
[AGENT]
root_helper = sudo quantum-rootwrap /etc/quantum/rootwrap.conf
[keystone_authtoken]
auth_host = $NOVA_CONTROLLER_HOSTNAME
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = quantum
admin_password = $SERVICE_PASSWORD
signing_dir = /var/lib/quantum/keystone-signing
QUANTUM_SERVER

#quantum metadata setting
cat << QUANTUM_META | sudo tee /etc/quantum/metadata_agent.ini > /dev/null
[DEFAULT]
auth_url = http://$NOVA_CONTROLLER_IP:35357/v2.0
auth_region = RegionOne
admin_tenant_name = service
admin_user = quantum
admin_password = $SERVICE_PASSWORD
nova_metadata_ip = $NOVA_CONTROLLER_IP
nova_metadata_port = 8775
metadata_proxy_shared_secret = stack
QUANTUM_META

#quantum service init
sudo \rm -rf /var/log/quantum/*
for i in dhcp-agent l3-agent metadata-agent server plugin-openvswitch-agent
do
  sudo stop quantum-$i ; sudo start quantum-$i
done

### NOVA ###
#nova install
sudo apt-get install -y nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy nova-doc nova-conductor
sudo apt-get install -y openstack-dashboard memcached
sudo apt-get install -y nova-compute

#memcached setting
sudo sed -i "s/127.0.0.1/$NOVA_CONTROLLER_IP/" /etc/memcached.conf
sudo service memcached restart

#nova.conf setting
sudo cp -a /etc/nova /etc/nova_bak

cat << NOVA_COMPUTE_SETUP | sudo tee /etc/nova/nova-compute.conf
[DEFAULT]
libvirt_type=kvm
libvirt_ovs_bridge=br-int
libvirt_vif_type=ethernet
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
libvirt_use_virtio_for_bridges=True
NOVA_COMPUTE_SETUP

#nova_api setting
sudo sed -i "s#127.0.0.1#$NOVA_CONTROLLER_HOSTNAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_TENANT_NAME%#service#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_USER%#nova#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_PASSWORD%#$SERVICE_PASSWORD#" /etc/nova/api-paste.ini

cat << NOVA_SETUP | sudo tee /etc/nova/nova.conf > /dev/null
[DEFAULT]
my_ip=$NOVA_COMPUTE_IP
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/run/lock/nova
verbose=True
api_paste_config=/etc/nova/api-paste.ini
scheduler_driver=nova.scheduler.filter_scheduler.FilterScheduler
rabbit_host=$NOVA_CONTROLLER_HOSTNAME
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS
nova_url=http://$NOVA_CONTROLLER_IP:8774/v1.1/
sql_connection=mysql://nova:$MYSQL_PASS_NOVA@$NOVA_CONTROLLER_HOSTNAME/nova
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf

#auth
use_deprecated_auth=false
auth_strategy=keystone

#glance
glance_api_servers=$NOVA_CONTROLLER_HOSTNAME:9292
image_service=nova.image.glance.GlanceImageService

#vnc
novnc_enabled=true
novncproxy_base_url=http://$NOVA_CONTROLLER_IP:6080/vnc_auto.html
novncproxy_port=6080
vncserver_proxyclient_address=\$my_ip
vncserver_listen=0.0.0.0
vnc_keymap=ja

#quantum
network_api_class=nova.network.quantumv2.api.API
quantum_url=http://$NOVA_CONTROLLER_IP:9696
quantum_auth_strategy=keystone
quantum_admin_tenant_name=service
quantum_admin_username=quantum
quantum_admin_password=$SERVICE_PASSWORD
quantum_admin_auth_url=http://$NOVA_CONTROLLER_IP:35357/v2.0
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.firewall.NoopFirewallDriver
security_group_api=quantum

#metadata
service_quantum_metadata_proxy=True
quantum_metadata_proxy_shared_secret=stack

#compute
compute_driver=libvirt.LibvirtDriver

#cinder
volume_api_class=nova.volume.cinder.API
osapi_volume_listen_port=5900
NOVA_SETUP

#nova db sync
sudo nova-manage db sync

#nova service init
sudo \rm -rf /var/log/nova/*
for proc in proc in api cert console consoleauth scheduler compute novncproxy conductor
do
  sudo service nova-$proc stop
  sudo service nova-$proc start
done

### CINDER ###
#cinder install
sudo apt-get install cinder-api cinder-scheduler cinder-volume tgt -y

#cinder setting
sudo cp -a /etc/cinder /etc/cinder_bak

sudo sed -i "s/%SERVICE_TENANT_NAME%/service/" /etc/cinder/api-paste.ini
sudo sed -i "s/%SERVICE_USER%/cinder/" /etc/cinder/api-paste.ini
sudo sed -i "s/%SERVICE_PASSWORD%/$SERVICE_PASSWORD/" /etc/cinder/api-paste.ini
sudo sed -i "s#127.0.0.1#$NOVA_CONTROLLER_HOSTNAME#" /etc/cinder/api-paste.ini
sudo sed -i "s#localhost#$NOVA_CONTROLLER_HOSTNAME#" /etc/cinder/api-paste.ini

cat << CINDER | sudo tee /etc/cinder/cinder.conf > /dev/null
[DEFAULT]
rootwrap_config=/etc/cinder/rootwrap.conf
sql_connection=mysql://cinder:$MYSQL_PASS_CINDER@$NOVA_CONTROLLER_HOSTNAME/cinder?charset=utf8
api_paste_config=/etc/cinder/api-paste.ini
iscsi_helper=tgtadm
volume_name_template=volume-%s
volume_group=cinder-volumes
state_path=/var/lib/cinder
volumes_dir=/var/lib/cinder/volumes
verbose=True
auth_strategy=keystone
iscsi_ip_address=$NOVA_CONTROLLER_HOSTNAME
rabbit_host=$NOVA_CONTROLLER_HOSTNAME
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS
CINDER

#cinder db sync
sudo cinder-manage db sync

#cinder service init
sudo \rm -rf /var/log/cinder/*
for i in volume api scheduler
do
  sudo start cinder-$i ; sudo restart cinder-$i
done

### KVM ###
#install kvm
sudo apt-get install -y kvm libvirt-bin pm-utils

#cgroup settings
cat << CGROUP | sudo tee -a /etc/libvirt/qemu.conf > /dev/null
cgroup_device_acl = [
"/dev/null", "/dev/full", "/dev/zero",
"/dev/random", "/dev/urandom",
"/dev/ptmx", "/dev/kvm", "/dev/kqemu",
"/dev/rtc", "/dev/hpet","/dev/net/tun"
]
CGROUP

#delete default virtual bridge
sudo virsh net-destroy default
sudo virsh net-undefine default

#live migration setting
sudo cp -a /etc/libvirt/libvirtd.conf /etc/libvirt/libvirtd.conf_orig
sudo sed -i 's@#listen_tls = 0@listen_tls = 0@' /etc/libvirt/libvirtd.conf
sudo sed -i 's@#listen_tcp = 1@listen_tcp = 1@' /etc/libvirt/libvirtd.conf
sudo sed -i 's@#auth_tcp = "sasl"@auth_tcp = "none"@' /etc/libvirt/libvirtd.conf
sudo cp -a /etc/init/libvirt-bin.conf /etc/init/libvirt-bin.conf_orig
sudo sed -i 's@env libvirtd_opts="-d"@env libvirtd_opts="-d -l"@' /etc/init/libvirt-bin.conf
sudo cp -a /etc/default/libvirt-bin /etc/default/libvirt-bin_orig
sudo sed -i 's@libvirtd_opts="-d"@libvirtd_opts="-d -l"@' /etc/default/libvirt-bin
sudo service libvirt-bin restart

### OpenStack  ###
#env
cat << NOVARC | sudo tee -a /etc/bash.bashrc > /dev/null
. /home/$STACK_USER/keystonerc
NOVARC

#tenant and user create
. /home/$STACK_USER/keystonerc
keystone tenant-create --name $TENANT_NAME
keystone user-create --name $TENANT_ADMIN --pass $TENANT_ADMIN_PASS
keystone user-create --name $TENANT_USER --pass $TENANT_USER_PASS
keystone user-role-add --user $TENANT_ADMIN --role admin --tenant $TENANT_NAME
keystone user-role-add --user $TENANT_USER --role Member --tenant $TENANT_NAME

#create tenant network
#internal
tenant=$(keystone tenant-list|awk "/$TENANT_NAME/ {print \$2}")
network_name=$TENANT_NETWORK

quantum net-create \
  --tenant-id $tenant $network_name

subnet_name=${network_name}-subnet
subnet=$TENANT_SUBNET
nameserver=$TENANT_NAME_SERVER

quantum subnet-create \
  --tenant-id $tenant \
  --name $subnet_name \
  --dns-nameserver $nameserver $network_name $subnet

quantum router-create --tenant-id $tenant ${TENANT_NAME}-router

l3_agent_id=$(quantum agent-list | grep L3 | awk '{print $2}')

quantum l3-agent-router-add $l3_agent_id ${TENANT_NAME}-router
quantum router-interface-add ${TENANT_NAME}-router $subnet_name
#external
quantum net-create \
  --tenant-id $tenant ext-network \
  --router:external=True
quantum subnet-create      \
   --tenant-id $tenant     \
   --gateway $GATEWAY      \
   --disable-dhcp          \
   --allocation-pool start=$IP_POOL_START,end=$IP_POOL_END ext-network $EXT_NETWORK
quantum router-gateway-set ${TENANT_NAME}-router ext-network

#credential file make
cd /home/$STACK_USER
cat << KEYSTONERC | sudo tee keystonerc01 > /dev/null
export OS_TENANT_NAME=$TENANT_NAME
export OS_USERNAME=$TENANT_ADMIN
export OS_PASSWORD=$TENANT_ADMIN_PASS
export OS_AUTH_URL=http://$NOVA_CONTROLLER_HOSTNAME:5000/v2.0/
KEYSTONERC
sudo chown $STACK_USER:$STACK_USER /home/$STACK_USER/keystonerc01

#env_file read for tenant
. /home/$STACK_USER/keystonerc01

#security group rule add
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
nova secgroup-add-rule default  tcp 22 22 0.0.0.0/0 

#keypair make
cd /home/$STACK_USER
nova keypair-add mykey > mykey
chown $STACK_USER:$STACK_USER mykey
chmod 600 mykey

#ami CoreOS
sudo mkdir -p /opt/virt/coreos ; cd /opt/virt/coreos
sudo -E wget http://storage.core-os.net/coreos/amd64-generic/dev-channel/coreos_production_openstack_image.img.bz2
sudo bunzip2 coreos_production_openstack_image.img.bz2
glance image-create --name="CoreOS" --is-public=true --container-format=ovf --disk-format=qcow2 < coreos_production_openstack_image.img

#ami cirros
#sudo mkdir -p /opt/virt/cirros; cd /opt/virt/cirros;
#sudo -E wget http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-uec.tar.gz
#sudo tar zxvf cirros-0.3.1-x86_64-uec.tar.gz
#glance image-create --name="cirros-kernel" --is-public=true --container-format=aki --disk-format=aki < cirros-0.3.1-x86_64-vmlinuz
#glance image-create --name="cirros-ramdisk" --is-public=true --container-format=ari --disk-format=ari < cirros-0.3.1-x86_64-initrd
#RAMDISK_ID=$(glance image-list | grep cirros-ramdisk | awk -F"|" '{print $2}' | sed -e 's/^[ ]*//g')
#KERNEL_ID=$(glance image-list | grep cirros-kernel | awk -F"|" '{print $2}' | sed -e 's/^[ ]*//g')
#glance image-create --name="cirros" --is-public=true --container-format=ami --disk-format=ami --property kernel_id=$KERNEL_ID --property ramdisk_id=$RAMDISK_ID < cirros-0.3.1-x86_64-blank.img

#ami ubuntu11.10
#sudo mkdir /opt/virt/ubuntu11.10 ; cd /opt/virt/ubuntu11.10
#sudo -E wget http://uec-images.ubuntu.com/releases/11.10/release/ubuntu-11.10-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_11.10" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-11.10-server-cloudimg-amd64-disk1.img

#ami ubuntu12.04
#sudo mkdir /opt/virt/ubuntu12.04 ; cd /opt/virt/ubuntu12.04
#sudo -E wget http://cloud-images.ubuntu.com/releases/precise/release/ubuntu-12.04-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_12.04_LTS" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-12.04-server-cloudimg-amd64-disk1.img

#ami ubuntu12.10
#sudo mkdir /opt/virt/ubuntu12.10 ; cd /opt/virt/ubuntu12.10
#sudo -E wget http://cloud-images.ubuntu.com/releases/quantal/release/ubuntu-12.10-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_12.10" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-12.10-server-cloudimg-amd64-disk1.img

#ami ubuntu13.04
#sudo mkdir -p /opt/virt/ubuntu13.04 ; cd /opt/virt/ubuntu13.04
#sudo -E wget http://cloud-images.ubuntu.com/releases/13.04/release/ubuntu-13.04-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_13.04_LTS" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-13.04-server-cloudimg-amd64-disk1.img

#ami fedora16
#sudo mkdir -p /opt/virt/fedora16; cd /opt/virt/fedora16;
#sudo -E wget http://berrange.fedorapeople.org/images/2012-02-29/f16-x86_64-openstack-sda.qcow2
#glance image-create --name="f16-jeos" --is-public=true --container-format=ovf --disk-format=qcow2 < f16-x86_64-openstack-sda.qcow2

#ami fedora17
#sudo mkdir -p /opt/virt/fedora17; cd /opt/virt/fedora17;
#sudo -E wget http://berrange.fedorapeople.org/images/2012-11-15/f17-x86_64-openstack-sda.qcow2
#glance image-create --name="f17-jeos" --is-public=true --container-format=ovf --disk-format=qcow2 < f17-x86_64-openstack-sda.qcow2

#Login Example
#For Ubuntu
#ssh -i /home/stack/mykey ubuntu@10.0.0.2

#For Fedora
#ssh -i /home/stack/mykey root@10.0.0.2

#For Cirros
#ssh -i /home/stack/mykey cirros@10.0.0.2

#For WorkAround
#If the following error occurs
# cat /var/log/quantum/openvswitch-agent.log
# ERROR [quantum.plugins.openvswitch.agent.ovs_quantum_agent] Failed to create OVS patch port. Cannot have tunneling enabled on this agent, since this version of OVS does not support tunnels or patch ports. Agent terminated!
# apt-get remove openvswitch-switch openvswitch-datapath-dkms quantum-plugin-openvswitch-agent -y
# reboot
# apt-get install openvswitch-switch openvswitch-datapath-dkms quantum-plugin-openvswitch-agent -y
# reboot	




