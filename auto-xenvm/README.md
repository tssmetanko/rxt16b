auto-xenvm
======
The auto-xenvm is scripts collection for automatically setup of XEN VMs. This using xenstore feature for share network and other setting between domU and dom0.
Put scripts etc and usr into your template, and use xe-master script inside dom0 for build VM.

Sample of usage of auto-xenmv
````
#In dom0 try this
xe-master -t my_template -h myvm.site.dom -d "{eth0:172.30.18.1,eth1:172.30.8.1}"
````  
This will create new vm with specified IP for each specified iface.


####Notes#####
* This scripts compatible with rhel6 only. 
* Tested on CentOS-6.3 only
* The network mask hardcoded into templates, see "usr/local/libexec/set_ifcfg.sh".
* Default gateway, and other specific settings hardcodet too.
