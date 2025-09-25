#!/bin/bash

CONF_FILE="/etc/wifi.conf"

# Check if config file exists
if [ ! -f "$CONF_FILE" ]; then
    echo "Config file $CONF_FILE not found"
    exit 1
fi

# Read ssid and password from config
SSID=$(grep -E '^ssid=' "$CONF_FILE" | cut -d'=' -f2-)
PASSWORD=$(grep -E '^password=' "$CONF_FILE" | cut -d'=' -f2-)

if [ -z "$SSID" ] || [ -z "$PASSWORD" ]; then
    echo "Missing ssid or password in $CONF_FILE"
    exit 1
fi

echo "Trying to connect to Wi-Fi: $SSID"

# Check if a connection with the same SSID already exists
if nmcli connection show | grep -q "$SSID"; then
    echo "Existing connection found, deleting..."
    nmcli connection delete "$SSID"
fi

# Attempt to connect
nmcli device wifi connect "$SSID" password "$PASSWORD"

if [ $? -eq 0 ]; then
    echo "Successfully connected to $SSID"
else
    echo "Failed to connect to $SSID"
    exit 1
fi