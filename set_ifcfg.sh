#!/bin/bash
IP=$2
IFNAME=$1

[[ -z $IFNAME ]] && ( echo "Error, IFNAME is empty"; exit 255)
[[ -z $IP ]]&&( echo "Error, IP is empty"; exit 255)

HWADDR=$( ifconfig ${IFNAME} | grep 'HWaddr'| grep -oP '(\w{2}\:){5}\w{2}' )

template(){
cat <<TEMP1
DEVICE="${IFNAME}"
BOOTPROTO="static"
HWADDR="${HWADDR}"
IPADDR="${IP}"
NETMASK="255.255.252.0"
NM_CONTROLLED="no"
ONBOOT="yes"
TYPE="Ethernet"
TEMP1
}

template > /etc/sysconfig/network-scripts/ifcfg-${IFNAME}
