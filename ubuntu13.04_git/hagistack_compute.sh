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
cd /opt/nova && sudo git checkout -b grizzly refs/tags/2013.1.rc1

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

#network
libvirt_use_virtio_for_bridges = True
network_manager=nova.network.manager.FlatDHCPManager
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
public_interface=br100
flat_interface=eth0
flat_network_bridge=br100
fixed_range=10.0.0.0/24
flat_network_dhcp_start=10.0.0.2
network_size=255
force_dhcp_release = True
flat_injected=false
use_ipv6=false

#firewall
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver

#vnc
novncproxy_base_url=http://$NOVA_CONTOLLER_IP:6080/vnc_auto.html
xvpvncproxy_base_url=http://$NOVA_CONTOLLER_IP:6081/console
vncserver_proxyclient_address=127.0.0.1
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
rabbit_host=$NOVA_CONTOLLER_HOSTNAME
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

#nova-network init script
cat << 'NOVA_NETWORK_INIT' | sudo tee /etc/init/nova-network.conf > /dev/null
description "Nova network worker"
author "Soren Hansen <soren@linux2go.dk>"

start on runlevel [2345]
stop on runlevel [!2345]

chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova/

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova/
end script

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-network -- --config-file=/etc/nova/nova.conf
NOVA_NETWORK_INIT

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

#nova service init
sudo usermod -G libvirtd nova
sudo start nova-compute ; sudo restart nova-compute
sleep 3
sudo start nova-network ; sudo restart nova-network
