#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Keyboard Customization Setup (keyd) ==="

# 1. Install keyd via PPA
echo "[1/5] Installing keyd..."
sudo add-apt-repository -y ppa:keyd-team/ppa
sudo apt install -y keyd

# 2. Disable interception-tools if present (replaced by keyd)
echo "[2/5] Disabling interception-tools (if installed)..."
sudo systemctl stop udevmon 2>/dev/null || true
sudo systemctl disable udevmon 2>/dev/null || true

# 3. Install keyd config
echo "[3/5] Installing keyd config..."
sudo cp "${REPO_DIR}/driver/keyd/macbook-internal.conf" /etc/keyd/macbook-internal.conf
sudo systemctl enable --now keyd
sudo systemctl restart keyd

# 4. GNOME keybindings: Super+Space -> Activities, remove input source switching
echo "[4/5] Configuring GNOME keybindings..."
gsettings set org.gnome.mutter overlay-key ''
gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>space']"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "[]"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "[]"

# 5. fcitx5: Henkan = activate (かな), Muhenkan = deactivate (英数)
echo "[5/5] Configuring fcitx5 hotkeys..."
FCITX5_CONFIG="${HOME}/.config/fcitx5/config"
if [ -f "$FCITX5_CONFIG" ]; then
    sed -i 's/^0=Alt+Alt_R$/0=Henkan/' "$FCITX5_CONFIG"
    sed -i 's/^0=Alt+Alt_L$/0=Muhenkan/' "$FCITX5_CONFIG"
    fcitx5 -r --enable all 2>/dev/null &
    echo "  fcitx5 config updated."
else
    echo "  WARNING: fcitx5 config not found. Run setup-fcitx5.sh first."
fi

echo ""
echo "=== Done ==="
echo "  CapsLock tap=Escape / hold=Ctrl"
echo "  Left Command tap=英数 (Muhenkan) / hold=Super"
echo "  Right Command tap=かな (Henkan) / hold=Super"
echo "  Super+Space = Activities"
echo ""
echo "Reboot recommended to fully apply keyd."
