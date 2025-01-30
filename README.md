# wazuhMailReport
Bash script that sends a daily report-mail to admins giving an overview over server and alert-statistics

> [!WARNING]
> Still under development, use with caution!

<br>


## Requirements

Running Wazuh instance and PostFix 

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
![report](https://github.com/user-attachments/assets/f04463d7-07a0-422b-8a2a-95c44640075a)
