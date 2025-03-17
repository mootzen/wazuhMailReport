#!/bin/bash

echo "[$$] Starting Wazuh Alert Report"
ascii_art="
                          _     __  __       _ _ ____                       _
 __      ____ _ _____   _| |__ |  \/  | __ _(_) |  _ \ ___ _ __   ___  _ __| |_
 \ \ /\ / / _\ |_  / | | | '_ \| |\/| |/ _\ | | | |_) / _ \ '_ \ / _ \| '__| __|
  \ V  V / (_| |/ /| |_| | | | | |  | | (_| | | |  _ <  __/ |_) | (_) | |  | |_
   \_/\_/ \__,_/___|\__,_|_| |_|_|  |_|\__,_|_|_|_| \_\___| .__/ \___/|_|   \__|
                                                          |_|
    by mootzen 2025
"
VERSION="0.1"
echo -e "$ascii_art"

# Prevent multiple instances
exec 200>/tmp/wazuh_report.lock
flock -n 200 || { echo "[$$] Another instance is running. Exiting."; exit 1; }

echo "[$$] Deleting existing tmp files..."
rm -f /tmp/alerts_combined.json /tmp/alerts_combined_final.json

echo "[$$] Current working directory: $(pwd)"

# Load config file
CONFIG_FILE="/usr/local/wazuhMailReport/report.conf"
echo "[$$] Checking for config file at: $CONFIG_FILE"

if [[ -f "$CONFIG_FILE" ]]; then
    echo "[$$] Config file found and sourced successfully."
    source "$CONFIG_FILE"
else
    echo "[$$] Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

echo "[$$] Memory usage after loading config:"
free -h

# Set time period
START_TIME=$(date --utc --date="24 hours ago" +%Y-%m-%dT%H:%M:%SZ)

# Output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

# Output file
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.html"

# Determine yesterday’s log filename
YESTERDAY=$(date --date="yesterday" +%d)
LOG_DIR="/var/ossec/logs/alerts/$(date +%Y/%b)"
PREV_LOG="$LOG_DIR/ossec-alerts-$YESTERDAY.json"
PREV_LOG_GZ="$PREV_LOG.gz"

echo "[$$] Debug: Searching for logs in $LOG_DIR"

# Use a normal file instead of a named pipe
touch /tmp/alerts_combined.json
echo "[$$] Extracting and merging logs using jq streaming..."

# Extract and merge logs
if [[ -f "$PREV_LOG_GZ" ]]; then
    echo "[$$] Extracting previous day's alerts from $PREV_LOG_GZ"
    gunzip -c "$PREV_LOG_GZ" | jq -c '. |= select(.timestamp >= "'$START_TIME'")' 2>> /tmp/jq_errors.log > /tmp/alerts_combined.json
elif [[ -f "$PREV_LOG" ]]; then
    echo "[$$] Using uncompressed previous day's alerts from $PREV_LOG"
    jq -c '. |= select(.timestamp >= "'$START_TIME'")' "$PREV_LOG" 2>> /tmp/jq_errors.log > /tmp/alerts_combined.json
else
    echo "[$$] No previous alerts found. Using only current logs."
    jq -c '. |= select(.timestamp >= "'$START_TIME'")' /var/ossec/logs/alerts/alerts.json 2>> /tmp/jq_errors.log > /tmp/alerts_combined.json
fi

# Wait a moment to ensure file is created
sleep 1

echo "[$$] Merging extracted JSON logs..."
jq -s '.' /tmp/alerts_combined.json 2>> /tmp/jq_errors.log > /tmp/alerts_combined_final.json

# Debug check
if [[ ! -s /tmp/alerts_combined_final.json ]]; then
    echo "[$$] Error: Merged log file is empty! Check /tmp/jq_errors.log"
    exit 1
else
    echo "[$$] Success: Merged log file contains data."
fi

# Debug: Check JSON file structure
jq empty /tmp/alerts_combined_final.json 2>> /tmp/jq_errors.log
if [[ $? -ne 0 ]]; then
    echo "[$$] Error: JSON parsing failed!"
    exit 1
fi

echo "[$$] Processing system updates check..."
UBUNTU_UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)

echo "[$$] Fetching latest Wazuh version..."
LATEST_WAZUH_VERSION=$(curl -s --max-time 10 https://api.github.com/repos/wazuh/wazuh/releases/latest | jq -r '.tag_name' | sed 's/^v//')

if [[ -z "$LATEST_WAZUH_VERSION" || "$LATEST_WAZUH_VERSION" == "null" ]]; then
    echo "[$$] Warning: Could not fetch the latest Wazuh version."
fi

echo "[$$] Checking disk usage..."
df -h | grep "/dev/mapper/ubuntu--vg-ubuntu--lv"

echo "[$$] Checking alerts directory usage..."
du -sh /var/ossec/logs/alerts

echo "[$$] Extracting non-critical alerts..."
NON_CRITICAL_ALERTS=$(jq -c '
    select(type == "object") | select(.rule.level < 7 and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' /tmp/alerts_combined_final.json 2>> /tmp/jq_errors.log | sort | uniq -c | sort -nr | head -n 10)

if [[ $? -ne 0 ]]; then
    echo "[$$] Error: jq failed to process non-critical alerts!"
    exit 1
fi

echo "[$$] Extracting critical alerts..."
CRITICAL_ALERTS=$(jq -c '
    select(type == "object") | select(.rule.level >= 7 and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' /tmp/alerts_combined_final.json 2>> /tmp/jq_errors.log | sort | uniq -c | sort -nr | head -n 10)

if [[ $? -ne 0 ]]; then
    echo "[$$] Error: jq failed to process critical alerts!"
    exit 1
fi

echo "[$$] Sending email report..."
(
echo "Subject: $MAIL_SUBJECT"
echo "MIME-Version: 1.0"
echo "Content-Type: text/html; charset=UTF-8"
cat "$REPORT_FILE"
) | sendmail -f "$MAIL_FROM" "$MAIL_TO"

# Cleanup
cleanup() {
    echo "[$$] Cleaning up temporary files..."
    rm -f /tmp/alerts_combined.json /tmp/alerts_combined_final.json
}
trap cleanup EXIT

echo "[$$] Script execution completed successfully!"
