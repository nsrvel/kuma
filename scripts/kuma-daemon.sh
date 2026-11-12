#!/usr/bin/env bash
# scripts/kuma-daemon.sh
# Management CLI for Kuma Daemon (build, install, uninstall, update, status, logs)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAEMON_DIR="${REPO_ROOT}/apps/daemon"

INSTALL_PREFIX="${KUMA_INSTALL_PREFIX:-${HOME}/.local/bin}"
BIN_NAME="kuma"
TARGET_BIN="${INSTALL_PREFIX}/${BIN_NAME}"
LAUNCH_AGENT_LABEL="com.kuma.daemon"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
DATA_DIR="${HOME}/Library/Application Support/Kuma"
LOG_OUT="${DATA_DIR}/daemon.log"
LOG_ERR="${DATA_DIR}/daemon.err.log"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}==>${NC} ${1}"; }
log_success() { echo -e "${GREEN}✔${NC} ${1}"; }
log_warn() { echo -e "${YELLOW}⚠${NC} ${1}"; }
log_error() { echo -e "${RED}✖${NC} ${1}"; }

ensure_dirs() {
    mkdir -p "${INSTALL_PREFIX}"
    mkdir -p "${DATA_DIR}"
    mkdir -p "${HOME}/Library/LaunchAgents"
}

check_in_path() {
    if ! echo "${PATH}" | tr ':' '\n' | grep -qx "${INSTALL_PREFIX}"; then
        log_warn "'${INSTALL_PREFIX}' is not in your \$PATH."
        log_warn "Add it by adding this line to your ~/.zshrc or ~/.bashrc:"
        echo -e "    ${YELLOW}export PATH=\"${INSTALL_PREFIX}:\$PATH\"${NC}"
    fi
}

cmd_build() {
    log_info "Building Kuma daemon & CLI (release mode)..."
    (
        cd "${DAEMON_DIR}"
        cargo build --release -p kuma-cli
    )
    log_success "Build complete: ${DAEMON_DIR}/target/release/${BIN_NAME}"
}

cmd_install() {
    cmd_build
    ensure_dirs

    log_info "Installing binary to ${TARGET_BIN}..."
    cp -f "${DAEMON_DIR}/target/release/${BIN_NAME}" "${TARGET_BIN}"
    chmod +x "${TARGET_BIN}"
    log_success "Binary installed at ${TARGET_BIN}"

    check_in_path

    log_info "Registering macOS LaunchAgent (${LAUNCH_AGENT_LABEL})..."
    cat <<EOF > "${PLIST_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TARGET_BIN}</string>
        <string>daemon</string>
        <string>run</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>KUMA_DATA_DIR</key>
        <string>${DATA_DIR}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_OUT}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_ERR}</string>
</dict>
</plist>
EOF

    # Stop any previous instance and reload
    launchctl bootout "gui/$(id -u)/${LAUNCH_AGENT_LABEL}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}" 2>/dev/null || launchctl load -w "${PLIST_PATH}"
    
    log_success "LaunchAgent registered and started."
    cmd_status
}

cmd_uninstall() {
    log_info "Stopping and removing LaunchAgent..."
    launchctl bootout "gui/$(id -u)/${LAUNCH_AGENT_LABEL}" 2>/dev/null || true
    launchctl unload -w "${PLIST_PATH}" 2>/dev/null || true
    rm -f "${PLIST_PATH}"
    log_success "LaunchAgent removed."

    if [ -f "${TARGET_BIN}" ]; then
        log_info "Removing binary ${TARGET_BIN}..."
        rm -f "${TARGET_BIN}"
        log_success "Binary removed."
    fi

    if [ "$1" == "--purge" ]; then
        log_warn "Purging data directory ${DATA_DIR}..."
        rm -rf "${DATA_DIR}"
        log_success "Data directory wiped."
    else
        log_info "Data kept at ${DATA_DIR} (use --purge to delete database & logs)."
    fi

    log_success "Kuma daemon uninstalled successfully."
}

cmd_update() {
    log_info "Updating Kuma daemon..."
    cmd_build
    log_info "Updating binary at ${TARGET_BIN}..."
    cp -f "${DAEMON_DIR}/target/release/${BIN_NAME}" "${TARGET_BIN}"
    
    log_info "Restarting daemon service..."
    cmd_restart
    log_success "Kuma daemon updated and restarted successfully."
}

cmd_start() {
    log_info "Starting daemon service..."
    if [ ! -f "${PLIST_PATH}" ]; then
        log_error "LaunchAgent plist not found. Please run '$0 install' first."
        exit 1
    fi
    launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}" 2>/dev/null || launchctl load -w "${PLIST_PATH}" 2>/dev/null || true
    log_success "Daemon started."
    cmd_status
}

cmd_stop() {
    log_info "Stopping daemon service..."
    launchctl bootout "gui/$(id -u)/${LAUNCH_AGENT_LABEL}" 2>/dev/null || launchctl unload -w "${PLIST_PATH}" 2>/dev/null || true
    log_success "Daemon stopped."
}

cmd_restart() {
    log_info "Restarting daemon..."
    cmd_stop
    sleep 1
    cmd_start
}

cmd_status() {
    echo ""
    log_info "Daemon status check:"
    local pid
    pid=$(pgrep -f "${TARGET_BIN} daemon run" || true)

    if [ -n "${pid}" ]; then
        log_success "Daemon is RUNNING (PID: ${pid})"
    else
        log_warn "Daemon process is NOT running."
    fi

    if [ -f "${PLIST_PATH}" ]; then
        echo -e "  LaunchAgent: ${GREEN}Installed${NC} (${PLIST_PATH})"
    else
        echo -e "  LaunchAgent: ${YELLOW}Not installed${NC}"
    fi

    if [ -f "${TARGET_BIN}" ]; then
        echo -e "  Binary:      ${GREEN}${TARGET_BIN}${NC}"
    else
        echo -e "  Binary:      ${YELLOW}Not installed${NC}"
    fi

    echo -e "  Data Dir:    ${DATA_DIR}"
    echo -e "  Log stdout:  ${LOG_OUT}"
    echo -e "  Log stderr:  ${LOG_ERR}"
    echo ""
}

cmd_logs() {
    log_info "Tailing daemon logs (Ctrl+C to stop)..."
    touch "${LOG_OUT}" "${LOG_ERR}"
    tail -f -n 50 "${LOG_OUT}" "${LOG_ERR}"
}

cmd_help() {
    cat <<EOF
Kuma Daemon Management Script

Usage: $(basename "$0") <command> [options]

Commands:
  install       Build release binary, install to ${INSTALL_PREFIX}, and register LaunchAgent
  uninstall     Unload LaunchAgent and remove binary (add --purge to also delete data)
  update        Rebuild release binary, overwrite installed binary, and restart service
  start         Start the background daemon service
  stop          Stop the background daemon service
  restart       Restart the background daemon service
  status        Show whether the daemon and LaunchAgent are active
  logs          Tail live daemon stdout and stderr logs
  build         Build release binary only without installing

Environment Variables:
  KUMA_INSTALL_PREFIX   Directory where binary is placed (default: ~/.local/bin)

Examples:
  $(basename "$0") install
  $(basename "$0") status
  $(basename "$0") logs
  $(basename "$0") update
  $(basename "$0") uninstall --purge
EOF
}

case "${1:-}" in
    install)
        cmd_install
        ;;
    uninstall)
        cmd_uninstall "${2:-}"
        ;;
    update)
        cmd_update
        ;;
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    restart)
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    build)
        cmd_build
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        cmd_help
        exit 1
        ;;
esac
