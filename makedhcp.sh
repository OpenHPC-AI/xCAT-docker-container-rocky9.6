#!/bin/bash
#
# Optimized DHCP setup script for xCAT
# Author: [Your Name] - CDAC
# Usage: Called during DHCP container or node init
set -e  # Exit on any command failure

LOGFILE="/var/log/makedhcp.log"
exec >> "$LOGFILE" 2>&1

echo "[$(date)] Starting DHCP configuration script..."

# Function to check if xCAT service is running
wait_for_xcat() {
    echo "Waiting for xCAT service to be ready..."

    while true; do
            if ps aux | grep -q "[x]catd: SSL listener"; then
                echo "xCAT service is running (via ps check)."
                break
            fi
        echo "xCAT not ready yet. Retrying in 30 seconds..."
        sleep 30
    done
}

# Proceed only if DHCP config file exists
if [[ -f /etc/dhcp/dhcpd.conf ]]; then
    wait_for_xcat

    echo "Running makehosts..."
    makehosts

    echo "Running makedhcp -n..."
    makedhcp -n

    echo "Starting dhcpd with nohup..."
    /etc/init.d/dhcpd start >> /var/log/dhcpd.out 2>&1 &
    echo "DHCP server started with PID $!"

else
    echo "[ERROR] /etc/dhcp/dhcpd.conf not found. Aborting DHCP setup."
    exit 1
fi

echo "[$(date)] DHCP configuration script completed."

