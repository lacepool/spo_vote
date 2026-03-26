#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="${REPO_OWNER:-lacepool}"
REPO_NAME="${REPO_NAME:-spo_vote}"
REPO_REF="${REPO_REF:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}}"

DESTDIR="${DESTDIR:-}"
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-${PREFIX}/bin}"
ETCDIR="${ETCDIR:-/etc}"
APPDIR="${APPDIR:-/var/lib/spo-vote}"
TMPDIR="${TMPDIR:-/tmp/spo-vote}"

TARGET_BIN="${DESTDIR}${BINDIR}/spo_vote"
TARGET_CONFIG="${DESTDIR}${ETCDIR}/spo_vote.conf"
TARGET_APPDIR="${DESTDIR}${APPDIR}"
TARGET_TMPDIR="${DESTDIR}${TMPDIR}"

MODE="${1:-}"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Required command not found: $1"
    exit 1
  fi
}

require_linux() {
  local os

  os="$(uname -s)"
  if [ "$os" != "Linux" ]; then
    echo "Error: This installer supports Linux only."
    exit 1
  fi
}

run_as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  else
    need_command sudo
    sudo "$@"
  fi
}

download_file() {
  local url="$1"
  local destination="$2"

  curl -fsSL "$url" -o "$destination"
}

install_from_dir() {
  local source_dir="$1"

  run_as_root install -d "${DESTDIR}${BINDIR}"
  run_as_root install -d "${DESTDIR}${ETCDIR}"
  run_as_root install -d "${TARGET_APPDIR}/keys"
  run_as_root install -d "${TARGET_APPDIR}/tx"
  run_as_root install -d "${TARGET_TMPDIR}"
  run_as_root install -m 0755 "${source_dir}/spo_vote.sh" "$TARGET_BIN"

  if run_as_root test -f "$TARGET_CONFIG"; then
    echo "Keeping existing config at $TARGET_CONFIG"
  else
    run_as_root install -m 0644 "${source_dir}/spo_vote.conf.example" "$TARGET_CONFIG"
    echo "Installed default config to $TARGET_CONFIG"
  fi

  cat <<EOF
Installed spo_vote to $TARGET_BIN

Next steps:
1. Edit $TARGET_CONFIG to match your node paths and network.
2. Place your key files under ${TARGET_APPDIR}/keys or update the config paths.
3. Ensure these commands are installed and on PATH: gum, jq, cardano-cli
4. Run: spo_vote
EOF
}

remote_install() {
  require_linux
  need_command curl
  need_command install
  need_command mktemp

  local workdir
  workdir="$(mktemp -d)"
  trap "rm -rf '$workdir'" EXIT

  echo "Downloading spo_vote files from ${REPO_OWNER}/${REPO_NAME}@${REPO_REF}..."
  download_file "${RAW_BASE}/spo_vote.sh" "${workdir}/spo_vote.sh"
  download_file "${RAW_BASE}/spo_vote.conf.example" "${workdir}/spo_vote.conf.example"
  install_from_dir "$workdir"
}

local_install() {
  require_linux
  need_command install

  if [ ! -f "$SCRIPT_DIR/spo_vote.sh" ] || [ ! -f "$SCRIPT_DIR/spo_vote.conf.example" ]; then
    echo "Error: Local install requires install.sh to be run from a checked-out repo."
    exit 1
  fi

  install_from_dir "$SCRIPT_DIR"
}

uninstall() {
  require_linux
  run_as_root rm -f "$TARGET_BIN"
  run_as_root rm -f "$TARGET_CONFIG"
}

check() {
  require_linux
  need_command gum
  need_command jq
  need_command cardano-cli
}

check_config() {
  require_linux
  if [ ! -f "$TARGET_CONFIG" ]; then
    echo "Error: Config file not found: $TARGET_CONFIG"
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: $0 [install|remote-install|uninstall|check|check-config]

Commands:
- install: install from the current checked-out repo
- remote-install: download files from GitHub and install them
- uninstall: remove the installed script and config
- check: verify gum, jq, and cardano-cli are available on PATH
- check-config: verify the configured spo_vote.conf exists

Platform support:
- Linux only

Environment overrides:
- DESTDIR, PREFIX, BINDIR, ETCDIR, APPDIR, TMPDIR
- REPO_OWNER, REPO_NAME, REPO_REF, RAW_BASE
EOF
}

if [ -n "${BASH_SOURCE[0]-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR=""
fi

if [ -z "$MODE" ]; then
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/spo_vote.sh" ] && [ -f "$SCRIPT_DIR/spo_vote.conf.example" ]; then
    MODE="install"
  else
    MODE="remote-install"
  fi
fi

case "$MODE" in
  install)
    local_install
    ;;
  remote-install)
    remote_install
    ;;
  uninstall)
    uninstall
    ;;
  check)
    check
    ;;
  check-config)
    check_config
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Error: Unknown command '$MODE'"
    usage
    exit 1
    ;;
esac
