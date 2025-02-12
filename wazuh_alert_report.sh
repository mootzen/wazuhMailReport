#!/bin/bash

# Load configuration
CONFIG_FILE="/usr/local/wazuhMailReport/report.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file not found at $CONFIG_FILE. Using defaults."
fi

# Set defaults if not defined in config
LEVEL=${LEVEL:-12}
TIME_PERIOD=${TIME_PERIOD:-"24 hours"}
TOP_ALERTS_COUNT=${TOP_ALERTS_COUNT:-10}
MAIL_TO=${MAIL_TO:-"your@mail.com"}
MAIL_SUBJECT=${MAIL_SUBJECT:-"Wazuh Daily Report - $(date)"}
MAIL_FROM=${MAIL_FROM:-"reporter@wazuh"}
FONT=${FONT:-"Arial, sans-serif"}
HEADING_COLOR=${HEADING_COLOR:-"powderblue"}
ENABLE_EMOJI=${ENABLE_EMOJI:-1}
SHOW_METRICS=${SHOW_METRICS:-1}

# Check for manual email argument
if [ $# -gt 0 ]; then
    MAIL_TO=$1
fi

# Calculate the start time for filtering
START_TIME=$(date --date="$TIME_PERIOD ago" --utc +%Y-%m-%dT%H:%M:%SZ)

# Define output directory and file
OUTPUT_DIR="/var/ossec/logs/reports"
mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/daily_wazuh_report.html"

# Start HTML report
echo "<html><body style='font-family: $FONT;'>" > "$REPORT_FILE"

echo "<h2 style='color:$HEADING_COLOR;'>${ENABLE_EMOJI:+🔹} Daily Wazuh Report - $(date)</h2>" >> "$REPORT_FILE"
echo "<p>Hello Team,</p><p>Here's the daily Wazuh alert summary:</p>" >> "$REPORT_FILE"

if [ "$SHOW_METRICS" -eq 1 ]; then
    echo "<h3>${ENABLE_EMOJI:+📊} System Metrics</h3>" >> "$REPORT_FILE"
    echo "<table border='1' cellspacing='0' cellpadding='5'>" >> "$REPORT_FILE"
    echo "<tr><th>Metric</th><th>Value</th></tr>" >> "$REPORT_FILE"
    echo "<tr><td>CPU Usage</td><td>$(top -bn1 | grep 'Cpu(s)' | awk '{print 100 - $8"%"}')"</td></tr>" >> "$REPORT_FILE"
    echo "<tr><td>Memory Usage</td><td>$(free | grep Mem | awk '{print ($3/$2) * 100 "%"}')"</td></tr>" >> "$REPORT_FILE"
    echo "<tr><td>Network Usage</td><td>$(ip -s link show eth0 | awk 'NR==4 {print $1 " bytes received, " $2 " bytes sent"}')"</td></tr>" >> "$REPORT_FILE"
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
