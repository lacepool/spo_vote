#!/usr/bin/env bash

set -euo pipefail

GUM_VERSION="${GUM_VERSION:-0.17.0}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Required command not found: $1"
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

detect_platform() {
  local os
  local arch

  os="$(uname -s)"
  arch="$(uname -m)"

  if [ "$os" != "Linux" ]; then
    echo "Error: This helper supports Linux only."
    exit 1
  fi

  platform_os="Linux"

  case "$arch" in
    x86_64)
      platform_arch="x86_64"
      ;;
    aarch64|arm64)
      platform_arch="arm64"
      ;;
    *)
      echo "Error: Unsupported architecture '$arch'."
      echo "Supported architectures: x86_64, arm64"
      exit 1
      ;;
  esac
}

need_command curl
need_command tar
need_command mktemp
need_command find
need_command install
need_command uname

detect_platform

archive_name="gum_${GUM_VERSION}_${platform_os}_${platform_arch}.tar.gz"
download_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${archive_name}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Downloading gum ${GUM_VERSION} for ${platform_os} ${platform_arch}..."
curl -fsSL "$download_url" | tar -xz -C "$tmp_dir"

gum_path="$(find "$tmp_dir" -type f -name gum | head -n 1)"

if [ -z "$gum_path" ]; then
  echo "Error: gum binary not found in downloaded archive"
  exit 1
fi

run_as_root install -d "$INSTALL_DIR"
run_as_root install -m 0755 "$gum_path" "$INSTALL_DIR/gum"

cat <<EOF
Installed gum to $INSTALL_DIR/gum

Detected platform:
- OS: $platform_os
- Architecture: $platform_arch

Supported by this helper:
- Linux x86_64
- Linux arm64

For other platforms, install gum using your system package manager or the official release instructions:
https://github.com/charmbracelet/gum
EOF
