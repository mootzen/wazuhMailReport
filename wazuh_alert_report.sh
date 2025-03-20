#!/bin/bash

echo "[$$] Starting Wazuh Mail Report"
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
rm -f /tmp/alerts_combined.json

echo "[$$] Current working directory: $(pwd)"

# Load config file
CONFIG_FILE="/usr/local/wazuhMailReport/report.conf"
echo "[$$] Checking for config file at: $CONFIG_FILE"

if [[ -f "$CONFIG_FILE" ]]; then
    echo "[$$] Config file found and sourced successfully."
    source "$CONFIG_FILE"
else
    echo "[$$] Error: Config file not found at $CONFIG_FILE" >> /var/ossec/logs/alerts/jq_errors.log
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

touch /tmp/alerts_combined.json
echo "[$$] Extracting and merging logs using jq streaming..."

if [[ -f "$PREV_LOG_GZ" ]]; then
    echo "[$$] Extracting previous day's alerts from $PREV_LOG_GZ"
    gunzip -c "$PREV_LOG_GZ" | jq -c 'select(. != null) | select(.timestamp >= "'$START_TIME'")' 2>> /tmp/jq_errors.log >> /tmp/alerts_combined.json
elif [[ -f "$PREV_LOG" ]]; then
    echo "[$$] Using uncompressed previous day's alerts from $PREV_LOG"
    jq -c 'select(. != null) | select(.timestamp >= "'$START_TIME'")' "$PREV_LOG" 2>> /tmp/jq_errors.log >> /tmp/alerts_combined.json
else
    echo "[$$] No previous alerts found. Using only current logs."
    jq -c 'select(. != null) | select(.timestamp >= "'$START_TIME'")' /var/ossec/logs/alerts/alerts.json 2>> /tmp/jq_errors.log >> /tmp/alerts_combined.json
fi

sleep 1

echo "[$$] Merging extracted JSON logs..."
jq -s '.' /tmp/alerts_combined.json 2>> /tmp/jq_errors.log > /tmp/alerts_combined.json

echo "[$$] Checking JSON structure..."
jq empty /tmp/alerts_combined.json 2>> /tmp/jq_errors.log
if [[ $? -ne 0 ]]; then
    echo "[$$] Error: JSON parsing failed!" >> /var/ossec/logs/alerts/jq_errors.log
fi

echo "[$$] Debug: First 10 lines of merged JSON file:"
head -n 10 /tmp/alerts_combined.json

# Cleanup function
cleanup() {
    echo "[$$] Cleaning up temporary files..."
    rm -f /tmp/alerts_combined.json
}
trap cleanup EXIT

swapoff -a; swapon -a
echo "[$$] Script execution completed successfully!"
