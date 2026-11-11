#!/bin/sh
# Written for Hagistack.
# Turns on netfilter for traffic crossing Linux bridges, which the
# iptables-based security group drivers of the Open vSwitch agent need:
# loads br_netfilter and sets the three bridge-nf-call sysctls to 1.
# Run as root (neutron-openvswitch-agent.service runs it before the agent).
# Exit status 1 if the module or a setting could not be applied.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if ! modprobe -b br_netfilter; then
    echo "neutron-enable-bridge-firewall: could not load br_netfilter" >&2
    exit 1
fi
rc=0
for key in net.bridge.bridge-nf-call-arptables \
           net.bridge.bridge-nf-call-iptables \
           net.bridge.bridge-nf-call-ip6tables; do
    if ! sysctl -q -w "$key=1" >/dev/null; then
        echo "neutron-enable-bridge-firewall: could not set $key=1" >&2
        rc=1
    fi
done
exit "$rc"
