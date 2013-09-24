hagistack is a set of scripts to quickly deploy an OpenStack cloud.

# And hagistack?

* To easy install OpenStack environments in a clean Ubuntu13.04
* However, it does not install also Qauntum Swift.

Read more at http://http://oss.fulltrust.co.jp/

# Prerequisite

* When you install the OS, please create a LVM named cinder-volumes.
* IP address must have been fixed.
* Please do not create the bridge interfaces.

# Versions

The hagistack master branch generally points to Grizzly versions of OpenStack components.

# Install Openstack

Installing in a dedicated disposable vm is safer than installing on your dev machine!  To start a dev cloud:

    bash ./hagistack_controller.sh

or 

The Prepare two NIC If you want to do also install the Quantum

    bash ./hagistack_controller_quantum.sh

or

If you want to do also install the Quantum (Number of necessary NIC 1)

    bash ./hagistack_compute_quantum.sh

When the script finishes executing, you should be able to access OpenStack endpoints, like so:

* Horizon: http://$NOVA_CONTROLLER_IP/horizon

If you want to use OpenStackAPI

    # source keystonerc file to load your environment with osapi and ec2 creds
    # However, it is set to /etc/bashrc
    . /home/$STACK_USER/keystonerc
    # list instances
    nova list

# Customizing

You can override environment variables used in `hagistack_controller.sh` by creating file name `stack.env`.

