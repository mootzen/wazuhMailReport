#!/bin/bash

# Load configuration
source "$(dirname "$0")/report.conf"

ALERT_FILE="/var/ossec/logs/alerts/alerts.json"
START_TIME=$(date --utc --date="24 hours ago" +%Y-%m-%dT%H:%M:%SZ)

echo "[DEBUG] START_TIME set to $START_TIME"
echo "[DEBUG] Processing alert file: $ALERT_FILE"
du -h "$ALERT_FILE"

# Limit to last ~100,000 lines for performance
echo "[DEBUG] Running jq filter..."
ALERTS=$(tail -n 100000 "$ALERT_FILE" | jq -c --arg start_time "$START_TIME" '
  select(
    type == "object"
    and (.rule.groups[]? == "authentication_failed" or .rule.mitre.technique[]? == "Brute Force")
    and (.timestamp >= $start_time)
  )
')

echo "[DEBUG] Filtered alerts: $(echo "$ALERTS" | wc -l)"

# Count total alerts
TOTAL_ALERTS=$(echo "$ALERTS" | wc -l)
echo "[DEBUG] Total alerts: $TOTAL_ALERTS"

# Extract top alerts
TOP_ALERTS=$(echo "$ALERTS" | jq -r '.rule.description' | sort | uniq -c | sort -nr | head -n "$TOP_ALERTS_COUNT")

# Generate HTML mail body
MAIL_BODY=$(cat <<EOF
<html>
<head>
  <style>
    body { font-family: Arial; }
    h2 { color: #2e6c80; }
    ul { padding-left: 20px; }
  </style>
</head>
<body>
  <h2>Wazuh Login Failure Report (${TIME_PERIOD})</h2>
  <p><strong>Total login failure alerts:</strong> $TOTAL_ALERTS</p>
  <h3>Top ${TOP_ALERTS_COUNT} Alert Types</h3>
  <ul>
$(echo "$TOP_ALERTS" | awk '{count=$1; $1=""; desc=substr($0,2); print "<li><strong>" count "</strong> - " desc "</li>"}')
  </ul>
</body>
</html>
EOF
)

# Send email
echo "$MAIL_BODY" | mail -a "Content-Type: text/html" -s "$MAIL_SUBJECT" "$MAIL_TO"
