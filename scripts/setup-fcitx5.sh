#!/usr/bin/env bash
set -euo pipefail

echo "=== Japanese Input Setup (fcitx5 + Mozc) ==="

# 1. Install packages
echo "[1/3] Installing packages..."
sudo apt install -y fcitx5 fcitx5-mozc fcitx5-config-qt

# 2. Autostart
echo "[2/3] Configuring autostart..."
mkdir -p ~/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop ~/.config/autostart/
im-config -n fcitx5

# 3. Environment variables
echo "[3/3] Adding environment variables..."
ZSHENV="${HOME}/.zshenv"
ENV_BLOCK='
# fcitx5 input method
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx'

if grep -q "GTK_IM_MODULE=fcitx" "$ZSHENV" 2>/dev/null; then
    echo "  Already set in ${ZSHENV}, skipping."
else
    echo "$ENV_BLOCK" >> "$ZSHENV"
    echo "  Added to ${ZSHENV}."
fi

echo ""
echo "Done. Log out and back in to activate fcitx5."
