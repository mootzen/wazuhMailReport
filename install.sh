#!/bin/bash

# Variables
REPO_URL="https://github.com/mootzen/wazuhMailReport.git"
INSTALL_DIR="/usr/local/wazuhMailReport"
SCRIPT_NAME="wazuh_alert_report.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
CONFIG_FILE="$INSTALL_DIR/report.conf"
CRON_JOB="/etc/cron.d/wazuh_report"

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root!" >&2
    exit 1
fi

# Install dependencies (if needed)
apt update && apt install -y jq mailutils

# Clone or update repository
if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    cd "$INSTALL_DIR" && git pull
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Ensure config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Creating default configuration file..."
    cat <<EOL > "$CONFIG_FILE"
LEVEL=12
TIME_PERIOD="24 hours"
TOP_ALERTS_COUNT=10
MAIL_TO="your@mail.com"
MAIL_SUBJECT="Wazuh Daily Report - \$(date)"
MAIL_FROM="reporter@wazuh"
FONT="Arial, sans-serif"
HEADING_COLOR="powderblue"
ENABLE_EMOJI=1
SHOW_METRICS=1
EOL
    chmod 644 "$CONFIG_FILE"
fi

# Set permissions
chmod +x "$SCRIPT_PATH"

# Create cron job (runs daily at 10am)
echo "0 10 * * * root $SCRIPT_PATH" > "$CRON_JOB"
chmod 644 "$CRON_JOB"

# Done
echo "Installation complete! The script is installed at $SCRIPT_PATH and scheduled to run daily."
