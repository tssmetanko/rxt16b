#!/bin/bash
NAME=$1

die(){
	echo $1
	exit 255
}

[[ -z $NAME ]] && die "Name do not correct"

sed -re "s/^HOSTNAME\=/HOSTNAME=${NAME}/" -i /etc/sysconfig/network

