#!/bin/bash

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -k=*|--api_key=*) AUTH_KEY="${1#*=}" ;;
    -i=*|--app_id=*) APP_ID="${1#*=}" ;;
    -c=*|--client=*) CLIENT="${1#*=}";;
    -e=*|--erp=*) ERP="${1#*=}"  ;;
    -s=*|--segment=*) SEGMENT="${1#*=}" ;;
    -p=*|--hosting_provider=*) HOSTING_PROVIDER="${1#*=}" ;;
    -o=*|--organization=*) ONESIGNAL_ORGANIZATION="${1#*=}" ;;
    -l=*|--licence=*) ONESIGNAL_LICENCE="${1#*=}" ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done
export CLIENT=$CLIENT
DATE=$(date +"%Y-%m-%d")
TMP_FILE=/data/tmp/grafana_onesignal_$CLIENT.tmp
TMP_FILE_DEVICES_CSV=/data/tmp/grafana_onesignal_subscribed_devices_all-time_$DATE_$CLIENT
DAY_START_TIMESTAMP=$(date -d "today 0" +%s)

if [ -z $SEGMENT ]
then
  SEGMENT=$(echo \"Subscribed Users\")
else
  SEGMENT=$(echo \"$SEGMENT\")
fi

if [ -z $HOSTING_PROVIDER ]
then
  HOSTING_PROVIDER="client"
fi

if [ -z $ONESIGNAL_ORGANIZATION ]
then
  ONESIGNAL_ORGANIZATION="none"
fi

if [ -z $ONESIGNAL_LICENCE ]
then
  ONESIGNAL_LICENCE="free"
fi



csv_export_subscribed_devices() {
#echo -e "Generate CSV Export ..."
CSV_FILE=$(/usr/bin/curl -s -H "Authorization: Basic $AUTH_KEY" -H "Content-Type: application/json" \
-d '{ "extra_fields": ["country","notification_types"], "segment_name": '"$SEGMENT"'  }' \
"https://onesignal.com/api/v1/players/csv_export?app_id=$APP_ID" \
| jq -r '.csv_file_url')

## Test if CSV file available because onesignal will provide a csv download url after sending previous command
/usr/bin/curl -s -I $CSV_FILE | grep "200 OK" 
## Update Status return code
STATUS=$?

## Init Loop counter
LOOP=0
while [ $STATUS -gt 0 ]
do
 ## Increment Loop counter
 let LOOP++
 ## Wait 2 seconds
 sleep 2
 ## Test if CSV file available
 curl -s -I $CSV_FILE | grep "200 OK" >/dev/null
 ## Update Status return code
 STATUS=$?
## Exit loop if CSV file available
done
## Download CSV file if available
#echo -e "Download $CSV_FILE ..."
/usr/bin/curl -s $CSV_FILE --output $TMP_FILE_DEVICES_CSV.csv.gz
}


gunzip_file() { 
if [ -z $1 ] 
  then
    echo "Missing argument date "
    exit 100;
fi
if [ -z $2 ]
  then
    echo "Missing argument date "
    exit 101;
fi

CSV_FILE=${1%.*}
#echo "Décompression fichier: $1 dans $CSV_FILE pour metrique: $2"
gunzip -c $1 > $CSV_FILE

}


extract_csv_metrics() {
CSV_FILE=${1%.*}
TOTAL_DEVICES=$(sed -n '1d;p' $CSV_FILE | wc -l)
TOTAL_DEVICES_ACTIVATED_IN_AML=$(sed -n '1d;p' $CSV_FILE | sed -s "s/,/ /g" | grep ""All"" | wc -l )
TOTAL_DEVICES_IOS=$(sed -n '1d;p' $CSV_FILE | sed -s "s/,/ /g" | awk '{print $8}' | grep 0 | wc -l)
TOTAL_DEVICES_IOS_ACTIVATED_IN_AML=$(sed -n '1d;p' $CSV_FILE | grep ""All"" | sed -s "s/,/ /g" | awk '{print $8}' | grep 0 | wc -l)
TOTAL_DEVICES_ANDROID=$(sed -n '1d;p' $CSV_FILE | sed -s "s/,/ /g" | awk '{print $8}' | grep 1 |wc -l)
TOTAL_DEVICES_ANDROID_ACTIVATED_IN_AML=$(sed -n '1d;p' $CSV_FILE | grep ""All"" | sed -s "s/,/ /g" | awk '{print $8}' | grep 1 | wc -l)
TOTAL_PROFILS_MORE_10_TAGS=$(sed -n '1d;p' $CSV_FILE |  grep ""All""  | sed 's/^.*\({.*}\).*$/\1/' | awk -F' ' '{print NF}' | sort -n | awk -F: '{if($1>20)print$1}' | wc -l)
## Extract devices par ORG_ID
while read COUNT ORG_ID
do
>$TMP_FILE
echo $ORG_ID $COUNT | sed -e "s/ /=/g" >> $TMP_FILE
done <<< $(sed -n '1d;p' $CSV_FILE | grep [0-9]*ORG | grep -o '""All"": ""true"",.*' | awk '{print $3}' | sed -e 's/"//g' | sed -e 's/://g' | sort | uniq -c)
NUM_ORG=$(cat $TMP_FILE | grep -o "ORG\|PAT" | wc -l)
i="2"
TOTAL_DEVICES_BY_ORG_ID=$(cat $TMP_FILE | sed -e "s/=/,/$i")
while [ $i -lt $NUM_ORG ]
do
  i=$(( $i + 1))
  TOTAL_DEVICES_BY_ORG_ID=$(echo $TOTAL_DEVICES_BY_ORG_ID |  sed -e "s/=/,/$i")
done

echo "$2,client=$CLIENT,erp=$ERP,hosting_provider=$HOSTING_PROVIDER,organization=$ONESIGNAL_ORGANIZATION,licence=$ONESIGNAL_LICENCE $TOTAL_DEVICES_BY_ORG_ID,total_devices=$TOTAL_DEVICES,total_devices_ios=$TOTAL_DEVICES_IOS,total_devices_android=$TOTAL_DEVICES_ANDROID,total_devices_activated_aml=$TOTAL_DEVICES_ACTIVATED_IN_AML,total_devices_ios_activated_aml=$TOTAL_DEVICES_IOS_ACTIVATED_IN_AML,total_devices_android_activated_aml=$TOTAL_DEVICES_ANDROID_ACTIVATED_IN_AML,total_profil_more_10_tags=$TOTAL_PROFILS_MORE_10_TAGS" 
}

csv_export_subscribed_devices
gunzip_file $TMP_FILE_DEVICES_CSV.csv.gz suscribed_users
extract_csv_metrics $TMP_FILE_DEVICES_CSV.csv.gz suscribed_users
