#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    exec sudo "$0" "$@"
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

NEW_HOSTNAME="$1"

echo "Changing hostname to '${NEW_HOSTNAME}'..."

hostnamectl set-hostname "$NEW_HOSTNAME"

if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 ${NEW_HOSTNAME}/" /etc/hosts
else
    echo "127.0.1.1 ${NEW_HOSTNAME}" | tee -a /etc/hosts >/dev/null
fi

echo
echo "Hostname changed."
echo "Current hostname: $(hostname)"
echo
echo "Reconnect via SSH to see the new hostname in your shell prompt."