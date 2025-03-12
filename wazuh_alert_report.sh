#!/bin/bash
ascii_art="
                          _     __  __       _ _ ____                       _
 __      ____ _ _____   _| |__ |  \/  | __ _(_) |  _ \ ___ _ __   ___  _ __| |_
 \ \ /\ / / _\` |_  / | | | '_ \| |\/| |/ _\` | | | |_) / _ \ '_ \ / _ \| '__| __|
  \ V  V / (_| |/ /| |_| | | | | |  | | (_| | | |  _ <  __/ |_) | (_) | |  | |_
   \_/\_/ \__,_/___|\__,_|_| |_|_|  |_|\__,_|_|_|_| \_\___| .__/ \___/|_|   \__|
                                                          |_|
"
VERSION="0.1"
echo -e "$ascii_art"
# If execution was canceled previously there might be unfinished tmp files that have to be removed
echo "Deleting existing tmp files..."
tmp_files=("/tmp/alerts_combined.json" "/tmp/alerts_combined_final.json")
for file in "${tmp_files[@]}"; do
    [[ -f "$file" ]] && rm "$file"
done

echo "Current working directory: $(pwd)"

# Load config file
CONFIG_FILE="/usr/local/wazuhMailReport/report.conf"
echo "Checking for config file at: $CONFIG_FILE"

if [[ -f "$CONFIG_FILE" ]]; then
    echo "Config file found."
    source "$CONFIG_FILE"
    echo "Config file sourced successfully."
else
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Add debug statements before the error message
echo "Debug: CONFIG_FILE is set to $CONFIG_FILE"

# Example of where the error might be triggered again
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

echo "Memory usage after loading config:"
free -h

# Set time period
START_TIME=$(date --utc --date="24 hours ago" +%Y-%m-%dT%H:%M:%SZ)

# Output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

#echo "Memory usage after setting time period and output directory:"
#free -h

# Output file
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.html"

# Determine yesterday’s log filename
YESTERDAY=$(date --date="yesterday" +%d)
LOG_DIR="/var/ossec/logs/alerts/$(date +%Y/%b)"  # Ensure this format matches your filesystem
PREV_LOG="$LOG_DIR/ossec-alerts-$YESTERDAY.json"
PREV_LOG_GZ="$PREV_LOG.gz"

echo "Debug: Searching for logs in $LOG_DIR" > /tmp/debug.log
echo "Debug: Expected yesterday's log: $PREV_LOG" >> /tmp/debug.log
echo "Debug: Expected yesterday's log (gz): $PREV_LOG_GZ" >> /tmp/debug.log

#echo "Memory usage after determining log filenames:"
#free -h

# Use a named pipe for streaming JSON data
mkfifo /tmp/alerts_combined.json
echo "Extracting and merging logs using jq streaming, this may take a while..."
# Extract and merge logs using jq streaming
if [[ -f "$PREV_LOG_GZ" ]]; then
    echo "Extracting previous day's alerts from $PREV_LOG_GZ" >> /tmp/debug.log
    gunzip -c "$PREV_LOG_GZ" | jq -c '. |= select(.timestamp >= "'$START_TIME'")' >> /tmp/alerts_combined.json &
elif [[ -f "$PREV_LOG" ]]; then
    echo "Using uncompressed previous day's alerts from $PREV_LOG" >> /tmp/debug.log
    jq -c '. |= select(.timestamp >= "'$START_TIME'")' "$PREV_LOG" >> /tmp/alerts_combined.json &
else
    echo "No previous alerts found. Using only current logs." >> /tmp/debug.log
    jq -c '. |= select(.timestamp >= "'$START_TIME'")' /var/ossec/logs/alerts/alerts.json >> /tmp/alerts_combined.json &
fi

# Process the combined JSON stream
jq -s '.' /tmp/alerts_combined.json > /tmp/alerts_combined_final.json

# Debug: Check if the merged file contains data
if [[ ! -s /tmp/alerts_combined_final.json ]]; then
    echo "Error: Merged log file is empty!" >> /tmp/debug.log
else
    echo "Success: Merged log file contains data." >> /tmp/debug.log
fi

# HTML report header
echo "<html><body style='font-family: Arial, sans-serif;'>" > "$REPORT_FILE"
echo "<h2 style='color:blue;'>🔹 Daily Wazuh Report - $(date) </h2>" >> "$REPORT_FILE"
echo "<p>Hello Team,</p><p>Here's your daily Wazuh alert summary:</p>" >> "$REPORT_FILE"

# jq function with streaming
jq_safe() {
    jq -c -r "$2" "$1" 2>/dev/null
}

# System Updates Check
echo "<h3>🔄 System Updates Status</h3>" >> "$REPORT_FILE"

# Check Ubuntu updates
UBUNTU_UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l) # Ensure your system locale is set to english, otherwise this might generate false-positives
if [[ "$UBUNTU_UPDATES" -gt 0 ]]; then
    echo "<p>🔴 <b>Ubuntu:</b> $UBUNTU_UPDATES updates available.</p>" >> "$REPORT_FILE"
else
    echo "<p>✅ <b>Ubuntu:</b> System is up to date.</p>" >> "$REPORT_FILE"
fi

# Get installed Wazuh version
INSTALLED_WAZUH_VERSION=$(dpkg-query -W -f='${Version}\n' wazuh-manager 2>/dev/null | cut -d '-' -f1)

# Fetch latest Wazuh version from the official API with a timeout
echo "Fetching latest Wazuh version from GitHub API..."
LATEST_WAZUH_VERSION=$(curl -s --max-time 10 https://api.github.com/repos/wazuh/wazuh/releases/latest | jq -r '.tag_name' | sed 's/^v//')

if [[ -z "$LATEST_WAZUH_VERSION" || "$LATEST_WAZUH_VERSION" == "null" ]]; then
    echo "<p>⚠️ <b>Wazuh:</b> Could not fetch the latest version info. Please check network connectivity.</p>" >> "$REPORT_FILE"
elif [[ "$INSTALLED_WAZUH_VERSION" == "$LATEST_WAZUH_VERSION" ]]; then
    echo "<p>✅ <b>Wazuh:</b> Version $INSTALLED_WAZUH_VERSION is up to date.</p>" >> "$REPORT_FILE"
else
    echo "<p>🔴 <b>Wazuh:</b> Update available! Installed: $INSTALLED_WAZUH_VERSION → Latest: $LATEST_WAZUH_VERSION</p>" >> "$REPORT_FILE"
fi

# Debug: Check logs before filtering
jq '.timestamp' /tmp/alerts_combined.json | head -n 10 >> /tmp/debug.log

# Disk Usage Overview
echo "<h3>💾 Disk Usage</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'>" >> "$REPORT_FILE"
echo "<tr><th>Filesystem</th><th>Size</th><th>Used</th><th>Avail</th><th>Use%</th></tr>" >> "$REPORT_FILE"
df -h | grep "/dev/mapper/ubuntu--vg-ubuntu--lv" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td></tr>"}' >> "$REPORT_FILE"
echo "</table>" >> "$REPORT_FILE"

# Alerts Directory Breakdown
echo "<h3>📂 Alerts Directory Usage</h3>" >> "$REPORT_FILE"

# Get total size of the alerts directory (in bytes)
TOTAL_ALERTS_SIZE=$(du -sb /var/ossec/logs/alerts | awk '{print $1}')

# Get sizes of subdirectories
ALERT_ITEMS=()
while read -r size path; do
    [[ "$path" =~ jq$|jq_errors.log$ ]] && continue  # Exclude jq and jq_errors.log
    ALERT_ITEMS+=("$size $path")
done < <(du -sb /var/ossec/logs/alerts/* 2>/dev/null | sort -nr)

# Get sizes of alerts.json and alerts.log separately (since du doesn't work well on them)
for file in /var/ossec/logs/alerts/alerts.json /var/ossec/logs/alerts/alerts.log; do
    if [[ -f "$file" ]]; then
        FILE_SIZE=$(stat -c %s "$file")  # Get file size in bytes
        ALERT_ITEMS+=("$FILE_SIZE $file")
    fi
done

# Print total size
echo "<p>Total size: <b>$(numfmt --to=iec-i --suffix=B $TOTAL_ALERTS_SIZE)</b></p>" >> "$REPORT_FILE"

echo "<table border='1' cellspacing='0' cellpadding='5'>" >> "$REPORT_FILE"
echo "<tr><th>Path</th><th>Size</th><th>Usage %</th></tr>" >> "$REPORT_FILE"

# Function to calculate percentage
calculate_percentage() {
    local size=$1
    local total=$2
    awk "BEGIN {printf \"%.2f%%\", ($size / $total) * 100}"
}

# Process the collected data
for entry in "${ALERT_ITEMS[@]}"; do
    ITEM_SIZE=$(echo "$entry" | awk '{print $1}')
    ITEM_PATH=$(echo "$entry" | awk '{$1=""; print $0}' | sed 's/^ *//')

    ITEM_PERCENT=$(calculate_percentage "$ITEM_SIZE" "$TOTAL_ALERTS_SIZE")
    echo "<tr><td>$ITEM_PATH</td><td>$(numfmt --to=iec-i --suffix=B $ITEM_SIZE)</td><td>$ITEM_PERCENT</td></tr>" >> "$REPORT_FILE"
done

echo "</table>" >> "$REPORT_FILE"

echo "<h3>🔄 Swap Usage</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Total</th><th>Used</th><th>Free</th></tr>" >> "$REPORT_FILE"
free -h | grep "Swap" | awk '{print "<tr><td>"$2"</td><td>"$3"</td><td>"$4"</td></tr>"}' >> "$REPORT_FILE"
echo "</table>" >> "$REPORT_FILE"
# Debug: Check the contents of the merged JSON file
echo "Debug: First 10 lines of merged JSON file:" >> /tmp/debug.log
head -n 10 /tmp/alerts_combined_final.json >> /tmp/debug.log

# Non-Critical Alerts
NON_CRITICAL_ALERTS=$(jq_safe "/tmp/alerts_combined_final.json" '
    select(type == "object") | select(.rule.level < '$LEVEL' and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -n $TOP_ALERTS_COUNT)

# Debug: Print non-critical alerts
echo "Debug: Non-Critical Alerts:" >> /tmp/debug.log
echo "$NON_CRITICAL_ALERTS" >> /tmp/debug.log

if [[ -z "$NON_CRITICAL_ALERTS" ]]; then
    echo "<p style='color: gray;'>No non-critical alerts found.</p>" >> "$REPORT_FILE"
    echo "Warning: No non-critical alerts found." >> /tmp/debug.log
else
    echo "<h3>⚠️ Top Non-Critical Alerts (Level < $LEVEL) from the last $TIME_PERIOD</h3>" >> "$REPORT_FILE"
    echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"
    echo "$NON_CRITICAL_ALERTS" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"
    echo "</table>" >> "$REPORT_FILE"
fi

# Critical Alerts
CRITICAL_ALERTS=$(jq_safe "/tmp/alerts_combined_final.json" '
    select(type == "object") | select(.rule.level >= '$LEVEL' and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -n $TOP_ALERTS_COUNT)

# Debug: Print critical alerts
echo "Debug: Critical Alerts:" >> /tmp/debug.log
echo "$CRITICAL_ALERTS" >> /tmp/debug.log

if [[ -z "$CRITICAL_ALERTS" ]]; then
    echo "<p style='color: gray;'>No critical alerts found.</p>" >> "$REPORT_FILE"
    echo "Warning: No critical alerts found." >> /tmp/debug.log
else
    echo "<h3>🚨 Top Critical Alerts (Level ≥ $LEVEL) from the last $TIME_PERIOD</h3>" >> "$REPORT_FILE"
    echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"
    echo "$CRITICAL_ALERTS" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"
    echo "</table>" >> "$REPORT_FILE"
fi

echo "<p style='font-size: 12px; color: lightgray;'>This is an automatically generated report. If you encounter any issues, please report them on <a href='https://github.com/mootzen/wazuhMailReport/issues' target='_blank'>GitHub</a>.</p>" >> "$REPORT_FILE"
# Close HTML
echo "</body></html>" >> "$REPORT_FILE"

# Send email
(
echo "Subject: $MAIL_SUBJECT"
echo "MIME-Version: 1.0"
echo "Content-Type: text/html; charset=UTF-8"
cat "$REPORT_FILE"
) | sendmail -f "$MAIL_FROM" "$MAIL_TO"

# Cleanup
tmp_files=("/tmp/alerts_combined.json" "/tmp/alerts_combined_final.json")
for file in "${tmp_files[@]}"; do
    [[ -f "$file" ]] && rm "$file"
done
rm -f /tmp/alerts_combined.json
rm -f /tmp/alerts_combined_final.json
swapoff -a; swapon -a
