#!/bin/bash

# original version from:
# https://github.com/Security-Onion-Solutions/securityonion/blob/d570b56c55d024cbe1c3c875db6c3cd4ef1268e2/salt/common/tools/sbin/so-sensor-clean

# Delete Zeek Logs based on defined CRIT_DISK_USAGE value
# Recommended use: put the following in /etc/cron.d/hunt-clean-logs
# * * * * * root flock /tmp/hunt-clean-logs /usr/local/bin/hunt_clean_logs.sh

DEBUG=

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

# TODO: take cli arguments and print help instead of using env variables

# Which directory holds the zeek logs?
if [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then      # LOG_DIR already set
    :
elif [ -d /opt/zeek/remotelogs/ ]; then              # AC-Hunter
    LOG_DIR='/opt/zeek/remotelogs/'
elif [ -d /opt/zeek/logs/ ]; then                    # Zeek as installed by Rita
    LOG_DIR='/opt/zeek/logs/'
elif [ -d /usr/local/zeek/logs/ ]; then              # Zeek package default
    LOG_DIR='/usr/local/zeek/logs/'
elif [ -d /nsm/zeek/logs/ ]; then                    # Security Onion
    LOG_DIR='/nsm/zeek/logs/'
else
    fail "Unable to locate Zeek log directory."
fi

# TODO: remove old docker images
#ai-hunter/web            latest          d9ad77fa3029   10 months ago   355MB
#ai-hunter/auth           latest          aff4ffac83f3   10 months ago   337MB
#ai-hunter/mongo_client   latest          57d8a47e91e6   10 months ago   439MB
#ai-hunter/api            latest          6745a867ece9   10 months ago   174MB
# untagged ethack/tht containers

clean() {
    local log_dir="$1"
    # find the oldest Zeek logs directory, excluding today
    # must match the date regex (e.g. 2022-03-04)
    # pull out the date from the path
    local today=$(date -u "+%Y-%m-%d")
    local oldest_date=$(\
        find "$log_dir" -type d -regextype egrep -regex '^.*/20[0-9][0-9]-[01][0-9]-[0123][0-9]$' ! -name "$today" 2>/dev/null \
        | rev | cut -d/ -f1 | rev \
        | sort | head -n 1)
    [ -n $DEBUG ] && debug
    if [ -z "$oldest_date" ]; then
        fail "No old Zeek logs available to clean up in $log_dir"
    fi

    status "Removing logs from: $oldest_date"
    # remove all directories matching that date in log_dir (in all sensors on AC-Hunter)
    find "$log_dir" -type d -name "$oldest_date" -exec $DEBUG rm -rf "{}" \; 2>/dev/null
    # remove the corresponding dataset in rita
    [ -x /usr/local/bin/rita ] && $DEBUG /usr/local/bin/rita delete -f -m "$oldest_date"
}

current_usage() {
    df -P "$1" | tail -1 | awk '{print $5}' | tr -d %
}

CRIT_DISK_USAGE=${CRIT_DISK_USAGE:-90}
[ -n $DEBUG ] && debug
iteration=0
while [ $(current_usage "$LOG_DIR") -gt $CRIT_DISK_USAGE ]; do
    clean "$LOG_DIR"

    # prevent infinite loop
    iteration=$((iteration+1))
    if [ $iteration -eq 10 ]; then
        fail "Could not bring disk below usage threshold of $CRIT_DISK_USAGE%"
    fi
done

