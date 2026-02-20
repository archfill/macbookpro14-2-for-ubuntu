# MacBook Pro 14,2 for Ubuntu

MacBook Pro 14,2（2017 13インチ Touch Bar）にUbuntuをインストールする際のセットアップガイド。

## ハードウェア情報

| 項目        | 詳細              |
| ----------- | ----------------- |
| モデル      | MacBookPro14,2    |
| 年式        | 2017 Mid          |
| サイズ      | 13インチ          |
| Touch Bar   | あり              |
| Wi-Fiチップ | Broadcom BCM43602 |
| CPU         | Intel             |

## セットアップ手順

### 1. 汎用パッケージ（バッテリー・温度・明るさ）

```bash
sudo apt install tlp powertop brightnessctl thermald
sudo systemctl enable tlp
sudo systemctl enable thermald
```

### 2. Wi-Fi（Broadcom BCM43602）

MacBookのBroadcomチップはデフォルトドライバでは接続が不安定。ドライバ差し替えと送信電力の制限が必要。

```bash
# ドライバ修正
sudo apt purge bcmwl-kernel-source
sudo apt update
sudo update-pciids
sudo apt install firmware-b43-installer
sudo reboot
```

再起動後、送信電力を制限して接続を安定化：

```bash
sudo iwconfig wlp2s0 txpower 10dBm
```

#### 送信電力設定の永続化（systemdサービス）

```bash
sudo tee /etc/systemd/system/set-wifi-power.service > /dev/null << 'EOF'
[Unit]
Description=Set WiFi TX Power for Broadcom BCM43602
After=network.target

[Service]
ExecStart=/sbin/iwconfig wlp2s0 txpower 10dBm
Type=oneshot

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable set-wifi-power.service
```

### 3. Touch Bar

MacBook Pro 14,2 の Touch Bar は Apple T1（iBridge）チップ経由で USB 接続されている。
[roadrunner2/macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver) をベースに、**kernel 6.17 で発生するデッドロック問題を修正**したパッチ済みドライバをこのリポジトリに同梱している。

#### セットアップ（自動）

```bash
sudo apt install dkms
./scripts/setup-touchbar.sh
sudo reboot
```

スクリプトが行うこと:

1. 既存の DKMS 登録をクリーンアップ
2. `driver/touchbar/` のソースを `/usr/src/appleibridge-0.1/` にコピー
3. DKMS でビルド＆インストール
4. udev ルール（`91-apple-touchbar.rules`）を配置

#### kernel 6.17 パッチの技術的背景

オリジナルドライバは HID probe コールバック内で `usb_set_configuration()` を同期的に呼び出していた。しかし Linux USB コアは probe 中にデバイスロックを保持しており、`usb_set_configuration()` も同じロックを取得しようとするため**デッドロック**が発生する。

本パッチでの修正:

- **`appleib_ensure_usb_config()`**: ACPI probe（デバイスロック非保持）のタイミングで iBridge USB デバイスを検索し、未設定なら `usb_set_configuration()` で config 1 を設定
- **`appleib_hid_probe()` の非同期フォールバック**: HID probe 時に config が違う場合は `usb_driver_set_configuration()`（非同期）を使い `-ENODEV` を返して probe をリトライさせる

#### トラブルシューティング

```bash
# Touch Bar が表示されない場合、手動でモジュールをロード
sudo modprobe apple-ibridge
sudo modprobe apple-ib-tb
sudo modprobe apple-ib-als

# カーネルログでエラーを確認
sudo dmesg | grep -i -E 'ibridge|touchbar|apple'

# DKMS ビルド状態を確認
dkms status

# usbmuxd が iBridge と競合する場合は停止
sudo systemctl stop usbmuxd
```

### 4. ファン制御

MacBook用のファン制御デーモン。温度に応じてファン速度を自動調整する。

```bash
sudo apt install mbpfan
sudo systemctl enable mbpfan
sudo systemctl start mbpfan
```

### 5. オーディオ

MacBook Pro用のHDAオーディオ修正が必要な場合がある。

```bash
sudo apt install linux-tools-common linux-tools-generic
```

音が出ない場合は [snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) を参照。

### 6. 日本語入力（fcitx5 + Mozc）

```bash
sudo apt install fcitx5 fcitx5-mozc fcitx5-config-qt

# 自動起動設定
mkdir -p ~/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop ~/.config/autostart/

# デフォルトIMに設定
im-config -n fcitx5
```

環境変数（`.zshenv`等に追加）：

```bash
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
```

### 7. CapsLock リマップ（タップ=Escape / ホールド=Ctrl）

`interception-tools` + `caps2esc` でカーネル入力レイヤーでリマップする。Wayland/X11/TTY すべてで動作。

```bash
sudo apt install interception-tools interception-caps2esc
```

設定ファイルを作成（Ubuntu 24.04 ではコマンド名がフルパス必須）：

```bash
sudo tee /etc/interception/udevmon.yaml > /dev/null << 'EOF'
- JOB: "/usr/bin/interception -g $DEVNODE | /usr/bin/caps2esc -m 1 | /usr/bin/uinput -d $DEVNODE"
  DEVICE:
    EVENTS:
      EV_KEY: [KEY_CAPSLOCK]
EOF
```

サービス有効化：

```bash
sudo systemctl enable udevmon
sudo systemctl restart udevmon
```

> `-m 1` はタップ=Escape、ホールド=Ctrl のモード。`-m 0`（デフォルト）は CapsLock を完全に Escape に置き換える。

## ディレクトリ構成

```
macbookpro14-2-for-ubuntu/
├── README.md
├── driver/
│   ├── touchbar/          # パッチ済み iBridge ドライバソース
│   │   ├── apple-ibridge.c
│   │   ├── apple-ibridge.h
│   │   ├── apple-ib-tb.c
│   │   ├── apple-ib-als.c
│   │   ├── Makefile
│   │   └── dkms.conf
│   └── udev/
│       └── 91-apple-touchbar.rules
└── scripts/
    └── setup-touchbar.sh  # DKMS セットアップ自動化
```

## パッケージ一覧

| カテゴリ     | パッケージ                                    | 用途                      |
| ------------ | --------------------------------------------- | ------------------------- |
| バッテリー   | `tlp`                                         | バッテリー最適化          |
| バッテリー   | `powertop`                                    | 電力消費分析              |
| 温度管理     | `thermald`                                    | CPU温度管理（Intel）      |
| 明るさ       | `brightnessctl`                               | 画面の明るさ調整          |
| Wi-Fi        | `firmware-b43-installer`                      | Broadcom BCM43602ドライバ |
| Touch Bar    | `appleibridge` (DKMS)                         | Touch Bar有効化           |
| ファン       | `mbpfan`                                      | MacBook用ファン制御       |
| 日本語入力   | `fcitx5`, `fcitx5-mozc`                       | 日本語入力メソッド        |
| タッチパッド | `libinput`                                    | トラックパッド対応        |
| キーリマップ | `interception-tools`, `interception-caps2esc` | CapsLock→Escape/Ctrl      |

## 参考リンク

- [MacBookPro14,2 Ubuntu Guide](https://github.com/twigglits/MacbookPro14-2Ubuntu)
- [Touch Bar Driver (roadrunner2)](https://github.com/roadrunner2/macbook12-spi-driver)
- [Linux on MacBook Pro 2017](https://gist.github.com/roadrunner2/1289542a748d9a104e7baec6a92f9cd7)
- [Wi-Fi Fix (2025)](https://james.cridland.net/blog/2025/wifi-on-macbook-pro-linux/)
- [Broadcom Wi-Fi Drivers](https://gist.github.com/torresashjian/e97d954c7f1554b6a017f07d69a66374)

## ライセンス

このリポジトリに含まれる Touch Bar ドライバソース (`driver/touchbar/`) は
[Ronald Tschalär](https://github.com/roadrunner2) による成果物をベースとし、
kernel 6.17 対応パッチを加えたものです。

- 原著作者: Ronald Tschalär, Copyright (c) 2017-2018
- ライセンス: [GNU General Public License v2.0](LICENSE)
- 参照元: [roadrunner2/macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver)

セットアップスクリプト・ドキュメント類も同ライセンス（GPL-2.0）の下で配布されます。
