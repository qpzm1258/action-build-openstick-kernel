#!/usr/bin/env bash
set -euo pipefail

IFACE="can0"
BT="1000000"
DBT="4000000"
TXQ="256"

# Auto setup canfd to can0
if /sbin/ip link set ${IFACE} up type can bitrate ${BT} dbitrate ${DBT} fd on; then
        echo "[INFO] Try to setup ${IFACE} with FD mode (bitrate=${BT}, dbitrate=${DBT})"
        /sbin/ifconfig ${IFACE} txqueuelen ${TXQ}
else
        echo "[WARN] Failed to setup FD mode and setup CAN 2.0 (bitrate=${BT})"
        /sbin/ip link set ${IFACE} up type can bitrate ${BT}
        /sbin/ifconfig ${IFACE} txqueuelen ${TXQ}
fi

