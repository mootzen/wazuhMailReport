#!/bin/bash

# Load config
CONFIG_FILE="$(dirname "$0")/report.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Set filters for login failures only
TIME_FILTER="now-${TIME_PERIOD}"

# Create a temporary file
TMP_FILE=$(mktemp)

# Extract relevant alerts from the last TIME_PERIOD with login failure context
jq -r --arg time_filter "$TIME_FILTER" \
  'select((.rule.groups[]? == "authentication_failed" or .rule.mitre.technique[]? == "Brute Force") and .["@timestamp"] >= $time_filter)' \
    /var/ossec/logs/alerts/alerts.json > "$TMP_FILE"

# Generate summary counts
TOTAL_ALERTS=$(wc -l < "$TMP_FILE")
MAIL_ALERTS=$(grep -c -i "email" "$TMP_FILE")

# Extract top alert messages
TOP_ALERTS=$(jq -r 'select(.rule.description?) | .rule.description' "$TMP_FILE" | sort | uniq -c | sort -nr | head -n ${TOP_ALERTS_COUNT})

# Compose HTML email
EMAIL_BODY="""
<html>
  <body style=\"font-family: Arial, sans-serif;\">
    <h2 style=\"color: #2c3e50;\">Wazuh Login Failure Report (Last $TIME_PERIOD)</h2>
    <p>Total login failure alerts: <strong>$TOTAL_ALERTS</strong></p>
    <p>Mail-related login failures: <strong>$MAIL_ALERTS</strong></p>
    <h3 style=\"color: #2c3e50;\">Top $TOP_ALERTS_COUNT Alert Types</h3>
    <pre style=\"background-color: #f4f4f4; padding: 10px; border: 1px solid #ccc;\">$TOP_ALERTS</pre>
  </body>
</html>
"""

# Send the email
echo "$EMAIL_BODY" | mail -a "Content-Type: text/html" -s "$MAIL_SUBJECT" -r "$MAIL_FROM" "$MAIL_TO"

# Clean up
rm "$TMP_FILE"
