#!/bin/bash
#set -x
set -e

HOST_CFG="/tmp/${HOSTNAME}.cfg"

die(){
        echo $1; exit 255
}

get_ip_of_dev(){
	local dev=$1
	local ip=$(ip addr show ${dev} | grep -P 'inet\s' | awk '{print $2}'|cut -d/ -f1)
	echo $ip	
}
template(){
cat <<TEMP1
        define host {
        host_name                       ${N_HOSTNAME}
        alias                           ${N_HOSTNAME} added by nagiosQL from api
        address                         ${IP_ADDR}
        use                             nrpe-host
	contacts                        null
	contact_groups                  null
	notifications_enabled		0
        register                        1
        }
TEMP1
}
printhelp(){
cat << HELP
	-d device where get IP address for host. This parameter used when no IP address set by '-i' only.
	-i ipaddress or fqdn of host. Nagios should monitoring this host by this address.
	-n hostname. The hostname of the host that will be added to the nagiosQL. Default - hostname of localhost.
	-s adderess of nagios server. The default nagios.dev.cinsay.com
	-f fixed. NagiosQL should write database to the nagios config files, and restart it if this flag activated. 
		Otherwise, new host will be added to nagiosQL database only, you need manually write changes to the nagios and restart it.			
HELP
}


while getopts "d:s:h:i:f" option; do
	case $option in
		s)NAGIOS_SRV="$OPTARG";;
		d)NET_DEV="$OPTARG";;
		n)N_HOSTNAME=$OPTARG;;
		i)IP_ADDR=$OPTARG;;
		f)FIX=1;;
		*|-h)printhelp;exit 0;;
	esac
done


[[ -z $NAGIOS_SRV ]]&&NAGIOS_SRV=nagios.dev.cinsay.com
[[ -z $N_HOSTNAME ]]&&N_HOSTNAME=$HOSTNAME
if [[ -z $IP_ADDR && -n $NET_DEV ]]; then
	IP_ADDR=$( get_ip_of_dev ${NET_DEV} )
	[[ -z $IP_ADDR ]]&& die "Cannot set IP addres by $NET_DEV"
elif [[  -z $IP_ADDR && -z $NET_DEV ]]; then
	die "IP address does not set, NET_DEV does not set too"
fi
 
template > "/tmp/${N_HOSTNAME}.cfg"
trap "rm -rf /tmp/${N_HOSTNAME}.cfg" EXIT

#add host to the nagios server
curl -F function=import -F domain=localhost -F"object=@/tmp/${N_HOSTNAME}.cfg" -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php

#fix host adding, flush nagiosQL database to the nagios configureatuion files.
if [[ $FIX == 1 ]]; then
	curl -F object=host -F function=write -F domain=localhost -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php
	curl -F function=check -F domain=localhost -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php 
	#| grep -q 'Error' && die "Error on nagios check"
	curl -F function=restart -F domain=localhost -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php	
fi

