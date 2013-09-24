#!/bin/bash
#description "OpenStack Deploy Script for Ubuntu 13.04"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm cinder-volumes and setting hosts
#Number of necessary NIC 1
#networking
#auto eth0
#iface eth0 inet static
#       address 192.168.10.50
#       netmask 255.255.255.0
#       network 192.168.10.0
#       broadcast 192.168.10.255
#       gateway 192.168.10.1
#       dns-nameservers 192.168.10.1

### ENV ###
#For openstack admin user
STACK_USER=stack
STACK_PASS=stack

#For nova.conf
NOVA_CONTROLLER_IP=192.168.10.50
NOVA_CONTROLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.51

#mysql(root) pass
MYSQL_PASS=nova 

#rabbitmq setting for common
RABBIT_PASS=password

MYSQL_PASS_QUANTUM=password
MYSQL_PASS_NOVA=password

#openstack env
export SERVICE_PASSWORD=secrete

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

### OpenVswitch ###
#openvswitch install
sudo apt-get install openvswitch-switch openvswitch-datapath-dkms -y

#create bridge
# br-int is vm integration
sudo ovs-vsctl --no-wait -- --may-exist add-br br-int

### QUANTUM ###
#quantum install
sudo apt-get install quantum-plugin-openvswitch-agent -y

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

sudo \rm -rf /var/log/quantum/*
for i in plugin-openvswitch-agent
do
  sudo stop quantum-$i ; sudo start quantum-$i
done

### NOVA ###
#nova install
sudo apt-get install -y nova-compute

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

#nova service init
sudo \rm -rf /var/log/nova/*
for proc in proc in compute
do
  sudo service nova-$proc stop
  sudo service nova-$proc start
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
sudo cp -a /etc/default/libvirt-bin /etc/default/libvirt-bin
sudo sed -i 's@libvirtd_opts="-d"@libvirtd_opts="-d -l"@' /etc/default/libvirt-bin
sudo service libvirt-bin restart

