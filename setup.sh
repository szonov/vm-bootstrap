#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

readonly REPO="szonov/vm-bootstrap"
readonly GITHUB_REF="main"
readonly BASE_URL="https://raw.githubusercontent.com/${REPO}/${GITHUB_REF}"

readonly GOST_VERSION="2.12.0"
readonly GOST_URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_amd64.tar.gz"

readonly SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgDS1XP+i0SnS/DHnBAlQcvhh0KL7nSvm4tBL/4TDQ6 vm"

if (( EUID != 0 )); then
    echo "This script must be run as root."
    echo
    echo "Run:"
    echo "  su -c \"wget -qO- ${BASE_URL}/setup.sh | bash\""
    exit 1
fi

REAL_USER="${SUDO_USER:-${USER:-}}"

if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
    echo "ERROR: Could not detect the regular user."
    echo
    echo "Run this script from your regular user account, for example:"
    echo "  su -c \"wget -qO- ${BASE_URL}/setup.sh | bash\""
    exit 1
fi

REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]]; then
    echo "ERROR: Could not detect home directory for user: $REAL_USER"
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "ERROR: /etc/os-release not found."
    exit 1
fi

. /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        echo "ERROR: Unsupported operating system."
        echo "Supported distributions: Debian, Ubuntu"
        exit 1
        ;;
esac

export DEBIAN_FRONTEND=noninteractive

echo
echo "== vm-bootstrap setup =="
echo "Operating system : ${PRETTY_NAME:-$ID}"
echo "Regular user    : ${REAL_USER}"
echo "Home directory  : ${REAL_HOME}"
echo

echo "== Updating system =="
apt update
apt full-upgrade -y

echo "== Installing base packages =="
apt install -y \
    sudo \
    qemu-guest-agent \
    locales \
    vim \
    mc \
    iptables-persistent \
    iputils-ping \
    net-tools \
    htop \
    duf \
    git \
    tcpdump \
    wget \
    ca-certificates

echo "== Configuring sudo access =="
usermod -aG sudo "$REAL_USER"

cat >/etc/sudoers.d/"$REAL_USER" <<EOF
$REAL_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF

chmod 440 /etc/sudoers.d/"$REAL_USER"

echo "== Configuring SSH authorized_keys =="
for home in "$REAL_HOME" /root; do
    install -d -m 700 "$home/.ssh"

    touch "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"

    if ! grep -Fxq "$SSH_PUBLIC_KEY" "$home/.ssh/authorized_keys"; then
        echo "$SSH_PUBLIC_KEY" >> "$home/.ssh/authorized_keys"
    fi
done

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.ssh"
chown -R root:root /root/.ssh

echo "== Creating .hushlogin =="
touch "$REAL_HOME/.hushlogin"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.hushlogin"

touch /root/.hushlogin
chown root:root /root/.hushlogin

echo "== Configuring locales =="
sed -i '/ru_RU.UTF-8/s/^# *//g' /etc/locale.gen
sed -i '/en_US.UTF-8/s/^# *//g' /etc/locale.gen
locale-gen

echo "== Configuring timezone =="
timedatectl set-timezone Asia/Novosibirsk

echo "== Enabling IPv4 forwarding =="
cat >/etc/sysctl.d/99-gateway.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl --system >/dev/null

echo "== Installing gost ${GOST_VERSION} =="
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if ! wget -qO "$tmpdir/gost.tar.gz" "$GOST_URL"; then
    echo "ERROR: Failed to download gost:"
    echo "  $GOST_URL"
    exit 1
fi

tar xzf "$tmpdir/gost.tar.gz" -C "$tmpdir"
install -m 0755 "$tmpdir/gost" /usr/local/bin/gost

echo "== Enabling qemu-guest-agent =="
systemctl enable --now qemu-guest-agent

echo "== Installing helper scripts =="
for script in prepare-template rename-host; do
    url="${BASE_URL}/${script}.sh"
    tmp="$(mktemp)"

    echo "  ${script}"

    if ! wget -qO "$tmp" "$url"; then
        echo "ERROR: Failed to download:"
        echo "  $url"
        rm -f "$tmp"
        exit 1
    fi

    if [[ ! -s "$tmp" ]]; then
        echo "ERROR: Downloaded file is empty:"
        echo "  $url"
        rm -f "$tmp"
        exit 1
    fi

    install -m 0755 "$tmp" "/usr/local/bin/${script}"
    rm -f "$tmp"
done

echo
echo "Installation completed successfully."
echo
echo "The following commands are now available:"
echo
echo "  prepare-template"
echo "  rename-host"
echo
echo "Before creating a VM template, run:"
echo "  prepare-template"
echo "  sudo poweroff"