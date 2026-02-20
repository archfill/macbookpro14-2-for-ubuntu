# MacBook Pro 14,2 for Ubuntu

MacBook Pro 14,2（2017 13インチ Touch Bar）にUbuntuをインストールする際のセットアップガイド。

## ハードウェア情報

| 項目         | 詳細               |
| ------------ | ------------------ |
| モデル       | MacBookPro14,2     |
| 年式         | 2017 Mid           |
| サイズ       | 13インチ           |
| Touch Bar    | あり               |
| Wi-Fiチップ  | Broadcom BCM43602  |
| CPU          | Intel              |
| 対象 OS      | Ubuntu 24.04.4 LTS |
| 対象カーネル | 6.17.0-14-generic  |

## セットアップ手順

### 一括セットアップ

```bash
./scripts/setup.sh
sudo reboot
```

各セクションを yes/no で選択しながら実行できる。個別に実行する場合は以下の手順を参照。

---

### 1. 汎用パッケージ（バッテリー・温度・明るさ・ファン）

```bash
./scripts/setup-base.sh
```

### 2. Wi-Fi（Broadcom BCM43602）

MacBookのBroadcomチップはデフォルトドライバでは接続が不安定。ドライバ差し替えと送信電力の制限、5GHz 用 NVRAM ファイルの導入が必要。

#### セットアップ（自動）

```bash
./scripts/setup-wifi.sh
sudo reboot
```

スクリプトが行うこと:

1. `bcmwl-kernel-source` を削除し `firmware-b43-installer` に差し替え
2. NVRAM ファイル（`brcmfmac43602-pcie.txt`）を取得・インストール → 5GHz 有効化
3. 送信電力制限サービス（`set-wifi-power.service`）を配置・有効化

再起動後、5GHz の確認：

```bash
iw phy phy0 info | grep "Band 2"
```

> CLM blob（`brcmfmac43602-pcie.clm_blob`）は Broadcom の配布制限により公式リポジトリに存在しない。
> 未導入でも主要な 5GHz チャンネル（ch36/40/44/48）は問題なく使用できる。
> BCM43602 はカーネル内で `BRCMF_FW_DEF`（CLM blob 不要）で定義されており、警告ログは非致命的。

#### トラブルシューティング

```bash
# 再起動後も 5GHz が表示されない → NVRAM が正しくロードされているか確認
sudo dmesg | grep -i brcm

# ドライバ再ロード時は brcmfmac_wcc を先に外す（依存関係）
sudo rmmod brcmfmac_wcc brcmfmac && sudo modprobe brcmfmac

# macaddr がズレている場合は NVRAM を再生成
MACADDR=$(ip link show wlp2s0 | awk '/ether/{print $2}')
sudo sed -i "s/macaddr=.*/macaddr=${MACADDR}/" /lib/firmware/brcm/brcmfmac43602-pcie.txt
sudo sed -i "s/macaddr=.*/macaddr=${MACADDR}/" \
  "/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro14,2.txt"
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
5. modprobe オプション（`apple-touchbar.conf`）を配置

#### fn キーモード

デフォルトは **ファンクションキー（F1〜F12）表示、fn 長押しで特殊キーに切替** に設定している。
変更する場合は `/etc/modprobe.d/apple-touchbar.conf` の `fnmode` を編集:

| fnmode | 動作                                                                  |
| ------ | --------------------------------------------------------------------- |
| `0`    | 常にファンクションキー                                                |
| `1`    | デフォルト：特殊キー、fn で切替（上流デフォルト）                     |
| `2`    | デフォルト：ファンクションキー、fn で切替（本リポジトリのデフォルト） |
| `3`    | 常に特殊キー                                                          |

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

#### 既知の問題と解決済み事項

**fn キーで Touch Bar が切り替わらない（解決済み）**

`interception-tools`（caps2esc）が `event4`（物理 SPI キーボード）を exclusive grab するため、
tbkbd ハンドラが fn キーイベントを受け取れない問題があった。

原因：`applespi` は BUS_SPI キーボードを 2 つ登録する。

- 物理デバイス（`phys="applespi/input0"`）: イベントを発行しない
- 仮想デバイス（`phys=""`）: KEY_FN を含む実際のイベントを発行する

元のドライバは物理デバイスに接続していたため fn キーが機能しなかった。
本リポジトリのパッチで `appletb_inp_connect()` が `phys` が空のデバイス（仮想）のみに接続するよう修正済み。
`interception-tools` との共存も問題なし（仮想デバイスは exclusive grab 対象外）。

### 4. ファン制御

`setup-base.sh` に含まれている。個別に実行する場合：

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
./scripts/setup-fcitx5.sh
```

環境変数（`GTK_IM_MODULE`, `QT_IM_MODULE`, `XMODIFIERS`）を `~/.zshenv` に自動追記する。
ログアウト・再ログイン後に有効になる。

### 7. CapsLock リマップ（タップ=Escape / ホールド=Ctrl）

`interception-tools` + `caps2esc` でカーネル入力レイヤーでリマップする。Wayland/X11/TTY すべてで動作。

```bash
./scripts/setup-capslock.sh
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
│   ├── modprobe.d/
│   │   └── apple-touchbar.conf
│   └── udev/
│       └── 91-apple-touchbar.rules
└── scripts/
    ├── setup.sh           # 一括セットアップ（各項目を yes/no で選択）
    ├── setup-base.sh      # 汎用パッケージ（バッテリー・温度・ファン）
    ├── setup-wifi.sh      # Wi-Fi ドライバ・NVRAM セットアップ
    ├── setup-touchbar.sh  # Touch Bar DKMS セットアップ
    ├── setup-fcitx5.sh    # 日本語入力（fcitx5 + Mozc）
    └── setup-capslock.sh  # CapsLock リマップ（tap=Esc / hold=Ctrl）
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
