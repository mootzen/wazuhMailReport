# wazuhMailReport
Bash script that sends a daily report email to admins, providing an overview of server and alert statistics.

> **⚠️ WARNING:** Still under development, use with caution!

## 🚀 Features
- 📊 Extracts alerts from Wazuh logs (`alerts.json`)
- 🚨 Filters alerts by severity level (configurable)
- 💾 Includes system information (disk & swap usage)
- 📩 Sends an HTML-formatted report via email
- 🔄 Retries failed log reads to handle permission issues
- 🛠️ Easy installation via an installer script

---

## 📌 Requirements
- Running Wazuh instance (not tested in Docker)
- `jq` and `mailutils`
- A working mail server (e.g., Postfix)

---

## 📥 Installation
### **Run the installer**
```bash
wget https://raw.githubusercontent.com/mootzen/wazuhMailReport/main/install.sh
bash install.sh
```
The installer will:

    Install necessary dependencies (jq, mailutils)
    Clone the repository to /usr/local/wazuhMailReport
    Set up a cron job to run the report daily at midnight
    Ensure correct file permissions

You're right to call that out! The issue was an unclosed code block. Here's the properly formatted README:

# wazuhMailReport
Bash script that sends a daily report email to admins, providing an overview of server and alert statistics.

> **⚠️ WARNING:** Still under development, use with caution!

## 🚀 Features
- 📊 Extracts alerts from Wazuh logs (`alerts.json`)
- 🚨 Filters alerts by severity level (configurable)
- 💾 Includes system information (disk & swap usage)
- 📩 Sends an HTML-formatted report via email
- 🔄 Retries failed log reads to handle permission issues
- 🛠️ Easy installation via an installer script

---

## 📌 Requirements
- Running Wazuh instance (not tested in Docker)
- `jq` and `mailutils`
- A working mail server (e.g., Postfix)

---

## 📥 Installation
### **Run the installer**
```bash
wget https://raw.githubusercontent.com/mootzen/wazuhMailReport/main/install.sh
bash install.sh

The installer will:

    Install necessary dependencies (jq, mailutils)
    Clone the repository to /usr/local/wazuhMailReport
    Set up a cron job to run the report daily at midnight
    Ensure correct file permissions

⚙️ Configuration

To customize the script, modify the variables at the top of wazuh_alert_report.sh:

MAIL_TO="your@mail.com"   # Change to recipient email
MAIL_FROM="reporter@wazuh"
LEVEL=12                  # Minimum severity level for critical alerts
TIME_PERIOD="24 hours"     # Time range for logs
TOP_ALERTS_COUNT=10        # Number of top alerts to display
## Example-Mail
![report](https://github.com/user-attachments/assets/0bf8bb90-70d8-4445-b189-508042c3323d)
