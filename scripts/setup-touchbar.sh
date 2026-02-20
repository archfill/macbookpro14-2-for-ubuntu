#!/usr/bin/env bash
set -euo pipefail

DRIVER_DIR="$(cd "$(dirname "$0")/../driver/touchbar" && pwd)"
UDEV_DIR="$(cd "$(dirname "$0")/../driver/udev" && pwd)"
MODPROBE_DIR="$(cd "$(dirname "$0")/../driver/modprobe.d" && pwd)"
DKMS_NAME="appleibridge"
DKMS_VER="0.1"
DEST="/usr/src/${DKMS_NAME}-${DKMS_VER}"

echo "=== Touch Bar Driver Setup (DKMS) ==="

echo "[0/4] Installing dependencies..."
sudo apt install -y dkms build-essential linux-headers-$(uname -r)

# Remove existing DKMS registration
sudo dkms remove "${DKMS_NAME}/${DKMS_VER}" --all 2>/dev/null || true
sudo rm -rf "$DEST"

# Copy source -> DKMS add -> build -> install
sudo cp -r "$DRIVER_DIR" "$DEST"
sudo dkms add "${DKMS_NAME}/${DKMS_VER}"
sudo dkms build "${DKMS_NAME}/${DKMS_VER}"
sudo dkms install "${DKMS_NAME}/${DKMS_VER}"

# udev rules
sudo cp "$UDEV_DIR/91-apple-touchbar.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules

# modprobe options (fnmode=2: default fn keys, fn pressed = special keys)
sudo cp "$MODPROBE_DIR/apple-touchbar.conf" /etc/modprobe.d/

echo ""
echo "Done. Reboot to activate Touch Bar."
echo "  Manual test: sudo modprobe apple-ibridge && sudo modprobe apple-ib-tb"
