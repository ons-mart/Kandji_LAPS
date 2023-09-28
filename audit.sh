#!/bin/bash

#
# Author  : Martijn Gregoire
# Created : 27/9/2023
# Updated : 17/9/2023
# Version : v0.1
#
#########################################################################################
# Description:
#	This script is part of the LAPS for Kandji solution. 
#
#########################################################################################
# Copyright © 2023 Martijn Gregoire
#
# This file is free software and is shared "as is" without any warranty of 
# any kind. The author gives unlimited permission to copy and/or distribute 
# it, with or without modifications, as long as this notice is preserved. 
# All usage is at your own risk and in no event shall the authors or 
# copyright holders be liable for any claim, damages or other liability.
#########################################################################################

APIkey="<KANDJI API Key>"
URL="<KANDJI API URL>"

### get device_id
serialnumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
deviceid=$(curl -sk GET "$URL/api/v1/devices?serial_number=$serialnumber" --header "Authorization: Bearer $APIkey" | grep -o '"device_id": *"[^"]*"' | awk -F '"' '{print$4}')

#loop through device notes for encrypted details
jsonoutput=$(curl -sk GET "$URL/api/v1/devices/$deviceid/notes" --header "Authorization: Bearer $APIkey")
index=$(plutil -extract "notes" raw - <<< $jsonoutput)

if [[ ${index} == 0 ]]; then
	echo "No notes found"
	exit 1
fi

for ((i=0; i<$index; i++)); do
	content=$(plutil -extract "notes".$i."content" raw - <<< $jsonoutput)
	regex='^<p>key:.*<br>secret:.*<br>nr:.*</p>$'
	if [[ $content =~  ${regex} ]]; then
		renewepoch=$(echo $content | awk -F '<br>nr: ' '{print$2}' | awk -F '-' '{print$1}')
		break
	fi
done

#check if epoch is found and coreetly formatted
epochregex='^[0-9]{10}$'
if [[ ! ${renewepoch} =~ ${epochregex} ]]; then
	echo "Incorrect epoch"
	exit 1
fi

#get current epoch
current=$(date +%s)

#check if renew epoch is in the future
if [[ ${current} > ${renewepoch} ]]; then
	echo "admin password needs to be renewed"
	exit 1
fi

exit 0