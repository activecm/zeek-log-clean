#!/bin/bash

# original version from:
# https://github.com/Security-Onion-Solutions/securityonion/blob/d570b56c55d024cbe1c3c875db6c3cd4ef1268e2/salt/common/tools/sbin/so-sensor-clean

# Delete Zeek Logs based on defined CRIT_DISK_USAGE value
# Recommended use: put the following in /etc/cron.d/hunt-clean-logs
# * * * * * root flock /tmp/hunt-clean-logs /usr/local/bin/hunt_clean_logs.sh

fail() {
    echo "$(date --iso-8601=seconds --utc) - $@" >&2
    exit 1
}

status() {
    echo "==== $@"
}

debug() {
    cat << EOF
    LOG_DIR: $LOG_DIR
    current_usage: $(current_usage "$LOG_DIR")
    CRIT_DISK_USAGE: $CRIT_DISK_USAGE
    OLDEST_DATE: $OLDEST_DATE
EOF
}


print_usage() {
    cat <<EOF
$0 will delete files and directories from the Zeek log directory until the disk 
utilization is under a threshold. It will also remove the corresponding RITA
databases.

Usage: $0 [--dir <log directory>] [--threshold <disk usage percent>] [--no-remove-rita]

Options:
    --dir <log dir>       Specifies the directory for Zeek logs. (Default: checks common locations)
    --threshold <1-100>   This script will remove files until disk usage is below the threshold. (Default: 90)
    --no-remove-rita      Specify this flag to disable deleting the corresponding RITA databases.
EOF
}

CRIT_DISK_USAGE=90
REMOVE_RITA_DB=true
LOG_DIR=
# Find default Zeek log directory
if [[ -d /opt/zeek/remotelogs/ ]]; then                # AC-Hunter
    LOG_DIR='/opt/zeek/remotelogs/'
elif [[ -d /opt/zeek/logs/ ]]; then                    # Zeek as installed by Rita
    LOG_DIR='/opt/zeek/logs/'
elif [[ -d /usr/local/zeek/logs/ ]]; then              # Zeek package default
    LOG_DIR='/usr/local/zeek/logs/'
elif [[ -d /nsm/zeek/logs/ ]]; then                    # Security Onion
    LOG_DIR='/nsm/zeek/logs/'
fi

# Parse through command args to override values
while [[ $# -gt 0 ]]; do
    case $1 in
    -h|--help)
        print_usage
        exit 0
        ;;
    --no-remove-rita)
        REMOVE_RITA_DB=false
        ;;
    --dir)
        shift
        LOG_DIR="$1"
        ;;
    --threshold)
        shift
        CRIT_DISK_USAGE=$(echo "$1" | tr -d %)
        ;;
    *)
        ;;
    esac
    shift
done

if [[ -z $LOG_DIR ]]; then
    fail "Unable to locate Zeek log directory."
elif [[ ! -d $LOG_DIR ]]; then
    fail "Specified Zeek log directory does not exist: $LOG_DIR"
fi

clean() {
    local log_dir="$1"
    # find the oldest Zeek logs directory, excluding today
    # must match the date regex (e.g. 2022-03-04)
    # pull out the date from the path
    local today=$(date -u "+%Y-%m-%d")
    local oldest_date=$(\
        find "$log_dir" \
            -type d \
            -regextype egrep \
            -regex '^.*/20[0-9][0-9]-[01][0-9]-[0123][0-9]$' \
            ! -name "$today" \
            2>/dev/null \
        | rev | cut -d/ -f1 | rev \
        | sort | head -n 1)

    if [ -z "$oldest_date" ]; then
        fail "No old Zeek logs available to clean up in $log_dir"
    fi

    status "Removing logs from: $oldest_date"
    # remove all directories matching that date in log_dir (in all sensors on AC-Hunter)
    find "$log_dir" -type d -name "$oldest_date" -exec rm -rf "{}" \; 2>/dev/null
    # remove the corresponding dataset in rita
    if $REMOVE_RITA_DB && [ -x /usr/local/bin/rita ]; then
        /usr/local/bin/rita delete -f -m "$oldest_date"
    fi
}

current_usage() {
    df -P "$1" | tail -1 | awk '{print $5}' | tr -d %
}

iteration=0
while [ $(current_usage "$LOG_DIR") -gt $CRIT_DISK_USAGE ]; do
    clean "$LOG_DIR"

    # prevent infinite loop
    iteration=$((iteration+1))
    if [ $iteration -eq 10 ]; then
        fail "Could not bring disk below usage threshold of $CRIT_DISK_USAGE%"
    fi
done

status "Finished cleaning logs."
