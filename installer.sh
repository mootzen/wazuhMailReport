#!/bin/bash

# Define installation directory
INSTALL_DIR="/opt/wazuh-alert-report"
SCRIPT_NAME="wazuh_alert_report.sh"
CONFIG_FILE="config.sh"
CRON_JOB="/etc/cron.d/wazuh_alert_report"

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root!" >&2
    exit 1
fi

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Copy the main script
cp "$SCRIPT_NAME" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Create a configuration file if it doesn't exist
if [ ! -f "$INSTALL_DIR/$CONFIG_FILE" ]; then
    cat <<EOL > "$INSTALL_DIR/$CONFIG_FILE"
# Wazuh Alert Report Configuration
LEVEL=12  # Rule level threshold for critical alerts
TIME_PERIOD="24 hours"  # Time period for alerts
TOP_ALERTS_COUNT=10  # Number of top alerts to display
MAIL_TO="your@mail.com"  # Recipient email address
MAIL_FROM="reporter@wazuh"  # Sender email address
EOL
fi

# Install required dependencies
apt-get update && apt-get install -y jq sendmail

# Set up cron job (runs daily at 08:00 AM)
echo "0 8 * * * root $INSTALL_DIR/$SCRIPT_NAME" > "$CRON_JOB"
chmod 644 "$CRON_JOB"

# Completion message
echo "Installation complete!"
echo "Edit the config file at $INSTALL_DIR/$CONFIG_FILE to customize settings."
echo "Logs can be found in /var/ossec/logs/reports/"
