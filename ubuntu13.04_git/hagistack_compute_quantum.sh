#!/bin/bash
#description "OpenStack Deploy Script"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm nova-volumes and setting hosts

#ENV
#For openstack admin user
STACK_USER=stack
#STACK_PASS=stack

#For nova.conf
NOVA_CONTOLLER_IP=192.168.10.50
NOVA_CONTOLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.51

#For nova api-paste.ini
ADMIN_TOKEN=ADMIN
ADMIN_USERNAME=admin
ADMIN_PASSWORD=secrete

OS_USERNAME=$ADMIN_USERNAME
OS_PASSWORD=$ADMIN_PASSWORD
OS_TENANT_NAME=$ADMIN_TENANT_NAME

#quantum password
SERVICE_TENANT_NAME=service
QUANTUM_ADMIN_NAME=quantum
QUANTUM_ADMIN_PASS=quantum

#rabbitmq setting for common
RABBIT_PASS=password

#mysql(nova) pass
MYSQL_PASS_NOVA=password

#os update
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install ntp -y
sudo apt-get install git gcc -y

#For Controller Node
#kernel setting
#cat << SYSCTL | sudo tee -a /etc/sysctl.conf > /dev/null
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv4.ip_forward=1
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
#SYSCTL

#dependency package install for common
sudo apt-get install -y python-dev python-pip libxml2-dev libxslt1-dev

#dependency package install for controller node
sudo apt-get install -y python-memcache dnsmasq-base dnsmasq-utils kpartx parted arping \
                   iptables ebtables libsqlite3-dev lvm2 curl python-mysqldb euca2ools  \
                   libapache2-mod-wsgi python-numpy curl vlan zlib1g-dev libssl-dev

#dependency package install for compute node
sudo apt-get install -y open-iscsi open-iscsi-utils kvm kvm-ipxe libvirt-bin bridge-utils python-libvirt

#quantum dependency package install
sudo apt-get install openvswitch-switch openvswitch-datapath-dkms iputils-arping -y

#live migration setting
sudo cp -a /etc/libvirt/libvirtd.conf /etc/libvirt/libvirtd.conf_orig
sudo sed -i 's@#listen_tls = 0@listen_tls = 0@' /etc/libvirt/libvirtd.conf
sudo sed -i 's@#listen_tcp = 1@listen_tcp = 1@' /etc/libvirt/libvirtd.conf
sudo sed -i 's@#auth_tcp = "sasl"@auth_tcp = "none"@' /etc/libvirt/libvirtd.conf
sudo cp -a /etc/init/libvirt-bin.conf /etc/init/libvirt-bin.conf_orig
sudo sed -i 's@env libvirtd_opts="-d"@env libvirtd_opts="-d -l"@' /etc/init/libvirt-bin.conf
sudo cp -a /etc/default/libvirt-bin /etc/default/libvirt-bin_bak
sudo sed -i 's@libvirtd_opts="-d"@libvirtd_opts="-d -l"@' /etc/default/libvirt-bin
sudo service libvirt-bin restart

#nova download
sudo git clone https://github.com/openstack/nova.git /opt/nova
cd /opt/nova && sudo git checkout -b grizzly origin/stable/grizzly

#novaclient download
sudo git clone https://github.com/openstack/python-novaclient.git /opt/python-novaclient

#nova install
###workaround
cat << PIP | sudo tee -a /opt/nova/tools/pip-requires > /dev/null
prettytable>=0.6,<0.7
PIP
apt-get remove python-requests -y
###
sudo pip install -r /opt/nova/tools/pip-requires
cd /opt/nova && sudo python setup.py install

#novaclient install
sudo pip install -r /opt/python-novaclient/tools/pip-requires
cd /opt/python-novaclient && sudo python setup.py install

#nova setting
sudo useradd nova -m -d /var/lib/nova -s /bin/false
sudo usermod -G libvirtd nova
sudo mkdir /etc/nova
sudo mkdir /var/log/nova
sudo mkdir /var/lib/nova/instances /var/lib/nova/images /var/lib/nova/keys /var/lib/nova/networks
sudo chown nova:nova /var/log/nova /var/lib/nova -R
sudo cp -a /opt/nova/etc/nova/* /etc/nova
sudo ln -s /usr/local/bin/nova-dhcpbridge /usr/bin/nova-dhcpbridge

#nova.conf setting
cat << NOVA_SETUP | sudo tee /etc/nova/nova.conf > /dev/null
[DEFAULT]
verbose=True
my_ip=$NOVA_COMPUTE_IP
allow_admin_api=True
api_paste_config=/etc/nova/api-paste.ini
instances_path=/var/lib/nova/instances
compute_driver=libvirt.LibvirtDriver
live_migration_uri=qemu+tcp://%s/system
live_migration_flag=VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE
rootwrap_config=/etc/nova/rootwrap.conf
multi_host=True
send_arp_for_ha=True
ec2_private_dns_show_ip=True

#behavior of an instance of when the host has been started
start_guests_on_host_boot=True
resume_guests_state_on_host_boot=True

#logging and other administrative
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova

#common network
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
force_dhcp_release = True
use_ipv6=false

#for nova-network
#firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver
#network_manager=nova.network.manager.FlatDHCPManager
#flat_injected=false
#libvirt_use_virtio_for_bridges = True
#public_interface=br100
#flat_interface=eth0
#flat_network_bridge=br100
#fixed_range=10.0.0.0/24
#flat_network_dhcp_start=10.0.0.2
#network_size=255

#for quantum
security_group_api = quantum
firewall_driver = nova.virt.firewall.NoopFirewallDriver
linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver
libvirt_vif_driver = nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
network_api_class = nova.network.quantumv2.api.API
service_quantum_metadata_proxy = True
quantum_url = http://$NOVA_CONTOLLER_IP:9696
quantum_admin_auth_url = http://$NOVA_CONTOLLER_IP:35357/v2.0
metadata_listen = $NOVA_COMPUTE_IP
metadata_listen_port = 8775
quantum_auth_strategy = keystone
quantum_admin_tenant_name = $SERVICE_TENANT_NAME
quantum_admin_username = $QUANTUM_ADMIN_NAME
quantum_admin_password = $QUANTUM_ADMIN_PASS

#vnc
novncproxy_base_url=http://$NOVA_CONTOLLER_IP:6080/vnc_auto.html
xvpvncproxy_base_url=http://$NOVA_CONTOLLER_IP:6081/console
vncserver_proxyclient_address=\$my_ip
vncserver_listen=0.0.0.0
vnc_keymap=ja

#scheduler
scheduler_driver=nova.scheduler.filter_scheduler.FilterScheduler

#object
s3_host=$NOVA_CONTOLLER_HOSTNAME
use_cow_images=yes

#glance
image_service=nova.image.glance.GlanceImageService
glance_api_servers=$NOVA_CONTOLLER_HOSTNAME:9292

#rabbit
rabbit_host=$NOVA_CONTOLLER_IP
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS

#nova database
sql_connection=mysql://nova:$MYSQL_PASS_NOVA@$NOVA_CONTOLLER_HOSTNAME/nova

#cinder
enabled_apis=ec2,osapi_compute,metadata
volume_api_class=nova.volume.cinder.API

#keystone
auth_strategy=keystone
keystone_ec2_url=http://$NOVA_CONTOLLER_HOSTNAME:5000/v2.0/ec2tokens

#memcache
#memcached_servers=$NOVA_CONTOLLER_HOSTNAME:11211
NOVA_SETUP

#nova_compute setting
cat << 'NOVA_COMPUTE' | sudo tee /etc/nova/nova-compute.conf > /dev/null
[default]
libvirt_type=kvm
NOVA_COMPUTE

#nova_api setting
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_TENANT_NAME%#$ADMIN_TENANT_NAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_USER%#$ADMIN_USERNAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_PASSWORD%#$ADMIN_PASSWORD#" /etc/nova/api-paste.ini

#nova-compute init script
cat << 'NOVA_COMPUTE_INIT' | sudo tee /etc/init/nova-compute.conf > /dev/null
description "Nova compute worker"
author "Soren Hansen <soren@linux2go.dk>"

start on runlevel [2345]
stop on runlevel [!2345]


chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova/

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova/

	modprobe nbd
end script

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-compute -- --config-file=/etc/nova/nova.conf --config-file=/etc/nova/nova-compute.conf
NOVA_COMPUTE_INIT

#sudo setting
cat << 'NOVA_SUDO' | sudo tee /etc/sudoers.d/nova_sudoers > /dev/null
Defaults:nova !requiretty

nova ALL = (root) NOPASSWD: /usr/local/bin/nova-rootwrap 
NOVA_SUDO
sudo chmod 440 /etc/sudoers.d/*

#quantum download
sudo git clone git://github.com/openstack/quantum /opt/quantum
cd /opt/quantum ; sudo git checkout -b grizzly origin/stable/grizzly
sudo pip install -r /opt/quantum/tools/pip-requires
cd /opt/quantum && sudo python setup.py install

#quantum install
sudo useradd quantum -m -d /var/lib/quantum -s /bin/false
sudo mkdir /etc/quantum
sudo mkdir /var/log/quantum
sudo chown quantum:quantum /var/log/quantum

#quantum setting
sudo cp -a /opt/quantum/etc/* /etc/quantum
sudo mv /etc/quantum/quantum/rootwrap.d /etc/quantum/rootwrap.d
sudo mv /etc/quantum/quantum/plugins /etc/quantum

#quantum server setting
cat << QUANTUM_SERVER | sudo tee /etc/quantum/quantum.conf > /dev/null
[DEFAULT]
auth_strategy = keystone
allow_overlapping_ips = True
policy_file = /etc/quantum/policy.json
debug = True
verbose = True
core_plugin = quantum.plugins.openvswitch.ovs_quantum_plugin.OVSQuantumPluginV2
rabbit_host=$NOVA_CONTOLLER_IP
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS
rpc_backend = quantum.openstack.common.rpc.impl_kombu
state_path = /var/lib/quantum
lock_path = \$state_path/lock
bind_host = 0.0.0.0
bind_port = 9696
api_paste_config = api-paste.ini
control_exchange = quantum
notification_driver = quantum.openstack.common.notifier.rpc_notifier
default_notification_level = INFO
notification_topics = notifications
[QUOTAS]
[DEFAULT_SERVICETYPE]
[AGENT]
root_helper = sudo /usr/local/bin/quantum-rootwrap /etc/quantum/rootwrap.conf
[keystone_authtoken]
auth_host = $NOVA_CONTOLLER_HOSTNAME
auth_port = 35357
auth_protocol = http
admin_tenant_name = $SERVICE_TENANT_NAME
admin_user = $QUANTUM_ADMIN_NAME
admin_password = $QUANTUM_ADMIN_PASS
signing_dir = /var/lib/quantum/keystone-signing
QUANTUM_SERVER

#quantum metadata setting
cat << QUANTUM_META | sudo tee /etc/quantum/metadata_agent.ini > /dev/null
[DEFAULT]
signing_dir = /var/lib/quantum/keystone-signing
root_helper = sudo /usr/local/bin/quantum-rootwrap /etc/quantum/rootwrap.conf
nova_metadata_ip = $NOVA_CONTOLLER_IP
nova_metadata_port = 8775
#metadata_proxy_shared_secret = stack
debug = True
verbose = True
auth_url = http://$NOVA_CONTOLLER_IP:35357/v2.0
auth_region = RegionOne
admin_tenant_name = $SERVICE_TENANT_NAME
admin_user = $QUANTUM_ADMIN_NAME
admin_password = $QUANTUM_ADMIN_PASS
QUANTUM_META

#quantum plugin setting
cat << QUANTUM_OVS | sudo tee /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini > /dev/null
[DATABASE]
sql_connection = mysql://quantum:$MYSQL_PASS_QUANTUM@$NOVA_CONTOLLER_HOSTNAME/ovs_quantum?charset=utf8
reconnect_interval = 2
[OVS]
local_ip = $NOVA_COMPUTE_IP
enable_tunneling = True
tunnel_id_ranges = 1:1000
tenant_network_type = gre
[AGENT]
root_helper = sudo /usr/local/bin/quantum-rootwrap /etc/quantum/rootwrap.conf
polling_interval = 2
[SECURITYGROUP]
firewall_driver = quantum.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
QUANTUM_OVS

#quantum sudo setting
cat << 'QUANTUM_SUDO' | sudo tee /etc/sudoers.d/quantum_sudoers > /dev/null
Defaults:quantum !requiretty

quantum ALL = (root) NOPASSWD: /usr/local/bin/quantum-rootwrap
QUANTUM_SUDO
sudo chmod 440 /etc/sudoers.d/*

#quantum demo ovs setting
sudo ovs-vsctl --no-wait -- --may-exist add-br br-int

#quantum metadata_agent init
cat << 'QUANTUM_METADATA_AGENT_INIT' | sudo tee /etc/init/quantum-metadata-agent.conf > /dev/null
description "Quantum metadata plugin agent"
author "Yolanda Robla <yolanda.robla@canonical.com>"

start on runlevel [2345]
stop on runlevel [016]

chdir /var/run

pre-start script
        mkdir -p /var/run/quantum
        chown quantum:root /var/run/quantum
end script

exec start-stop-daemon --start --chuid quantum --exec /usr/local/bin/quantum-metadata-agent -- \
            --config-file=/etc/quantum/quantum.conf --config-file=/etc/quantum/metadata_agent.ini \
            --log-file=/var/log/quantum/metadata-agent.log
QUANTUM_METADATA_AGENT_INIT

#quantum quantum-plugin-openvswitch-agent init script
cat << 'QUANTUM_OVS_AGENT_INIT' | sudo tee /etc/init/quantum-plugin-openvswitch-agent.conf > /dev/null
description "Quantum openvswitch plugin agent"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [016]

chdir /var/run

pre-start script
        mkdir -p /var/run/quantum
        chown quantum:root /var/run/quantum
end script

exec start-stop-daemon --start --chuid quantum --exec /usr/local/bin/quantum-openvswitch-agent -- --config-file=/etc/quantum/quantum.conf --config-file=/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini --log-file=/var/log/quantum/openvswitch-agent.log
QUANTUM_OVS_AGENT_INIT

#quantum service init
for i in openvswitch-agent metadata-agent
do
  sudo stop quantum-$i ; sudo start quantum-$i
done

#nova service init
sudo usermod -G libvirtd nova
sudo start nova-compute ; sudo restart nova-compute
sleep 3
