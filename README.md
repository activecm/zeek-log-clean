# Zeek Log Clean

This script will delete Zeek log files until disk usage is under a given threshold (default 90% used).

## Running

Recommended use: put the following in `/etc/cron.d/zeek-log-clean`

```cron
* * * * * root flock /tmp/zeek-log-clean /usr/local/bin/zeek_log_clean.sh
```

## Testing

Clone the repo and run the included `test.sh` script inside a VM. You must have `sudo` privileges to run the script.

(Note: I explored running tests in docker but the test mechanism relies on mounting an image, which isn't practical to do in a continainer.)