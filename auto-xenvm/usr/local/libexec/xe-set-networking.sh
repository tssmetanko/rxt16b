#!/bin/bash

WORK_PATH="/usr/local/libexec"

DOMID=$(xenstore-read domid)
NAME=$(xenstore-read name)

$WORK_PATH/set_hostname.sh ${NAME}

for ETH in eth0 eth1 eth2 eth3; do
	xenstore-exists vm-data/${ETH}||continue
	IP=$(xenstore-read vm-data/${ETH})
	if [[ -n $IP && -n $ETH ]]; then
		$WORK_PATH/set_ifcfg.sh $ETH $IP
	fi
done
