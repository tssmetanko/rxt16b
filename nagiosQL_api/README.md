nagiosQL API
======
The nagiosQL API provides interface to manage nagiosQL remotely via http POST and GET requests

####do_config_l.php####

Basically nagiosQL do not have feature for remote management via API, it have only local command line interface.
The PHP script "scripts/do_config_l.php" based on the "scripts/do_config.php" and provides features for remote managing of nagiosQL.

You can use this like in BASH block follow
```
#------------------------------------------------------
#Add SOME_NAG_CONFIG.cfg to the nagiosQL.
curl -F function=import -F domain=localhost -F"object=@/tmp/SOME_NAG_CONFIS.cfg" -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php
#Flush nagiosQL database to nagios configs
curl -F object=host -F function=write -F domain=localhost -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php
#Check nagios configs
curl -F function=check -F domain=localhost -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php
#Apply changes by reloading of daemons.
curl -F function=restart -F domain=localhost -k https://${NAGIOS_SRV}/nagiosql/scripts/do_config_l.php
#------------------------------------------------------```
```
Where SOME_NAG_CONFIG.cfg somethig like this:
```
#------------------------------------------------------
define host {
        host_name                       ${N_HOSTNAME}
        alias                           ${N_HOSTNAME} added by nagiosQL from api
        address                         ${IP_ADDR}
        use                             nrpe-host
      	contacts                        null
	      contact_groups                  null
	      notifications_enabled		        0
        register                        1
}
#------------------------------------------------------
```
Just simple nagios host/service/etc definition.

####add_host_to_nagiosQL.sh####

This scripts for adding self host information to the nagiosQL. Use help -h for more info.

