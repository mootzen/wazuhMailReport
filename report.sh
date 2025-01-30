#!/bin/bash

# Define output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

# Define output file
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.log"

# Timestamp
echo "Daily Wazuh Report - $(date)" > "$REPORT_FILE"
echo "==========================================" >> "$REPORT_FILE"

# Disk Usage
echo -e "\nDisk Usage for /dev/mapper/ubuntu--vg-ubuntu--lv:" >> "$REPORT_FILE" # Change to drive you want to monitor 
echo -e "Filesystem\tSize\tUsed\tAvail\tUse%" >> "$REPORT_FILE"
df -h | grep "/dev/mapper/ubuntu--vg-ubuntu--lv" >> "$REPORT_FILE" # Change to drive you want to monitor 

# Swap Usage
echo -e "\nSwap Usage:" >> "$REPORT_FILE"
echo -e "Total\tUsed\tFree" >> "$REPORT_FILE"
free -h | grep "Swap" >> "$REPORT_FILE"

# Separator
echo -e "\n==========================================\n" >> "$REPORT_FILE"

# Generate Top Triggered Alerts (non-critical)
echo -e "Top 10 Wazuh Alerts (Non-Critical - Level < 12):" >> "$REPORT_FILE"
(echo -e "Count\tLevel\tRule_ID\tDescription"; \
jq -r 'select(.rule.level < 12) | "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"' /var/ossec/logs/alerts/alerts.json | sort | uniq -c | sort -nr | head -10) | column -s $'\t' -t >> "$REPORT_FILE"

# Separator
echo -e "\n==========================================\n" >> "$REPORT_FILE"

# Generate Top Emailed Alerts (Critical - Level >= 12)
echo -e "Top 10 Wazuh Alerts That Triggered Emails (Level ≥ 12):" >> "$REPORT_FILE"
(echo -e "Count\tLevel\tRule_ID\tDescription"; \
jq -r 'select(.rule.level >= 12) | "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"' /var/ossec/logs/alerts/alerts.json | sort | uniq -c | sort -nr | head -10) | column -s $'\t' -t >> "$REPORT_FILE"

# Send the combined report via email
MAIL_TO="admin@organisation.com"  # Change this to your email
echo -e "Subject: Daily Wazuh Report\nContent-Type: text/plain; charset=UTF-8\n\n$(cat "$REPORT_FILE")" | sendmail "$MAIL_TO"
