#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    exec sudo "$0" "$@"
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

export DEBIAN_FRONTEND=noninteractive

echo "== Updating system =="
apt update
apt full-upgrade -y

echo "== Removing unused packages and cleaning APT cache =="
apt autoremove --purge -y
apt clean
rm -rf /var/lib/apt/lists/*

echo "== Removing SSH host keys =="
rm -f /etc/ssh/ssh_host_*

cat >/etc/systemd/system/regenerate-ssh-host-keys.service <<'EOF'
[Unit]
Description=Regenerate SSH host keys on first boot
Before=ssh.service
ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF

systemctl enable regenerate-ssh-host-keys.service

echo "== Cleaning machine-id =="
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

echo "== Cleaning cloud-init state if installed =="
if command -v cloud-init >/dev/null 2>&1; then
    cloud-init clean --logs
fi

echo "== Cleaning DHCP leases =="
rm -f /var/lib/systemd/netif/leases/*
rm -f /var/lib/NetworkManager/*.lease 2>/dev/null || true

echo "== Cleaning logs =="
journalctl --rotate || true
journalctl --vacuum-time=1s || true
find /var/log -type f -exec truncate -s 0 {} \; || true

echo "== Cleaning temporary files =="
rm -rf /tmp/*
rm -rf /var/tmp/*

echo "== Cleaning user history and cache files =="
for home in "$REAL_HOME" /root; do
    rm -f "$home/.bash_history"
    rm -f "$home/.zsh_history"
    rm -f "$home/.lesshst"
    rm -f "$home/.viminfo"
    rm -f "$home/.wget-hsts"
    rm -f "$home/.python_history"
    rm -f "$home/.sqlite_history"
done

echo "== Syncing disks =="
sync

echo
echo "Template preparation completed."
echo "Now shut down the VM and use it as a template:"
echo "  sudo poweroff"