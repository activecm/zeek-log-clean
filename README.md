# Zeek Log Clean

This script will delete the oldest Zeek log files until disk usage is under a given threshold (default 90% used).

## Running

Place the script in your path (e.g. `/usr/local/bin/zeek_log_clean.sh`).
```bash
sudo curl -o /usr/local/bin/zeek_log_clean.sh https://raw.githubusercontent.com/activecm/zeek-log-clean/main/zeek_log_clean.sh && sudo chmod +x /usr/local/bin/zeek_log_clean.sh
```

The recommended use is to automate running of the script with cron. The following command will configure this.
```bash
echo "* * * * * root flock -n /tmp/zeek-log-clean /usr/local/bin/zeek_log_clean.sh" | sudo tee /etc/cron.d/zeek-log-clean
```

You can run the script ad hoc.
```bash
zeek_log_clean.sh
```

The script will attempt to find the correct location of your zeek log files automatically. You can also pass in the location. 
```bash
zeek_log_clean.sh --dir /opt/zeek/logs
```

The script will delete files until the disk usage is under 90% by default. You can set a different threshold.
```bash
zeek_log_clean.sh --threshold 80
```

If `rita` is available, the script will also attempt to delete the corresponding [RITA](https://github.com/activecm/rita) dataset. You can disable this behavior. 
```bash
zeek_log_clean.sh --no-remove-rita
```

## Testing

Clone the repo and run the included `test.sh` script inside a VM. The user you run the script as must have `sudo` privileges.

<!--
(Note: I explored running tests in docker but the test mechanism relies on mounting an image, which isn't practical to do in a continainer.)
-->
