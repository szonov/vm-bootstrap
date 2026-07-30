#!/usr/bin/env bash

set -Eeuo pipefail

readonly SINGBOX_VERSION="v1.14.0-beta.3"

log() {
    printf '\n\033[1;32m==>\033[0m %s\n' "$*"
}

error() {
    printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
}

on_error() {
    local exit_code=$?
    error "Command failed on line $1."
    exit "${exit_code}"
}

trap 'on_error "${LINENO}"' ERR

if [[ ${EUID} -ne 0 ]]; then
    error "Please run this script as root."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    error "Unable to detect the operating system."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        error "Unsupported operating system: ${PRETTY_NAME:-unknown}"
        exit 1
        ;;
esac

case "$(dpkg --print-architecture)" in
    amd64)
        readonly ARCH="amd64"
        ;;
    arm64)
        readonly ARCH="arm64"
        ;;
    *)
        error "Unsupported architecture: $(dpkg --print-architecture)"
        exit 1
        ;;
esac

log "Installing dependencies"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl

readonly PACKAGE="sing-box_${SINGBOX_VERSION#v}_linux_${ARCH}.deb"
readonly URL="https://github.com/SagerNet/sing-box/releases/download/${SINGBOX_VERSION}/${PACKAGE}"

TMP_DIR="$(mktemp -d)"
readonly TMP_DIR

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

log "Downloading ${PACKAGE}"

curl -fL \
    --retry 3 \
    --retry-delay 2 \
    --output "${TMP_DIR}/${PACKAGE}" \
    "${URL}"

log "Installing sing-box ${SINGBOX_VERSION}"

dpkg -i "${TMP_DIR}/${PACKAGE}"

log "Done"

sing-box version
