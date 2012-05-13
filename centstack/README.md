hagiStack is a set of scripts to quickly deploy an OpenStack cloud.

# And Centstack?

* To easy install OpenStack environments in a clean CentOS6.2(minimal)
* However, it does not install also Qauntum Swift.

Read more at http://http://oss.fulltrust.co.jp/

# Prerequisite

* When you install the OS, please create a LVM named nova-volumes.
* IP address must have been fixed.
* Please do not create the bridge interfaces.

# Versions

The hagistack master branch generally points to Essex versions of OpenStack components.

# Install Openstack

Installing in a dedicated disposable vm is safer than installing on your dev machine!  To start a dev cloud:

    ./centstack.sh

When the script finishes executing, you should be able to access OpenStack endpoints, like so:

* Horizon: http://$NOVA_CONTOLLER_IP/

If you want to use OpenStackAPI

    # source keystonerc file to load your environment with osapi and ec2 creds
    # However, it is set to /etc/bashrc
    . /home/$STACK_USER/keystonerc
    # list instances
    nova list

If you want to use EC2API

    # source eucarc to generate EC2 credentials and set up the environment
    # However, it is set to /etc/bashrc
    . /home/$STACK_USER/eucarc
    # list instances using ec2 api
    euca-describe-instances

# Customizing

You can override environment variables used in `centstack.sh` by creating file name `stack.env`.

