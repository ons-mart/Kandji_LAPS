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
adminaccount="<Admin account>"
initialpassword="<Initial admin password>"
passwordlength=12
specialchar="true" #add special characters in password. true or false.
renewdays=30 #standard password rotation after x days

#### MAIN CODE ####

### get device_id
serialnumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
deviceid=$(curl -sk GET "$URL/api/v1/devices?serial_number=$serialnumber" --header "Authorization: Bearer $APIkey" | grep -o '"device_id": *"[^"]*"' | awk -F '"' '{print$4}')

### verify local account exists
#get all local user accounts
jsonoutput=$(curl -sk GET "$URL/api/v1/devices/$deviceid/details" --header "Authorization: Bearer $APIkey")
index=$(plutil -extract "users"."regular_users" raw - <<< $jsonoutput)

localusers=()
for (( i=0 ; i<$index; i++)); do
	localusers+=($(plutil -extract "users"."regular_users".$i."username" raw - <<< $jsonoutput))
done

#verify if admin account exists on the device
if [[ ! " ${localusers[*]} " =~ " $adminaccount " ]]; then
	echo "Admin account \"$adminaccount\" does not exist"
	exit 1
fi

###get the current password and check if correct
#loop through device notes for encrypted details
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

#check if the encrypted details have been found, if not try the initial password
if [[ ! ${content} =~ ${regex} ]]; then
	#No encrypted details found
	OLDpassword="${initialpassword}"
else
	#Encrypted details found, decrypting password
	OLDpassword=$(echo "${OLDkey}" | openssl enc -aes-256-cbc -md sha512 -a -d -salt -pass pass:${OLDsecret})
fi

#Verify if the found password is correct
validpw="No"
validpw=$(dscl . -authonly ${adminaccount} ${OLDpassword})
if [[ $validpw != "" ]]; then
	echo "Authentication failed, current password could not be verified"
	exit 1
fi

### create new password
password="$(openssl rand -base64 32 | tr -d '/' | tr -d '\' | tr -d ' ' | cut -c -$passwordlength)"
chars='@#$%&_+=!?'
spchar=${chars:$((RANDOM % ${#chars})):1}

if $specialchar == true ; then
	finalpass="$(echo $password | cut -c 2-)$spchar"
else
	finalpass=$password
fi

# Random Secret used to Encrypt and Decrypt password
secret=$(openssl rand -base64 32 | cut -c -14 | tr -d \/ | tr -d //)

# Encrypt Random password and save to file
cryptkey=$(echo "$finalpass" | openssl enc -aes-256-cbc -md sha512 -a -salt -pass pass:$secret)

###Set new password
sysadminctl -adminUser ${adminaccount} -adminPassword ${OLDpassword} -resetPasswordFor ${adminaccount} -newPassword ${finalpass}

#verify new password has been set
validpw="No"
validpw=$(dscl . -authonly ${adminaccount} ${finalpass})
if [[ $validpw != "" ]]; then
	echo "Authentication failed, password not set correctly"
	exit 1
else
	echo "New password validated"
fi

#delete admin user Keychain (as this is inaccessible)
rm -rf /Users/${adminaccount}/Library/Keychains/*



###kandji housekeeping
#delete old note from Kandji
curl -sk -X DELETE "$URL/api/v1/devices/$deviceid/notes/${OLDnoteid}" --header "Authorization: Bearer $APIkey"

#get epoch time
epoch=$(date +%s)

#next renew time
epochoffset=$((${renewdays} * 86400))
renewepoch=$((${epoch} + ${epochoffset}))
renewhuman=$(date -r ${renewepoch} '+%d/%m/%Y')

#Report to Slack
curl -X POST -H 'Content-type: application/json' "${Slack}" --data '{
	"blocks": [
		{
			"type": "header",
			"text": {
				"type": "plain_text",
				"text": "Admin password rotated :closed_lock_with_key:",
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
					"text": ">*Next renewal:*\n>'"${renewhuman}"'"
				}
			]
		}
	]
}'

#post new pass and secret to Kandji
curl -sk -X POST "$URL/api/v1/devices/$deviceid/notes" --header "Authorization: Bearer $APIkey" --header 'Content-Type: application/json' --data-raw '{"content": "<p>key: '$cryptkey'<br>secret: '${secret}'<br>nr: '${renewepoch}'<\/p>"
}'

exit 0