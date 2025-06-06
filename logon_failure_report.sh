#!/bin/bash

# Configuration
LEVEL=5
TIME_PERIOD="1d"
MAIL_TO="x@y.com"
MAIL_FROM="reporter@wazuh"
MAIL_SUBJECT="Wazuh Login Failure Report"
FONT="Arial, sans-serif"
HEADING_COLOR="#b30000"
USE_EMOJIS=true

# Emoji function
emoji() {
    if [ "$USE_EMOJIS" = true ]; then
        echo "$1"
    else
        echo ""
    fi
}

# Temporary file to hold alerts
TMP_ALERTS=$(mktemp /tmp/wazuh_alerts_XXXX.json)

# Fetch alerts
/var/ossec/bin/wazuh-logtest -j > /dev/null 2>&1  # ensure it runs once if needed
/var/ossec/bin/wazuh-db query "SELECT * FROM alert WHERE level >= $LEVEL AND timestamp > datetime('now', '-$TIME_PERIOD');" > "$TMP_ALERTS"

# Extract login failure alerts
LOGIN_FAILURE_ALERTS=$(jq -r '
  select(
    type == "object" and 
    (.rule.groups | index("authentication_success") | not) and
    (
      (.rule.groups | index("authentication_failed")) or 
      (.rule.mitre.technique == "Valid Accounts")
    )
  ) 
  | "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"
' "$TMP_ALERTS" | sort | uniq -c | sort -nr | head -n 10)

# Count total matching alerts
TOTAL_LOGIN_FAILURES=$(jq -r '
  select(
    type == "object" and 
    (.rule.groups | index("authentication_success") | not) and
    (
      (.rule.groups | index("authentication_failed")) or 
      (.rule.mitre.technique == "Valid Accounts")
    )
  )
' "$TMP_ALERTS" | wc -l)

# Compose HTML report
REPORT_HTML=$(cat <<EOF
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: $FONT; background: #f9f9f9; padding: 20px; }
    h2 { color: $HEADING_COLOR; }
    table { border-collapse: collapse; width: 100%; background: #fff; }
    th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
    th { background: #eee; }
    .emoji { font-size: 1.2em; }
  </style>
</head>
<body>
  <h2>${MAIL_SUBJECT}</h2>
  <p>${TOTAL_LOGIN_FAILURES} login failure alerts in the last ${TIME_PERIOD}.</p>

  <h3>🔐 Top Login Failures</h3>
  <table>
    <tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>
EOF
)

# Add alert rows
while IFS=$'\t' read -r COUNT LEVEL RULE_ID DESC; do
  REPORT_HTML+="<tr><td>$COUNT</td><td>$LEVEL</td><td>$RULE_ID</td><td>$DESC</td></tr>"
done <<< "$LOGIN_FAILURE_ALERTS"

# Close HTML
REPORT_HTML+="</table></body></html>"

# Send mail
echo "$REPORT_HTML" | mail -a "Content-Type: text/html" -s "$MAIL_SUBJECT" -r "$MAIL_FROM" "$MAIL_TO"

# Cleanup
rm "$TMP_ALERTS"
