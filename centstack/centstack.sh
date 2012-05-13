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
NOVA_COMPUTE_IP=192.168.10.60

#rabbitmq setting for common
RABBIT_PASS=password

#mysql(nova) pass
MYSQL_PASS=nova 
MYSQL_PASS_NOVA=password
MYSQL_PASS_KEYSTONE=password
MYSQL_PASS_GLANCE=password
MYSQL_PASS_HORIZON=password 
MYSQL_PASS_QUANTUM=password 

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

#dependency package install for controller
#yum install -y rabbitmq-server mysql-server memcached
yum install -y mysql-server memcached

#service qpidd stop
#service rabbitmq-server restart
#chkconfig rabbitmq-server on
#chkconfig qpidd off

#rabbitmq setting for controller node
#rabbitmqctl add_vhost /nova
#rabbitmqctl add_user nova $RABBIT_PASS
#rabbitmqctl set_permissions -p /nova nova ".*" ".*" ".*"
#rabbitmqctl delete_user guest

#mysql setting for contoller node
service mysqld start
chkconfig mysqld on
mysql -uroot -e "set password for root@localhost=password('$MYSQL_PASS');"
mysql -uroot -p$MYSQL_PASS -e "set password for root@127.0.0.1=password('$MYSQL_PASS');"
mysql -uroot -p$MYSQL_PASS -e "set password for root@$NOVA_CONTOLLER_HOSTNAME=password('$MYSQL_PASS');"

#memcached start
service memcached start
chkconfig memcached on

#dependency package install for compute node
yum install -y iscsi-initiator-utils qemu-kvm \
               libvirt bridge-utils libvirt-python
service libvirtd start

#qpidd setup
sed -i 's/auth=yes/auth=no/' /etc/qpidd.conf
service qpidd restart
chkconfig qpidd on

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

#keystone install
yum install -y openstack-keystone

#keystone setting
cp -a /etc/keystone /etc/keystone_bak
sed -i "s#mysql://keystone:keystone@localhost/keystone#mysql://keystone:$MYSQL_PASS_KEYSTONE@$NOVA_CONTOLLER_HOSTNAME/keystone#" /etc/keystone/keystone.conf
sed -i "s#ADMIN#$ADMIN_TOKEN#" /etc/keystone/keystone.conf
sed -i "s#keystone.catalog.backends.sql.Catalog#keystone.catalog.backends.templated.TemplatedCatalog#" /etc/keystone/keystone.conf
sed -i "s/localhost/$NOVA_CONTOLLER_HOSTNAME/" /etc/keystone/default_catalog.templates

: << '#COMMENT_OUT'
cat << KEYSTONE_TEMPLATE | tee -a /etc/keystone/default_catalog.templates > /dev/null

catalog.RegionOne.s3.publicURL = http://$NOVA_CONTOLLER_HOSTNAME:3333
catalog.RegionOne.s3.adminURL = http://$NOVA_CONTOLLER_HOSTNAME:3333
catalog.RegionOne.s3.internalURL = http://$NOVA_CONTOLLER_HOSTNAME:3333
catalog.RegionOne.s3.name = S3 Service

catalog.RegionOne.object-store.publicURL = http://$NOVA_CONTOLLER_HOSTNAME:8080/v1/AUTH_\$(tenant_id)s
catalog.RegionOne.object-store.adminURL = http://$NOVA_CONTOLLER_HOSTNAME:8080/
catalog.RegionOne.object-store.internalURL = http://$NOVA_CONTOLLER_HOSTNAME:8080/v1/AUTH_\$(tenant_id)s
catalog.RegionOne.object-store.name = Swift Service

catalog.RegionOne.network.publicURL = http://$NOVA_CONTOLLER_HOSTNAME:9696/
catalog.RegionOne.network.adminURL = http://$NOVA_CONTOLLER_HOSTNAME:9696/
catalog.RegionOne.network.internalURL = http://$NOVA_CONTOLLER_HOSTNAME:9696/
catalog.RegionOne.network.name = Quantum Service
KEYSTONE_TEMPLATE
#COMMENT_OUT

#keystone db make
mysql -u root -pnova -e "create database keystone;"
mysql -u root -pnova -e "grant all privileges on keystone.* to 'keystone'@'%' identified by '$MYSQL_PASS_KEYSTONE';"
mysql -u root -pnova -e "grant all privileges on keystone.* to 'keystone'@'localhost' identified by '$MYSQL_PASS_KEYSTONE';"
mysql -u root -pnova -e "grant all privileges on keystone.* to 'keystone'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_KEYSTONE';"
keystone-manage db_sync

#keystone service init
service openstack-keystone start
chkconfig openstack-keystone on

#keystone setting2
sleep 3
cd /home/$STACK_USER ; cp -a /usr/share/openstack-keystone/sample_data.sh .
sed -i "s/127.0.0.1/$NOVA_CONTOLLER_HOSTNAME/" /home/$STACK_USER/sample_data.sh
sed -i "s/localhost/$NOVA_CONTOLLER_HOSTNAME/" /home/$STACK_USER/sample_data.sh
sed -i "66s/secrete/$ADMIN_PASSWORD/" /home/$STACK_USER/sample_data.sh
#sed -i '63a\ENABLE_SWIFT=1' /home/$STACK_USER/sample_data.sh
##sed -i '63a\ENABLE_ENDPOINTS=1' /home/$STACK_USER/sample_data.sh
#sed -i '63a\ENABLE_QUANTUM=1' /home/$STACK_USER/sample_data.sh
/home/$STACK_USER/sample_data.sh

#glance install
yum install -y openstack-glance

#glance setting
cp -a /etc/glance /etc/glance_orig
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-api-paste.ini
sed -i "s/%SERVICE_TENANT_NAME%/$ADMIN_TENANT_NAME/" /etc/glance/glance-api-paste.ini
sed -i "s/%SERVICE_USER%/$ADMIN_USERNAME/" /etc/glance/glance-api-paste.ini
sed -i "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" /etc/glance/glance-api-paste.ini
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-api.conf
echo -e "\n[paste_deploy]\nflavor = keystone"  | tee -a /etc/glance/glance-api.conf
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_TENANT_NAME%/$ADMIN_TENANT_NAME/" /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_USER%/$ADMIN_USERNAME/" /etc/glance/glance-registry-paste.ini
sed -i "s/%SERVICE_PASSWORD%/$ADMIN_PASSWORD/" /etc/glance/glance-registry-paste.ini
sed -i "s#mysql://glance:glance@localhost/glance#mysql://glance:$MYSQL_PASS_GLANCE@$NOVA_CONTOLLER_HOSTNAME/glance#" /etc/glance/glance-registry.conf
echo -e "\n[paste_deploy]\nflavor = keystone"  | tee -a /etc/glance/glance-registry.conf
mysql -u root -pnova -e "create database glance;"
mysql -u root -pnova -e "grant all privileges on glance.* to 'glance'@'%' identified by '$MYSQL_PASS_GLANCE';"
mysql -u root -pnova -e "grant all privileges on glance.* to 'glance'@'localhost' identified by '$MYSQL_PASS_NOVA';"
mysql -u root -pnova -e "grant all privileges on glance.* to 'glance'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_NOVA';"
glance-manage version_control 0
glance-manage db_sync

#glance service init
chown glance:glance /var/log/glance -R
for i in api registry
do
  service openstack-glance-$i start
done
for i in api registry
do
  chkconfig openstack-glance-$i on
done

#nova install
yum install -y openstack-nova

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

#nova db make
mysql -u root -pnova -e "create database nova;"
mysql -u root -pnova -e "grant all privileges on nova.* to 'nova'@'%' identified by '$MYSQL_PASS_NOVA';"
mysql -u root -pnova -e "grant all privileges on nova.* to 'nova'@'localhost' identified by '$MYSQL_PASS_NOVA';"
mysql -u root -pnova -e "grant all privileges on nova.* to 'nova'@'$NOVA_CONTOLLER_HOSTNAME' identified by '$MYSQL_PASS_NOVA';"
nova-manage db sync

#epel openstack workaround
mkdir /var/lock/nova
chown nova:root /var/lock/nova
sed -i '37s/int(self.partition or 0)/-1/' /usr/lib/python2.6/site-packages/nova/virt/disk/guestfs.py

#nova service init
for proc in api metadata-api cert network compute objectstore console scheduler consoleauth volume direct-api xvpvncproxy
do
  service openstack-nova-$proc start
done
for proc in api metadata-api cert network compute objectstore console scheduler consoleauth volume direct-api xvpvncproxy
do
  chkconfig openstack-nova-$proc on
done

#horizon install
rpm -ivh http://kojipkgs.fedoraproject.org/packages/Django/1.3.1/1.el6/noarch/Django-1.3.1-1.el6.noarch.rpm
yum install -y openstack-dashboard

#horizon setting
cp -a /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings_orig
sed -i "s#127.0.0.1#$NOVA_CONTOLLER_HOSTNAME#" /etc/openstack-dashboard/local_settings
sed -i "s#locmem://#memcached://$NOVA_CONTOLLER_HOSTNAME:11211#g" /etc/openstack-dashboard/local_settings
sed -i '24,30s/^/#/' /etc/openstack-dashboard/local_settings
cat << HORIZON_SETUP | tee -a /etc/openstack-dashboard/local_settings > /dev/null
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
cd /usr/share/openstack-dashboard && ./manage.py syncdb

#horizon work arround bug 
sed -i 's/430/441/' /usr/lib/python2.6/site-packages/horizon/dashboards/nova/templates/nova/instances_and_volumes/instances/_detail_vnc.html

#apache2 setting
cp -a /etc/httpd/conf.d/openstack-dashboard.conf /etc/httpd/conf.d/openstack-dashboard.conf_orig
sed -i 's#WSGIScriptAlias /dashboard#WSGIScriptAlias /#' /etc/httpd/conf.d/openstack-dashboard.conf

#novnc install
yum install -y rpm-build make gcc
yum install -y numpy python-matplotlib
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
echo '%_topdir %(echo $HOME)/rpmbuild' > ~/.rpmmacros
wget http://admiyo.fedorapeople.org/noVNC/novnc.spec -P ~/rpmbuild/SPECS
wget http://admiyo.fedorapeople.org/noVNC/novnc-0.2.0GITf8380f.tar.gz -P ~/rpmbuild/SOURCES
cd ~/rpmbuild/SPECS
rpmbuild -ba novnc.spec
rpm -ivh /root/rpmbuild/RPMS/x86_64/novnc-0.2.0GITf8380f-0.el6.x86_64.rpm
rpm -ivh http://admiyo.fedorapeople.org/noVNC/novnc-nonvc-openstack-nova-0.2.0GITf8380f-0.f17ayoung.x86_64.rpm
cat << 'EOF' | tee /etc/init.d/openstack-nova-novnc > /dev/null
#!/bin/sh
#
# openstack-nova-novnc  noVNC for OpenStack Nova
#
# chkconfig:   - 20 80
# description: OpenStack Nova noVNC
# author       Shiro Hagihara(Fulltrust.inc) <hagihara@fulltrust.co.jp @hagix9 fulltrust.co.jp>

start() {
  cd /usr/share/novnc && /usr/bin/nova-vncproxy --flagfile=/etc/nova/nova.conf –web . >/dev/null 2>&1 &
}

stop() {
  kill $(ps -ef | grep nova-vncproxy | grep -v grep | awk '{print $2}')
}

restart() {
    stop
    start
}

reload() {
    restart
}

case "$1" in
    start)
        $1
        ;;
    stop)
        $1
        ;;
    restart)
        $1
        ;;
    *)
        echo $"Usage: $0 {start|stop|restart}"
        exit 2
esac
exit $?
EOF
chmod 755  /etc/init.d/openstack-nova-novnc
service openstack-nova-novnc start
chkconfig openstack-nova-novnc on

#iptables setting
sed -i '10a-A INPUT -m state --state NEW -m tcp -p tcp --dport 6080 -j ACCEPT' /etc/sysconfig/iptables
sed -i '10a-A INPUT -m state --state NEW -m tcp -p tcp --dport 443 -j ACCEPT' /etc/sysconfig/iptables
sed -i '10a-A INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT' /etc/sysconfig/iptables
service iptables restart

#apache2 restart
service httpd restart
chkconfig httpd on

#env_file2 make
. /home/$STACK_USER/keystonerc
USER_ID=$(keystone user-list | awk "/$ADMIN_USERNAME / {print \$2}")
ACCESS_KEY=$(keystone ec2-credentials-list --user $USER_ID | awk "/$ADMIN_USERNAME / {print \$4}")
SECRET_KEY=$(keystone ec2-credentials-list --user $USER_ID | awk "/$ADMIN_USERNAME / {print \$6}")
cd /home/$STACK_USER
cat > novarc <<EOF
export EC2_URL=http://$NOVA_CONTOLLER_HOSTNAME:8773/services/Cloud
export EC2_ACCESS_KEY=$ACCESS_KEY
export EC2_SECRET_KEY=$SECRET_KEY
EOF
chown $STACK_USER:$STACK_USER novarc
chmod 600 novarc
. /home/$STACK_USER/novarc

cat << NOVARC | tee -a /etc/bashrc > /dev/null
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
nova-manage float create --ip_range=$FLOAT_IP_RANGE
#keypair make
cd /home/$STACK_USER
nova keypair-add mykey > mykey
chown $STACK_USER:$STACK_USER mykey
chmod 600 mykey

#security group rule add
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
nova  secgroup-add-rule default  tcp 22 22 0.0.0.0/0 

#warning workaround
sed -i '141,143s/^/#/' /usr/lib64/python2.6/site-packages/SQLAlchemy-0.7.3-py2.6-linux-x86_64.egg/sqlalchemy/pool.py
sed -i '149s/^/#/' /usr/lib64/python2.6/site-packages/SQLAlchemy-0.7.3-py2.6-linux-x86_64.egg/sqlalchemy/pool.py

#ami ubuntu11.10
#mkdir /opt/virt/ubuntu11.10 ; cd /opt/virt/ubuntu11.10
#wget http://uec-images.ubuntu.com/releases/11.10/release/ubuntu-11.10-server-cloudimg-amd64-disk1.img
#glance add name="Ubuntu 11.10" is_public=true container_format=ovf disk_format=qcow2 < ubuntu-11.10-server-cloudimg-amd64-disk1.img

#ami ubuntu12.04
#mkdir /opt/virt/ubuntu12.04 ; cd /opt/virt/ubuntu12.04
#wget http://cloud-images.ubuntu.com/releases/precise/release/ubuntu-12.04-server-cloudimg-amd64-disk1.img
#glance add name="Ubuntu 12.04 LTS" is_public=true container_format=ovf disk_format=qcow2 < ubuntu-12.04-server-cloudimg-amd64-disk1.img
#COMMENT_OUT

#ami fedora16
mkdir -p /opt/virt/fedora; cd /opt/virt/fedora;
wget http://berrange.fedorapeople.org/images/2012-02-29/f16-x86_64-openstack-sda.qcow2
glance add name=f16-jeos is_public=true disk_format=qcow2 container_format=ovf < f16-x86_64-openstack-sda.qcow2
#ex
#ssh -i /home/$STACK_USER/mykey ec2-user@10.0.0.4
