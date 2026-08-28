#!/bin/sh
set -e
set -x

BASEDIR=$(dirname "$0")
cd $BASEDIR

if [ "$EUID" -ne 0 ]; then
  echo "[Warning] Tun script not running as root"
fi

# On macOS, sing-box creates the utun device and manages routes itself
# when running as root; no iptables/ip-route preparation is needed.
exec "./nekobox_core" run -c "$CONFIG_PATH"
