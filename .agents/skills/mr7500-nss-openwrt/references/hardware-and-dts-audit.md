# MR7500 Hardware, Blob & DTS Patch Reference

## 1. MTD Partition Layout (512 MB NAND, `erasesize=0x20000`)

| MTD | Offset / Size | Name | Criticality & Role |
|---|---|---|---|
| `mtd0` | `0x00180000` (1.5 MiB) | `0:SBL1` | Primary Secondary Bootloader (Verified bit-identical to backup) |
| `mtd1` | `0x00100000` (1.0 MiB) | `0:MIBIB` | Partition table / SMEM (Verified bit-identical to backup) |
| `mtd2` | `0x00380000` (3.5 MiB) | `0:QSEE` | TrustZone / Secure Execution Environment (Verified bit-identical) |
| `mtd3` | `0x00080000` (512 KiB) | `0:DEVCFG` | TZ Device Configuration (Verified bit-identical) |
| `mtd4` | `0x00080000` (512 KiB) | `0:RPM` | Resource Power Manager FW (Verified bit-identical) |
| `mtd5` | `0x00080000` (512 KiB) | `0:CDT` | Config Data Table (Verified bit-identical) |
| `mtd6` | `0x00080000` (512 KiB) | `0:APPSBLENV` | Qualcomm U-Boot default env (Verified bit-identical) |
| `mtd7` | `0x00180000` (1.5 MiB) | `0:APPSBL` | U-Boot (`CBT U-Boot ver: 1.0.12`, Verified bit-identical) |
| `mtd8` | `0x00080000` (512 KiB) | **`0:ART`** | **Factory RF Calibration Data (IRREPLACEABLE - Verified bit-identical)** |
| `mtd9` | `0x00080000` (512 KiB) | **`0:ETHPHYFW`** | **Marvell AQR114C Flash (Verified bit-identical)** |
| `mtd10` | `0x00080000` (512 KiB) | **`u_env`** | Active U-Boot environment (`boot_part=1`, `boot_part_ready=3`) |
| `mtd11` | `0x00040000` (256 KiB) | **`s_env`** | Linksys boot state counter env |
| `mtd12` | `0x00040000` (256 KiB) | **`devinfo`** | Factory serial, MACs (`hw_mac_addr`), certs (Verified bit-identical) |
| `mtd13` | `0x05200000` (82 MiB) | `kernel` | **Slot 1 Active OpenWrt 6.12.92 + NSS 12.5 FIT Kernel** |
| `mtd14` | `0x04a00000` (74 MiB) | `rootfs` | **Slot 1 Active OpenWrt SquashFS + UBIFS Overlay** |
| `mtd15` | `0x05200000` (82 MiB) | `alt_kernel` | **Slot 2 Stock OEM 1.1.12.216943 Kernel (Verified bit-identical to backup)** |
| `mtd16` | `0x04a00000` (74 MiB) | `alt_rootfs` | **Slot 2 Stock OEM 1.1.12.216943 Rootfs (Verified bit-identical to backup)** |
| `mtd17` | `0x00400000` (4 MiB) | `sysdiag` | OEM diagnostics (Verified bit-identical) |
| `mtd18` | `0x13d00000` (317 MiB) | `syscfg` | OEM persistent UBIFS config |
| `mtd19` | `0x00500000` (5 MiB) | `app_data` | OEM app data (Verified bit-identical) |

---

## 2. Kernel & DTS Patches in Custom Build

### 1. `0982-net-mdio-fwnode-wait-for-c45-phy-with-reset-gpios.patch`
* **File:** `drivers/net/mdio/fwnode_mdio.c`
* **Purpose:** Allows Clause 45 PHYs (Marvell/Aquantia AQR114C) up to 15 seconds to boot their internal ROM and respond to MDIO address 8 on cold boot. Verified resolving cold-boot probe race (`C45 PHY at address 8 became ready after 260 ms`). Persisted directly in `target/linux/qualcommax/patches-6.12/`.

### 2. `ipq6018-mr7500.dts`
* `aqr114c`: `compatible = "ethernet-phy-ieee802.3-c45"`, `reset-gpios = <&tlmm 77 GPIO_ACTIVE_LOW>`, `firmware-name = "marvell/AQR114C.cld"`.
* `nss_macsec0`: `phy_addr = <0x8>`.
* `pcie0`: `wifi@0,0` with `qcom,ath11k-calibration-variant = "Linksys-MR7500"`, `qcom,ath11k-fw-memory-mode = <1>`.
* `wifi`: `qcom,ath11k-calibration-variant = "Linksys-MR7500"`, `qcom,ath11k-fw-memory-mode = <1>`.
* `usb3`: `dr_mode = "host"`.

### 3. Default Hardware Offload & Wireless Configuration (`files/`)
* `files/etc/uci-defaults/99-mr7500-nss-defaults`:
  * Default LAN IP: `10.143.1.1/24` (`ipaddr='10.143.1.1'`, `netmask='255.255.255.0'`).
  * Firewall: `flow_offloading='0'`, `flow_offloading_hw='0'`.
  * ECM: `acceleration_engine='nss'`, `enable_bridge_filtering='1'`.
  * NSS: `enable_rps='1'`, `memory_profile='512mb'`, `auto_scale='1'`.
  * `ath11k`: `nss_offload=0 frame_mode=0` in `/etc/modules.d/ath11k`.
* `files/etc/rc.local`:
  * Asynchronous one-shot initializer for `phy0..phy2` auto-enabling 2.4G (`HE40`), 5G (`HE80`), and 6G (`HE160`, `OWE`, `ieee80211w=2`).
  * Aquantia AQR114C USXGMII in-band auto-negotiation keeper daemon (`4:0xc441 = 0x0008`).

---

## 3. Peripheral Hardware & Bluetooth Subsystem

* **Bluetooth Subsystem (CSR8811 / CSR8x11):**
  * **Chipset:** CSR / Qualcomm CSR8811 A08 (BLE 4.1).
  * **UART Port:** `blsp1_uart2` (`/dev/ttyMSM1`, `0x078b0000`) @ 115200 baud, BCSP protocol.
  * **Power / Reset GPIO:** `tlmm 34` (Linux 6.12 `gpio546`).
  * **Power Control:**
    * Power ON / Enable: `echo 546 > /sys/class/gpio/export && echo out > /sys/class/gpio/gpio546/direction && echo 1 > /sys/class/gpio/gpio546/value`
    * Power OFF / Reset: `echo 0 > /sys/class/gpio/gpio546/value && echo 546 > /sys/class/gpio/unexport`
  * **Design Choice:** Linksys OEM firmware only used this BLE chip for initial smartphone onboarding via the Linksys app. Holding it in reset (`GPIO 34 = 0`) saves ~50–80 mW of power and eliminates 2.4 GHz RF co-existence degradation.
* **USB 3.0 / 2.0 Subsystem:**
  * **Controller:** Qualcomm DWC3 xHCI SuperSpeed host controller (`xhci-hcd.1.auto`).
  * **VBUS Regulator:** `reg_usb_vbus` driven by GPIO 25 (`tlmm 25 GPIO_ACTIVE_LOW`).
  * **USB LED:** `blue:usb` with `usbport` kernel trigger.
  * **Supported Filesystems:** Built-in `ext4`, plus `kmod-fs-vfat`, `kmod-fs-exfat`, `kmod-nls-*`, and `usbutils`.
* **Auxiliary I2C Bus (`i2c@78b7000` / `blsp1_i2c3`):**
  * SCL = GPIO 42, SDA = GPIO 43.
  * Attached device: NXP PCA9632 4-bit Fm+ I2C LED driver at address `0x62`. Handled by U-Boot in preboot; disabled in Linux kernel as primary LEDs are driven via internal PWM.
