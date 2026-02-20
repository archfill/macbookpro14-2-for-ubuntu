#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "[touchpad] Installing dependencies..."
sudo apt install -y libinput-tools

echo "[touchpad] Installing libinput quirks for DWT fix..."

sudo mkdir -p /etc/libinput
sudo cp "${REPO_DIR}/driver/libinput/local-overrides.quirks" /etc/libinput/local-overrides.quirks

echo "[touchpad] Reloading udev rules..."
sudo udevadm trigger /dev/input/event* 2>/dev/null || true

echo "[touchpad] Verifying quirk is applied..."
if libinput quirks list /dev/input/event4 2>/dev/null | grep -q "AttrKeyboardIntegration=internal"; then
    echo "[touchpad] OK: AttrKeyboardIntegration=internal applied to keyboard"
else
    echo "[touchpad] WARNING: quirk not confirmed on event4. Reboot to apply."
fi

echo "[touchpad] Done. Reboot to fully apply DWT fix."
