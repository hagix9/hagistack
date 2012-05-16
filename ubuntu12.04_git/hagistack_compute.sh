#!/bin/bash
#description "OpenStack Deploy Script"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm nova-volumes and setting hosts

#ENV
#For openstack admin user
STACK_USER=stack

#For nova.conf
NOVA_CONTOLLER_IP=192.168.10.50
NOVA_CONTOLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.51

#rabbitmq setting for common
RABBIT_PASS=password

#mysql(nova) pass
MYSQL_PASS_NOVA=password

#os update
apt-get update
apt-get upgrade -y
apt-get ntp -y
apt-get install git gcc -y

#For Controller Node
#kernel setting
#cat << SYSCTL | tee -a /etc/sysctl.conf > /dev/null
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv4.ip_forward=1
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
#SYSCTL

#dependency package install for common
apt-get install -y python-dev python-pip libxml2-dev libxslt1-dev

#dependency package install for controller node
apt-get install -y python-memcache dnsmasq-base dnsmasq-utils kpartx parted arping \
                   iptables ebtables libsqlite3-dev lvm2 curl python-mysqldb euca2ools
                   libapache2-mod-wsgi python-numpy curl vlan

#dependency package install for compute node
apt-get install -y open-iscsi open-iscsi-utils kvm kvm-ipxe libvirt-bin bridge-utils python-libvirt

#kvm setting
modprobe nbd
modprobe kvm
/etc/init.d/libvirt-bin restart

#keystoneclient download
git clone git://github.com/openstack/python-keystoneclient /opt/python-keystoneclient
cd /opt/python-keystoneclient ; git checkout -b essex refs/tags/2012.1
#workaround
sed -i 's/prettytable/prettytable==0.5/' /opt/python-keystoneclient/setup.py

#glance download
git clone git://github.com/openstack/glance /opt/glance
cd /opt/glance ; git checkout -b essex origin/stable/essex

#glance install
sed -i 's/^-e/#-e/' /opt/glance/tools/pip-requires
pip install -r /opt/glance/tools/pip-requires
cd /opt/glance && python setup.py install

#nova download
git clone https://github.com/openstack/nova.git /opt/nova
cd /opt/nova && git checkout -b essex origin/stable/essex

#novaclient download
git clone https://github.com/openstack/python-novaclient.git /opt/python-novaclient
cd /opt/python-novaclient ; git checkout -b essex refs/tags/2012.1

#nova install
pip install -r /opt/nova/tools/pip-requires
cd /opt/nova && python setup.py install

#novaclient install
cd /opt/python-novaclient && python setup.py install

#nova setting
useradd nova -m -d /var/lib/nova -s /bin/false
usermod -G libvirtd nova
usermod -G stack nova
mkdir /etc/nova
mkdir /var/log/nova
mkdir /var/lib/nova/instances /var/lib/nova/images /var/lib/nova/keys /var/lib/nova/networks
chown nova:nova /var/log/nova /var/lib/nova -R

#nova.conf setting
cat << 'NOVA_SETUP' | tee /etc/nova/nova.conf > /dev/null
[DEFAULT]
#verbose=true
allow_admin_api=true
api_paste_config=/etc/nova/api-paste.ini
instances_path=/var/lib/nova/instances
connection_type=libvirt
root_helper=sudo nova-rootwrap
multi_host=true
send_arp_for_ha=true

#behavior of an instance of when the host has been started
start_guests_on_host_boot=true
resume_guests_state_on_host_boot=true

#logging and other administrative
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova

#network
libvirt_use_virtio_for_bridges = true
network_manager=nova.network.manager.FlatDHCPManager
dhcpbridge_flagfile=/etc/nova/nova.conf 
dhcpbridge=/usr/bin/nova-dhcpbridge
public_interface=eth0
flat_interface=eth0 flat_network_bridge=br100
fixed_range=10.0.0.0/8
flat_network_dhcp_start=10.0.0.2
network_size=255
force_dhcp_release = true
flat_injected=false
use_ipv6=false

#vnc
novncproxy_base_url=http://$NOVA_CONTOLLER_IP:6080/vnc_auto.html
xvpvncproxy_base_url=http://$NOVA_CONTOLLER_IP:6081/console
#vnc compute node ip override
vncserver_proxyclient_address=$NOVA_COMPUTE_IP
vncserver_listen=$NOVA_COMPUTE_IP
vnc_keymap=ja

#scheduler
scheduler_driver=nova.scheduler.simple.SimpleScheduler

#object
s3_host=$NOVA_CONTOLLER_HOSTNAME
use_cow_images=yes

#glance
image_service=nova.image.glance.GlanceImageService
glance_api_servers=$NOVA_CONTOLLER_HOSTNAME:9292

#rabbit
rabbit_host=$NOVA_CONTOLLER_HOSTNAME
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS

#nova database
sql_connection=mysql://nova:$MYSQL_PASS_NOVA@$NOVA_CONTOLLER_HOSTNAME/nova

#volumes
volume_group=nova-volumes
aoe_eth_dev=eth0
iscsi_ip_prefix=10.
iscsi_helper=tgtadm

#keystone
auth_strategy=keystone
keystone_ec2_url=http://$NOVA_CONTOLLER_HOSTNAME:5000/v2.0/ec2tokens

#memcache
memcached_servers=$NOVA_CONTOLLER_HOSTNAME:11211
NOVA_SETUP

#nova_compute setting
cat << 'NOVA_COMPUTE' | tee /etc/nova/nova-compute.conf > /dev/null
[default]
libvirt_type=kvm
NOVA_COMPUTE

#nova-api init script
cat << 'NOVA_API_INIT' | tee /etc/init/nova-api.conf > /dev/null
description "Nova API server"
author "Soren Hansen <soren@linux2go.dk>"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]


chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova/

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova/
end script

exec su -s /bin/sh -c "exec nova-api --flagfile=/etc/nova/nova.conf" nova
NOVA_API_INIT

#nova-network init script
cat << 'NOVA_NETWORK_INIT' | tee /etc/init/nova-network.conf > /dev/null
description "Nova network worker"
author "Soren Hansen <soren@linux2go.dk>"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]

chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova/

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova/
end script

exec su -s /bin/sh -c "exec nova-network --flagfile=/etc/nova/nova.conf" nova
NOVA_NETWORK_INIT

#nova-compute init script
cat << 'NOVA_COMPUTE_INIT' | tee /etc/init/nova-compute.conf > /dev/null
description "Nova compute worker"
author "Soren Hansen <soren@linux2go.dk>"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]


chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova/

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova/

	modprobe nbd
end script

exec su -s /bin/sh -c "exec nova-compute --flagfile=/etc/nova/nova.conf --flagfile=/etc/nova/nova-compute.conf" nova
NOVA_COMPUTE_INIT

#sudo setting
cat << 'NOVA_SUDO' | tee /etc/sudoers.d/nova > /dev/null
Defaults:nova !requiretty

nova ALL = (root) NOPASSWD: /usr/local/bin/nova-rootwrap
nova ALL = (root) NOPASSWD: SETENV: NOVACMDS
NOVA_SUDO
chmod 440 /etc/sudoers.d/nova

#nova service init
usermod -G $STACK_USER nova
usermod -G libvirtd nova
for i in api network compute
do
  start nova-$i ; restart nova-$i
done

