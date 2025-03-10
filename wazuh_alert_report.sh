#!/bin/bash

# Load config file
CONFIG_FILE="/usr/local/wazuhMailReport/report.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Set time period
START_TIME=$(date --utc --date="24 hours ago" +%Y-%m-%dT%H:%M:%SZ)

# Output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

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

# Copy current log to temporary file
if [[ -f "/var/ossec/logs/alerts/alerts.json" ]]; then
    cp /var/ossec/logs/alerts/alerts.json /tmp/alerts.json
else
    echo "Warning: Current alerts.json file not found!" >> /tmp/debug.log
    touch /tmp/alerts.json  # Ensure the file exists to avoid errors
fi

# Extract and merge logs
if [[ -f "$PREV_LOG_GZ" ]]; then
    echo "Extracting previous day's alerts from $PREV_LOG_GZ" >> /tmp/debug.log
    gunzip -c "$PREV_LOG_GZ" > /tmp/prev_alerts.json
    jq -s 'add' /tmp/alerts.json /tmp/prev_alerts.json > /tmp/alerts_combined.json
    rm -f /tmp/prev_alerts.json  # Cleanup
elif [[ -f "$PREV_LOG" ]]; then
    echo "Using uncompressed previous day's alerts from $PREV_LOG" >> /tmp/debug.log
    jq -s 'add' /tmp/alerts.json "$PREV_LOG" > /tmp/alerts_combined.json
else
    echo "No previous alerts found. Using only current logs." >> /tmp/debug.log
    cp /tmp/alerts.json /tmp/alerts_combined.json
fi

# Debug: Check if the merged file contains data
if [[ ! -s /tmp/alerts_combined.json ]]; then
    echo "Error: Merged log file is empty!" >> /tmp/debug.log
else
    echo "Success: Merged log file contains data." >> /tmp/debug.log
fi

# HTML report header
echo "<html><body style='font-family: Arial, sans-serif;'>" > "$REPORT_FILE"
echo "<h2 style='color:blue;'>🔹 Daily Wazuh Report - $(date) 🔹</h2>" >> "$REPORT_FILE"
echo "<p>Hello Team,</p><p>Here's the daily Wazuh alert summary:</p>" >> "$REPORT_FILE"

# jq function
jq_safe() {
    jq -r "$2" "$1" 2>/dev/null
}

# Debug: Check logs before filtering
jq '.timestamp' /tmp/alerts_combined.json | head -n 10 >> /tmp/debug.log

# Non-Critical Alerts
NON_CRITICAL_ALERTS=$(jq_safe "/tmp/alerts_combined.json" '
    select(type == "object") | select(.rule.level < '$LEVEL' and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -n $TOP_ALERTS_COUNT)

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
CRITICAL_ALERTS=$(jq_safe "/tmp/alerts_combined.json" '
    select(type == "object") | select(.rule.level >= '$LEVEL' and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -n $TOP_ALERTS_COUNT)

if [[ -z "$CRITICAL_ALERTS" ]]; then
    echo "<p style='color: gray;'>No critical alerts found.</p>" >> "$REPORT_FILE"
    echo "Warning: No critical alerts found." >> /tmp/debug.log
else
    echo "<h3>🚨 Top Critical Alerts (Level ≥ $LEVEL) from the last $TIME_PERIOD</h3>" >> "$REPORT_FILE"
    echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"
    echo "$CRITICAL_ALERTS" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"
    echo "</table>" >> "$REPORT_FILE"
fi
echo "<p>This is an automatically generated report. If you encounter any issues, please report them on <a href='https://github.com/mootzen/wazuhMailReport/issues' target='_blank'>GitHub Issues</a>.</p>" >> "$REPORT_FILE"
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
tmp_files=("/tmp/alerts.json" "/tmp/alerts_combined.json")
for file in "${tmp_files[@]}"; do
    [[ -f "$file" ]] && rm "$file"
done
