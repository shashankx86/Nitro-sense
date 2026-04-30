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

usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  install     Install driver and TUI to ${INSTALL_DIR} and create 'nitros' command
  uninstall   Remove installed files and 'nitros' command
  launch      Launch the nitro-sense TUI (requires install first)
  help        Show this help message

Install actions:
  - Copies driver source to ${INSTALL_DIR}/driver and builds/installs kernel module
  - Copies TUI app to ${INSTALL_DIR}/app
  - Creates symlink ${BIN_DIR}/nitros -> ${INSTALL_DIR}/app/nitro_sense_tui.py
EOF
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

    if [ -e "${PROFILE_PATH:-/sys/firmware/acpi/platform_profile}" ]; then
        append_tmpfiles_entry "f /sys/firmware/acpi/platform_profile 0664 root ${ACCESS_GROUP}"
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

cmd_install() {
    require_root "$@"

    echo "==> Installing nitro-sense to ${INSTALL_DIR}..."

    # Create install directories
    mkdir -p "${INSTALL_DIR}/driver"
    mkdir -p "${INSTALL_DIR}/app"

    # Copy driver source
    echo "==> Copying driver source..."
    cp -r "${DRIVER_DIR}/." "${INSTALL_DIR}/driver/"

    # Build and install kernel module
    echo "==> Building kernel module..."
    make -C "${INSTALL_DIR}/driver"

    echo "==> Installing kernel module..."
    make -C "${INSTALL_DIR}/driver" install

    # Copy TUI app
    echo "==> Copying TUI app..."
    cp "${APP_DIR}/nitro_sense_tui.py" "${INSTALL_DIR}/app/nitro_sense_tui.py"
    chmod +x "${INSTALL_DIR}/app/nitro_sense_tui.py"

    # Create nitros command symlink
    echo "==> Creating 'nitros' command..."
    mkdir -p "${BIN_DIR}"
    ln -sf "${INSTALL_DIR}/app/nitro_sense_tui.py" "${BIN_DIR}/nitros"

    configure_non_root_access

    echo ""
    echo "==> Installation complete!"
    echo "    - Driver installed for kernel $(uname -r)"
    echo "    - Load module: sudo modprobe nitro_sense"
    echo "    - Run TUI: nitros"
}

cmd_uninstall() {
    require_root "$@"

    echo "==> Uninstalling nitro-sense..."

    # Uninstall kernel module
    if [ -d "${INSTALL_DIR}/driver" ]; then
        echo "==> Uninstalling kernel module..."
        make -C "${INSTALL_DIR}/driver" uninstall 2>/dev/null || true
    fi

    # Remove nitros command
    echo "==> Removing 'nitros' command..."
    rm -f "${BIN_DIR}/nitros"

    echo "==> Removing non-root access settings..."
    cleanup_non_root_access

    # Remove install directory
    echo "==> Removing ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"

    echo "==> Uninstallation complete."
    echo "    You may need to unload the module: sudo rmmod nitro_sense"
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
