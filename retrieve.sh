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
Slack="<Slack Webhook>"
Renewsec="3600"

#######################################

reply=$(dialog \
--bannerimage "/Library/Application Support/LAPS/KandjiLapsBanner.png" \
--title "none" \
--icon "/Library/Application Support/LAPS/lock icon.png" --iconsize 170 \
--message "Please enter the serial of the device you wish to see the Admin password for.\n Please specify the reason why this password is required." \
--messagefont "name=Arial,size=17" \
--button1text "Continue" \
--button2text "Quit" \
--textfield "Serial,required" \
--textfield "Reason,required" \
--ontop \
--json \
--moveable)
		
serial=$(echo ${reply} | awk -F '"Serial" : "' '{print$2}' | awk -F '"' '{print$1}')
reason=$(echo ${reply} | awk -F '"Reason" : "' '{print$2}' | awk -F '"' '{print$1}')

if [[ ${serial} == "" ]] || [[ ${reason} == "" ]]; then
	echo "Aborting"
	exit 1
fi


deviceid=$(curl -sk GET "$URL/api/v1/devices?serial_number=$serial" --header "Authorization: Bearer $APIkey" | grep -o '"device_id": *"[^"]*"' | awk -F '"' '{print$4}')

until [[ ${deviceid} != "" ]]; do
	reply=$(dialog \
	--bannerimage "/Library/Application Support/LAPS/KandjiLapsBanner.png" \
	--title "none" \
	--icon "/Library/Application Support/LAPS/lock icon.png" --iconsize 170 \
	--message "Please enter the serial of the device you wish to see the Admin password for.\n Please specify the reason why this password is required.\n \n **Serial not found, please try again.**" \
	--messagefont "name=Arial,size=17" \
	--button1text "Continue" \
	--button2text "Quit" \
	--textfield "Serial,required" \
	--textfield "Reason,required" \
	--ontop \
	--json \
	--moveable)
			
	serial=$(echo ${reply} | awk -F '"Serial" : "' '{print$2}' | awk -F '"' '{print$1}')
	reason=$(echo ${reply} | awk -F '"Reason" : "' '{print$2}' | awk -F '"' '{print$1}')
	
	if [[ ${serial} == "" ]] || [[ ${reason} == "" ]]; then
		echo "Aborting"
		exit 1
	fi
		
	deviceid=$(curl -sk GET "$URL/api/v1/devices?serial_number=${serial}" --header "Authorization: Bearer $APIkey" | grep -o '"device_id": *"[^"]*"' | awk -F '"' '{print$4}')
done

#get notes for the requested device
jsonoutput=$(curl -sk GET "$URL/api/v1/devices/$deviceid/notes" --header "Authorization: Bearer $APIkey")
index=$(plutil -extract "notes" raw - <<< $jsonoutput)

for ((i=0; i<$index; i++)); do
	content=$(plutil -extract "notes".$i."content" raw - <<< $jsonoutput)
	OLDnoteid=$(plutil -extract "notes".$i."note_id" raw - <<< $jsonoutput)
	regex='^<p>key:.*<br>secret:.*<br>nr:.*</p>$'
	if [[ $content =~  ${regex} ]]; then
		OLDkey=$(echo $content | awk -F '<p>key: ' '{print$2}' | awk -F '<br>' '{print$1}')
		OLDsecret=$(echo $content | awk -F '<br>secret: ' '{print$2}' | awk -F '<' '{print$1}')
		break
	fi
done
		
#Slack Notification
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
curl -X POST -H 'Content-type: application/json' "${Slack}" --data '{
	"blocks": [
		{
			"type": "header",
			"text": {
				"type": "plain_text",
				"text": "Admin password requested :closed_lock_with_key:",
				"emoji": true
			}
		},
		{
			"type": "divider"
		},
		{
			"type": "section",
			"fields": [
				{
					"type": "mrkdwn",
					"text": ">*Serial:*\n>'"${serial}"'"
				},
				{
					"type": "mrkdwn",
					"text": ">*Requested by:*\n>'"${loggedInUser}"'"
				},
				{
					"type": "mrkdwn",
					"text": ">*Reason for Request:*\n>'"$reason"'"
				},
			]
		}
	]
}'

#Decrypt old password
passwd=$(echo ${OLDkey} | openssl enc -aes-256-cbc -md sha512 -a -d -salt -pass pass:${OLDsecret})

###kandji housekeeping
#delete old note from Kandji
curl -sk -X DELETE "$URL/api/v1/devices/$deviceid/notes/${OLDnoteid}" --header "Authorization: Bearer $APIkey"

#get epoch time
epoch=$(date +%s)

#next renew time
renewepoch=$((${epoch} + ${Renewsec} ))

#post new epoch
curl -sk -X POST "$URL/api/v1/devices/$deviceid/notes" --header "Authorization: Bearer $APIkey" --header 'Content-Type: application/json' --data-raw '{"content": "<p>key: '${OLDkey}'<br>secret: '${OLDsecret}'<br>nr: '${renewepoch}'<\/p>"
}'

Renewmin=$(($Renewsec/60))

dialog \
--bannerimage "/Library/Application Support/LAPS/KandjiLapsBanner.png" \
--title "none" \
--icon "/Library/Application Support/LAPS/Open Lock Icon.png" --iconsize 170 \
--message "The admin Password for ${serial} is ${passwd} \n\n This request has been logged and the password will be reset after ${Renewmin} minutes." \
--messagefont "name=Arial,size=17" \
--button1text "Close" \
--ontop \
--timer 30 \
--moveable
		
exit 0