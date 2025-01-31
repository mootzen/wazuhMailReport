#!/bin/bash

# Define output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

# Define output file (HTML format)
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.html"

# Start HTML report
echo "<html><body style='font-family: Arial, sans-serif;'>" > "$REPORT_FILE"

# Greeting & Summary
echo "<h2>🔹 Daily Wazuh Report - $(date)</h2>" >> "$REPORT_FILE"
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

# Function to safely run jq with error handling
jq_safe() {
    # Run jq and capture the output
    output=$(jq -r "$2" "$1" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "Warning: jq error: $output" >> /var/ossec/logs/alerts/jq_errors.log
        return 1  # Return an error code
    else
        echo "$output"
        return 0  # Success
    fi
}

# Top 10 Non-Critical Alerts (Level < 12)
echo "<h3>🚨 Top 10 Non-Critical Alerts (Level < 12)</h3>" >> "$REPORT_FILE"
echo "<p>These are the top 10 non-critical alerts (level < 12) from the last 24 hours:</p>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"

# Get Non-Critical Alerts
jq_safe "/var/ossec/logs/alerts/alerts.json" '
    select(type == "object") | select(.rule.level < 12) |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -10 | \
awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"

# Debug: Output the same content to the terminal to check if data is being captured
jq_safe "/var/ossec/logs/alerts/alerts.json" '
    select(type == "object") | select(.rule.level < 12) |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -10

echo "</table>" >> "$REPORT_FILE"

# Top 10 Critical Alerts (Level ≥ 12)
echo "<h3>📩 Top 10 Critical Alerts (Level ≥ 12)</h3>" >> "$REPORT_FILE"
echo "<p>These are the top 10 critical alerts (level ≥ 12) that triggered email notifications in the last 24 hours:</p>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"

# Get Critical Alerts (Level ≥ 12)
jq_safe "/var/ossec/logs/alerts/alerts.json" '
    select(type == "object") | select(.rule.level > 11) |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -10 | \
awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"

echo "</table>" >> "$REPORT_FILE"

# Debug: Print Critical Alerts to Terminal for Inspection
echo "Debugging Critical Alerts (Level >= 12):"
jq_safe "/var/ossec/logs/alerts/alerts.json" '
    select(type == "object") | select(.rule.level > 11) |
    "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' | sort | uniq -c | sort -nr | head -10

echo "</table>" >> "$REPORT_FILE"

# Close HTML
echo "</body></html>" >> "$REPORT_FILE"

# Send the email with HTML formatting
MAIL_TO="your@mail.com" # <------------ Change this to your mail address 
MAIL_SUBJECT="Wazuh Daily Report - $(date)"
(
echo "Subject: $MAIL_SUBJECT"
echo "MIME-Version: 1.0"
echo "Content-Type: text/html; charset=UTF-8"
cat "$REPORT_FILE"
) | sendmail "$MAIL_TO"
