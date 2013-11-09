#!/bin/bash
#description "OpenStack Deploy Script"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm cinder-volumes and setting hosts

#ENV
#For nova.conf
NOVA_CONTROLLER_IP=192.168.10.50
NOVA_CONTROLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.51

#rabbitmq setting for common
RABBIT_PASS=password

#mysql(nova) pass
MYSQL_PASS_NOVA=password

#read the configuration from external
if [ -f stack.env ] ; then
  . ./stack.env
fi

#grizzly repo add
sudo apt-get install python-software-properties -y
sudo add-apt-repository ppa:openstack-ubuntu-testing/grizzly-trunk-testing -y

#os update
sudo apt-get update
sudo apt-get upgrade -y

#kernel setting
#cat << SYSCTL | sudo tee -a /etc/sysctl.conf > /dev/null
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv4.ip_forward=1
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
#SYSCTL

#dependency package for common
sudo apt-get install -y ntp python-mysqldb python-memcache

#dependency package install for compute node
sudo apt-get install -y open-iscsi open-iscsi-utils kvm kvm-ipxe libvirt-bin bridge-utils python-libvirt

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

#nova install
sudo apt-get install -y nova-compute nova-compute-kvm nova-network

#nova.conf setting
sudo cp -a /etc/nova /etc/nova_bak
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
novncproxy_base_url=http://$NOVA_CONTROLLER_IP:6080/vnc_auto.html
xvpvncproxy_base_url=http://$NOVA_CONTROLLER_IP:6081/console
vncserver_proxyclient_address=\$my_ip
vncserver_listen=0.0.0.0
vnc_keymap=ja

#scheduler
scheduler_driver=nova.scheduler.filter_scheduler.FilterScheduler

#object
s3_host=$NOVA_CONTROLLER_HOSTNAME
use_cow_images=yes

#glance
image_service=nova.image.glance.GlanceImageService
glance_api_servers=$NOVA_CONTROLLER_HOSTNAME:9292

#rabbit
rabbit_host=$NOVA_CONTROLLER_HOSTNAME
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS

#nova database
sql_connection=mysql://nova:$MYSQL_PASS_NOVA@$NOVA_CONTROLLER_HOSTNAME/nova

#cinder
enabled_apis=ec2,osapi_compute,metadata
volume_api_class=nova.volume.cinder.API

#keystone
auth_strategy=keystone
keystone_ec2_url=http://$NOVA_CONTROLLER_HOSTNAME:5000/v2.0/ec2tokens

#memcache
#memcached_servers=$NOVA_CONTROLLER_HOSTNAME:11211
NOVA_SETUP

#nova_api setting
sudo sed -i "s#127.0.0.1#$NOVA_CONTROLLER_HOSTNAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_TENANT_NAME%#$SERVICE_TENANT_NAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_USER%#$NOVA_ADMIN_NAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_PASSWORD%#$NOVA_ADMIN_PASS#" /etc/nova/api-paste.ini

#nova service init
for proc in compute network
do
  sudo service nova-$proc stop
  sudo service nova-$proc start
done

