#!/bin/bash

# Load mail config
CONFIG_FILE="./report.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[$$] ERROR: Config file '$CONFIG_FILE' not found."
    exit 1
fi

LOGON_MAIL_SUBJECT="Wazuh Logon Report - $(date '+%Y-%m-%d %H:%M')"
REPORT_FILE="/tmp/wazuh_logon_failure_report.html"
START_TIME=$(date --utc -d "24 hours ago" +%Y-%m-%dT%H:%M:%SZ)
ENABLE_EMOJIS=false

if [[ -z "$LOGON_MAIL_TO" || -z "$LOGON_MAIL_FROM" ]]; then
    echo "[$$] ERROR: LOGON_MAIL_TO or LOGON_MAIL_FROM is not set in config."
    exit 1
fi

REPORT_FILE="/tmp/wazuh_logon_failure_report.html"
rm -f "$REPORT_FILE"

echo "[DEBUG] START_TIME set to $START_TIME"
echo "[DEBUG] Writing report to $REPORT_FILE"

YESTERDAY=$(date --date="yesterday" +%d)
LOG_DIR="/var/ossec/logs/alerts/$(date +%Y/%b)"
PREV_LOG="$LOG_DIR/ossec-alerts-$YESTERDAY.json"
PREV_LOG_GZ="$PREV_LOG.gz"

touch /tmp/logon_combined.json
echo "[$$] Extracting and merging logs using jq streaming..."

if [[ -f "$PREV_LOG_GZ" ]]; then
    echo "[$$] Extracting previous day's alerts from $PREV_LOG_GZ"
    gunzip -c "$PREV_LOG_GZ" | jq -c --arg start_time "$START_TIME" 'select(. != null and .timestamp >= $start_time)' 2>> /tmp/jq_errors.log >> /tmp/logon_combined.json
elif [[ -f "$PREV_LOG" ]]; then
    echo "[$$] Using uncompressed previous day's alerts from $PREV_LOG"
    jq -c --arg start_time "$START_TIME" 'select(. != null and .timestamp >= $start_time)' "$PREV_LOG" 2>> /tmp/jq_errors.log >> /tmp/logon_combined.json
else
    echo "[$$] No previous alerts found. Using only current logs."
fi

jq -c --arg start_time "$START_TIME" 'select(. != null and .timestamp >= $start_time)' /var/ossec/logs/alerts/alerts.json 2>> /tmp/jq_errors.log >> /tmp/logon_combined.json

CRIT_EMOJI="🚨"
WARN_EMOJI="⚠️"
AGENT_EMOJI="🤖"
[[ "$ENABLE_EMOJIS" != true ]] && CRIT_EMOJI="" && WARN_EMOJI="" && AGENT_EMOJI=""

echo "[$$] Extracting login failure alerts..."

LOGIN_FAILURES_RAW=$(jq -r --arg start_time "$START_TIME" '
  select(
    (.rule.description | test("login|authentication"; "i")) or
    (.rule.groups | index("authentication_failed"))
  )
  | select(.rule.description | test("CIS"; "i") | not)
  | select((.rule.id | tonumber) as $id | [$id] | inside([92657, 112001, 5501, 5502, 5715, 92652]) | not)
  | select(.timestamp >= $start_time)
  | "\(.rule.level)|\(.rule.id)|\(.rule.description)"' /tmp/logon_combined.json)

LOGIN_FAILURES=$(echo "$LOGIN_FAILURES_RAW" | sort | uniq -c | sort -nr | head -n 10 | sed 's/^[[:space:]]*\([0-9]\+\) \(.*\)/\1|\2/')

CHART_LABELS=$(echo "$LOGIN_FAILURES" | cut -d'|' -f3- | sed 's/"/\\"/g' | awk '{print "\"" $0 "\""}' | paste -sd "," -)
CHART_COUNTS=$(echo "$LOGIN_FAILURES" | cut -d'|' -f1 | paste -sd "," -)

# Clean label format (remove quotes from labels)
LABELS_CLEAN=$(echo "$CHART_LABELS" | sed 's/"//g')
node render_pie_chart.js "$LABELS_CLEAN" "$CHART_COUNTS"

TOP_AGENTS=$(jq -r --arg start_time "$START_TIME" '
    select(
        (.rule.description | test("login|authentication"; "i")) or
        (.rule.groups | index("authentication_failed"))
    )
    | select(.rule.description | test("CIS"; "i") | not)
    | select((.rule.id | tonumber) as $id | [$id] | inside([92657, 112001, 5501, 5502, 5715, 92652]) | not)
    | select(.timestamp >= $start_time)
    | .agent.name
' /tmp/logon_combined.json | sort | uniq -c | sort -nr | head -n 10)

# HTML Header
cat <<EOF >> "$REPORT_FILE"
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; }
    h2 { color: #2c3e50; }
    table { border-collapse: collapse; width: 100%; }
    th, td { padding: 8px 12px; border: 1px solid #ccc; }
    th { background-color: #f5f5f5; }
    .critical { background-color: #ffe0e0; }
    .warning { background-color: #fff3cd; }
    .gray { color: gray; }
  </style>
</head>
<body>
<h2>$CRIT_EMOJI Wazuh Login Failure Report (Last 24 Hours)</h2>
EOF

# Pie Chart
if [[ -f /tmp/login_chart.png ]]; then
  echo "<h3>Login Failure Distribution (Top 10)</h3>" >> "$REPORT_FILE"
  echo "<img src=\"cid:loginchart\">" >> "$REPORT_FILE"
fi

# Login failures table
if [[ -z "$LOGIN_FAILURES" ]]; then
  echo "<p class='gray'>No login failures found in the last 24 hours.</p>" >> "$REPORT_FILE"
else
  echo "<h3>$WARN_EMOJI Top Login Failures</h3>" >> "$REPORT_FILE"
  echo "<table><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"
  echo "$LOGIN_FAILURES" | while IFS="|" read -r count level rule_id desc; do
    cls=$([[ "$level" -ge 12 ]] && echo "critical" || echo "warning")
    echo "<tr class=\"$cls\"><td>$count</td><td>$level</td><td>$rule_id</td><td>$desc</td></tr>"
  done >> "$REPORT_FILE"
  echo "</table>" >> "$REPORT_FILE"
fi

# Top agents
if [[ -z "$TOP_AGENTS" ]]; then
  echo "<p class='gray'>No agents reported login failures in the last 24 hours.</p>" >> "$REPORT_FILE"
else
  echo "<h3>$AGENT_EMOJI Top Agents (by login failure count)</h3>" >> "$REPORT_FILE"
  echo "<table><tr><th>Count</th><th>Agent Name</th></tr>" >> "$REPORT_FILE"
  echo "$TOP_AGENTS" | awk '{print "<tr><td>"$1"</td><td>"$2"</td></tr>"}' >> "$REPORT_FILE"
  echo "</table>" >> "$REPORT_FILE"
fi

# Footer
echo "<p style='font-size: 12px; color: lightgray;'>This is an automatically generated login failure report. Issues? Report on <a href='https://github.com/mootzen/wazuhMailReport/issues' target='_blank'>GitHub</a>.</p>" >> "$REPORT_FILE"
echo "</body></html>" >> "$REPORT_FILE"

(
echo "Subject: $LOGON_MAIL_SUBJECT"
echo "MIME-Version: 1.0"
echo "Content-Type: multipart/related; boundary=\"boundary42\""
echo
echo "--boundary42"
echo "Content-Type: text/html; charset=UTF-8"
echo "Content-Transfer-Encoding: 7bit"
echo
cat "$REPORT_FILE"
echo
echo "--boundary42"
echo "Content-Type: image/png"
echo "Content-Transfer-Encoding: base64"
echo "Content-ID: <loginchart>"
echo "Content-Disposition: inline; filename=\"login_chart.png\""
echo
base64 /tmp/login_chart.png
echo "--boundary42--"
) | sendmail -f "$LOGON_MAIL_FROM" "$LOGON_MAIL_TO"

cleanup() {
    echo "[$$] Cleaning up temporary files..."
    rm -f /tmp/logon_combined.json
}
trap cleanup EXIT
echo "[$$] Script execution completed successfully!"
