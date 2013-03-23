#!/bin/bash
#description "OpenStack Image Make Script"
#author "Shiro Hagihara(Fulltrust.inc) <hagihara@fulltrust.co.jp @hagix9 fulltrust.co.jp>"
#prerequisite install Ubuntu or CentOS

#env
DIR=/opt/virt

#os judgement
BASE=$(cat /etc/issue | awk '{print $1}' | grep -v "^$" | tr A-Z a-z)

#read the configuration from external
if [ -f ami.env ] ; then
  . ./ami.env
fi

if [ $BASE == ubuntu ] ; then
  apt-get install virtinst -y
elif [ $BASE == centos ] ; then
  yum install -y python-virtinst
else
  echo "Please enter your ubuntu or centos"
fi

mkdir -p $DIR/CentOS6.4
mkdir /mnt/ec2-ami
qemu-img create -f raw $DIR/CentOS6.4/CentOS6.4.img 10G
mke2fs -t ext4 -F -j $DIR/CentOS6.4/CentOS6.4.img
mount -o loop $DIR/CentOS6.4/CentOS6.4.img /mnt/ec2-ami
mkdir /mnt/ec2-ami/dev
cd /mnt/ec2-ami/dev

if [ $BASE == ubuntu ] ; then
  MAKEDEV consoleonly
  MAKEDEV null
  #ls | egrep -v 'console|null|zero' | xargs rm -r
elif [ $BASE == centos ] ; then
  for i in console null zero ; do /sbin/MAKEDEV -d /mnt/ec2-fs/dev -x $i; done
else
  echo "Please enter your ubuntu or centos"
fi

mkdir /mnt/ec2-ami/etc
cat << FSTAB_AMI | tee /mnt/ec2-ami/etc/fstab > /dev/null
LABEL=uec-rootfs / ext4 defaults 1 1
tmpfs /dev/shm tmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
sysfs /sys sysfs defaults 0 0
proc /proc proc defaults 0 0
/dev/sda2 /mnt ext3 defaults 0 0
/dev/sda3 swap swap defaults 0 0
FSTAB_AMI
cd /mnt/ec2-ami/etc
cat << YUM_AMI | tee /mnt/ec2-ami/etc/yum-ami.conf > /dev/null
[main]
cachedir=/var/cache/yum
debuglevel=2
logfile=/var/log/yum.log
exclude=*-debuginfo
gpgcheck=0
obsoletes=1
reposdir=/dev/null

[base]
name=CentOS Linux - Base
baseurl=http://ftp.riken.jp/Linux/centos/6.4/os/x86_64/
enabled=1
gpgcheck=0

[updates]  
name=CentOS-6 - Updates  
baseurl=http://ftp.riken.jp/Linux/centos/6.4/updates/x86_64/  
enabled=1
gpgcheck=0
YUM_AMI
mkdir /mnt/ec2-ami/proc
mount -t proc none /mnt/ec2-ami/proc
apt-get install yum -y
yum -c /mnt/ec2-ami/etc/yum-ami.conf --installroot=/mnt/ec2-ami -y groupinstall Core
yum -c /mnt/ec2-ami/etc/yum-ami.conf --installroot=/mnt/ec2-ami -y groupinstall Base
cat << NIC_AMI | tee /mnt/ec2-ami/etc/sysconfig/network-scripts/ifcfg-eth0 > /dev/null
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=yes
PEERDNS=yes
IPV6INIT=no
NIC_AMI
cat << NETWORKING_AMI | tee /mnt/ec2-ami/etc/sysconfig/network > /dev/null
NETWORKING=yes
NETWORKING_AMI
chroot /mnt/ec2-ami cp -p /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.org
chroot /mnt/ec2-ami sed -i 's/^#baseurl/baseurl/g' /etc/yum.repos.d/CentOS-Base.repo
chroot /mnt/ec2-ami sed -i 's/$releasever/6.4/g' /etc/yum.repos.d/CentOS-Base.repo
cat << DNS_AMI | tee /mnt/ec2-ami/etc/resolv.conf > /dev/null
nameserver 8.8.8.8
DNS_AMI
chroot /mnt/ec2-ami yum install curl -y
cat << RC_LOCAL_AMI | tee -a /mnt/ec2-ami/etc/rc.local > /dev/null
depmod -a
modprobe acpiphp
/usr/local/sbin/get-credentials.sh
RC_LOCAL_AMI
chroot /mnt/ec2-ami sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
chroot /mnt/ec2-ami chkconfig ip6tables off
chroot /mnt/ec2-ami chkconfig iptables off
chroot /mnt/ec2-ami chkconfig ntpd on
cat << CREDS_AMI | tee -a /mnt/ec2-ami/usr/local/sbin/get-credentials.sh > /dev/null
#!/bin/bash

# Retreive the credentials from relevant sources.

# Fetch any credentials presented at launch time and add them to
# root's public keys

PUB_KEY_URI=http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key
PUB_KEY_FROM_HTTP=/tmp/openssh_id.pub
PUB_KEY_FROM_EPHEMERAL=/mnt/openssh_id.pub ROOT_AUTHORIZED_KEYS=/root/.ssh/authorized_keys



# We need somewhere to put the keys.
if [ ! -d /root/.ssh ] ; then
mkdir -p /root/.ssh
chmod 700 /root/.ssh
fi

# Fetch credentials...

# First try http
curl --retry 3 --retry-delay 0 --silent --fail -o $PUB_KEY_FROM_HTTP $PUB_KEY_URI
if [ $? -eq 0 -a -e $PUB_KEY_FROM_HTTP ] ; then
if ! grep -q -f $PUB_KEY_FROM_HTTP $ROOT_AUTHORIZED_KEYS
then
cat $PUB_KEY_FROM_HTTP >> $ROOT_AUTHORIZED_KEYS
echo "New key added to authrozied keys file from parameters"|logger -t "ec2"
fi
chmod 600 $ROOT_AUTHORIZED_KEYS
rm -f $PUB_KEY_FROM_HTTP

elif [ -e $PUB_KEY_FROM_EPHEMERAL ] ; then
# Try back to ephemeral store if http failed.
# NOTE: This usage is deprecated and will be removed in the future
if ! grep -q -f $PUB_KEY_FROM_EPHEMERAL $ROOT_AUTHORIZED_KEYS
then
cat $PUB_KEY_FROM_EPHEMERAL >> $ROOT_AUTHORIZED_KEYS
echo "New key added to authrozied keys file from ephemeral store"|logger -t "ec2"

fi
chmod 600 $ROOT_AUTHORIZED_KEYS
chmod 600 $PUB_KEY_FROM_EPHEMERAL

fi

if [ -e /mnt/openssh_id.pub ] ; then
if ! grep -q -f /mnt/openssh_id.pub /root/.ssh/authorized_keys
then
cat /mnt/openssh_id.pub >> /root/.ssh/authorized_keys
echo "New key added to authrozied keys file from ephemeral store"|logger -t "ec2"

fi
chmod 600 /root/.ssh/authorized_keys
fi
CREDS_AMI
chmod 755 /mnt/ec2-ami/usr/local/sbin/get-credentials.sh

#Additional packages
chroot /mnt/ec2-ami yum install http://ftp.riken.jp/Linux/fedora/epel/6/x86_64/epel-release-6-8.noarch.rpm -y
chroot /mnt/ec2-ami yum install cloud-init telnet ftp -y

cp /mnt/ec2-ami/boot/initramfs-*.x86_64.img $DIR/CentOS6.4
cp /mnt/ec2-ami/boot/vmlinuz-*.x86_64 $DIR/CentOS6.4
cd
umount /mnt/ec2-ami/proc
umount /mnt/ec2-ami
tune2fs -L uec-rootfs $DIR/CentOS6.4/CentOS6.4.img
cd $DIR/CentOS6.4
qemu-img convert -O qcow2 -c CentOS6.4.img CentOS6.4.qcow2
\rm CentOS6.4.img

#For OpenStack Example

#cd $DIR/CentOS6.4
#glance image-create --name="centos64_kernel" --is-public=true --container-format=aki --disk-format=aki < $(ls | grep vmlinuz)
#glance image-create --name="centos64_ramdisk" --is-public=true --container-format=ari --disk-format=ari < $(ls | grep initram)
#RAMDISK_ID=$(glance image-list | grep centos64_ramdisk | awk -F"|" '{print $2}' | sed -e 's/^[ ]*//g')
#KERNEL_ID=$(glance image-list | grep centos64_kernel | awk -F"|" '{print $2}' | sed -e 's/^[ ]*//g')
#glance image-create --name="centos64_ami" --is-public=true --container-format=ami --disk-format=ami --property kernel_id=$KERNEL_ID --property ramdisk_id=$RAMDISK_ID < CentOS6.4.qcow2
#nova boot --flavor 1 --image centos64_ami centos64_001 --key_name mykey
#ssh -i mykey root@10.0.0.2
