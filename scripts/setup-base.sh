#!/usr/bin/env bash
set -euo pipefail

echo "=== Base Packages Setup (battery / thermal / fan) ==="

# 1. General packages
echo "[1/2] Installing packages..."
sudo apt install -y tlp powertop brightnessctl thermald mbpfan

# 2. Enable services
echo "[2/2] Enabling services..."
sudo systemctl enable tlp
sudo systemctl enable thermald
sudo systemctl enable mbpfan
sudo systemctl start mbpfan

echo ""
echo "Done."
