#!/bin/bash
WORK_PATH="/usr/local/libexec"

DOMID=$(xenstore-read domid)
NAME=$(xenstore-read vm-data/hostname)

$WORK_PATH/xe-set-hostname.sh ${NAME}

for ETH in "eth1 eth2 eth3 eth4"; do
	IP=$(xenstore-read vm-data/${ETH})
	if [[ -n $IP && -n $ETH ]]; then
		$WORK_PATH/set_ifcfg.sh $ETH $IP
	fi
done
