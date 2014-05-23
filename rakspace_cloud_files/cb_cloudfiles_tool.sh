#!/bin/bash
#set -c
set -e
#set -x
source /etc/cloud/settings.conf
#Block for assidentialy removing of $CONTAINER, than may be exported from settings.conf
unset CONTAINER
  
TMP_FILE="/tmp/${RANDOM}"
trap "rm -rf $TMP_FILE" EXIT
#[[ -n $1 ]]&&[[ $1 =~ ^[a-zA-Z0-9_\+-\.]+$ ]] && RM_CONTAINER=$1 || ( echo -e "Container name not specified. usage: cb_remove-container.sh <CONTAINER_NAME>\nFor get list of containers use cb_list-containers.sh"; exit 2 )
#GET X-Auth-Token and X-Storage-Url 
curl -X GET -s -D - -H "X-Auth-User:$CLOUDFILES_USERNAME" -H "X-Auth-Key:$CLOUDFILES_APIKEY" "https://identity.api.rackspacecloud.com/v1.0" > $TMP_FILE
X_STORAGE_URL="`grep "X-Storage-Url:" $TMP_FILE |awk  '{FS=": "} {print $2}' | tr -d '\r'`"
X_AUTH_TOKEN="`grep "X-Auth-Token:" $TMP_FILE |awk '{FS=": "} {print $2}' | tr -d '\r'`"

protector(){
	local CONTENT=$1
	[[ $2 = "--force" ]] && return 0
	[[ $OP_FORCE = 1 ]] && return 0
	echo "ALL DATA in $CONTENT will be destroed. Are you sure?(y/n)"
	while read answer; do
		case $answer in 
			"y") echo "Trying delete $CONTAINER"; break ;;
			"n") echo "Exit by user"; exit 0 ;;
			*)echo "type y on n";;
		esac
	done
}
usage(){
	cat <<- USAGE0001
		-c <container/path/to/some/data> container name. This option specify container or object path
		-r remove. flag to remove container
		-e erase. Remove data cpecified with -c
		-l list. flag to list files from the container or from the path
		-f force. flag to force all operation without protection
		-i info. get information about objects. use this flag with -l
		-g get. get data from path specified by -c
		-a <path/to/local/data> append local data to path specified by -c
		-C <dir_name> change dir. Change dir before operations, works only with and -g
		SAMPLES:
		cb_cloudfiles_tool -l 
		List all available containers

		cb_cloudfiles_tool -c im_backup -r
		Remove "im_backup" container from cloud files

		cb_cloudfiles_tool -c tomcat_apps/data/stuff -e -f
		Remove direcrory data/stuff from container tomcat_apps without questions.

		cb_cloudfiles_tool -c tomcat_apps/data -a /srv/mega_app
		Append directory /srv/mega_app to tomcat_apps/data/mega_app
		
		cb_cloudfiles_tool -c tomcat_apps/data/mega_app -g  -C /home/jonson
		Get directory mega_app from cloud files to home for Jonson.

		cb_cloudfiles_tool -c tomcat_apps/data/mega_app -l -i
		get addional information about objects in data/mega_app
	USAGE0001
	
}
list_objects(){
	curl -X GET -s -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}/${CONTAINER}" | grep -P "^${DEST}\b"
}
get_container_info(){
	local conatiner=$*
	[[ $container =~ ^\s*$ ]] && container=$CONTAINER
        curl -X HEAD -I -s -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}/${container}"
}
show_containers(){
	if [[ $SHOW_INFO = 1 ]]; then
		local IFS=$'\012';local used_space=''
		for container in $( curl -X GET -s  -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}" ); do
			used_space=$( get_container_info $container|grep 'X-Container-Bytes-Used'|awk '{FS=":";printf "%.4f\n", $2/(1024*1024)}' | sed 's/^\s*//' )
			printf "$used_space\t\t$container\n"
		done
	else
		curl -X GET -s  -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}"
	fi
	
}
delete_file(){
	#local CONTAINER=''
	local FILE=''
	[[ -n $1 && $1 =~ ^.+$ ]] && FILE=$1 || ( usage; echo "error delete file"; exit 2)
	protector $FILE $2
	echo -en "$1: "
	curl -X DELETE -s -D - -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}/${CONTAINER}/${FILE}" > $TMP_FILE 2>&1
	grep -P '204\s+No\s+Content' $TMP_FILE > /dev/null 2>&1 && echo "DELETED" || echo "ERR"
}
cleanup_container(){
	protector "${CONTAINER}/${DEST}"
	list_objects | while read file; do
		delete_file "$file" --force
	done
}
remove_container(){
	cleanup_container
	echo -n "Removing container: $CONTAINER: "
	curl -X DELETE -s -D - -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}/${CONTAINER}" > $TMP_FILE 2>&1
	grep -P '204\s+No\s+Content' $TMP_FILE > /dev/null 2>&1 && echo "DELETED" || echo "ERR"
}
create_container(){
	echo "Creation of new container $CONTAINER"
	curl -X PUT -s -D - -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}/${CONTAINER}" > $TMP_FILE 2>&1
        grep -P '201\s+Created' $TMP_FILE > /dev/null 2>&1 && echo "CREATED" || echo "ERR"
}
put_files_to_container(){
	local FILE=$1
	#local file=''
	#local DEST=$2
	if [[ -d $FILE && -r $FILE ]]; then
		#This flag indicate than files taked from directory and needed to save file relative path when put it to container
		SAVE_FILE_PATH=1
		#if file is a directory and it ended at '/' than copy directory content instead directory 
		[[ ! $FILE =~ /$ ]]&& DEST="${DEST}/`echo $FILE | awk -F '/' '{print $NF}'`"
		cd $FILE
		find -type f | while read file; do
			put_files_to_container $file
		done
	elif [[ -f $FILE && -r $FILE ]]; then
		echo "Send $FILE to cloud files"
		#If SAVE_FILE_PATH flag not set use short name of the file when put it into the container 
		[[ $SAVE_FILE_PATH -ne 1 ]] && FILE=`echo $FILE | awk -F '/' '{print $NF}'`
		FILE_PATH=`echo "${DEST}/${FILE}"|sed -re "s%^/+%%" |sed -re 's%//+%/%' | sed -re 's%\./%%'` 
		#| sed -re "s%/+%/%"`
		curl -X PUT -s -H "X-Auth-Token:$X_AUTH_TOKEN" -T $FILE "${X_STORAGE_URL}/${CONTAINER}/$FILE_PATH"
	#elif [[ $FILE =~ \*$ ]]; then
	#	echo "Tree"
	#	#If used shell substions search all files and put it into cloudfiles
 	#	find $FILE |while read file; do
	#		put_files_to_container $file
	#	done		
	else
		echo -e "File $FILE \nnot accessible or it does not exist or it is not directory or regular file. Skiping"; 
		return 0
	fi

}
get_files_from_container(){
	#local FILE=$1
	local OBJ_PATH=''
	cd $CHANGE_DIR
	list_objects | while read OBJ_PATH; do
		#Split object path to FILE_NAME - short name of file. And DIR_PATH - path to file without global $DEST
		[[ -n $OBJ_PATH ]] && local FILE_NAME=`echo "$OBJ_PATH" | awk -F '/' '{print $NF}'`
		[[ -n $DEST ]] && local DIR_PATH=`echo "$OBJ_PATH" | sed -re "s%${DEST}%%" | sed -re "s%$FILE_NAME%%"`
		if [[ -n  $DIR_PATH ]]; then
			[[ ! $DEST =~ /$ ]]&&DIR_PATH="`echo $DEST | awk -F '/' '{print $NF}'`/${DIR_PATH}"
			DIR_PATH="`echo $DIR_PATH|sed -re "s%//+%/%;s%/$%%"`"
			[[ -d $DIR_PATH ]] || mkdir -p $DIR_PATH
		fi
		#Сoncatenate FILE_NAME and DIR_PATH, remove repeated // symbols
		local FILE_PATH=`echo "${DIR_PATH}/${FILE_NAME}" | sed -re "s%//+%/%;s%/$%%"`
		echo "Copy $FILE_NAME to ${PWD}/${FILE_PATH}"
		curl -X GET -s -H "X-Auth-Token:$X_AUTH_TOKEN" -o "${PWD}/$FILE_PATH" "${X_STORAGE_URL}/${CONTAINER}/${OBJ_PATH}" 
	done
}
get_object_info(){
	#echo "" > $TMP_FILE
	local object=$*;local obsize=''; local mtime=''
	local IFS=$'\012'
	#echo "$DEST"
	for header_l in $( curl -X HEAD -s -I -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL}/${CONTAINER}/$object" ); do
		[[ $header_l =~ Content-Length ]] && objsize=`echo $header_l | cut -d: -f 2|sed 's/^\s*//;s/\s*$//'`
		[[ $header_l =~ Last-Modified ]] && mtime=`echo $header_l | cut -d: -f 2-|sed 's/^\s*//;s/\s*$//'`
	done
	mtime=`date -d $mtime +%s`
	echo -e "${objsize}\t${mtime}"
}

parse_container(){
	#Parse container. The CONTAINER VAR may contain some path in cloud files.
	#For the most operations we need parse container to container name, and destination path 
	[[ $CONTAINER =~ ^[a-zA-Z0-9_\.-]+\/.* ]] && DEST=`echo $CONTAINER|cut -d'/' -f '2-'` || DEST=''
	CONTAINER=`echo $CONTAINER|cut -d'/' -f'1'`
	#echo $DEST
}

show_objects(){
        local IFS=$'\012'
	local object=''; local objinf=''
        for object in $( list_objects ); do
                if [[ -n $SHOW_INFO ]];then
			local objinf=`get_object_info $object`
			local objmtime=`echo $objinf | awk '{print $2}'`
			objmtime=`date -d "@$objmtime" "+%Y %b %d %T"`
			local objsize=`echo $objinf | awk '{printf "%.4f\n" ,$1/(1024*1024)}'`
			printf "$objsize\t$objmtime\t$object\n"
		else
			printf "$object\n"
        	fi
	done
}


#s -show containers, l <container> - list files in container, -d delete file, -r remove container, -c conatiner name 

while getopts "fsld:rec:ga:nC:hi" option; do
	case $option in
		f)OP_FORCE=1;;
		s)SHOW_CONTAINERS=1;;
		l)LIST=1;;
		d)DELETE_FILE=$OPTARG;;
		r)RM_CONTAINER=1;;
		e)ERASE_CONTAINER=1;;
		c)CONTAINER=$OPTARG;;
		g)GET_DATA=1;;
		a)APPEND_FILE="$OPTARG";;
		n)CREATE_CONTAINER=1;;
		C)CHANGE_DIR=$OPTARG;;
		h)usage;exit 0;;
		i)SHOW_INFO=1;;
		*)usage;;
	esac
done

if [[ -n $LIST && -z $CONTAINER ]]; then
	show_containers
fi
if [[ -n $LIST && -n $CONTAINER ]]; then
	parse_container
	#list_objects
	show_objects
fi
if [[ -n $DELETE_FILE && -n $CONTAINER && -z $LIST ]]; then
	delete_file "$DELETE_FILE"
fi
if [[ -n $RM_CONTAINER && -n $CONTAINER && -z $LIST ]]; then
	remove_container
fi
if [[ -n $CONTAINER && -n $APPEND_FILE && -z $LIST ]]; then
	parse_container
	put_files_to_container $APPEND_FILE
	#append_files_to_cloudfiles $APPEND_FILE
fi
if [[ -n $CONTAINER && -n $GET_DATA && -z $LIST ]]; then
	parse_container
	get_files_from_container
fi
if [[ -n $CONTAINER && -n $ERASE_CONTAINER && -z $LIST ]]; then
	parse_container
	cleanup_container
fi
if [[ -n $CONTAINER && -n $CREATE_CONTAINER && -z $LIST ]]; then
	parse_container
	create_container
fi
if [[ -n $CONTAINER && -n $SHOW_INFO && -z $LIST ]]; then
	parse_container
	get_container_info
	
fi

#REMOVE container
#curl -X DELETE -D - -H "X-Auth-Token:$X_AUTH_TOKEN" "${X_STORAGE_URL%\\r}/${RM_CONTAINER}"
#echo "---------------------------"
#echo "$X_AUTH_TOKEN"
#echo "$X_STORAGE_URL"

