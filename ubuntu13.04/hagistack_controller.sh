#!/bin/bash
#description "OpenStack Deploy Script for Ubuntu 13.04"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm cinder-volumes and setting hosts

#ENV
#For openstack admin user
STACK_USER=stack
STACK_PASS=stack

#For nova.conf
NOVA_CONTOLLER_IP=192.168.10.50
NOVA_CONTOLLER_HOSTNAME=stack01
NOVA_COMPUTE_IP=192.168.10.50

#rabbitmq setting for common
RABBIT_PASS=password

#mysql(nova) pass
MYSQL_PASS=nova 
MYSQL_PASS_NOVA=password
MYSQL_PASS_KEYSTONE=password
MYSQL_PASS_GLANCE=password
MYSQL_PASS_CINDER=password

#openstack env
#export ADMIN_TOKEN=$(openssl rand -hex 10)
ADMIN_TOKEN=ADMIN
ADMIN_USERNAME=admin
ADMIN_PASSWORD=secrete
ADMIN_TENANT_NAME=demo
SERVICE_TENANT_NAME=service
GLANCE_ADMIN_NAME=glance
GLANCE_ADMIN_PASS=glance
NOVA_ADMIN_NAME=nova
NOVA_ADMIN_PASS=nova

#floating ip range setting
FLOAT_IP_RANGE=192.168.10.112/28

#read the configuration from external
if [ -f stack.env ] ; then
  . ./stack.env
fi

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

#mysql setting
cat <<MYSQL_DEBCONF | sudo debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.5 mysql-server/start_on_boot boolean true
MYSQL_DEBCONF

#dependency package for common
sudo apt-get install -y ntp python-mysqldb python-memcache

#dependency package install for controller
sudo apt-get install -y tgt rabbitmq-server mysql-server memcached

#rabbitmq setting for controller node
sudo rabbitmqctl add_vhost /nova
sudo rabbitmqctl add_user nova $RABBIT_PASS
sudo rabbitmqctl set_permissions -p /nova nova ".*" ".*" ".*"
sudo rabbitmqctl delete_user guest

#mysql setting for contoller node
sudo sed -i 's#127.0.0.1#0.0.0.0#g' /etc/mysql/my.cnf
sudo restart mysql

#dependency package install for compute node
sudo apt-get install -y open-iscsi open-iscsi-utils kvm kvm-ipxe \
                        libvirt-bin bridge-utils python-libvirt

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

#memcached setting for controller node
sudo sed -i "s/127.0.0.1/$NOVA_CONTOLLER_IP/" /etc/memcached.conf
sudo service memcached restart

#env_file make
cd /home/$STACK_USER
cat << KEYSTONERC | sudo tee keystonerc > /dev/null
export ADMIN_TOKEN=$ADMIN_TOKEN
export OS_USERNAME=$ADMIN_USERNAME
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_TENANT_NAME=$ADMIN_TENANT_NAME
export OS_AUTH_URL=http://$NOVA_CONTOLLER_HOSTNAME:5000/v2.0/
KEYSTONERC
sudo chown $STACK_USER:$STACK_USER /home/$STACK_USER/keystonerc

#env_file read
. /home/$STACK_USER/keystonerc

#keystone install
sudo apt-get install -y keystone

#keystone setting
sudo cp -a /etc/keystone /etc/keystone_bak
sudo sed -i "s@# admin_token = ADMIN@admin_token = $ADMIN_TOKEN@" /etc/keystone/keystone.conf
sudo sed -i "s@# bind_host = 0.0.0.0@bind_host = 0.0.0.0@" /etc/keystone/keystone.conf
sudo sed -i "s@# public_port = 5000@public_port = 5000@" /etc/keystone/keystone.conf
sudo sed -i "s@# admin_port = 35357@admin_port = 35357@" /etc/keystone/keystone.conf
sudo sed -i "s@# compute_port = 8774@compute_port = 8774@" /etc/keystone/keystone.conf
sudo sed -i "s@# debug = False@debug = True@" /etc/keystone/keystone.conf
sudo sed -i "s@# verbose = False@verbose = True@" /etc/keystone/keystone.conf
sudo sed -i "s#sqlite:////var/lib/keystone/keystone.db#mysql://keystone:$MYSQL_PASS_KEYSTONE@$NOVA_CONTOLLER_HOSTNAME/keystone?charset=utf8#" /etc/keystone/keystone.conf
sudo sed -i "s@# idle_timeout = 200@idle_timeout = 200@" /etc/keystone/keystone.conf
sudo sed -i "s@keystone.token.backends.kvs.Token@keystone.token.backends.kvs.Token@" /etc/keystone/keystone.conf
sudo sed -i "s@keystone.contrib.ec2.backends.kvs.Ec2@keystone.contrib.ec2.backends.kvs.Ec2@" /etc/keystone/keystone.conf
sudo sed -i "s@#token_format = PKI@token_format = UUID@" /etc/keystone/keystone.conf

#keystone db make
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists keystone;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database keystone character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'%' identified by '$MYSQL_PASS_KEYSTONE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'localhost' identified by '$MYSQL_PASS_KEYSTONE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_KEYSTONE';"
sudo keystone-manage db_sync

#keystone service init
sudo stop keystone ; sudo start keystone

#keystone setting2
sleep 3
cd /usr/local/src ; sudo cp -a /usr/share/keystone/sample_data.sh .
export SERVICE_ENDPOINT=http://$NOVA_CONTOLLER_HOSTNAME:35357/v2.0/
export ADMIN_PASSWORD=$ADMIN_PASSWORD
sudo sed -i "s/localhost/$NOVA_CONTOLLER_HOSTNAME/" /usr/local/src/sample_data.sh
export ENABLE_ENDPOINTS=yes
sudo -E bash /usr/local/src/sample_data.sh

#glance install
sudo apt-get install -y glance

#glance setting
sudo cp -a /etc/glance /etc/glance_bak
sudo sed -i "s#sqlite:////var/lib/glance/glance.sqlite#mysql://glance:$MYSQL_PASS_GLANCE@$NOVA_CONTOLLER_HOSTNAME/glance?charset=utf8#" /etc/glance/glance-api.conf
sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT_NAME/" /etc/glance/glance-api.conf
sudo sed -i "s/%SERVICE_USER%/$GLANCE_ADMIN_NAME/" /etc/glance/glance-api.conf
sudo sed -i "s/%SERVICE_PASSWORD%/$GLANCE_ADMIN_PASS/" /etc/glance/glance-api.conf
sudo sed -i "s/#flavor=/flavor = keystone/" /etc/glance/glance-api.conf
sudo sed -i "s/notifier_strategy = noop/notifier_strategy = rabbit/" /etc/glance/glance-api.conf
sudo sed -i "s/rabbit_host = localhost/rabbit_host=$NOVA_CONTOLLER_HOSTNAME/" /etc/glance/glance-api.conf
sudo sed -i "s/rabbit_userid = guest/rabbit_userid = nova/" /etc/glance/glance-api.conf
sudo sed -i "s/rabbit_password = guest/rabbit_password = $RABBIT_PASS/" /etc/glance/glance-api.conf
sudo sed -i "s@rabbit_virtual_host = /@rabbit_virtual_host = /nova@" /etc/glance/glance-api.conf
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-api.conf
sudo sed -i "s#localhost#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-api.conf
sudo sed -i "s#sqlite:////var/lib/glance/glance.sqlite#mysql://glance:$MYSQL_PASS_GLANCE@$NOVA_CONTOLLER_HOSTNAME/glance?charset=utf8#" /etc/glance/glance-registry.conf
sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT_NAME/" /etc/glance/glance-registry.conf
sudo sed -i "s/%SERVICE_USER%/$GLANCE_ADMIN_NAME/" /etc/glance/glance-registry.conf
sudo sed -i "s/%SERVICE_PASSWORD%/$GLANCE_ADMIN_PASS/" /etc/glance/glance-registry.conf
sudo sed -i "s/#flavor=/flavor = keystone/" /etc/glance/glance-registry.conf
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-registry.conf
sudo sed -i "s#localhost#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-registry.conf

sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists glance;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database glance character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'%' identified by '$MYSQL_PASS_GLANCE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'localhost' identified by '$MYSQL_PASS_GLANCE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_GLANCE';"
sudo glance-manage db_sync

###warning workaround###
sudo wget -P /etc/glance https://raw.github.com/openstack/glance/master/etc/schema-image.json
########################

#glance service init
for i in api registry
do
  sudo start glance-$i ; sudo restart glance-$i
done

#cinder install
sudo apt-get install cinder-api cinder-scheduler cinder-volume \
                     python-cinderclient tgt -y

#cinder setting
sudo cp -a /etc/cinder /etc/cinder_bak
cat << CINDER | sudo tee /etc/cinder/cinder.conf > /dev/null
[DEFAULT]
#misc
verbose=True
auth_strategy=keystone
rootwrap_config=/etc/cinder/rootwrap.conf
api_paste_config=/etc/cinder/api-paste.ini
state_path=/var/lib/cinder
volumes_dir=/var/lib/cinder/volumes

#log
log_file=cinder.log
log_dir=/var/log/cinder

#osapi
osapi_volume_extension=cinder.api.contrib.standard_extensions

#rabbit
rabbit_host=$NOVA_CONTOLLER_HOSTNAME
rabbit_virtual_host=/nova
rabbit_userid=nova
rabbit_password=$RABBIT_PASS

#sql
sql_connection=mysql://cinder:$MYSQL_PASS_CINDER@$NOVA_CONTOLLER_HOSTNAME/cinder?charset=utf8

#volume
volume_name_template=volume-%s
volume_group=cinder-volumes

#iscsi
iscsi_helper=tgtadm
CINDER

sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT_NAME/" /etc/cinder/api-paste.ini
sudo sed -i "s/%SERVICE_USER%/$NOVA_ADMIN_NAME/" /etc/cinder/api-paste.ini
sudo sed -i "s/%SERVICE_PASSWORD%/$NOVA_ADMIN_PASS/" /etc/cinder/api-paste.ini
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/cinder/api-paste.ini
sudo sed -i "s#localhost#$NOVA_CONTOLLER_HOSTNAME#" /etc/cinder/api-paste.ini

sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists cinder;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database cinder character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'%' identified by '$MYSQL_PASS_CINDER';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'localhost' identified by '$MYSQL_PASS_CINDER';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_CINDER';"
sudo cinder-manage db sync

#cinder service init
sudo chown cinder:cinder /var/log/cinder/*
for i in volume api scheduler
do
  sudo start cinder-$i ; sudo restart cinder-$i
done

#nova install
sudo apt-get install -y nova-api nova-cert nova-compute             \
                        nova-objectstore nova-scheduler nova-doc    \
                        nova-network nova-console nova-consoleauth  \
                        nova-conductor openstack-dashboard          \
                        nova-novncproxy websockify novnc

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

#nova_api setting
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_TENANT_NAME%#$SERVICE_TENANT_NAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_USER%#$NOVA_ADMIN_NAME#" /etc/nova/api-paste.ini
sudo sed -i "s#%SERVICE_PASSWORD%#$NOVA_ADMIN_PASS#" /etc/nova/api-paste.ini

#nova db make
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists nova;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database nova;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on nova.* to 'nova'@'%' identified by '$MYSQL_PASS_NOVA';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on nova.* to 'nova'@'localhost' identified by '$MYSQL_PASS_NOVA';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on nova.* to 'nova'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_NOVA';"
sudo nova-manage db sync

#nova service init
for proc in proc in api cert console consoleauth scheduler compute network novncproxy conductor
do
  sudo service nova-$proc stop
  sudo service nova-$proc start
done

#env
cat << NOVARC | sudo tee -a /etc/bash.bashrc > /dev/null
. /home/$STACK_USER/keystonerc
NOVARC

#network make 
sudo nova-manage network create   \
     --label nova_network1        \
     --fixed_range_v4=10.0.0.0/25 \
     --bridge_interface=eth0      \
     --multi_host=T

#floating ip-range make
sudo nova-manage floating create --ip_range=$FLOAT_IP_RANGE

#keypair make
cd /home/$STACK_USER
nova keypair-add mykey > mykey
chown $STACK_USER:$STACK_USER mykey
chmod 600 mykey

#security group rule add
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
nova secgroup-add-rule default  tcp 22 22 0.0.0.0/0 
nova secgroup-list-rules default

#ami cirros
sudo mkdir -p /opt/virt/cirros; cd /opt/virt/cirros;
sudo wget http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-uec.tar.gz
sudo tar zxvf cirros-0.3.1-x86_64-uec.tar.gz
glance image-create --name="cirros-kernel" --is-public=true --container-format=aki --disk-format=aki < cirros-0.3.1-x86_64-vmlinuz
glance image-create --name="cirros-ramdisk" --is-public=true --container-format=ari --disk-format=ari < cirros-0.3.1-x86_64-initrd
RAMDISK_ID=$(glance image-list | grep cirros-ramdisk | awk -F"|" '{print $2}' | sed -e 's/^[ ]*//g')
KERNEL_ID=$(glance image-list | grep cirros-kernel | awk -F"|" '{print $2}' | sed -e 's/^[ ]*//g')
glance image-create --name="cirros" --is-public=true --container-format=ami --disk-format=ami --property kernel_id=$KERNEL_ID --property ramdisk_id=$RAMDISK_ID < cirros-0.3.1-x86_64-blank.img

#ami ubuntu11.10
#sudo mkdir /opt/virt/ubuntu11.10 ; cd /opt/virt/ubuntu11.10
#sudo wget http://uec-images.ubuntu.com/releases/11.10/release/ubuntu-11.10-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_11.10" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-11.10-server-cloudimg-amd64-disk1.img

#ami ubuntu12.04
#sudo mkdir /opt/virt/ubuntu12.04 ; cd /opt/virt/ubuntu12.04
#sudo wget http://cloud-images.ubuntu.com/releases/precise/release/ubuntu-12.04-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_12.04_LTS" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-12.04-server-cloudimg-amd64-disk1.img

#ami ubuntu12.10
#sudo mkdir /opt/virt/ubuntu12.10 ; cd /opt/virt/ubuntu12.10
#sudo wget http://cloud-images.ubuntu.com/releases/quantal/release/ubuntu-12.10-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_12.10" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-12.10-server-cloudimg-amd64-disk1.img

#ami ubuntu13.04
#sudo mkdir -p /opt/virt/ubuntu13.04 ; cd /opt/virt/ubuntu13.04
#sudo wget http://cloud-images.ubuntu.com/releases/13.04/release/ubuntu-13.04-server-cloudimg-amd64-disk1.img
#glance image-create --name="Ubuntu_13.04_LTS" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-13.04-server-cloudimg-amd64-disk1.img

#ami fedora16
#sudo mkdir -p /opt/virt/fedora16; cd /opt/virt/fedora16;
#sudo wget http://berrange.fedorapeople.org/images/2012-02-29/f16-x86_64-openstack-sda.qcow2
#glance image-create --name="f16-jeos" --is-public=true --container-format=ovf --disk-format=qcow2 < f16-x86_64-openstack-sda.qcow2

#ami fedora17
#sudo mkdir -p /opt/virt/fedora17; cd /opt/virt/fedora17;
#sudo wget http://berrange.fedorapeople.org/images/2012-11-15/f17-x86_64-openstack-sda.qcow2
#glance image-create --name="f17-jeos" --is-public=true --container-format=ovf --disk-format=qcow2 < f17-x86_64-openstack-sda.qcow2

#Login Example
#For Ubuntu
#ssh -i /home/stack/mykey ubuntu@10.0.0.2

#For Fedora
#ssh -i /home/stack/mykey root@10.0.0.2

#For Cirros
#ssh -i /home/stack/mykey cirros@10.0.0.2


