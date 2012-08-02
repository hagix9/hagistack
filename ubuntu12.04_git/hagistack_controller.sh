#!/bin/bash
#description "OpenStack Deploy Script"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm nova-volumes and setting hosts

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
MYSQL_PASS_HORIZON=password

#openstack env
#export ADMIN_TOKEN=$(openssl rand -hex 10)
ADMIN_TOKEN=999888777666
ADMIN_USERNAME=admin
ADMIN_PASSWORD=password
ADMIN_TENANT_NAME=admin

#floating ip range setting
FLOAT_IP_RANGE=192.168.10.112/28

#read the configuration from external
if [ -f stack.env ] ; then
  . ./stack.env
fi

#os update
apt-get update
apt-get upgrade -y
apt-get install ntp -y
apt-get install git gcc -y

#For Controller Node
#kernel setting
#cat << SYSCTL | tee -a /etc/sysctl.conf > /dev/null
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv4.ip_forward=1
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
#SYSCTL

#mysql setting
MYSQL_PASS=nova 
NOVA_PASS=password
cat <<MYSQL_DEBCONF | debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.5 mysql-server/start_on_boot boolean true
MYSQL_DEBCONF

#dependency package install for common
apt-get install -y python-dev python-pip python-mysqldb libxml2-dev libxslt1-dev

#dependency package install for controller node
apt-get install -y tgt memcached python-memcache \
                   dnsmasq-base dnsmasq-utils kpartx parted arping        \
                   iptables ebtables sqlite3 libsqlite3-dev lvm2 curl     \
                   mysql-server rabbitmq-server euca2ools curl vlan       \
                   apache2 libapache2-mod-wsgi python-numpy

#rabbitmq setting for controller node
rabbitmqctl add_vhost /nova
rabbitmqctl add_user nova $RABBIT_PASS
rabbitmqctl set_permissions -p /nova nova ".*" ".*" ".*"
rabbitmqctl delete_user guest

#mysql setting for contoller node
sed -i 's#127.0.0.1#0.0.0.0#g' /etc/mysql/my.cnf
restart mysql

#dependency package install for compute node
apt-get install -y open-iscsi open-iscsi-utils kvm kvm-ipxe libvirt-bin bridge-utils python-libvirt

#kvm setting
modprobe nbd
modprobe kvm
/etc/init.d/libvirt-bin restart

#memcached setting for controller node
sed -i "s/127.0.0.1/$NOVA_CONTOLLER_IP/" /etc/memcached.conf
/etc/init.d/memcached restart

#env_file make
cd /home/$STACK_USER
cat > keystonerc << EOF
#export ADMIN_TOKEN=$(openssl rand -hex 10)
#export ADMIN_TOKEN=$ADMIN_TOKEN
export OS_USERNAME=$ADMIN_USERNAME
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_TENANT_NAME=$ADMIN_TENANT_NAME
export OS_AUTH_URL=http://$NOVA_CONTOLLER_HOSTNAME:5000/v2.0/
EOF
chown $STACK_USER:$STACK_USER /home/$STACK_USER/keystonerc

#env_file read
. /home/$STACK_USER/keystonerc

#keystone download
git clone git://github.com/openstack/keystone /opt/keystone
cd /opt/keystone ; git checkout -b essex refs/tags/2012.1.1

#keystoneclient download
git clone git://github.com/openstack/python-keystoneclient /opt/python-keystoneclient
cd /opt/python-keystoneclient ; git checkout -b essex refs/tags/2012.1
#workaround
sed -i 's/prettytable/prettytable==0.5/' /opt/python-keystoneclient/tools/pip-requires
sed -i 's/prettytable/prettytable==0.5/' /opt/python-keystoneclient/setup.py 

#keystone install
pip install -r /opt/keystone/tools/pip-requires
cd /opt/keystone && python setup.py install

#keystoneclient install
cd /opt/python-keystoneclient && python setup.py install

#keystone setting
useradd keystone -m -d /var/lib/keystone -s /bin/false
mkdir /etc/keystone
mkdir /var/log/keystone
chown keystone:keystone /var/log/keystone

#keystone setting
cp -a /opt/keystone/etc/* /etc/keystone
sed -i "s#sqlite:///keystone.db#mysql://keystone:$MYSQL_PASS_KEYSTONE@$NOVA_CONTOLLER_HOSTNAME/keystone#" /etc/keystone/keystone.conf
sed -i "s#ADMIN#$ADMIN_TOKEN#" /etc/keystone/keystone.conf
sed -i 's|./etc/default_catalog.templates|/etc/keystone/default_catalog\.templates|' /etc/keystone/keystone.conf
sed -i 's#driver = keystone.identity.backends.kvs.Identity#driver = keystone.identity.backends.sql.Identity#' /etc/keystone/keystone.conf
sed -i 's#driver = keystone.contrib.ec2.backends.kvs.Ec2#driver = keystone.contrib.ec2.backends.sql.Ec2#' /etc/keystone/keystone.conf
sed -i 's#keystone.token.backends.kvs.Token#keystone.token.backends.sql.Token#' /etc/keystone/keystone.conf
sed -i '8a\log_file = /var/log/keystone/keystone.log' /etc/keystone/keystone.conf
sed -i "s/localhost/$NOVA_CONTOLLER_HOSTNAME/" /etc/keystone/default_catalog.templates
#cat << KEYSTONE_TEMPLATE | tee -a /etc/keystone/default_catalog.templates > /dev/null
#
#catalog.RegionOne.s3.publicURL = http://$NOVA_CONTOLLER_HOSTNAME:3333
#catalog.RegionOne.s3.adminURL = http://$NOVA_CONTOLLER_HOSTNAME:3333
#catalog.RegionOne.s3.internalURL = http://$NOVA_CONTOLLER_HOSTNAME:3333
#catalog.RegionOne.s3.name = S3 Service
#
#catalog.RegionOne.object-store.publicURL = http://$NOVA_CONTOLLER_HOSTNAME:8080/v1/AUTH_\$(tenant_id)s
#catalog.RegionOne.object-store.adminURL = http://$NOVA_CONTOLLER_HOSTNAME:8080/
#catalog.RegionOne.object-store.internalURL = http://$NOVA_CONTOLLER_HOSTNAME:8080/v1/AUTH_\$(tenant_id)s
#catalog.RegionOne.object-store.name = Swift Service
#
#catalog.RegionOne.network.publicURL = http://$NOVA_CONTOLLER_HOSTNAME:9696/
#catalog.RegionOne.network.adminURL = http://$NOVA_CONTOLLER_HOSTNAME:9696/
#catalog.RegionOne.network.internalURL = http://$NOVA_CONTOLLER_HOSTNAME:9696/
#catalog.RegionOne.network.name = Quantum Service
#KEYSTONE_TEMPLATE

#keystone db make
mysql -u root -pnova -e "create database keystone;"
mysql -u root -pnova -e "grant all privileges on keystone.* to 'keystone'@'%' identified by '$MYSQL_PASS_KEYSTONE';"
mysql -u root -pnova -e "grant all privileges on keystone.* to 'keystone'@'localhost' identified by '$MYSQL_PASS_KEYSTONE';"
mysql -u root -pnova -e "grant all privileges on keystone.* to 'keystone'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_KEYSTONE';"
keystone-manage db_sync

#keystone init script
cat << 'KEYSTONE_INIT' | tee /etc/init/keystone.conf > /dev/null
description "Keystone API server"
author "Soren Hansen <soren@linux2go.dk>"

start on (local-filesystems and net-device-up IFACE!=lo)
stop on runlevel [016]

respawn

exec su -s /bin/sh -c "exec keystone-all" keystone
KEYSTONE_INIT

#keystone service init
stop keystone ; start keystone

#keystone setting2
sleep 3
cd /home/$STACK_USER ; cp -a /opt/keystone/tools/sample_data.sh .
sed -i "s/127.0.0.1/$NOVA_CONTOLLER_HOSTNAME/" /home/$STACK_USER/sample_data.sh
sed -i "s/localhost/$NOVA_CONTOLLER_HOSTNAME/" /home/$STACK_USER/sample_data.sh
sed -i "66s/secrete/$ADMIN_PASSWORD/" /home/$STACK_USER/sample_data.sh
#sed -i '63a\ENABLE_SWIFT=1' /home/$STACK_USER/sample_data.sh
#sed -i '63a\ENABLE_ENDPOINTS=1' /home/$STACK_USER/sample_data.sh
#sed -i '63a\ENABLE_QUANTUM=1' /home/$STACK_USER/sample_data.sh
/home/$STACK_USER/sample_data.sh

#glance download
git clone git://github.com/openstack/glance /opt/glance
cd /opt/glance ; git checkout -b essex refs/tags/2012.1.1

#glance install
sed -i 's/^-e/#-e/' /opt/glance/tools/pip-requires
pip install -r /opt/glance/tools/pip-requires
cd /opt/glance && python setup.py install

#glance setting
useradd glance -m -d /var/lib/glance -s /bin/false
mkdir /etc/glance /var/log/glance
mkdir /var/lib/glance/scrubber /var/lib/glance/image-cache

#glance setting
cp -a /opt/glance/etc/* /etc/glance
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-api-paste.ini
sed -i "s/%SERVICE_TENANT_NAME%/$ADMIN_TENANT_NAME/" /etc/glance/glance-api-paste.ini
sed -i "s/%SERVICE_USER%/$ADMIN_USERNAME/" /etc/glance/glance-api-paste.ini
sed -i "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" /etc/glance/glance-api-paste.ini
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-api.conf
echo $'\n'[paste_deploy]$'\n'flavor = keystone  | tee -a /etc/glance/glance-api.conf
sed -i "s/# auth_url = http:\/\/127.0.0.1:5000\/v2.0\//auth_url = http:\/\/$NOVA_CONTOLLER_HOSTNAME:5000\/v2.0\//" /etc/glance/glance-cache.conf
sed -i "s/%SERVICE_TENANT_NAME%/$ADMIN_TENANT_NAME/" /etc/glance/glance-cache.conf
sed -i "s/%SERVICE_USER%/$ADMIN_USERNAME/" /etc/glance/glance-cache.conf
sed -i "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" /etc/glance/glance-cache.conf
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_TENANT_NAME%/$ADMIN_TENANT_NAME/" /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_USER%/$ADMIN_USERNAME/" /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" /etc/glance/glance-registry-paste.ini
sed -i "s#sql_connection = sqlite:///glance.sqlite#sql_connection = mysql://glance:password@$NOVA_CONTOLLER_HOSTNAME/glance#" /etc/glance/glance-registry.conf
echo $'\n'[paste_deploy]$'\n'flavor = keystone  | tee -a /etc/glance/glance-registry.conf
chown glance:glance /var/log/glance /var/lib/glance/scrubber /var/lib/glance/image-cache

#glance db make
mysql -u root -pnova -e "create database glance;"
mysql -u root -pnova -e "grant all privileges on glance.* to 'glance'@'%' identified by '$MYSQL_PASS_GLANCE';"
mysql -u root -pnova -e "grant all privileges on glance.* to 'glance'@'localhost' identified by '$MYSQL_PASS_NOVA';"
mysql -u root -pnova -e "grant all privileges on glance.* to 'glance'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_NOVA';"
glance-manage db_sync

#glance-api init script
cat << 'GLANCE_API' | tee /etc/init/glance-api.conf > /dev/null
description "Glance API server"
author "Soren Hansen <soren@linux2go.dk>"

start on (local-filesystems and net-device-up IFACE!=lo)
stop on runlevel [016]

respawn

exec su -s /bin/sh -c "exec glance-api" glance
GLANCE_API

#glance-registry init script
cat << 'GLANCE_REG' | tee /etc/init/glance-registry.conf > /dev/null
description "Glance registry server"
author "Soren Hansen <soren@linux2go.dk>"

start on (local-filesystems and net-device-up IFACE!=lo)
stop on runlevel [016]

respawn

exec su -s /bin/sh -c "exec glance-registry" glance
GLANCE_REG

#glance service init
#cd /opt/glance && python setup.py install
chown glance:glance /var/log/glance/*
for i in api registry
do
  start glance-$i ; restart glance-$i
done

#nova download
git clone https://github.com/openstack/nova.git /opt/nova
cd /opt/nova && git checkout -b essex refs/tags/2012.1.1

#novaclient download
git clone https://github.com/openstack/python-novaclient.git /opt/python-novaclient
cd /opt/python-novaclient ; git checkout -b essex refs/tags/2012.1
#workaround
sed -i 's/prettytable/prettytable==0.5/' /opt/python-novaclient/tools/pip-requires
sed -i 's/prettytable/prettytable==0.5/' /opt/python-novaclient/setup.py 

#nova install
pip install -r /opt/nova/tools/pip-requires
cd /opt/nova && python setup.py install

#novaclient install
cd /opt/python-novaclient && python setup.py install

#nova setting
useradd nova -m -d /var/lib/nova -s /bin/false
usermod -G libvirtd nova
mkdir /etc/nova
mkdir /var/log/nova
mkdir /var/lib/nova/instances /var/lib/nova/images /var/lib/nova/keys /var/lib/nova/networks
chown nova:nova /var/log/nova /var/lib/nova -R

#nova.conf setting
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
dhcpbridge=/usr/local/bin/nova-dhcpbridge
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

#nova_api setting
cp -a /opt/nova/etc/nova/* /etc/nova
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/nova/api-paste.ini
sed -i "s#%SERVICE_TENANT_NAME%#$ADMIN_TENANT_NAME#" /etc/nova/api-paste.ini
sed -i "s#%SERVICE_USER%#$ADMIN_USERNAME#" /etc/nova/api-paste.ini
sed -i "s#%SERVICE_PASSWORD%#$ADMIN_PASSWORD#" /etc/nova/api-paste.ini

#nova db make
mysql -u root -pnova -e "create database nova;"
mysql -u root -pnova -e "grant all privileges on nova.* to 'nova'@'%' identified by '$MYSQL_PASS_NOVA';"
mysql -u root -pnova -e "grant all privileges on nova.* to 'nova'@'localhost' identified by '$MYSQL_PASS_NOVA';"
mysql -u root -pnova -e "grant all privileges on nova.* to 'nova'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_NOVA';"
nova-manage db sync

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

#nova-cert init script
cat << 'NOVA_CERT_INIT' | tee /etc/init/nova-cert.conf > /dev/null
description "Nova cert"
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

exec su -s /bin/sh -c "exec nova-cert --flagfile=/etc/nova/nova.conf" nova
NOVA_CERT_INIT

#nova-objectstore init script
cat << 'NOVA_OBJECT_INIT' | tee /etc/init/nova-objectstore.conf > /dev/null
description "Nova object store"
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

exec su -s /bin/sh -c "exec nova-objectstore --flagfile=/etc/nova/nova.conf" nova
NOVA_OBJECT_INIT

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

#nova-scheduler init script
cat << 'NOVA_SCHEDULER_INIT' | tee /etc/init/nova-scheduler.conf > /dev/null
description "Nova scheduler"
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

exec su -s /bin/sh -c "exec nova-scheduler --flagfile=/etc/nova/nova.conf" nova
NOVA_SCHEDULER_INIT

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

#nova-volume init script
cat << 'NOVA_VOLUME_INIT' | tee /etc/init/nova-volume.conf > /dev/null
description "Nova Volume server"
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

exec su -s /bin/sh -c "exec nova-volume --flagfile=/etc/nova/nova.conf" nova
NOVA_VOLUME_INIT

#nova-consoleauth init script
cat << 'NOVA_CONSOLE_AUTH_INIT' | tee /etc/init/nova-consoleauth.conf > /dev/null
description "Nova Console"
author "Vishvananda Ishaya <vishvananda@gmail.com>"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]

respawn

chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova
end script

exec su -s /bin/sh -c "exec nova-consoleauth --flagfile=/etc/nova/nova.conf" nova
NOVA_CONSOLE_AUTH_INIT

#nova-console init script
cat << 'NOVA_CONSOLE_INIT' | tee /etc/init/nova-console.conf > /dev/null
description "Nova Console"
author "Vishvananda Ishaya <vishvananda@gmail.com>"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]

respawn

chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova
end script

exec su -s /bin/sh -c "exec nova-console --flagfile=/etc/nova/nova.conf" nova
NOVA_CONSOLE_INIT

#vncproxy init script
cat << 'NOVA_PROXY_INIT' | tee /etc/init/nova-xvpvncproxy.conf > /dev/null
description "Nova VNC proxy"
author "Vishvananda Ishaya <vishvananda@gmail.com>"

start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]


chdir /var/run

pre-start script
	mkdir -p /var/run/nova
	chown nova:root /var/run/nova/

	mkdir -p /var/lock/nova
	chown nova:root /var/lock/nova/
end script

exec su -c "nova-xvpvncproxy --flagfile=/etc/nova/nova.conf" root
NOVA_PROXY_INIT

#sudo setting
cat << 'NOVA_SUDO' | tee /etc/sudoers.d/nova > /dev/null
Defaults:nova !requiretty

nova ALL = (root) NOPASSWD: /usr/local/bin/nova-rootwrap
nova ALL = (root) NOPASSWD: SETENV: NOVACMDS
NOVA_SUDO
chmod 440 /etc/sudoers.d/nova

#nova service init
usermod -G libvirtd nova
for i in api network objectstore scheduler compute volume xvpvncproxy console cert consoleauth
do
  start nova-$i ; restart nova-$i
done

#horizon download
git clone https://github.com/openstack/horizon.git /opt/horizon
cd /opt/horizon ; git checkout -b essex refs/tags/2012.1

#horizon install
sed -i 's/^-e/#-e/' /opt/horizon/tools/pip-requires
pip install -r /opt/horizon/tools/pip-requires
cd /opt/horizon && python setup.py install

#horizon setting
cp -a /opt/horizon/openstack_dashboard/local/local_settings.py.example /opt/horizon/openstack_dashboard/local/local_settings.py
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /opt/horizon/openstack_dashboard/local/local_settings.py
sed -i "s#locmem://#memcached://$NOVA_CONTOLLER_HOSTNAME:11211#g" /opt/horizon/openstack_dashboard/local/local_settings.py
cat << HORIZON_SETUP | tee -a /opt/horizon/openstack_dashboard/local/local_settings.py > /dev/null
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': 'horizon',
        'USER': 'horizon',
        'PASSWORD': '$MYSQL_PASS_HORIZON',
        'HOST': '$NOVA_CONTOLLER_HOSTNAME',
        'default-character-set': 'utf8'
    }
}
HORIZON_CONFIG = {
    'dashboards': ('nova', 'syspanel', 'settings',),
    'default_dashboard': 'nova',
    'user_home': 'openstack_dashboard.views.user_home',
}
SESSION_ENGINE = 'django.contrib.sessions.backends.cached_db'
HORIZON_SETUP

#horizon db make
mysql -u root -pnova -e "create database horizon;"
mysql -u root -pnova -e "grant all privileges on horizon.* to 'horizon'@'%' identified by '$MYSQL_PASS_HORIZON';"
mysql -u root -pnova -e "grant all privileges on horizon.* to 'horizon'@'localhost' identified by '$MYSQL_PASS_HORIZON';"
mysql -u root -pnova -e "grant all privileges on horizon.* to 'horizon'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_HORIZON';"
cd /opt/horizon && ./manage.py syncdb

#horizon setting2
mkdir -p /opt/horizon/.blackhole
cp -a /etc/apache2/sites-available/default /etc/apache2/sites-available/default_orig
cat << 'APACHE_SETUP' | tee /etc/apache2/sites-available/default > /dev/null
<VirtualHost *:80>
    WSGIScriptAlias / /opt/horizon/openstack_dashboard/wsgi/django.wsgi
    WSGIDaemonProcess horizon user=www-data group=www-data processes=3 threads=10
    SetEnv APACHE_RUN_USER www-data
    SetEnv APACHE_RUN_GROUP www-data
    WSGIProcessGroup horizon

    DocumentRoot /opt/horizon/.blackhole
    Alias /media /opt/horizon/openstack_dashboard/static/
    #Alias /vpn /opt/stack/vpn

    <Directory />
        Options FollowSymLinks
        AllowOverride None
    </Directory>

    <Directory /opt/horizon/>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride None
        Order allow,deny
        allow from all
    </Directory>

    ErrorLog /var/log/apache2/error.log
    LogLevel warn
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>
APACHE_SETUP

#horizon work arround bug 
sed -i 's/430/441/' /opt/horizon/horizon/dashboards/nova/templates/nova/instances_and_volumes/instances/_detail_vnc.html

#apache2 restart
service apache2 restart

#novnc download
git clone https://github.com/cloudbuilders/noVNC.git /opt/noVNC

#novnc init script
cat << 'noVNC_INIT' | tee /etc/init/nova-novncproxy.conf > /dev/null
description "noVNC"
author "hagix9 <hagihara.shiro@fulltrust.co.jp>"

start on runlevel [2345]
stop on runlevel [016]

post-start script
  cd /opt/noVNC && ./utils/nova-novncproxy --flagfile=/etc/nova/nova.conf --web . >/dev/null 2>&1 &
end script
post-stop script
  kill $(ps -ef | grep nova-novncproxy | grep -v grep | awk '{print $2}')
end script
noVNC_INIT

stop nova-novncproxy ; start nova-novncproxy

#env_file2 make
. /home/$STACK_USER/keystonerc
USER_ID=$(keystone user-list | awk '/admin / {print $2}')
ACCESS_KEY=$(keystone ec2-credentials-list --user $USER_ID | awk '/admin / {print $4}')
SECRET_KEY=$(keystone ec2-credentials-list --user $USER_ID | awk '/admin / {print $6}')
cd /home/$STACK_USER
cat > novarc <<EOF
export EC2_URL=http://$NOVA_CONTOLLER_HOSTNAME:8773/services/Cloud
export EC2_ACCESS_KEY=$ACCESS_KEY
export EC2_SECRET_KEY=$SECRET_KEY
EOF
chown $STACK_USER:$STACK_USER novarc
chmod 600 novarc
. /home/$STACK_USER/novarc

cat << NOVARC | tee -a /etc/bash.bashrc > /dev/null
. /home/$STACK_USER/keystonerc
. /home/$STACK_USER/novarc
NOVARC

#network make 
nova-manage network create   \
--label nova_network1        \
--fixed_range_v4=10.0.0.0/25 \
--bridge_interface=eth0      \
--multi_host=T

#floating ip-range make
nova-manage float create  --ip_range=$FLOAT_IP_RANGE

#keypair make
cd /home/$STACK_USER
nova keypair-add mykey > mykey
chown $STACK_USER:$STACK_USER mykey
chmod 600 mykey

#security group rule add
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
nova secgroup-add-rule default  tcp 22 22 0.0.0.0/0 
nova secgroup-list-rules default

#ami ttylinux
mkdir -p /opt/virt/ttylinux; cd /opt/virt/ttylinux;
wget http://smoser.brickies.net/ubuntu/ttylinux-uec/ttylinux-uec-amd64-12.1_2.6.35-22_1.tar.gz
tar zxvf ttylinux-uec-amd64-12.1_2.6.35-22_1.tar.gz
glance add name="ttylinux-aki" is_public=true container_format=aki disk_format=aki < ttylinux-uec-amd64-12.1_2.6.35-22_1-vmlinuz
glance add name="ttylinux-ari" is_public=true container_format=ari disk_format=ari < ttylinux-uec-amd64-12.1_2.6.35-22_1-loader
RAMDISK_ID=$(glance index | grep ttylinux-ari | awk '{print $1}')
KERNEL_ID=$(glance index | grep ttylinux-aki | awk '{print $1}')
glance add name="ttylinux-ami" is_public=true container_format=ami disk_format=ami kernel_id=$KERNEL_ID ramdisk_id=$RAMDISK_ID < ttylinux-uec-amd64-12.1_2.6.35-22_1.img

#ami ubuntu11.10
#mkdir /opt/virt/ubuntu11.10 ; cd /opt/virt/ubuntu11.10
#wget http://uec-images.ubuntu.com/releases/11.10/release/ubuntu-11.10-server-cloudimg-amd64-disk1.img
#glance add name="Ubuntu 11.10" is_public=true container_format=ovf disk_format=qcow2 < ubuntu-11.10-server-cloudimg-amd64-disk1.img

#ami ubuntu12.04
#mkdir /opt/virt/ubuntu12.04 ; cd /opt/virt/ubuntu12.04
#wget http://cloud-images.ubuntu.com/releases/precise/release/ubuntu-12.04-server-cloudimg-amd64-disk1.img
#glance add name="Ubuntu 12.04 LTS" is_public=true container_format=ovf disk_format=qcow2 < ubuntu-12.04-server-cloudimg-amd64-disk1.img

#ami fedora16
#mkdir -p /opt/virt/fedora; cd /opt/virt/fedora;
#wget http://berrange.fedorapeople.org/images/2012-02-29/f16-x86_64-openstack-sda.qcow2
#glance add name=f16-jeos is_public=true disk_format=qcow2 container_format=ovf < f16-x86_64-openstack-sda.qcow2

