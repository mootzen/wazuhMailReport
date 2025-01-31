#!/bin/bash

# Variables
REPO_URL="https://github.com/mootzen/wazuhMailReport.git"
INSTALL_DIR="/usr/local/wazuhMailReport"
SCRIPT_NAME="report.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"
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

# Set permissions
chmod +x "$SCRIPT_PATH"

# Create cron job (runs daily at 10am)
echo "0 10 * * * root $SCRIPT_PATH" > "$CRON_JOB"
chmod 644 "$CRON_JOB"

# Done
echo "Installation complete! The script is installed at $SCRIPT_PATH and scheduled to run daily."
