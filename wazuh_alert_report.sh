#!/bin/bash

ascii_art="
                          _     __  __       _ _ ____                       _
 __      ____ _ _____   _| |__ |  \/  | __ _(_) |  _ \ ___ _ __   ___  _ __| |_
 \ \ /\ / / _\` |_  / | | | '_ \| |\/| |/ _\` | | | |_) / _ \ '_ \ / _ \| '__| __|
  \ V  V / (_| |/ /| |_| | | | | |  | | (_| | | |  _ <  __/ |_) | (_) | |  | |_
   \_/\_/ \__,_/___|\__,_|_| |_|_|  |_|\__,_|_|_|_| \_\___| .__/ \___/|_|   \__|
                                                          |_|
    by mootzen 2025
"

VERSION="0.2"
echo -e "$ascii_art"

# Lockfile to prevent multiple instances running
LOCKFILE="/tmp/wazuh_report.lock"
if [ -e "$LOCKFILE" ]; then
    echo "Another instance of the script is running. Exiting."
    exit 1
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Cleanup function
cleanup() {
    rm -f /tmp/alerts_combined.json /tmp/alerts_combined_final.json /tmp/wazuh_report.lock
}
trap cleanup EXIT  # Ensures cleanup on script exit

# Remove old temp files if they exist
echo "Deleting existing temp files..."
rm -f /tmp/alerts_combined.json /tmp/alerts_combined_final.json

# Load config file
CONFIG_FILE="/usr/local/wazuhMailReport/report.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi
source "$CONFIG_FILE"

echo "Config file loaded successfully."

# Set time period
START_TIME=$(date --utc --date="24 hours ago" +%Y-%m-%dT%H:%M:%SZ)

# Output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

# Output file
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.html"

# Determine previous day's log file
YESTERDAY=$(date --date="yesterday" +%d)
LOG_DIR="/var/ossec/logs/alerts/$(date +%Y/%b)"
PREV_LOG="$LOG_DIR/ossec-alerts-$YESTERDAY.json"
PREV_LOG_GZ="$PREV_LOG.gz"

echo "Searching for logs in $LOG_DIR"
echo "Expected yesterday's log: $PREV_LOG"
echo "Expected yesterday's log (gz): $PREV_LOG_GZ"

# Ensure `alerts.json` exists and is valid JSON before proceeding
ALERTS_JSON="/var/ossec/logs/alerts/alerts.json"
if [[ ! -s "$ALERTS_JSON" ]] || ! jq empty "$ALERTS_JSON" > /dev/null 2>&1; then
    echo "Error: alerts.json is empty or not valid JSON!"
    exit 1
fi

# Use a unique FIFO file for merging logs
FIFO_FILE="/tmp/alerts_combined_$$.json"  # Unique filename using process ID
mkfifo "$FIFO_FILE"

echo "Extracting and merging logs using jq streaming..."
if [[ -f "$PREV_LOG_GZ" ]]; then
    gunzip -c "$PREV_LOG_GZ" | jq -c 'select(.timestamp >= "'$START_TIME'")' > "$FIFO_FILE" &
elif [[ -f "$PREV_LOG" ]]; then
    jq -c 'select(.timestamp >= "'$START_TIME'")' "$PREV_LOG" > "$FIFO_FILE" &
else
    jq -c 'select(.timestamp >= "'$START_TIME'")' "$ALERTS_JSON" > "$FIFO_FILE" &
fi

# Process the combined JSON stream
jq -s '.' "$FIFO_FILE" > /tmp/alerts_combined_final.json
rm -f "$FIFO_FILE"  # Cleanup FIFO file

# Validate the merged JSON file
if [[ ! -s /tmp/alerts_combined_final.json ]]; then
    echo "Error: Merged log file is empty!"
    exit 1
fi

# Generate HTML report
echo "<html><body style='font-family: Arial, sans-serif;'>" > "$REPORT_FILE"
echo "<h2 style='color:blue;'>🔹 Daily Wazuh Report - $(date) </h2>" >> "$REPORT_FILE"
echo "<p>Hello Team,</p><p>Here's your daily Wazuh alert summary:</p>" >> "$REPORT_FILE"

# System Updates Check
UBUNTU_UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
if [[ "$UBUNTU_UPDATES" -gt 0 ]]; then
    echo "<p>🔴 <b>Ubuntu:</b> $UBUNTU_UPDATES updates available.</p>" >> "$REPORT_FILE"
else
    echo "<p>✅ <b>Ubuntu:</b> System is up to date.</p>" >> "$REPORT_FILE"
fi

# Fetch latest Wazuh version
INSTALLED_WAZUH_VERSION=$(dpkg-query -W -f='${Version}\n' wazuh-manager 2>/dev/null | cut -d '-' -f1)
LATEST_WAZUH_VERSION=$(curl -s --max-time 10 https://api.github.com/repos/wazuh/wazuh/releases/latest | jq -r '.tag_name' | sed 's/^v//')

if [[ -z "$LATEST_WAZUH_VERSION" || "$LATEST_WAZUH_VERSION" == "null" ]]; then
    echo "<p>⚠️ <b>Wazuh:</b> Could not fetch the latest version info.</p>" >> "$REPORT_FILE"
elif [[ "$INSTALLED_WAZUH_VERSION" == "$LATEST_WAZUH_VERSION" ]]; then
    echo "<p>✅ <b>Wazuh:</b> Version $INSTALLED_WAZUH_VERSION is up to date.</p>" >> "$REPORT_FILE"
else
    echo "<p>🔴 <b>Wazuh:</b> Update available! Installed: $INSTALLED_WAZUH_VERSION → Latest: $LATEST_WAZUH_VERSION</p>" >> "$REPORT_FILE"
fi

# Disk Usage
echo "<h3>💾 Disk Usage</h3>" >> "$REPORT_FILE"
echo "<pre>$(df -h | grep "/dev/mapper/ubuntu--vg-ubuntu--lv")</pre>" >> "$REPORT_FILE"

# Swap Usage
echo "<h3>🔄 Swap Usage</h3>" >> "$REPORT_FILE"
echo "<pre>$(free -h | grep "Swap")</pre>" >> "$REPORT_FILE"

# Footer
echo "<p style='font-size: 12px; color: gray;'>This is an automatically generated report.</p>" >> "$REPORT_FILE"
echo "</body></html>" >> "$REPORT_FILE"

# Send email
(
echo "Subject: $MAIL_SUBJECT"
echo "MIME-Version: 1.0"
echo "Content-Type: text/html; charset=UTF-8"
cat "$REPORT_FILE"
) | sendmail -f "$MAIL_FROM" "$MAIL_TO"

echo "Report sent successfully to $MAIL_TO."
exit 0
