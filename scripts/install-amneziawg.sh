#!/usr/bin/env bash

# Установка kernel-модуля AmneziaWG и amneziawg-tools.
#
# Поддерживаемые ОС:
#   - Debian
#   - Ubuntu
#
# Требования:
#   - запуск от root;
#   - наличие пакета linux-headers-$(uname -r);
#   - обычная VM или физическая машина, не WSL.
#
# Конфигурации:
#   /etc/amnezia/amneziawg/*.conf

set -Eeuo pipefail

readonly AWG_MODULE_REPO="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git"
readonly AWG_TOOLS_REPO="https://github.com/amnezia-vpn/amneziawg-tools.git"

readonly SOURCE_DIR="/usr/local/src"
readonly MODULE_DIR="${SOURCE_DIR}/amneziawg-linux-kernel-module"
readonly TOOLS_DIR="${SOURCE_DIR}/amneziawg-tools"

readonly DKMS_MODULE="amneziawg"
readonly DKMS_VERSION="1.0.0"

readonly KERNEL_VERSION="$(uname -r)"
readonly HEADERS_PACKAGE="linux-headers-${KERNEL_VERSION}"

log() {
    printf '\n\033[1;32m==>\033[0m %s\n' "$*"
}

warn() {
    printf '\n\033[1;33mWARNING:\033[0m %s\n' "$*" >&2
}

error() {
    printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
}

on_error() {
    local exit_code=$?
    local line_number=$1

    error "Команда завершилась с ошибкой в строке ${line_number}."
    exit "${exit_code}"
}

trap 'on_error "${LINENO}"' ERR

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        error "Запусти скрипт от root."
        exit 1
    fi
}

detect_os() {
    if [[ ! -r /etc/os-release ]]; then
        error "Не удалось определить операционную систему."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID:-}" in
        debian|ubuntu)
            ;;
        *)
            error "Поддерживаются только Debian и Ubuntu."
            error "Обнаружена система: ${PRETTY_NAME:-unknown}."
            exit 1
            ;;
    esac

    if ! command -v apt-get >/dev/null 2>&1; then
        error "Команда apt-get не найдена."
        exit 1
    fi

    if ! command -v dpkg >/dev/null 2>&1; then
        error "Команда dpkg не найдена."
        exit 1
    fi

    log "Система: ${PRETTY_NAME:-unknown}"
    log "Текущее ядро: ${KERNEL_VERSION}"
    log "Архитектура: $(dpkg --print-architecture)"
}

check_virtualization() {
    if [[ -e /proc/sys/kernel/osrelease ]] &&
       grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease; then
        error "Установка kernel-модуля AmneziaWG в WSL не поддерживается."
        exit 1
    fi
}

install_dependencies() {
    log "Обновление списка пакетов"
    apt-get update

    if ! apt-cache show "${HEADERS_PACKAGE}" >/dev/null 2>&1; then
        error "Не найден пакет ${HEADERS_PACKAGE}."
        error "Возможно, используется нестандартное ядро или требуется перезагрузка после обновления ядра."
        error "Текущее ядро: ${KERNEL_VERSION}"
        exit 1
    fi

    log "Установка зависимостей"

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        git \
        build-essential \
        dkms \
        pkg-config \
        libmnl-dev \
        "${HEADERS_PACKAGE}" \
        bash \
        iproute2 \
        iptables \
        kmod

    if [[ ! -e "/lib/modules/${KERNEL_VERSION}/build/Makefile" ]]; then
        error "Не найдены заголовочные файлы для текущего ядра ${KERNEL_VERSION}."
        error "Проверь пакет ${HEADERS_PACKAGE}."
        exit 1
    fi
}

get_default_branch() {
    local repository_dir=$1
    local default_branch

    default_branch="$(
        git -C "${repository_dir}" symbolic-ref \
            --quiet \
            --short \
            refs/remotes/origin/HEAD 2>/dev/null \
            || true
    )"

    default_branch="${default_branch#origin/}"

    if [[ -z "${default_branch}" ]]; then
        default_branch="$(
            git -C "${repository_dir}" remote show origin 2>/dev/null \
                | sed -n 's/^[[:space:]]*HEAD branch: //p' \
                | head -n 1
        )"
    fi

    if [[ -z "${default_branch}" ]]; then
        default_branch="master"
    fi

    printf '%s\n' "${default_branch}"
}

update_repository() {
    local repository_url=$1
    local repository_dir=$2
    local repository_name=$3
    local default_branch

    log "Загрузка исходников ${repository_name}"

    if [[ -d "${repository_dir}/.git" ]]; then
        git -C "${repository_dir}" remote set-url origin "${repository_url}"
        git -C "${repository_dir}" fetch origin --tags --prune

        default_branch="$(get_default_branch "${repository_dir}")"

        log "Основная ветка ${repository_name}: ${default_branch}"

        git -C "${repository_dir}" checkout -B \
            "${default_branch}" \
            "origin/${default_branch}"

        git -C "${repository_dir}" reset --hard \
            "origin/${default_branch}"

        git -C "${repository_dir}" clean -ffd
    else
        rm -rf "${repository_dir}"
        git clone "${repository_url}" "${repository_dir}"
    fi
}

install_kernel_module() {
    update_repository \
        "${AWG_MODULE_REPO}" \
        "${MODULE_DIR}" \
        "модуля AmneziaWG"

    if [[ ! -f "${MODULE_DIR}/src/Makefile" ]]; then
        error "В репозитории модуля не найден ${MODULE_DIR}/src/Makefile."
        exit 1
    fi

    log "Подготовка исходников AmneziaWG для DKMS"

    make -C "${MODULE_DIR}/src" dkms-install

    log "Проверка регистрации модуля в DKMS"

    if ! dkms status "${DKMS_MODULE}/${DKMS_VERSION}" 2>/dev/null \
        | grep -qE 'added|built|installed'; then
        dkms add \
            -m "${DKMS_MODULE}" \
            -v "${DKMS_VERSION}"
    fi

    log "Сборка модуля для ядра ${KERNEL_VERSION}"

    if ! dkms status "${DKMS_MODULE}/${DKMS_VERSION}" 2>/dev/null \
        | grep -F "${KERNEL_VERSION}" \
        | grep -q "installed"; then

        dkms build \
            -m "${DKMS_MODULE}" \
            -v "${DKMS_VERSION}" \
            -k "${KERNEL_VERSION}"

        dkms install \
            -m "${DKMS_MODULE}" \
            -v "${DKMS_VERSION}" \
            -k "${KERNEL_VERSION}"
    else
        log "Модуль уже установлен для ядра ${KERNEL_VERSION}"
    fi

    log "Обновление зависимостей модулей"
    depmod -a "${KERNEL_VERSION}"

    log "Настройка автоматической загрузки модуля"
    printf '%s\n' "${DKMS_MODULE}" \
        > "/etc/modules-load.d/${DKMS_MODULE}.conf"

    if lsmod | grep -q "^${DKMS_MODULE}[[:space:]]"; then
        log "Модуль ${DKMS_MODULE} уже загружен"
    else
        log "Загрузка модуля ${DKMS_MODULE}"
        modprobe "${DKMS_MODULE}"
    fi
}

install_tools() {
    update_repository \
        "${AWG_TOOLS_REPO}" \
        "${TOOLS_DIR}" \
        "amneziawg-tools"

    if [[ ! -f "${TOOLS_DIR}/src/Makefile" ]]; then
        error "В репозитории tools не найден ${TOOLS_DIR}/src/Makefile."
        exit 1
    fi

    log "Сборка awg и awg-quick"

    make -C "${TOOLS_DIR}/src" clean
    make -C "${TOOLS_DIR}/src"

    log "Установка awg, awg-quick и systemd unit-файлов"

    make -C "${TOOLS_DIR}/src" install \
        PREFIX=/usr \
        WITH_WGQUICK=yes \
        WITH_SYSTEMDUNITS=yes \
        WITH_BASHCOMPLETION=yes

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
    fi
}

create_config_directory() {
    log "Создание каталога конфигурации"
    install -d -m 0700 /etc/amnezia/amneziawg
}

verify_installation() {
    log "Проверка установки"

    if ! command -v awg >/dev/null 2>&1; then
        error "Команда awg не найдена."
        exit 1
    fi

    if ! command -v awg-quick >/dev/null 2>&1; then
        error "Команда awg-quick не найдена."
        exit 1
    fi

    if ! modinfo "${DKMS_MODULE}" >/dev/null 2>&1; then
        error "Информация о модуле ${DKMS_MODULE} недоступна."
        exit 1
    fi

    if ! lsmod | grep -q "^${DKMS_MODULE}[[:space:]]"; then
        error "Модуль ${DKMS_MODULE} установлен, но не загружен."
        exit 1
    fi
}

print_result() {
    printf '\n'
    printf 'Установка завершена успешно.\n\n'

    printf 'Система:\n'
    printf '  %s\n' "${PRETTY_NAME:-unknown}"

    printf '\nЯдро:\n'
    printf '  %s\n' "${KERNEL_VERSION}"

    printf '\nВерсия tools:\n'
    awg --version || true

    printf '\nDKMS:\n'
    dkms status | grep "${DKMS_MODULE}" || true

    printf '\nМодуль:\n'
    modinfo "${DKMS_MODULE}" \
        | grep -E '^(filename|version|description|vermagic):' \
        || true

    printf '\nЗагруженные модули:\n'
    lsmod \
        | grep -E '^(amneziawg|udp_tunnel|ip6_udp_tunnel)[[:space:]]' \
        || true

    printf '\nИсполняемые файлы:\n'
    printf '  awg:       %s\n' "$(command -v awg)"
    printf '  awg-quick: %s\n' "$(command -v awg-quick)"

    printf '\nКаталог конфигурации:\n'
    printf '  /etc/amnezia/amneziawg/\n'

    printf '\nПример запуска:\n'
    printf '  awg-quick up amn0\n'
    printf '  systemctl enable --now awg-quick@amn0\n'
}

main() {
    require_root
    detect_os
    check_virtualization

    mkdir -p "${SOURCE_DIR}"

    install_dependencies
    install_kernel_module
    install_tools
    create_config_directory
    verify_installation
    print_result
}

main "$@"
