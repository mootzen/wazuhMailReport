#!/bin/bash

# Load config file
CONFIG_FILE="./report.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Calculate the time since set Time-Period (for filtering)
START_TIME=$(date --date="$TIME_PERIOD ago" --utc +%Y-%m-%dT%H:%M:%SZ)

# Define output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

# Define output file (HTML format)
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.html"

# Determine previous day's log file
YESTERDAY=$(date --date="yesterday" +%Y%m%d)
PREV_LOG="/var/ossec/logs/alerts/alerts-$YESTERDAY.json"

# Copy and merge log files to avoid read conflicts
cp /var/ossec/logs/alerts/alerts.json /tmp/alerts.json 2>/dev/null
if [[ -f "$PREV_LOG" ]]; then
    jq -s 'add' /tmp/alerts.json "$PREV_LOG" > /tmp/alerts_combined.json
else
    cp /tmp/alerts.json /tmp/alerts_combined.json
fi

# Start HTML report
echo "<html><body style='font-family: Arial, sans-serif;'>" > "$REPORT_FILE"

# Greeting & Summary
echo "<h2 style='color:blue;'>🔹 Daily Wazuh Report - $(date)</h2>" >> "$REPORT_FILE"
echo "<p>Hello Team,</p><p>Here's the daily Wazuh alert summary:</p>" >> "$REPORT_FILE"

# Function to safely run jq with error handling
jq_safe() {
    jq -r "$2" "$1" 2>/dev/null
}

# Top Non-Critical Alerts (Level < $LEVEL)
echo "<h3>🚨 Top Non-Critical Alerts (Level < $LEVEL) from the last $TIME_PERIOD</h3>" >> "$REPORT_FILE"
echo "<p>These are the top $TOP_ALERTS_COUNT non-critical alerts (level < $LEVEL) from the last $TIME_PERIOD:</p>" >> "$REPORT_FILE"

NON_CRITICAL_ALERTS=$(jq_safe "/tmp/alerts_combined.json" '
    select(type == "object") | select(.rule.level < '$LEVEL' and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -n $TOP_ALERTS_COUNT)

if [[ -z "$NON_CRITICAL_ALERTS" ]]; then
    echo "<p style='color: gray;'>No non-critical alerts found in the last $TIME_PERIOD.</p>" >> "$REPORT_FILE"
else
    echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"
    echo "$NON_CRITICAL_ALERTS" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"
    echo "</table>" >> "$REPORT_FILE"
fi

# Top Critical Alerts (Level ≥ $LEVEL)
echo "<h3>📩 Top Critical Alerts (Level ≥ $LEVEL) from the last $TIME_PERIOD</h3>" >> "$REPORT_FILE"
echo "<p>These are the top $TOP_ALERTS_COUNT critical alerts (level ≥ $LEVEL) from the last $TIME_PERIOD:</p>" >> "$REPORT_FILE"

CRITICAL_ALERTS=$(jq_safe "/tmp/alerts_combined.json" '
    select(type == "object") | select(.rule.level >= '$LEVEL' and .timestamp >= "'$START_TIME'") |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -n $TOP_ALERTS_COUNT)

if [[ -z "$CRITICAL_ALERTS" ]]; then
    echo "<p style='color: gray;'>No critical alerts found in the last $TIME_PERIOD.</p>" >> "$REPORT_FILE"
else
    echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"
    echo "$CRITICAL_ALERTS" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"
    echo "</table>" >> "$REPORT_FILE"
fi

# Close HTML
echo "</body></html>" >> "$REPORT_FILE"

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
