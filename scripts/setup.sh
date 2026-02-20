#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

confirm() {
    local msg="$1"
    read -rp "${msg} [y/N] " ans
    [[ "${ans,,}" == "y" ]]
}

echo "======================================"
echo " MacBook Pro 14,2 Ubuntu Setup"
echo "======================================"
echo ""

if confirm "[1] Base packages (battery / thermal / fan)?"; then
    bash "${SCRIPTS_DIR}/setup-base.sh"
    echo ""
fi

if confirm "[2] Wi-Fi (BCM43602 driver + 5GHz NVRAM)?"; then
    bash "${SCRIPTS_DIR}/setup-wifi.sh"
    echo ""
fi

if confirm "[3] Touch Bar (DKMS driver)?"; then
    sudo apt install -y dkms
    bash "${SCRIPTS_DIR}/setup-touchbar.sh"
    echo ""
fi

if confirm "[4] Touchpad (DWT fix for typing interference)?"; then
    bash "${SCRIPTS_DIR}/setup-touchpad.sh"
    echo ""
fi

if confirm "[5] Audio (CS8409 internal speaker, DKMS)?"; then
    bash "${SCRIPTS_DIR}/setup-audio.sh"
    echo ""
fi

if confirm "[6] Japanese input (fcitx5 + Mozc)?"; then
    bash "${SCRIPTS_DIR}/setup-fcitx5.sh"
    echo ""
fi

if confirm "[7] CapsLock remap (tap=Escape / hold=Ctrl)?"; then
    bash "${SCRIPTS_DIR}/setup-capslock.sh"
    echo ""
fi

echo "======================================"
echo " All selected setups completed."
echo " Reboot recommended."
echo "======================================"
