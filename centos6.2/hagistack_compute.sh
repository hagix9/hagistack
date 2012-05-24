#!/bin/bash
#description "OpenStack(Essex) Deploy Script for CentOS6.2"
#author "Shiro Hagihara(Fulltrust.inc) <hagihara@fulltrust.co.jp @hagix9 fulltrust.co.jp>"
#prerequisite make lvm nova-volumes , setting /etc/hosts (NOVA_CONTOLLER_HOSTNAME)

#ENV
#For openstack admin user
STACK_PASS=stack
STACK_USER=stack

#For nova.conf
NOVA_CONTOLLER_IP=192.168.10.60
NOVA_CONTOLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.61

#rabbitmq setting for common
RABBIT_PASS=password

#mysql(nova) pass
MYSQL_PASS=nova 
MYSQL_PASS_NOVA=password

#openstack env
#export ADMIN_TOKEN=$(openssl rand -hex 10)
ADMIN_TOKEN=999888777666
ADMIN_USERNAME=admin
ADMIN_PASSWORD=password
ADMIN_TENANT_NAME=admin

#useradd
useradd $STACK_USER
echo $STACK_PASS | passwd $STACK_USER --stdin

#hosts setting
cat << HOSTS | tee -a /etc/hosts > /dev/null
$NOVA_CONTOLLER_IP $NOVA_CONTOLLER_HOSTNAME
HOSTS

#os update
yum update -y
yum upgrade -y

#selinux disabled
cp -a /etc/selinux/config /etc/selinux/config_bak
sed -i 's#SELINUX=enforcing#SELINUX=disabled#' /etc/selinux/config
setenforce 0

#kernel setting
#cat << SYSCTL | tee -a /etc/sysctl.conf > /dev/null
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv4.ip_forward=1
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
#SYSCTL

#dependency package for common
yum install -y ntp man wget openssh-clients
service ntpd start
chkconfig ntpd on

#add epel
rpm -i http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-6.noarch.rpm

#dependency package install for compute node
yum install -y iscsi-initiator-utils qemu-kvm \
               libvirt bridge-utils libvirt-python
service libvirtd start

#nova install
yum install -y openstack-nova python-keystone python-keystoneclient python-memcached

#iscsi setup
service tgtd start
chkconfig tgtd on

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
libvirt_inject_partition = -1

#behavior of an instance of when the host has been started
start_guests_on_host_boot=true
resume_guests_state_on_host_boot=true

#logging and other administrative
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova

#network
#don't use quantum
network_manager=nova.network.manager.FlatDHCPManager

#use quantum
#network_manager=nova.network.quantum.manager.QuantumManager
#linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
#quantum_use_dhcp=True

#use openvswitch plugin
#libvirt_ovs_bridge=br-int
#libvirt_vif_type=ethernet
#libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtOpenVswitchDriver

#network common
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
#rabbit_host=$NOVA_CONTOLLER_HOSTNAME
#rabbit_virtual_host=/nova
#rabbit_userid=nova
#rabbit_password=$RABBIT_PASS

#qpid
rpc_backend=nova.rpc.impl_qpid
qpid_hostname=$NOVA_CONTOLLER_HOSTNAME
qpid_port=5672
#qpid_username=$QPID_USER
#qpid_password=$QPID_PASS

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

#nova_api setting
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/nova/api-paste.ini
sed -i "s#%SERVICE_TENANT_NAME%#$ADMIN_TENANT_NAME#" /etc/nova/api-paste.ini
sed -i "s#%SERVICE_USER%#$ADMIN_USERNAME#" /etc/nova/api-paste.ini
sed -i "s#%SERVICE_PASSWORD%#$ADMIN_PASSWORD#" /etc/nova/api-paste.ini

#epel openstack workaround
mkdir /var/lock/nova
chown nova:root /var/lock/nova
sed -i '37s/int(self.partition or 0)/-1/' /usr/lib/python2.6/site-packages/nova/virt/disk/guestfs.py

#nova service init
for proc in api network compute
do
  service openstack-nova-$proc start
done
for proc in api network compute
do
  chkconfig openstack-nova-$proc on
done

