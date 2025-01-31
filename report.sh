#!/bin/bash

# Define output directory
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"

# Define output file (HTML format)
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.html"

# Get alert counts for summary
TOTAL_ALERTS=$(jq --argjson last24 "$(date --date='-24 hours' +%s)" '[.[] | select(.timestamp | fromdateiso8601 > $last24)] | length' /var/ossec/logs/alerts/alerts.json)
MAIL_ALERTS=$(grep -c "wazuh-mail-alert" /var/log/mail.log)  # Adjust for your mail log

# Start HTML report
echo "<html><body style='font-family: Arial, sans-serif;'>" > "$REPORT_FILE"

# Greeting & Summary
echo "<h2>🔹 Daily Wazuh Report - $(date)</h2>" >> "$REPORT_FILE"
echo "<p>Hello Team,</p><p>Here's the daily Wazuh alert summary:</p>" >> "$REPORT_FILE"
echo "<ul><li><b>Total alerts in the last 24 hours:</b> $TOTAL_ALERTS</li><li><b>Email alerts sent:</b> $MAIL_ALERTS</li></ul>" >> "$REPORT_FILE"

# Disk & Swap Usage
echo "<h3>💾 Disk & Swap Usage</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'>" >> "$REPORT_FILE"
echo "<tr><th>Filesystem</th><th>Size</th><th>Used</th><th>Avail</th><th>Use%</th></tr>" >> "$REPORT_FILE"
df -h | grep "/dev/mapper/ubuntu--vg-ubuntu--lv" | awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td></tr>"}' >> "$REPORT_FILE"
echo "</table>" >> "$REPORT_FILE"

echo "<h3>🔄 Swap Usage</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Total</th><th>Used</th><th>Free</th></tr>" >> "$REPORT_FILE"
free -h | grep "Swap" | awk '{print "<tr><td>"$2"</td><td>"$3"</td><td>"$4"</td></tr>"}' >> "$REPORT_FILE"
echo "</table>" >> "$REPORT_FILE"

# Top 10 Non-Critical Alerts
echo "<h3>🚨 Top 10 Non-Critical Wazuh Alerts (Level < 12)</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"

jq -r 'select(.rule.level < 12) | "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"' /var/ossec/logs/alerts/alerts.json | \
sort | uniq -c | sort -nr | head -10 | \
awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"

echo "</table>" >> "$REPORT_FILE"

# Top 10 Email-Triggered Alerts
echo "<h3>📩 Top 10 Alerts That Triggered Emails (Level ≥ 12)</h3>" >> "$REPORT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"

jq -r 'select(.rule.level >= 12) | "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"' /var/ossec/logs/alerts/alerts.json | \
sort | uniq -c | sort -nr | head -10 | \
awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"substr($0, index($0,$4))"</td></tr>"}' >> "$REPORT_FILE"

echo "</table>" >> "$REPORT_FILE"

# Close HTML
echo "</body></html>" >> "$REPORT_FILE"

# Send the email with HTML formatting
MAIL_TO="admin@organisation.com"  # Change this to your email <========================================
MAIL_SUBJECT="Wazuh Daily Report - $(date)"
(
echo "Subject: $MAIL_SUBJECT"
echo "MIME-Version: 1.0"
echo "Content-Type: text/html; charset=UTF-8"
cat "$REPORT_FILE"
) | sendmail "$MAIL_TO"
