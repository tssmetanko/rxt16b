#!/bin/bash
NAME=$1

die(){
	echo $1
	exit 255
}

echo -n "Setting of hostname: "
[[ -z $NAME ]] && die "Name do not correct. Skiping"
sed -re "s/^HOSTNAME\=.*$/HOSTNAME=${NAME}/" -i /etc/sysconfig/network && echo " $NAME" || die "Err"
hostname ${NAME}

