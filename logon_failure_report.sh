#!/bin/bash
# Load mail config
CONFIG_FILE="./report.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[$$] ERROR: Config file '$CONFIG_FILE' not found."
    exit 1
fi

# Subject set dynamically
MAIL_SUBJECT="🚨 Wazuh Logon Report - $(date '+%Y-%m-%d %H:%M')"

# Other constants
REPORT_FILE="/tmp/wazuh_logon_failure_report.html"
START_TIME=$(date --utc -d "24 hours ago" +%Y-%m-%dT%H:%M:%SZ)
ENABLE_EMOJIS=true

# Verify mail settings
if [[ -z "$MAIL_TO" || -z "$MAIL_FROM" ]]; then
    echo "[$$] ERROR: MAIL_TO or MAIL_FROM is not set in config."
    exit 1
fi

if [[ -z "$MAIL_TO" || -z "$MAIL_FROM" || -z "$MAIL_SUBJECT" ]]; then
    echo "[$$] ERROR: MAIL_TO, MAIL_FROM, or MAIL_SUBJECT is not set."
    exit 1
fi

echo "[DEBUG] START_TIME set to $START_TIME"
echo "[DEBUG] Writing report to $REPORT_FILE"

# Log sources
YESTERDAY=$(date --date="yesterday" +%d)
LOG_DIR="/var/ossec/logs/alerts/$(date +%Y/%b)"
PREV_LOG="$LOG_DIR/ossec-alerts-$YESTERDAY.json"
PREV_LOG_GZ="$PREV_LOG.gz"

echo "[$$] Debug: Searching for logs in $LOG_DIR"

# Combine logs
touch /tmp/alerts_combined.json
echo "[$$] Extracting and merging logs using jq streaming..."

if [[ -f "$PREV_LOG_GZ" ]]; then
    echo "[$$] Extracting previous day's alerts from $PREV_LOG_GZ"
    gunzip -c "$PREV_LOG_GZ" | jq -c 'select(. != null and .timestamp >= "'$START_TIME'")' 2>> /tmp/jq_errors.log >> /tmp/alerts_combined.json
elif [[ -f "$PREV_LOG" ]]; then
    echo "[$$] Using uncompressed previous day's alerts from $PREV_LOG"
    jq -c 'select(. != null and .timestamp >= "'$START_TIME'")' "$PREV_LOG" 2>> /tmp/jq_errors.log >> /tmp/alerts_combined.json
else
    echo "[$$] No previous alerts found. Using only current logs."
fi

jq -c 'select(. != null and .timestamp >= "'$START_TIME'")' /var/ossec/logs/alerts/alerts.json 2>> /tmp/jq_errors.log >> /tmp/alerts_combined.json

# Emoji toggle
CRIT_EMOJI="🚨"
WARN_EMOJI="⚠️"
AGENT_EMOJI="🤖"
[[ "$ENABLE_EMOJIS" != true ]] && CRIT_EMOJI="" && WARN_EMOJI="" && AGENT_EMOJI=""

# Extract login failure alerts
echo "[$$] Extracting login failure alerts..."

LOGIN_FAILURES=$(jq -r '
    select(.rule.description | test("login|authentication"; "i")) 
    | select(.timestamp >= "'$START_TIME'")
    | "\(.rule.level)\t\(.rule.id)\t\(.rule.description)"' /tmp/alerts_combined.json |
    sort | uniq -c | sort -nr | head -n 10)

TOP_AGENTS=$(jq -r '
    select(.rule.description | test("login|authentication"; "i")) 
    | select(.timestamp >= "'$START_TIME'")
    | .agent.name' /tmp/alerts_combined.json | sort | uniq -c | sort -nr | head -n 10)

# HTML Header
echo "<html><head><style>
body { font-family: Arial, sans-serif; }
h2 { color: #2c3e50; }
table { border-collapse: collapse; width: 100%; }
th, td { padding: 8px 12px; border: 1px solid #ccc; }
th { background-color: #f5f5f5; }
.critical { background-color: #ffe0e0; }
.warning { background-color: #fff3cd; }
.gray { color: gray; }
</style></head><body>" > "$REPORT_FILE"

echo "<h2>$CRIT_EMOJI Wazuh Login Failure Report (Last 24 Hours)</h2>" >> "$REPORT_FILE"

# Login failures
if [[ -z "$LOGIN_FAILURES" ]]; then
    echo "<p class='gray'>No login failures found in the last 24 hours.</p>" >> "$REPORT_FILE"
else
    echo "<h3>$WARN_EMOJI Top Login Failures</h3>" >> "$REPORT_FILE"
    echo "<table><tr><th>Count</th><th>Level</th><th>Rule ID</th><th>Description</th></tr>" >> "$REPORT_FILE"
    echo "$LOGIN_FAILURES" | awk -v emojis=$ENABLE_EMOJIS '
    {
        level=$2;
        cls = (level >= 12) ? "critical" : "warning";
        print "<tr class=\"" cls "\"><td>" $1 "</td><td>" $2 "</td><td>" $3 "</td><td>" substr($0, index($0,$4)) "</td></tr>";
    }' >> "$REPORT_FILE"
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
echo "[$$] Sending email report..."

if sendmail -f "$MAIL_FROM" "$MAIL_TO" <<EOF
Subject: $MAIL_SUBJECT
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8

$(cat "$REPORT_FILE")
EOF
then
    echo "[$$] Email sent successfully."
else
    echo "[$$] ERROR: Failed to send email."
fi
