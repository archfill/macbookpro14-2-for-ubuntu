#!/usr/bin/env bash
set -euo pipefail

# snd_hda_macbookpro (davidjo) for MacBook Pro CS8409 internal speaker support
# Repo: https://github.com/davidjo/snd_hda_macbookpro
#
# NOTE: Ubuntu HWE kernels (e.g. 6.17) do not have linux-source packages.
#       This script bypasses the Ubuntu source check and uses kernel.org source instead.
#       The sound/hda subsystem is not significantly patched in Ubuntu HWE kernels.

DKMS_NAME="snd_hda_macbookpro"
DKMS_VER="0.1"
DKMS_SRC="/usr/src/${DKMS_NAME}-${DKMS_VER}"
REPO_URL="https://github.com/davidjo/snd_hda_macbookpro.git"
TMP_DIR="$(mktemp -d)"

echo "=== Audio Setup (CS8409 internal speaker) ==="

# 1. Install dependencies
echo "[1/4] Installing dependencies..."
sudo apt install -y git dkms build-essential linux-headers-$(uname -r)

# 2. Clone repo
echo "[2/4] Cloning ${REPO_URL}..."
git clone "$REPO_URL" "$TMP_DIR/snd_hda_macbookpro"

# 3. Patch install script to bypass Ubuntu HWE kernel source check
#    The script requires linux-source-X.Y.Z which doesn't exist for HWE kernels.
#    Forcing isubuntu=0 makes it download sound/hda from kernel.org instead.
echo "[3/4] Applying HWE kernel workaround..."
sed -i 's/^if \[ \$isubuntu -ge 1 \]; then$/isubuntu=0  # PATCHED: force non-ubuntu for HWE kernel\nif [ $isubuntu -ge 1 ]; then/' \
    "$TMP_DIR/snd_hda_macbookpro/install.cirrus.driver.sh"

# 4. Install to DKMS source directory with patched script
echo "[4/4] Installing via DKMS..."
sudo dkms remove "${DKMS_NAME}/${DKMS_VER}" --all 2>/dev/null || true
sudo rm -rf "$DKMS_SRC"
sudo cp -r "$TMP_DIR/snd_hda_macbookpro" "$DKMS_SRC"

# Apply patch to the DKMS source copy as well (PRE_BUILD uses this copy)
sudo sed -i 's/^if \[ \$isubuntu -ge 1 \]; then$/isubuntu=0  # PATCHED: force non-ubuntu for HWE kernel\nif [ $isubuntu -ge 1 ]; then/' \
    "${DKMS_SRC}/install.cirrus.driver.sh"

sudo dkms add -m "$DKMS_NAME" -v "$DKMS_VER"
sudo dkms build "${DKMS_NAME}/${DKMS_VER}"
sudo dkms install "${DKMS_NAME}/${DKMS_VER}"

rm -rf "$TMP_DIR"

echo ""
dkms status "$DKMS_NAME"
echo ""
echo "Done. Reboot to activate."
echo "  After reboot, verify: sudo dmesg | grep -i 'patch_cs8409\\|APPLE'"
