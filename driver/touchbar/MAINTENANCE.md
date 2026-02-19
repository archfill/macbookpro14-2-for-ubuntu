# Touch Bar ドライバ メンテナンスガイド

MacBook Pro 14,2（2017, T1 chip）の Touch Bar を Linux kernel 6.17+ で動作させるための
パッチ済みドライバに関する技術詳細。カーネル更新時の再対応に必要な情報をまとめている。

## 目次

- [ハードウェア概要](#ハードウェア概要)
- [ドライバアーキテクチャ](#ドライバアーキテクチャ)
- [根本原因：USB デッドロック](#根本原因usb-デッドロック)
- [パッチ内容の詳細](#パッチ内容の詳細)
- [USB コア関連の背景知識](#usb-コア関連の背景知識)
- [既知の問題と注意点](#既知の問題と注意点)
- [カーネル更新時のチェックリスト](#カーネル更新時のチェックリスト)
- [デバッグ手順](#デバッグ手順)
- [関連リソース](#関連リソース)

---

## ハードウェア概要

### Apple iBridge (T1 chip)

| 項目                 | 値                  |
| -------------------- | ------------------- |
| USB Vendor ID        | `05ac` (Apple Inc.) |
| USB Product ID       | `8600`              |
| USB デバイス名       | iBridge             |
| ACPI デバイス ID     | `APP7777`           |
| USB バス位置         | 通常 `1-3`          |
| USB Configuration 数 | 3                   |

### 3つの USB Configuration

| Config | bConfigurationValue | 用途                                                                      |
| ------ | ------------------- | ------------------------------------------------------------------------- |
| 1      | 1                   | **Default iBridge Interfaces** — HID キーボードモード（本ドライバが使用） |
| 2      | 2                   | Default iBridge Interfaces(OS X) — macOS フルコントロールモード           |
| 3      | 3                   | Default iBridge Interfaces(Recovery) — リカバリモード                     |

Config 1 で公開されるインターフェース:

- USB HID × 2（Touch Bar キー入力 + 環境光センサー）
- UVC × 2（内蔵カメラ / iSight）

### デバイスの特性

- **Composite USB device**: `bDeviceClass=0`（機能はインターフェースレベルで定義）
- **Vendor-specific インターフェース**: `bInterfaceClass=0xFF` を使用するため、カーネルの `usb_choose_configuration()` が自動で正しい config を選択できない場合がある
- ドライバが明示的に config 1 を設定する必要がある

---

## ドライバアーキテクチャ

### モジュール構成

```
apple-ibridge (ACPI ドライバ / MFD コア)
├── apple-ib-tb (Touch Bar サブドライバ)
└── apple-ib-als (環境光センサー サブドライバ)
```

### 初期化フロー

```
1. カーネルが ACPI デバイス APP7777:00 を検出
2. appleib_probe() (ACPI probe) が呼ばれる
   ├── appleib_alloc_device() — デバイス構造体の初期化
   ├── appleib_ensure_usb_config() — ★パッチ追加: USB config の事前設定
   ├── devm_mfd_add_devices() — MFD サブデバイス登録
   └── hid_register_driver() — HID ドライバ登録
3. USB コアが iBridge の HID インターフェースを検出
4. appleib_hid_probe() (HID probe) が呼ばれる
   ├── config チェック → 不一致なら非同期切り替え + -ENODEV で retry
   ├── hid_parse() → hid_hw_start()
   └── appleib_add_device() → サブドライバ probe
5. apple-ib-tb が Touch Bar モード制御を開始
6. apple-ib-als が IIO デバイスとして環境光センサーを登録
```

### mainline カーネルとの違い

| 項目                | mainline (hid-appletb-\*)     | 本ドライバ (apple-ibridge)       |
| ------------------- | ----------------------------- | -------------------------------- |
| USB config 切り替え | なし（自動選択に依存）        | 明示的に config 1 を設定         |
| 登録方法            | 直接 HID ドライバ             | ACPI → MFD → HID demux           |
| Touch Bar モード    | 基本のみ                      | FN キーモード切替、自動 dim/idle |
| 環境光センサー      | なし                          | IIO デバイスとして提供           |
| mainline 状態       | kernel 6.13+ に存在（未成熟） | out-of-tree (DKMS)               |

---

## 根本原因：USB デッドロック

### 問題の概要

kernel 6.17 で Touch Bar ドライバ（F13-Kr1pt0n 版ベース）をロードすると、
**システムがハング**（デッドロック）する問題が発生した。

### デッドロックのメカニズム

```
Linux ドライバコアのロック保持チェーン:

1. ドライバコアが device_lock を取得
2. usb_probe_interface() を呼び出し（device_lock 保持のまま）
3. apple-ibridge HID probe が実行される
4. probe 内で usb_set_configuration() を同期的に呼ぶ
   └── usb_set_configuration() も device_lock を要求 → ★デッドロック
```

具体的には:

- `usb_probe_device()` と `usb_probe_interface()` は **ドキュメントに「called from driver core with dev locked」と明記**
- `usb_set_configuration()` は **「Caller holds device lock」が前提条件**
- probe コールバック内から `usb_set_configuration()` を同期呼び出しすると、既に保持されている device_lock を再取得しようとして永久ブロック

### なぜ以前は動いていたか

オリジナルの roadrunner2 版ドライバ（2019年パッチ）は **安全な非同期パターン**を使っていた:

```c
// 安全: usb_driver_set_configuration() は workqueue に投げて即座に返る
rc = usb_driver_set_configuration(udev, APPLETB_BASIC_CONFIG);
return rc ? rc : -ENODEV;  // probe を中断、再列挙後に retry
```

F13-Kr1pt0n の `>= 6.15` 向けコードパスで `apple_ib_set_tb_mode()` → `usb_set_configuration()` の**同期呼び出し**に変更されたことでデッドロックが発生するようになった。

### 2つの USB Configuration API の違い

| API                              | ロック                                               | 安全なコンテキスト             |
| -------------------------------- | ---------------------------------------------------- | ------------------------------ |
| `usb_set_configuration()`        | caller が device_lock を保持している前提             | sysfs handler, suspend/resume  |
| `usb_driver_set_configuration()` | workqueue で非同期実行、worker が device_lock を取得 | **probe コールバック内で安全** |

`usb_driver_set_configuration()` は fire-and-forget:

- `schedule_work()` で workqueue にキューイング、即座に return 0
- **caller に完了通知なし**（ドキュメント: "The caller has no way to know whether the queued request will eventually succeed"）
- worker (`driver_set_config_work`) が `usb_lock_device()` → `usb_set_configuration()` → `usb_unlock_device()` の順で実行

### kernel 6.17 での追加問題：未設定状態

kernel 6.17 では USB コアが iBridge を**未設定状態（bConfigurationValue = 空）のまま放置**するケースが確認された。
これは `usb_choose_configuration()` が vendor-specific インターフェースを持つデバイスに対して config を選択しない（または選択した config が適用されない）ことに起因する可能性がある。

`usb_choose_configuration()` のロジック:

1. 電力予算 (`bus_mA`) を超える config はスキップ
2. UAC3 オーディオを優先（該当なし）
3. RNDIS/ActiveSync を回避（該当なし）
4. **最初の非 vendor-specific class の config を選択**
5. 全て vendor-specific なら最初の config にフォールバック

iBridge は vendor-specific class を使用するため、自動選択が期待通りに動作しない場合がある。

---

## パッチ内容の詳細

### 修正 1: `appleib_ensure_usb_config()` の追加

**ファイル**: `apple-ibridge.c` (L961-L992)

ACPI probe のタイミング（device_lock 非保持）で iBridge USB デバイスを検索し、
未設定なら `usb_set_configuration()` で config 1 を設定する。

```c
static void appleib_ensure_usb_config(void)
{
    struct usb_device *udev = NULL;
    usb_for_each_dev(&udev, appleib_match_ibridge);
    if (!udev) return;

    if (!udev->actconfig) {
        usb_set_configuration(udev, APPLETB_BASIC_CONFIG);
    }
    usb_put_dev(udev);
}
```

**安全な理由**: ACPI probe は USB device_lock を保持していないため、
`usb_set_configuration()` の同期呼び出しが安全。

**呼び出し箇所**: `appleib_probe()` 内、`hid_register_driver()` の直前 (L1040)

### 修正 2: `appleib_hid_probe()` の非同期フォールバック

**ファイル**: `apple-ibridge.c` (L809-L831)

HID probe 時に config が一致しない場合、非同期 API を使用:

```c
if (!udev->actconfig ||
    udev->actconfig->desc.bConfigurationValue != APPLETB_BASIC_CONFIG) {
    rc = usb_driver_set_configuration(udev, APPLETB_BASIC_CONFIG);
    return rc ? rc : -ENODEV;
}
```

**ポイント**:

- `udev->actconfig` の NULL チェックを追加（オリジナルにはなかった）
- `usb_driver_set_configuration()` で非同期切り替え（デッドロック回避）
- `-ENODEV` を返して probe を中断、config 変更後に再 probe される

### 修正 3: MBP14,3 Touch Bar モード管理（apple_ib_set_tb_mode）

`>= 6.15` 向けに追加された `apple_ib_set_tb_mode()` は残置しているが、
**probe 内からは呼ばれないように修正**。sysfs や suspend/resume など
device_lock 非保持のコンテキストからのみ呼ばれる設計。

---

## USB コア関連の背景知識

### USB デバイス初期化フロー

```
usb_new_device()           — デバイス登録（config 未設定）
  └── device_add()         — ドライバコアに登録
       └── usb_generic_driver_probe()  — device_lock 保持
            ├── usb_choose_configuration()  — config 選択
            └── usb_set_configuration()     — config 適用、interface 登録
                 └── interface driver probe  — HID probe (device_lock 保持のまま)
```

### 関連する CVE / カーネルバグ修正

| CVE / Commit   | 内容                                               | 関連性                              |
| -------------- | -------------------------------------------------- | ----------------------------------- |
| CVE-2024-26934 | `usb_deauthorize_interface` のデッドロック         | device_lock の循環依存パターン      |
| CVE-2024-26933 | port disable sysfs のデッドロック                  | sysfs + device_lock の競合          |
| `bc82e5f4d7dc` | driver-core device_lock 回帰（6.12/6.6）           | probe 中のロック強制変更            |
| `a87b8e3be926` | `choose_configuration` コールバック追加（2023-12） | USB config 選択アーキテクチャの進化 |

### USB コアのロック安定性 (v6.10 - v6.17)

v6.10 から v6.17 にかけて、probe/configuration 関連のロック機構に**変更はなかった**。
主な変更は LPM（Link Power Management）のリワーク、遅延ワークのロック修正、
dynamic ID リストのロック統合（Greg Kroah-Hartman, 2024-11）など。

つまり、**probe 中の device_lock 保持パターンは意図的な設計であり、今後も変更される可能性は低い**。

---

## 既知の問題と注意点

### usbmuxd との競合

`usbmuxd`（iOS デバイス通信用）が iBridge の USB ID `05ac:8600` にマッチし、
HID ドライバの初期化を阻害する。

**対処法**:

```bash
# usbmuxd を停止
sudo systemctl stop usbmuxd
sudo systemctl disable usbmuxd

# または udev ルールから iBridge を除外
# /lib/udev/rules.d/39-usbmuxd.rules から 05ac:8600 を削除
```

### IIO API の互換性 (kernel 6.10)

`apple-ib-als.c` の `iio_device_alloc()` が kernel 6.10 で API 変更により
ビルドエラーになった問題。本ドライバでは `LINUX_VERSION_CODE` で分岐して対応済み:

```c
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 9, 0)
    iio_dev = iio_device_alloc(sizeof(als_dev));
#else
    iio_dev = iio_device_alloc(&als_dev->hid_dev->dev, sizeof(als_dev));
#endif
```

### mainline hid-appletb-kbd の問題

mainline の `hid-appletb-kbd`（2025-02 追加）には初期段階で以下のバグがあった:

- slab use-after-free in probe (2025-07, commit `38224c47`)
- input_handler_list のメモリ破壊 (2025-07, commit `c80f2b04`)
- backlight デバイス参照カウント不正 (2025-06, commit `4540e41e`)

mainline ドライバへの移行を検討する場合は、使用カーネルに上記修正が含まれているか確認すること。

### modules-load.d による自動ロード

現在 `/etc/modules-load.d/apple-touchbar.conf` で以下を設定:

```
apple-ibridge
apple-ib-tb
apple-ib-als
```

udev ルール（`91-apple-touchbar.rules`）でも iBridge 検出時に modprobe する冗長構成。

---

## カーネル更新時のチェックリスト

### DKMS ビルド確認

```bash
# カーネル更新後、DKMS が自動ビルドしているか確認
dkms status

# 手動で再ビルドが必要な場合
sudo dkms build appleibridge/0.1
sudo dkms install appleibridge/0.1
```

### 動作確認手順

```bash
# 1. モジュールがロードされているか
lsmod | grep apple

# 2. USB config が設定されているか
cat /sys/bus/usb/devices/1-3/bConfigurationValue
# → "1" が表示されれば OK、空なら未設定

# 3. USB インターフェースが存在するか
ls /sys/bus/usb/devices/1-3:*
# → 1-3:1.0, 1-3:1.1 等が存在すれば OK

# 4. カーネルログの確認
sudo dmesg | grep -i -E 'ibridge|touchbar|apple-ib|APP7777'

# 5. Touch Bar sysfs
ls /sys/devices/pci*/*/APP7777:00/apple-ib-tb.*/ 2>/dev/null
```

### 新カーネルで壊れた場合の調査ポイント

1. **ビルドエラー**: API 変更を `LINUX_VERSION_CODE` マクロで分岐
   - 特に注意: `iio_device_alloc`, `iio_trigger_alloc`, `platform_driver.remove` の返り値型
2. **ロード時ハング**: `usb_set_configuration` / `usb_driver_set_configuration` のロック状況を確認
   - `dmesg` で `hung_task` や `INFO: task blocked` が出ているか
   - probe コンテキストから同期 config 変更していないか
3. **ロードはされるが Touch Bar 無反応**:
   - `bConfigurationValue` が空 → `ensure_usb_config` が動作していない
   - HID インターフェースが登録されていない → `usb_choose_configuration` の挙動変化
4. **USB コアの変更確認**:
   ```bash
   # 新カーネルでの USB コア変更を確認
   git log v6.17..v<新バージョン> -- drivers/usb/core/generic.c drivers/usb/core/driver.c drivers/usb/core/message.c
   ```

### 将来の mainline 移行の判断基準

以下が全て満たされたとき、out-of-tree ドライバから mainline への移行を検討:

- [ ] `hid-appletb-kbd` のメモリ安全性バグが全て修正済み
- [ ] mainline が USB config 1 を自動選択、または明示的に設定する仕組みがある
- [ ] FN キーモード切替が正常動作
- [ ] 環境光センサーが不要、または別途 mainline ドライバで対応可能

---

## デバッグ手順

### iBridge USB デバイスの状態確認

```bash
# デバイス存在確認
lsusb | grep 05ac:8600

# 詳細情報
lsusb -v -d 05ac:8600

# sysfs からの確認
cat /sys/bus/usb/devices/1-3/idVendor        # 05ac
cat /sys/bus/usb/devices/1-3/idProduct       # 8600
cat /sys/bus/usb/devices/1-3/product         # iBridge
cat /sys/bus/usb/devices/1-3/bConfigurationValue  # 1（正常時）
cat /sys/bus/usb/devices/1-3/bNumConfigurations   # 3
cat /sys/bus/usb/devices/1-3/authorized      # 1
```

### USB デバイスの手動リバインド

Touch Bar が反応しない場合、USB デバイスの unbind/bind で復旧できる場合がある:

```bash
# USB デバイスパスの確認
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 1
echo "1-3" | sudo tee /sys/bus/usb/drivers/usb/bind
```

### ドライバの手動ロード / アンロード

```bash
# アンロード（逆順）
sudo modprobe -r apple-ib-als
sudo modprobe -r apple-ib-tb
sudo modprobe -r apple-ibridge

# ロード
sudo modprobe apple-ibridge
sudo modprobe apple-ib-tb
sudo modprobe apple-ib-als

# デバッグ情報付きロード
sudo modprobe apple-ibridge dyndbg=+p
```

### カーネルデッドロックの検出

```bash
# hung_task 検出の確認
cat /proc/sys/kernel/hung_task_timeout_secs

# デッドロック発生時のログ
sudo dmesg | grep -i -E 'hung_task|blocked|deadlock|lockdep'
```

---

## 関連リソース

### ソースコード / リポジトリ

- [roadrunner2/macbook12-spi-driver](https://github.com/roadrunner2/macbook12-spi-driver) — オリジナルドライバ（touchbar-driver-hid-driver ブランチ）
- [t2linux/apple-ib-drv](https://github.com/t2linux/apple-ib-drv) — T2 Mac 向けフォーク
- [F13-Kr1pt0n 版](https://github.com/F13-Kr1pt0n/macbook12-spi-driver) — kernel 6.15+ 対応パッチ（本ドライバのベース）

### カーネルソース（参照用パス）

- `drivers/usb/core/generic.c` — `usb_generic_driver_probe`, `usb_choose_configuration`
- `drivers/usb/core/driver.c` — `usb_probe_device`, `usb_probe_interface`, `usb_driver_set_configuration`
- `drivers/usb/core/message.c` — `usb_set_configuration`
- `drivers/usb/core/hub.c` — `usb_new_device`, `usb_authorize_device`
- `drivers/hid/hid-appletb-kbd.c` — mainline Touch Bar keyboard ドライバ
- `drivers/hid/hid-appletb-bl.c` — mainline Touch Bar backlight ドライバ

### 調査メモ（2026-02-19 セッション）

本ドキュメントの根拠となる詳細な調査ログは以下で参照可能:

- claude-mem プロジェクト: `macbookpro14-2-for-ubuntu` / `macbook-pro-touchbar-driver`
- 主要な observation ID: #108 (root cause), #134 (deadlock mechanism), #142 (probe analysis), #146 (error handling)

---

_最終更新: 2026-02-20_
_対象カーネル: 6.17.0-14-generic_
_DKMS パッケージ: appleibridge/0.1_
