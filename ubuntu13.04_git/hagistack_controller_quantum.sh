#!/bin/bash
#description "OpenStack Deploy Script"
#author "Shiro Hagihara <hagihara@fulltrust.co.jp @hagix9>"
#prerequisite make lvm cinder-volumes and setting hosts

#ENV
#For openstack admin user
STACK_USER=stack

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
MYSQL_PASS_QUANTUM=password

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
QUANTUM_ADMIN_NAME=quantum
QUANTUM_ADMIN_PASS=quantum

#read the configuration from external
if [ -f stack.env ] ; then
  . ./stack.env
fi

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

#mysql setting
#mysql setting
cat <<MYSQL_DEBCONF | sudo debconf-set-selections
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASS
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASS
mysql-server-5.5 mysql-server/start_on_boot boolean true
MYSQL_DEBCONF

#dependency package install for common
sudo apt-get install -y python-dev python-pip python-mysqldb libxml2-dev libxslt1-dev

#quantum dependency package install
sudo apt-get install openvswitch-switch openvswitch-datapath-dkms iputils-arping -y

#dependency package install for controller node
sudo apt-get install -y tgt memcached python-memcache \
                   dnsmasq-base dnsmasq-utils kpartx parted arping        \
                   iptables ebtables sqlite3 libsqlite3-dev lvm2 curl     \
                   mysql-server rabbitmq-server euca2ools curl vlan       \
                   apache2 libapache2-mod-wsgi python-numpy nodejs-legacy

#rabbitmq setting for controller node
sudo rabbitmqctl add_vhost /nova
sudo rabbitmqctl add_user nova $RABBIT_PASS
sudo rabbitmqctl set_permissions -p /nova nova ".*" ".*" ".*"
sudo rabbitmqctl delete_user guest

#mysql setting for contoller node
sudo sed -i 's#127.0.0.1#0.0.0.0#g' /etc/mysql/my.cnf
sudo restart mysql

#dependency package install for compute node
sudo apt-get install -y open-iscsi open-iscsi-utils kvm kvm-ipxe libvirt-bin bridge-utils python-libvirt

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

#memcached setting for controller node
sudo sed -i "s/127.0.0.1/$NOVA_CONTOLLER_IP/" /etc/memcached.conf
sudo service memcached restart

#env_file make
cd /home/$STACK_USER
cat << KEYSTONERC | sudo tee keystonerc > /dev/null
export ADMIN_TOKEN=$ADMIN_TOKEN
export OS_SERVICE_TOKEN=$ADMIN_TOKEN
export OS_USERNAME=$ADMIN_USERNAME
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_TENANT_NAME=$ADMIN_TENANT_NAME
export OS_AUTH_URL=http://$NOVA_CONTOLLER_HOSTNAME:5000/v2.0/
KEYSTONERC
sudo chown $STACK_USER:$STACK_USER /home/$STACK_USER/keystonerc

#env_file read
. /home/$STACK_USER/keystonerc

#keystone download
sudo git clone git://github.com/openstack/keystone /opt/keystone
cd /opt/keystone ; sudo git checkout -b grizzly origin/stable/grizzly

#dependency package install for keystone
sudo apt-get install zlib1g-dev -y

#keystone install
sudo pip install -r /opt/keystone/tools/pip-requires
cd /opt/keystone && sudo python setup.py install

#keystone setting
sudo useradd keystone -m -d /var/lib/keystone -s /bin/false
sudo mkdir /etc/keystone
sudo mkdir /var/log/keystone
sudo chown keystone:keystone /var/log/keystone

#keystone setting
sudo cp -a /opt/keystone/etc/* /etc/keystone
sudo mv /etc/keystone/keystone.conf.sample /etc/keystone/keystone.conf
sudo mv /etc/keystone/logging.conf.sample /etc/keystone/logging.conf
sudo sed -i "s/# admin_token = ADMIN/admin_token = ADMIN/" /etc/keystone/keystone.conf
sudo sed -i "s/# bind_host = 0.0.0.0/bind_host = 0.0.0.0/" /etc/keystone/keystone.conf
sudo sed -i "s/# public_port = 5000/public_port = 5000/" /etc/keystone/keystone.conf
sudo sed -i "s/# admin_port = 35357/admin_port = 35357/" /etc/keystone/keystone.conf
sudo sed -i "s/# compute_port = 8774/compute_port = 8774/" /etc/keystone/keystone.conf
sudo sed -i "s/# debug = False/debug = True/" /etc/keystone/keystone.conf
sudo sed -i "s/# verbose = False/verbose = True/" /etc/keystone/keystone.conf
sudo sed -i "s/# log_file = keystone.log/log_file = keystone.log/" /etc/keystone/keystone.conf
sudo sed -i "s@# log_dir = /var/log/keystone@log_dir = /var/log/keystone@" /etc/keystone/keystone.conf
sudo sed -i "s[# connection = sqlite:///keystone.db[connection = mysql://keystone:$MYSQL_PASS_KEYSTONE@$NOVA_CONTOLLER_HOSTNAME/keystone?charset=utf8[" /etc/keystone/keystone.conf
sudo sed  -i "s/# idle_timeout = 200/idle_timeout = 200/" /etc/keystone/keystone.conf
sudo sed  -i "s/# driver = keystone.identity.backends.sql.Identity/driver = keystone.identity.backends.sql.Identity/" /etc/keystone/keystone.conf
sudo sed  -i "s/# driver = keystone.catalog.backends.sql.Catalog/driver = keystone.catalog.backends.sql.Catalog/" /etc/keystone/keystone.conf
sudo sed  -i "s/# driver = keystone.token.backends.kvs.Token/driver = keystone.token.backends.sql.Token/" /etc/keystone/keystone.conf
sudo sed  -i "s/# driver = keystone.policy.backends.sql.Policy/driver = keystone.policy.backends.sql.Policy/" /etc/keystone/keystone.conf
sudo sed  -i "s/# driver = keystone.contrib.ec2.backends.kvs.Ec2/driver = keystone.contrib.ec2.backends.sql.Ec2/" /etc/keystone/keystone.conf
sudo sed  -i "s/#token_format = PKI/token_format = UUID/" /etc/keystone/keystone.conf
sudo sed  -i "s/localhost/$nova_contoller_hostname/" /etc/keystone/default_catalog.templates

#keystone db make
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists keystone;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database keystone character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'%' identified by '$MYSQL_PASS_KEYSTONE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'localhost' identified by '$MYSQL_PASS_KEYSTONE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on keystone.* to 'keystone'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_KEYSTONE';"
sudo keystone-manage db_sync

#keystone init script
cat << 'KEYSTONE_INIT' | sudo tee /etc/init/keystone.conf > /dev/null
description "Keystone API server"
author "Soren Hansen <soren@linux2go.dk>"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

exec start-stop-daemon --start --chuid keystone \
            --chdir /var/lib/keystone --name keystone \
            --exec /usr/local/bin/keystone-all
KEYSTONE_INIT

#keystone service init
sudo rm /var/log/keystone/*
sudo stop keystone ; sudo start keystone

#keystone data setting
sleep 3
cd /usr/local/src ; sudo cp -a /opt/keystone/tools/sample_data.sh .
export SERVICE_ENDPOINT=http://$NOVA_CONTOLLER_HOSTNAME:35357/v2.0
sudo sed -i "s/localhost/$NOVA_CONTOLLER_HOSTNAME/" /usr/local/src/sample_data.sh
sudo -E bash /usr/local/src/sample_data.sh

#glance download
sudo git clone git://github.com/openstack/glance /opt/glance
sudo git clone git://github.com/openstack/python-glanceclient /opt/python-glanceclient
cd /opt/glance ; sudo git checkout -b grizzly origin/stable/grizzly

#dependency package install for glance
sudo apt-get install libssl-dev -y

#glance install
sudo pip install -r /opt/glance/tools/pip-requires
cd /opt/glance && sudo python setup.py install
sudo pip install -r /opt/python-glanceclient/tools/pip-requires
cd /opt/python-glanceclient && sudo python setup.py install

#glance setting
sudo useradd glance -m -d /var/lib/glance -s /bin/false
sudo mkdir /etc/glance /var/log/glance
sudo mkdir /var/lib/glance/scrubber /var/lib/glance/image-cache

#glance setting
sudo cp -a /opt/glance/etc/* /etc/glance
sudo sed -i "s#sqlite:///glance.sqlite#mysql://glance:$MYSQL_PASS_GLANCE@$NOVA_CONTOLLER_HOSTNAME/glance?charset=utf8#" /etc/glance/glance-api.conf
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
sudo sed -i "s#sqlite:///glance.sqlite#mysql://glance:$MYSQL_PASS_GLANCE@$NOVA_CONTOLLER_HOSTNAME/glance?charset=utf8#" /etc/glance/glance-registry.conf
sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT_NAME/" /etc/glance/glance-registry.conf
sudo sed -i "s/%SERVICE_USER%/$GLANCE_ADMIN_NAME/" /etc/glance/glance-registry.conf
sudo sed -i "s/%SERVICE_PASSWORD%/$GLANCE_ADMIN_PASS/" /etc/glance/glance-registry.conf
sudo sed -i "s/#flavor=/flavor = keystone/" /etc/glance/glance-registry.conf
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-registry.conf
sudo sed -i "s#localhost#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-registry.conf
chown glance:glance /var/log/glance /var/lib/glance/scrubber /var/lib/glance/image-cache

#glance db make
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists glance;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database glance character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'%' identified by '$MYSQL_PASS_GLANCE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'localhost' identified by '$MYSQL_PASS_GLANCE';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on glance.* to 'glance'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_GLANCE';"
sudo glance-manage db_sync

#glance-api init script
cat << 'GLANCE_API' | sudo tee /etc/init/glance-api.conf > /dev/null
description "Glance API server"
author "Soren Hansen <soren@linux2go.dk>"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

exec start-stop-daemon --start --chuid glance \
            --chdir /var/lib/glance --name glance-api \
            --exec /usr/local/bin/glance-api
GLANCE_API

#glance-registry init script
cat << 'GLANCE_REG' | sudo tee /etc/init/glance-registry.conf > /dev/null
description "Glance registry server"
author "Soren Hansen <soren@linux2go.dk>"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

exec start-stop-daemon --start --chuid glance \
            --chdir /var/lib/glance --name glance-registry \
            --exec /usr/local/bin/glance-registry
GLANCE_REG

#glance service init
sudo chown glance:glance /var/log/glance
sudo chown glance:glance /var/log/glance/*
for i in api registry
do
  sudo start glance-$i ; sudo restart glance-$i
done

#cinder download
sudo git clone git://github.com/openstack/cinder /opt/cinder
cd /opt/cinder ; sudo git checkout -b grizzly origin/stable/grizzly

#cinderclient download
sudo git clone git://github.com/openstack/python-cinderclient /opt/python-cinderclient

#cinder install
sudo pip install -r /opt/cinder/tools/pip-requires
cd /opt/cinder && sudo python setup.py install

#cinderclient install
sudo pip install -r /opt/python-glanceclient/tools/pip-requires
cd /opt/python-cinderclient && sudo python setup.py install

#cinder setting
sudo useradd cinder -m -d /var/lib/cinder -s /bin/false
sudo mkdir /etc/cinder
sudo mkdir /var/log/cinder
sudo chown cinder:cinder /var/log/cinder
sudo cp -a /opt/cinder/etc/* /etc
sudo mv /etc/cinder/cinder.conf.sample /etc/cinder/cinder.conf
sudo mv /etc/cinder/logging_sample.conf /etc/cinder/logging.conf

#cinder.conf setting
cat << CINDER_SETUP | sudo tee /etc/cinder/cinder.conf > /dev/null
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
CINDER_SETUP

#cinder_api setting
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/cinder/api-paste.ini
sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT_NAME/" /etc/cinder/api-paste.ini
sudo sed -i "s/%SERVICE_USER%/$NOVA_ADMIN_NAME/" /etc/cinder/api-paste.ini
sudo sed -i "s/%SERVICE_PASSWORD%/$NOVA_ADMIN_PASS/" /etc/cinder/api-paste.ini

#cinder db make
sudo mysql -uroot -p$MYSQL_PASS -e "create database cinder character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'%' identified by '$MYSQL_PASS_CINDER';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'localhost' identified by '$MYSQL_PASS_CINDER';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on cinder.* to 'cinder'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_CINDER';"
sudo cinder-manage db sync

#cinder-api init script
cat << 'CINDER_API_INIT' | sudo tee /etc/init/cinder-api.conf > /dev/null
description "Cinder api server"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [!2345]

chdir /var/run

pre-start script
    mkdir -p /var/run/cinder
    chown cinder:cinder /var/run/cinder

    mkdir -p /var/lock/cinder
    chown cinder:root /var/lock/cinder
end script

exec start-stop-daemon --start --chuid cinder --exec /usr/local/bin/cinder-api \
     -- --config-file=/etc/cinder/cinder.conf --log-file=/var/log/cinder/cinder-api.log
CINDER_API_INIT

cat << 'CINDER_VOLUME_INIT' | sudo tee /etc/init/cinder-volume.conf > /dev/null
description "Cinder volume server"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [!2345]

chdir /var/run

pre-start script
    mkdir -p /var/run/cinder
    chown cinder:cinder /var/run/cinder

    mkdir -p /var/lock/cinder
    chown cinder:root /var/lock/cinder
end script

exec start-stop-daemon --start --chuid cinder --exec /usr/local/bin/cinder-volume \
     -- --config-file=/etc/cinder/cinder.conf --log-file=/var/log/cinder/cinder-volume.log
CINDER_VOLUME_INIT

cat << 'CINDER_SCHEDULER_INIT' | sudo tee /etc/init/cinder-scheduler.conf > /dev/null
description "Cinder scheduler server"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [!2345]

chdir /var/run

pre-start script
    mkdir -p /var/run/cinder
    chown cinder:cinder /var/run/cinder

    mkdir -p /var/lock/cinder
    chown cinder:root /var/lock/cinder
end script

exec start-stop-daemon --start --chuid cinder --exec /usr/bin/cinder-scheduler \
     -- --config-file=/etc/cinder/cinder.conf --log-file=/var/log/cinder/cinder-scheduler.log
CINDER_SCHEDULER_INIT

#sudo setting
cat << 'CINDER_SUDO' | sudo tee /etc/sudoers.d/cinder_sudoers > /dev/null
Defaults:cinder !requiretty

cinder ALL = (root) NOPASSWD: /usr/local/bin/cinder-rootwrap
CINDER_SUDO
sudo chmod 440 /etc/sudoers.d/*

#iscsi setting
echo "include /var/lib/cinder/volumes/*" | sudo tee /etc/tgt/conf.d/cinder_tgt.conf
sudo restart tgt

#cinder process init
sudo rm /var/log/cinder/*
for i in volume api scheduler
do
  sudo start cinder-$i ; sudo restart cinder-$i
done

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

#quantum dhcp setting
cat << QUANTUM_DHCP | sudo tee /etc/quantum/dhcp_agent.ini > /dev/null
[DEFAULT]
dhcp_agent_manager = quantum.agent.dhcp_agent.DhcpAgentWithStateReport
signing_dir = /var/lib/quantum/keystone-signing
admin_password = $QUANTUM_ADMIN_PASS
admin_user = $QUANTUM_ADMIN_NAME
admin_tenant_name = $SERVICE_TENANT_NAME
auth_url = http://$NOVA_CONTOLLER_HOSTNAME:35357/v2.0
root_helper = sudo /usr/local/bin/quantum-rootwrap /etc/quantum/rootwrap.conf
use_namespaces = True
debug = True
verbose = True
interface_driver = quantum.agent.linux.interface.OVSInterfaceDriver
dhcp_driver = quantum.agent.linux.dhcp.Dnsmasq
QUANTUM_DHCP

#quantum l3 setting
cat << QUANTUM_L3 | sudo tee /etc/quantum/l3_agent.ini > /dev/null
[DEFAULT]
l3_agent_manager = quantum.agent.l3_agent.L3NATAgentWithStateReport
external_network_bridge = br-ex
signing_dir = /var/lib/quantum/keystone-signing
admin_password = $QUANTUM_ADMIN_PASS
admin_user = $QUANTUM_ADMIN_NAME
admin_tenant_name = $SERVICE_TENANT_NAME
auth_url = http://$NOVA_CONTOLLER_HOSTNAME:35357/v2.0
root_helper = sudo /usr/local/bin/quantum-rootwrap /etc/quantum/rootwrap.conf
use_namespaces = True
debug = True
verbose = True
interface_driver = quantum.agent.linux.interface.OVSInterfaceDriver
QUANTUM_L3

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

#quantum keystone setting
function get_id () {
    echo `"$@" | awk '/ id / { print $4 }'`
}
ADMIN_ROLE=$(keystone role-list | grep " admin" | awk '{print $2}')
SERVICE_TENANT=$(keystone tenant-list | grep service | awk '{print $2}')
QUANTUM_USER=$(get_id keystone user-create --name="$QUANTUM_ADMIN_NAME" \
                                           --pass="$QUANTUM_ADMIN_PASS"   \
                                           --tenant_id $SERVICE_TENANT  \
                                           --email=quantum@example.com)
keystone user-role-add --tenant_id $SERVICE_TENANT \
                       --user_id $QUANTUM_USER     \
                       --role_id $ADMIN_ROLE
QUANTUM_SERVICE=$(get_id keystone service-create \
   --name=quantum \
   --type=network \
   --description="Quantum Service")
keystone endpoint-create \
    --region RegionOne \
    --service_id $QUANTUM_SERVICE \
    --publicurl "http://$NOVA_CONTOLLER_HOSTNAME:9696/" \
    --adminurl "http://$NOVA_CONTOLLER_HOSTNAME:9696/" \
    --internalurl "http://$NOVA_CONTOLLER_HOSTNAME:9696/"

#quantum database setting
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists ovs_quantum;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database ovs_quantum character set utf8;"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on ovs_quantum.* to 'quantum'@'%' identified by '$MYSQL_PASS_QUANTUM';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on ovs_quantum.* to 'quantum'@'localhost' identified by '$MYSQL_PASS_QUANTUM';"
sudo mysql -uroot -p$MYSQL_PASS -e "grant all privileges on ovs_quantum.* to 'quantum'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_QUANTUM';"

#quantum sudo setting
cat << 'QUANTUM_SUDO' | sudo tee /etc/sudoers.d/quantum_sudoers > /dev/null
Defaults:quantum !requiretty

quantum ALL = (root) NOPASSWD: /usr/local/bin/quantum-rootwrap
QUANTUM_SUDO
sudo chmod 440 /etc/sudoers.d/*

#quantum server init script
cat << 'QUANTUM_SERVER_INIT' | sudo tee /etc/init/quantum-server.conf > /dev/null
description "Quantum server"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [016]

chdir /var/run

pre-start script
        mkdir -p /var/run/quantum
        chown quantum:root /var/run/quantum
end script

script
        [ -r /etc/default/quantum-server ] && . /etc/default/quantum-server
        [ -r "$QUANTUM_PLUGIN_CONFIG" ] && CONF_ARG="--config-file $QUANTUM_PLUGIN_CONFIG"
        exec start-stop-daemon --start --chuid quantum --exec /usr/local/bin/quantum-server -- \
            --config-file /etc/quantum/quantum.conf \
            --log-file /var/log/quantum/server.log $CONF_ARG
end script
QUANTUM_SERVER_INIT

#quantum dhcp_agent init script
cat << 'QUANTUM_DHCP_AGENT_INIT' | sudo tee /etc/init/quantum-dhcp-agent.conf > /dev/null
description "Quantum DHCP agent"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [016]

chdir /var/run

pre-start script
        mkdir -p /var/run/quantum
        chown quantum:root /var/run/quantum
end script

exec start-stop-daemon --start --chuid quantum --exec /usr/local/bin/quantum-dhcp-agent -- --config-file=/etc/quantum/quantum.conf --config-file=/etc/quantum/dhcp_agent.ini --log-file=/var/log/quantum/dhcp-agent.log
QUANTUM_DHCP_AGENT_INIT

#quantum l3_agent init script
cat << 'QUANTUM_L3_AGENT_INIT' | sudo tee /etc/init/quantum-l3-agent.conf > /dev/null
description "Quantum l3 plugin agent"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [016]

chdir /var/run

pre-start script
        mkdir -p /var/run/quantum
        chown quantum:root /var/run/quantum
end script

exec start-stop-daemon --start --chuid quantum --exec /usr/local/bin/quantum-l3-agent -- --config-file=/etc/quantum/quantum.conf --config-file=/etc/quantum/l3_agent.ini --log-file=/var/log/quantum/l3-agent.log
QUANTUM_L3_AGENT_INIT

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

#quantum plugin settings
echo 'QUANTUM_PLUGIN_CONFIG="/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini"'  | sudo tee /etc/default/quantum-server

#quantum service init
for i in dhcp-agent l3-agent metadata-agent server
do
  sudo stop quantum-$i ; sudo start quantum-$i
done

#nova download
sudo git clone https://github.com/openstack/nova.git /opt/nova
cd /opt/nova && sudo git checkout -b grizzly origin/stable/grizzly

#novaclient download
sudo git clone https://github.com/openstack/python-novaclient.git /opt/python-novaclient

#nova install
sudo pip install -r /opt/nova/tools/pip-requires
cd /opt/nova && sudo python setup.py install

#novaclient install
sudo pip install -r /opt/python-glanceclient/tools/pip-requires
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
sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT_NAME/" /etc/nova/api-paste.ini
sudo sed -i "s/%SERVICE_USER%/$NOVA_ADMIN_NAME/" /etc/nova/api-paste.ini
sudo sed -i "s/%SERVICE_PASSWORD%/$NOVA_ADMIN_PASS/" /etc/nova/api-paste.ini

#nova db make
sudo mysql -uroot -p$MYSQL_PASS -e "drop database if exists nova;"
sudo mysql -uroot -p$MYSQL_PASS -e "create database nova;"
sudo mysql -u root -p$MYSQL_PASS  -e "grant all privileges on nova.* to 'nova'@'%' identified by '$MYSQL_PASS_NOVA';"
sudo mysql -u root -p$MYSQL_PASS  -e "grant all privileges on nova.* to 'nova'@'localhost' identified by '$MYSQL_PASS_NOVA';"
sudo mysql -u root -p$MYSQL_PASS  -e "grant all privileges on nova.* to 'nova'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_NOVA';"
sudo nova-manage db sync

#nova-api init script
cat << 'NOVA_API_INIT' | sudo tee /etc/init/nova-api.conf > /dev/null
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

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-api -- --config-file=/etc/nova/nova.conf
NOVA_API_INIT

#nova-cert init script
cat << 'NOVA_CERT_INIT' | sudo tee /etc/init/nova-cert.conf > /dev/null
description "Nova cert"
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

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-cert -- --config-file=/etc/nova/nova.conf
NOVA_CERT_INIT

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

#nova-conductor init script
cat << 'NOVA_CONDUCTOR_INIT' | sudo tee /etc/init/nova-conductor.conf > /dev/null
description "Nova conductor"
author "Chuck Short <zulcss@ubuntu.com>"

start on runlevel [2345]
stop on runlevel [!2345]


chdir /var/run

pre-start script
        mkdir -p /var/run/nova
        chown nova:root /var/run/nova/

        mkdir -p /var/lock/nova
        chown nova:root /var/lock/nova/
end script

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-conductor -- --config-file=/etc/nova/nova.conf
NOVA_CONDUCTOR_INIT

#nova-consolauth init script
cat << 'NOVA_CONSOLEAUTH_INIT' | sudo tee /etc/init/nova-consoleauth.conf > /dev/null
description "Nova Console"
author "Vishvananda Ishaya <vishvananda@gmail.com>"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

chdir /var/run

pre-start script
        mkdir -p /var/run/nova
        chown nova:root /var/run/nova

        mkdir -p /var/lock/nova
        chown nova:root /var/lock/nova
end script

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-consoleauth -- --config-file=/etc/nova/nova.conf
NOVA_CONSOLEAUTH_INIT

#nova-consol init script
cat << 'NOVA_CONSOLE_INIT' | sudo tee /etc/init/nova-console.conf > /dev/null
description "Nova Console"
author "Vishvananda Ishaya <vishvananda@gmail.com>"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

chdir /var/run

pre-start script
        mkdir -p /var/run/nova
        chown nova:root /var/run/nova

        mkdir -p /var/lock/nova
        chown nova:root /var/lock/nova
end script

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-console -- --config-file=/etc/nova/nova.conf
NOVA_CONSOLE_INIT

#nova-novncproxy init script
cat << 'NOVA_NOVNCPXORY_INIT' | sudo tee /etc/init/nova-novncproxy.conf > /dev/null
description "Nova NoVNC proxy"
author "Vishvananda Ishaya <vishvananda@gmail.com>"

start on runlevel [2345]
stop on runlevel [!2345]

chdir /var/run

pre-start script
   mkdir -p /var/run/nova
   chown nova:root /var/run/nova/

   mkdir -p /var/lock/nova
   chown nova:root /var/lock/nova/
end script

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-novncproxy -- --config-file=/etc/nova/nova.conf
NOVA_NOVNCPXORY_INIT

#nova-objectstore init script
cat << 'NOVA_OBJECTSTORE_INIT' | sudo tee /etc/init/nova-objectstore.conf > /dev/null
description "Nova object store"
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

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-objectstore -- --config-file=/etc/nova/nova.conf
NOVA_OBJECTSTORE_INIT

#nova-scheduler init script
cat << 'NOVA_SCHEDULER_INIT' | sudo tee /etc/init/nova-scheduler.conf > /dev/null
description "Nova scheduler"
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

exec start-stop-daemon --start --chuid nova --exec /usr/local/bin/nova-scheduler -- --config-file=/etc/nova/nova.conf
NOVA_SCHEDULER_INIT

#sudo setting
cat << 'NOVA_SUDO' | sudo tee /etc/sudoers.d/nova_sudoers > /dev/null
Defaults:nova !requiretty

nova ALL = (root) NOPASSWD: /usr/local/bin/nova-rootwrap
NOVA_SUDO
sudo chmod 440 /etc/sudoers.d/*

#novnc download
sudo git clone git://github.com/kanaka/noVNC.git /opt/noVNC
sudo ln -s /opt/noVNC /usr/share/novnc

#nova service init
sudo usermod -G libvirtd nova
for i in api cert compute conductor consoleauth console novncproxy objectstore scheduler
do
  sudo start nova-$i ; sudo restart nova-$i
done

#horizon download
sudo git clone https://github.com/openstack/horizon.git /opt/horizon
cd /opt/horizon ; sudo git checkout -b grizzly origin/stable/grizzly

#horizon install
sudo pip install -r /opt/horizon/tools/pip-requires
cd /opt/horizon && sudo python setup.py install

#horizon setting
sudo cp -a /opt/horizon/openstack_dashboard/local/local_settings.py.example /opt/horizon/openstack_dashboard/local/local_settings.py
sudo sed -i "s#'django.core.cache.backends.locmem.LocMemCache'#'django.core.cache.backends.memcached.MemcachedCache',#" /opt/horizon/openstack_dashboard/local/local_settings.py
sudo sed -i "78a\        'LOCATION' : '127.0.0.1:11211'" /opt/horizon/openstack_dashboard/local/local_settings.py
sudo sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /opt/horizon/openstack_dashboard/local/local_settings.py

#apache setting
sudo mkdir -p /opt/horizon/.blackhole
sudo mkdir /opt/horizon/static
sudo chown www-data:www-data /opt/horizon/static
cat << 'APACHE_SETUP' | sudo tee /etc/apache2/conf.d/openstack-dashboard.conf > /dev/null
<VirtualHost *:80>
    WSGIScriptAlias / /opt/horizon/openstack_dashboard/wsgi/django.wsgi
    WSGIDaemonProcess horizon user=www-data group=www-data processes=3 threads=10 home=/opt/horizon
    WSGIApplicationGroup %{GLOBAL}

    SetEnv APACHE_RUN_USER www-data
    SetEnv APACHE_RUN_GROUP www-data
    WSGIProcessGroup horizon

    DocumentRoot /opt/horizon/.blackhole
    Alias /media /opt/horizon/openstack_dashboard/static/


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
    ErrorLog /var/log/apache2/horizon_error.log
    LogLevel warn
    CustomLog /var/log/apache2/horizon_access.log combined
</VirtualHost>

WSGISocketPrefix /var/run/apache2
APACHE_SETUP

#apache2 restart
sudo service apache2 restart

#env
cat << NOVARC | sudo tee -a /etc/bash.bashrc > /dev/null
. /home/$STACK_USER/keystonerc
NOVARC

#keypair make
cd /home/$STACK_USER
nova keypair-add mykey > mykey
chown $STACK_USER:$STACK_USER mykey
chmod 600 mykey

#security group rule add
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
nova secgroup-add-rule default  tcp 22 22 0.0.0.0/0
nova secgroup-list-rules default

#quantum demo ovs setting
sudo ovs-vsctl --no-wait -- --may-exist add-br br-ex
sudo ovs-vsctl --no-wait -- --may-exist add-br br-int
sudo ovs-vsctl --no-wait br-set-external-id br-int bridge-id br-int
sudo ip addr flush dev br-ex
sudo ip addr add 200.0.0.1/24 dev br-ex
sudo ip link set br-ex up

#quantum demo network settings
INT_TENANT_NAME=$ADMIN_TENANT_NAME
INT_TENANT_ID=$(keystone tenant-list | grep $INT_TENANT_NAME | awk -F'|' '{print $2}' | cut -c2-)
quantum net-create --tenant_id $INT_TENANT_ID private

PRIVATE_NETWORK_ID=$(quantum net-list | grep private | awk -F'|' '{print $2}' | cut -c2-)
quantum subnet-create --tenant_id $INT_TENANT_ID --ip_version 4 --gateway 100.0.0.254 $PRIVATE_NETWORK_ID 100.0.0.0/24
quantum router-create --tenant_id $INT_TENANT_ID router1

SUBNET_INT_ID=$(quantum subnet-list | grep "100.0.0.0" | awk -F'|' '{print $2}' | cut -c2-)
ROUTER_ID=$(quantum router-list | grep router1 | awk -F'|' '{print $2}' | cut -c2-)
quantum router-interface-add $ROUTER_ID $SUBNET_INT_ID

quantum net-create nova -- --router:external=True

EXT_NETWORK_ID=$(quantum net-list | grep nova | awk -F'|' '{print $2}' | cut -c2-)
quantum subnet-create --ip_version 4 $EXT_NETWORK_ID 200.0.0.0/24 -- --enable_dhcp=False
quantum router-gateway-set $ROUTER_ID $EXT_NETWORK_ID

ROUTER_GW_IP=$(quantum port-list -c fixed_ips -c device_owner | grep router_gateway | awk -F '"' '{ print $8; }')
sudo route add -net 100.0.0.0/24 gw $ROUTER_GW_IP

#bridge init script
cat << 'BR_EX_INIT' | sudo tee /etc/init.d/bridge-add > /dev/null
#! /bin/sh
### BEGIN INIT INFO
# Provides:          bridge-add
# Required-Start:    $all
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Bridge Interface Add
### END INIT INFO

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
. /lib/lsb/init-functions

case $1 in
    start)
        ip addr flush dev br-ex
        ip addr add 200.0.0.1/24 dev br-ex
        ip link set br-ex up
        route add -net 100.0.0.0 netmask 255.255.0.0 gw 200.0.0.2
        ;;
    stop)
        sudo ip link set br-ex down
        ;;
    *)
        echo "Usage: $0 {start|stop}" >&2
        exit 3
        ;;
esac

exit 0
BR_EX_INIT

sudo chmod 755 /etc/init.d/bridge-add
sudo update-rc.d bridge-add defaults 21 19

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
sudo mkdir -p /opt/virt/ubuntu13.04 ; cd /opt/virt/ubuntu13.04
sudo wget http://cloud-images.ubuntu.com/releases/13.04/release/ubuntu-13.04-server-cloudimg-amd64-disk1.img
glance image-create --name="Ubuntu_13.04_LTS" --is-public=true --container-format=ovf --disk-format=qcow2 < ubuntu-13.04-server-cloudimg-amd64-disk1.img

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
