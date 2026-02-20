#!/usr/bin/env bash
set -euo pipefail

echo "=== CapsLock Remap Setup (tap=Escape / hold=Ctrl) ==="

# 1. Install packages
echo "[1/3] Installing packages..."
sudo apt install -y interception-tools interception-caps2esc

# 2. Write udevmon config
echo "[2/3] Writing /etc/interception/udevmon.yaml..."
sudo mkdir -p /etc/interception
sudo tee /etc/interception/udevmon.yaml > /dev/null << 'EOF'
- JOB: "/usr/bin/interception -g $DEVNODE | /usr/bin/caps2esc -m 1 | /usr/bin/uinput -d $DEVNODE"
  DEVICE:
    EVENTS:
      EV_KEY: [KEY_CAPSLOCK]
EOF

# 3. Enable service
echo "[3/3] Enabling udevmon service..."
sudo systemctl enable udevmon
sudo systemctl restart udevmon

echo ""
echo "Done. CapsLock: tap=Escape, hold=Ctrl."
