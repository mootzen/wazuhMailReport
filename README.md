# wazuhMailReport
Bash script that sends a daily report-mail to admins giving an overwiev over server and alert-statistics

## Install:
### Create new file as sudo: 
```bash
sudo nano /usr/local/bin/report.sh
```
### Adust script

Paste script contents and modify target mail-address and adust rule-level triggers

### make the script executable
```bash
chmod +x /usr/local/bin/report.sh
```
### add cronjob
```bash
crontab -e
```
run daily at 10am
```
0 10 * * * /usr/local/bin/report.sh
```
### Test Mail 
by calling script manually
```bash
/bin/bash /usr/local/bin/report.sh
```
## Example-Mail
