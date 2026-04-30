#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/nitro-sense"
BIN_DIR="/usr/local/bin"
DRIVER_DIR="$(cd "$(dirname "$0")/../driver" && pwd)"
APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_NAME="nitro_sense"
SYSFS_BASE="/sys/module/${MODULE_NAME}/drivers/platform:acer-wmi/acer-wmi"
ACCESS_GROUP="${MODULE_NAME}"
TMPFILES_CONF="/etc/tmpfiles.d/${MODULE_NAME}.conf"
PLATFORM_PROFILE_PATH="/sys/firmware/acpi/platform_profile"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [all|app|driver]

Commands:
  install     Install all components by default, or only app/driver
  uninstall   Remove all components by default, or only app/driver
  launch      Launch the nitro-sense TUI (requires install first)
  help        Show this help message

Install actions:
  - Copies driver source to ${INSTALL_DIR}/driver and builds/installs kernel module
  - Copies TUI app to ${INSTALL_DIR}/app
  - Creates symlink ${BIN_DIR}/nitros -> ${INSTALL_DIR}/app/nitro_sense_tui.py

Examples:
  sudo $(basename "$0") install
  sudo $(basename "$0") install app
  sudo $(basename "$0") uninstall driver
EOF
}

component_name() {
    local component="${1:-all}"

    case "${component}" in
        all|app|driver)
            printf '%s\n' "${component}"
            ;;
        *)
            echo "Error: Unknown component '${component}'. Use one of: all, app, driver." >&2
            exit 1
            ;;
    esac
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This command requires root privileges." >&2
        echo "Run with: sudo $(basename "$0") $*" >&2
        exit 1
    fi
}

real_user() {
    if [ -n "${SUDO_USER:-}" ]; then
        printf '%s\n' "${SUDO_USER}"
    else
        id -un
    fi
}

append_tmpfiles_entry() {
    local entry="$1"
    touch "${TMPFILES_CONF}"
    if ! grep -qxF "${entry}" "${TMPFILES_CONF}"; then
        printf '%s\n' "${entry}" >> "${TMPFILES_CONF}"
    fi
}

configure_non_root_access() {
    local user
    user="$(real_user)"

    echo "==> Configuring non-root access for '${user}'..."

    if ! getent group "${ACCESS_GROUP}" >/dev/null; then
        groupadd "${ACCESS_GROUP}"
    fi

    if [ "${user}" != "root" ]; then
        usermod -aG "${ACCESS_GROUP}" "${user}"
    fi

    touch "${TMPFILES_CONF}"

    local model
    model=""
    if [ -d "${SYSFS_BASE}/predator_sense" ]; then
        model="predator_sense"
    elif [ -d "${SYSFS_BASE}/nitro_sense" ]; then
        model="nitro_sense"
    fi

    if [ -n "${model}" ]; then
        local model_path
        model_path="${SYSFS_BASE}/${model}"
        local model_fields
        model_fields=(
            "backlight_timeout"
            "battery_calibration"
            "battery_limiter"
            "boot_animation_sound"
            "fan_speed"
            "lcd_override"
            "usb_charging"
        )

        local field
        for field in "${model_fields[@]}"; do
            if [ -e "${model_path}/${field}" ]; then
                append_tmpfiles_entry "f ${model_path}/${field} 0660 root ${ACCESS_GROUP}"
            fi
        done

        if [ -d "${SYSFS_BASE}/four_zoned_kb" ]; then
            local kb_field
            for kb_field in "four_zone_mode" "per_zone_mode"; do
                if [ -e "${SYSFS_BASE}/four_zoned_kb/${kb_field}" ]; then
                    append_tmpfiles_entry "f ${SYSFS_BASE}/four_zoned_kb/${kb_field} 0660 root ${ACCESS_GROUP}"
                fi
            done
        fi
    else
        echo "    ! Warning: ${MODULE_NAME} sysfs model path not found yet;"
        echo "      load module first and re-run: sudo systemd-tmpfiles --create ${TMPFILES_CONF}"
    fi

    if [ -e "${PLATFORM_PROFILE_PATH}" ]; then
        append_tmpfiles_entry "f ${PLATFORM_PROFILE_PATH} 0664 root ${ACCESS_GROUP}"
    fi

    systemd-tmpfiles --create "${TMPFILES_CONF}" || true

    if [ "${user}" != "root" ]; then
        echo "    - Added ${user} to group ${ACCESS_GROUP}"
        echo "    - You may need to log out/in (or run: newgrp ${ACCESS_GROUP})"
    fi
}

cleanup_non_root_access() {
    local user
    user="$(real_user)"

    rm -f "${TMPFILES_CONF}"

    if getent group "${ACCESS_GROUP}" >/dev/null; then
        if [ "${user}" != "root" ]; then
            gpasswd -d "${user}" "${ACCESS_GROUP}" >/dev/null 2>&1 || true
        fi
        groupdel "${ACCESS_GROUP}" >/dev/null 2>&1 || true
    fi
}

cleanup_install_dir() {
    rmdir "${INSTALL_DIR}/app" 2>/dev/null || true
    rmdir "${INSTALL_DIR}/driver" 2>/dev/null || true
    rmdir "${INSTALL_DIR}" 2>/dev/null || true
}

install_driver() {
    mkdir -p "${INSTALL_DIR}/driver"

    echo "==> Copying driver source..."
    cp -r "${DRIVER_DIR}/." "${INSTALL_DIR}/driver/"

    echo "==> Building kernel module..."
    make -C "${INSTALL_DIR}/driver"

    echo "==> Installing kernel module..."
    make -C "${INSTALL_DIR}/driver" install

    configure_non_root_access
}

install_app() {
    mkdir -p "${INSTALL_DIR}/app"

    echo "==> Copying TUI app..."
    cp "${APP_DIR}/nitro_sense_tui.py" "${INSTALL_DIR}/app/nitro_sense_tui.py"
    chmod +x "${INSTALL_DIR}/app/nitro_sense_tui.py"

    echo "==> Creating 'nitros' command..."
    mkdir -p "${BIN_DIR}"
    ln -sf "${INSTALL_DIR}/app/nitro_sense_tui.py" "${BIN_DIR}/nitros"
}

uninstall_driver() {
    if [ -d "${INSTALL_DIR}/driver" ]; then
        echo "==> Uninstalling kernel module..."
        make -C "${INSTALL_DIR}/driver" uninstall 2>/dev/null || true
        rm -rf "${INSTALL_DIR}/driver"
    fi

    echo "==> Removing non-root access settings..."
    cleanup_non_root_access
}

uninstall_app() {
    echo "==> Removing 'nitros' command..."
    rm -f "${BIN_DIR}/nitros"
    rm -rf "${INSTALL_DIR}/app"
}

cmd_install() {
    require_root "$@"

    local component
    component="$(component_name "${2:-all}")"

    echo "==> Installing '${component}' to ${INSTALL_DIR}..."

    case "${component}" in
        all)
            install_driver
            install_app
            ;;
        driver)
            install_driver
            ;;
        app)
            install_app
            ;;
    esac

    echo ""
    echo "==> Installation complete!"

    if [ "${component}" = "all" ] || [ "${component}" = "driver" ]; then
        echo "    - Driver installed for kernel $(uname -r)"
        echo "    - Load module: sudo modprobe nitro_sense"
    fi

    if [ "${component}" = "all" ] || [ "${component}" = "app" ]; then
        echo "    - Run TUI: nitros"
    fi
}

cmd_uninstall() {
    require_root "$@"

    local component
    component="$(component_name "${2:-all}")"

    echo "==> Uninstalling '${component}' from ${INSTALL_DIR}..."

    case "${component}" in
        all)
            uninstall_app
            uninstall_driver
            ;;
        driver)
            uninstall_driver
            ;;
        app)
            uninstall_app
            ;;
    esac

    cleanup_install_dir

    echo "==> Uninstallation complete."

    if [ "${component}" = "all" ] || [ "${component}" = "driver" ]; then
        echo "    You may need to unload the module: sudo rmmod nitro_sense"
    fi
}

cmd_launch() {
    if [ ! -f "${INSTALL_DIR}/app/nitro_sense_tui.py" ]; then
        echo "Error: TUI not found. Run 'sudo $(basename "$0") install' first." >&2
        exit 1
    fi
    python3 "${INSTALL_DIR}/app/nitro_sense_tui.py"
}

case "${1:-help}" in
    install)
        cmd_install "$@"
        ;;
    uninstall)
        cmd_uninstall "$@"
        ;;
    launch|tui|run)
        cmd_launch
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Error: Unknown command '$1'" >&2
        echo "" >&2
        usage
        exit 1
        ;;
esac
