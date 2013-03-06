#!/bin/sh

################################################################################
#
# transfer.sh
#
# Script is intended to be run via cron (thru cygwin or native *nix), which
# attempts to upload the file via HTTP POST (please note that this is done
# via curl @file.txt -- literally stream it via x-www-form-urlencoded; and not
# via multipart/form-data.
#
# Usage: 
#
#   transfer.sh -dir <watch directory> \
#		-retry <retry count> \
#		-uri <http endpoint> \
#		-purge <min days before purging> \
#		[-prefix <log filename prefix>]
#
#   transfer.sh -dir /var/log/service/ -retry 5 \
#			 -uri http://host/log.cgi -purge 5 -prefix db
#
################################################################################

BASEDIR=`dirname $0`

PID_FILE="${BASEDIR}/.pid"
LAST_RUN="${BASEDIR}/.lastrun"

if [[ -f $PID_FILE ]]; then
	EXISTING_PID=`cat $PID_FILE`
	echo "Process [${EXISTING_PID}] already running. Exiting."
	exit -1
fi

################################################################################
###                     DO NOT MODIFY BELOW THESE LINE                       ###
################################################################################

USAGE="Usage: $0 -dir <watch_dir> -retry <retry_count> -uri <server_uri> -purge <min_days_before_purge> [-prefix <filename_prefix>]"

DEBUG=0

while test -n "$1"; do
	case "$1" in
		-d)
			DEBUG=1
			shift
			;;
		-dir)
			WATCH_FOLDER=$2
			shift
			;;
		-retry)
			MAX_RETRY=$2
			shift
			;;
		-uri)
			SERVER_URI=$2
			shift
			;;
		-purge)
			MIN_DAYS_BEFORE_PURGE=$2
			shift
			;;
		-prefix)
			FILENAME_PREFIX=$2
			shift
			;;
		*)
			echo "Unknown argument: $1"
			echo $USAGE;
			;;
	esac
	shift
done

################################################################################
### Functions
################################################################################

DATE_FORMAT='+%Y-%m-%d %H:%M:%S'

################################################################################
### Log an ERROR message
################################################################################
function ERROR {
	printf "[`date "$DATE_FORMAT"`] [ERROR] $1\n"
}

################################################################################
### Log a DEBUG message
################################################################################
function DEBUG {
	if [[ ${DEBUG} -eq 1 ]]; then
		printf "[`date "$DATE_FORMAT"`] [DEBUG] $1\n"
	fi
}

################################################################################
### Log an INFO message
################################################################################
function INFO {
	printf "[`date "$DATE_FORMAT"`] [INFO] $1\n"
}

################################################################################
### Check argument if it exists
################################################################################
function CHECK_ARGS {
        if [[ -z $1 ]]; then
                echo $USAGE
                exit
        fi
}

################################################################################
### Upload the file and return the HTTP response code
### arg[1]: File URI to Upload
################################################################################
function SEND_FILE {
	FILE_URI="${1}"
	RESULT=`curl ${SERVER_URI} --header "Expect:" --data-binary "@${FILE_URI}" --silent -w "%{http_code} %{time_total} %{size_upload} %{speed_upload}" -o /dev/null`
	INFO $RESULT
	INFO "`printf "File: [%s]; HTTP Response: [%s]; Total Time: [%s]; Size Uploaded: [%s]; Speed Upload: [%s];\n" "${FILE_URI}" ${RESULT}`"
	RESPONSE_CODE=`echo "${RESULT}" | awk -F ' ' '{ print $1 }'`
}

################################################################################
### Handle failed transmission
### arg[1]: Retry Attempt Count
### arg[2]: File URI to Upload
################################################################################
function HANDLE_FAILED_TRANSMISSION {
	RETRY_ATTEMPT="${1}"
	FILE_URI="${2}"

	if [[ ${MAX_RETRY} -lt 1 ]]; then
		ERROR "File: [${FILE_URI}] - Retry is disabled; moving the file to the failed folder."
		mv "${FILE_URI}" "${FAILED_FOLDER}"
	elif [[ ${RETRY_ATTEMPT} -lt ${MAX_RETRY} ]]; then
		NEXT_RETRY_ATTEMPT=`expr ${RETRY_ATTEMPT} + 1`
		NEXT_RETRY_BUCKET="${RETRY_FOLDER}/${NEXT_RETRY_ATTEMPT}"
		ERROR "File: [${FILE_URI}] - Retry #${RETRY_ATTEMPT} failed, moving to the next retry bucket [${NEXT_RETRY_BUCKET}]."
		mv "${FILE_URI}" "${NEXT_RETRY_BUCKET}"
	else
		ERROR "File: [${FILE_URI}] - Retry attempt count has reached limit, moving to failed folder."
		mv "${FILE_URI}" "${FAILED_FOLDER}"
	fi
}

################################################################################
### Process all the files in this directory for upload
### arg[1]: Retry Attempt Count
### arg[2]: Folder to process
################################################################################
function PROCESS_DIRECTORY {
	RETRY_ATTEMPT="${1}"
	FOLDER_URI="${2}"

	DEBUG "Processing directory ${FOLDER_URI}"
	find "${FOLDER_URI}" -maxdepth 1 ${FIND_OPTION} -type f | while read FILE
	do
		DEBUG "Processing file ${FILE}"
		SEND_FILE "${FILE}"
		if [[ ${RESPONSE_CODE} == "200" ]]; then
			INFO "Successfully transmitted ${FILE}; moving to success folder"	

			# Touch the file so we can purge it after x time
			touch "${FILE}"

			mv "${FILE}" "${SUCCESS_FOLDER}"
		else
			HANDLE_FAILED_TRANSMISSION "${RETRY_ATTEMPT}" "${FILE}"
		fi
	done
}

################################################################################
### Check Arguments
################################################################################

CHECK_ARGS "${WATCH_FOLDER}"
CHECK_ARGS "${MAX_RETRY}"
CHECK_ARGS "${SERVER_URI}"
CHECK_ARGS "${MIN_DAYS_BEFORE_PURGE}"

SUCCESS_FOLDER="${WATCH_FOLDER}/Success"
FAILED_FOLDER="${WATCH_FOLDER}/Failed"
RETRY_FOLDER="${WATCH_FOLDER}/Retry"

if [[ ${FILENAME_PREFIX} != "" ]]; then
	FIND_OPTION="-name ${FILENAME_PREFIX}*"
else
	FIND_OPTION=""
fi


################################################################################
###                             START PROGRAM                                ###
################################################################################

INFO "Script started"

################################################################################
### Step 1: Initialization
################################################################################

# [A] Lock with the PID
echo $$ > $PID_FILE

# [B] Verify retry subfolders exists
for (( i=1; i<=${MAX_RETRY}; i++ )); do
	RETRY_SUBFOLDER="${RETRY_FOLDER}/${i}"
	if [ ! -d "${RETRY_SUBFOLDER}" ]; then
		INFO "Creating retry subfolder ${RETRY_SUBFOLDER}"
		mkdir -p "${RETRY_SUBFOLDER}"
	fi
done

# [C] Verify success/failed folder exists
mkdir -p "${SUCCESS_FOLDER}"
mkdir -p "${FAILED_FOLDER}"


################################################################################
### Step 2: Find files to process
################################################################################

# [A] Loop thru retry folders
for (( i=${MAX_RETRY}; i>=1; i-- )); do
	RETRY_SUBFOLDER="${RETRY_FOLDER}/${i}"
	PROCESS_DIRECTORY ${i} "${RETRY_SUBFOLDER}"
done

# [B] Loop thru watch folder
PROCESS_DIRECTORY 0 "${WATCH_FOLDER}"

################################################################################
### Step 3: Clean up the Success Folder
################################################################################

for FILE in `find "${SUCCESS_FOLDER}" -type f -mtime +${MIN_DAYS_BEFORE_PURGE}`; do
	INFO "Purging file ${FILE}"
	rm "${FILE}"
done

################################################################################
### Clean Up
################################################################################

touch $LAST_RUN
rm $PID_FILE

INFO "Script stopped"
