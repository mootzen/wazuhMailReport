#!/bin/bash

# Load config file
CONFIG_FILE="/etc/wazuhMailReport.conf"

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

# Start HTML report
echo "<html><body style='font-family: Arial, sans-serif;'>" > "$REPORT_FILE"

# Greeting & Summary
echo "<h2 style='color:blue;'>🔹 Daily Wazuh Report - $(date)</h2>" >> "$REPORT_FILE"
echo "<p>Hello Team,</p><p>Here's the daily Wazuh alert summary:</p>" >> "$REPORT_FILE"

# Disk & Swap Usage
echo "<h3>💾 Disk Usage</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'>" >> "$REPORT_FILE"
echo "<tr><th>Filesystem</th><th>Size</th><th>Used</th><th>Avail</th><th>Use%</th></tr>" >> "$REPORT_FILE"
df -h | grep "/dev/mapper/ubuntu--vg-ubuntu--lv" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td></tr>"}' >> "$REPORT_FILE"
echo "</table>" >> "$REPORT_FILE"

echo "<h3>🔄 Swap Usage</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Total</th><th>Used</th><th>Free</th></tr>" >> "$REPORT_FILE"
free -h | grep "Swap" | awk '{print "<tr><td>"$2"</td><td>"$3"</td><td>"$4"</td></tr>"}' >> "$REPORT_FILE"
echo "</table>" >> "$REPORT_FILE"

# Function to safely run jq with error handling, retries, and timeout - when indexer writes to the json we cannot read it
jq_safe() {
    local retries=10
    local wait_time=10  # Wait time between retries in seconds
    local timeout=60    # Total timeout for retries in seconds
    local count=0
    local success=0
    local output=""
    local start_time=$(date +%s)  # Record start time for timeout

    while [[ $count -lt $retries && $success -eq 0 ]]; do
        output=$(jq -r "$2" "$1" 2>/tmp/jq_error.log)  # Capture only errors separately

        if [[ $? -ne 0 ]]; then
            local error_msg=$(cat /tmp/jq_error.log)
            if grep -q "Permission denied" <<< "$error_msg"; then
                echo "Warning: jq permission error. Retrying... ($((count+1))/$retries)" >> /var/ossec/logs/alerts/jq_errors.log
            elif [[ ! -z "$error_msg" ]]; then
                echo "Warning: jq error: $error_msg" >> /var/ossec/logs/alerts/jq_errors.log
                return 1  # Exit if it's not a permission issue
            fi
        else
            success=1
            echo "$output"  # ✅ Only return valid JSON output, do not log it
        fi

        ((count++))
        sleep $wait_time
    done

    if [[ $success -eq 0 ]]; then
        echo "Error: jq failed after $retries retries." >> /var/ossec/logs/alerts/jq_errors.log
        return 1
    fi

    return 0
}

# Top Non-Critical Alerts (Level < $LEVEL)
echo "<h3>🚨 Top Non-Critical Alerts (Level < $LEVEL) from the last $TIME_PERIOD</h3>" >> "$REPORT_FILE"
echo "<p>These are the top $TOP_ALERTS_COUNT non-critical alerts (level < $LEVEL) from the last $TIME_PERIOD:</p>" >> "$REPORT_FILE"

# Get Top Non-Critical Alerts (level < $LEVEL)
NON_CRITICAL_ALERTS=$(jq_safe "/var/ossec/logs/alerts/alerts.json" '
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

# Get Top Critical Alerts (level >= $LEVEL)
CRITICAL_ALERTS=$(jq_safe "/var/ossec/logs/alerts/alerts.json" '
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
