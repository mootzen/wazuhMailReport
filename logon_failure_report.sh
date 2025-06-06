#!/bin/bash

# Load configuration
source "$(dirname "$0")/config.cfg"

# Set alert file location
ALERT_FILE="/var/ossec/logs/alerts/alerts.json"

# Calculate time filter
TIME_FILTER=$(date -d "$TIME_PERIOD ago" --iso-8601=seconds)

# Filter alerts
ALERTS=$(jq -c --arg time_filter "$TIME_FILTER" '
  select(
    (
      (.rule.groups[]? == "authentication_failed")
      or (.rule.mitre.technique[]? == "Brute Force")
      or (.rule.mitre.technique[]? == "Valid Accounts")
    )
    and (."@timestamp" >= $time_filter)
  )
' "$ALERT_FILE")

# Count total alerts
TOTAL_ALERTS=$(echo "$ALERTS" | wc -l)

# Count mail-related alerts
MAIL_ALERTS=$(echo "$ALERTS" | jq -r '
  select(.data.srcuser? | test("mail|smtp|imap|healthmailbox"; "i"))
' | wc -l)

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
  <p><strong>Mail-related login failures:</strong> $MAIL_ALERTS</p>
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
