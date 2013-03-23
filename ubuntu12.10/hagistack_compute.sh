#!/bin/bash
#description "OpenStack Deploy Script"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm nova-volumes and setting hosts

#ENV
#For nova.conf
NOVA_CONTOLLER_IP=192.168.10.50
NOVA_CONTOLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.51

#rabbitmq setting for common
RABBIT_PASS=password

#mysql(nova) pass
MYSQL_PASS_NOVA=password

#read the configuration from external
if [ -f stack.env ] ; then
  . ./stack.env
fi

#os update
apt-get update
apt-get upgrade -y

#kernel setting
#cat << SYSCTL | tee -a /etc/sysctl.conf > /dev/null
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv4.ip_forward=1
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
#SYSCTL

#dependency package for common
apt-get install -y ntp python-mysqldb python-memcache

#dependency package install for compute node
apt-get install -y open-iscsi open-iscsi-utils kvm kvm-ipxe libvirt-bin bridge-utils python-libvirt

#nova install
apt-get install -y nova-api nova-compute nova-compute-kvm nova-network python-keystone

#nova.conf setting
cp -a /etc/nova /etc/nova_bak
cat << NOVA_SETUP | tee /etc/nova/nova.conf > /dev/null
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
flat_interface=eth0
flat_network_bridge=br100
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

#nova service init
for proc in api compute network
do
  service nova-$proc stop
  service nova-$proc start
done

