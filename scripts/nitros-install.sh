#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/nitro-sense"
BIN_DIR="/usr/local/bin"
DRIVER_DIR="$(cd "$(dirname "$0")/../driver" && pwd)"
APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
