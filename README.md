# Linksys MR7500 (Hydra Pro 6E) — OpenWrt with Qualcomm NSS Hardware Offloading

[![License](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Qualcommax%20IPQ60xx-orange.svg)](https://openwrt.org)
[![NSS Firmware](https://img.shields.io/badge/Qualcomm%20NSS-12.5--210-green.svg)](https://github.com/qosmio/openwrt-ipq)
[![Wi-Fi](https://img.shields.io/badge/Wi--Fi%206E-Tri--Band%20(2.4%2F5%2F6GHz)-blueviolet.svg)](https://openwrt.org)

Custom OpenWrt firmware build for the **Linksys MR7500 v1 (Hydra Pro 6E, codename `divo`)** powered by the **Qualcomm IPQ6018** quad-core ARM Cortex-A53 SoC. 

This repository provides full out-of-the-box **Qualcomm Network Subsystem (NSS) hardware acceleration**, enabling wire-speed NAT/routing with **< 0.1% host CPU utilization**, multi-gigabit WAN support via the **Marvell/Aquantia AQR114C 5GbE PHY**, and automated zero-touch **Tri-Band Wi-Fi 6E** operation (including 160 MHz on 6 GHz).

---

## Key Features & Verified Capabilities

- **Qualcomm NSS Hardware Offloading:** NSS Core 0 firmware (`NSS.FW.12.5-210-CP.R`) with UBI32 dynamic clock scaling (up to 1.4976 GHz) and RPS distribution across all 4 Cortex-A53 cores.
- **Line-Rate Forwarding at Zero CPU Load:** 944+ Mbps NAT throughput with **99.95% host CPU idle** (0.03% softirq) accelerated via Qualcomm ECM + NSS.
- **Hardware Crypto Engine:** Qualcomm EIP-197 cryptographic hardware engine enabled (`kmod-qca-nss-crypto`).
- **Multi-Gigabit 5GbE WAN Port:** Synopsys XGMAC + Marvell/Aquantia **AQR114C** PHY operating over USXGMII with cold-boot probe timing fix (`0982` patch) and OEM `v5.6.5` firmware. Tested and verified linking up to 2500 Mb/s Full Duplex.
- **Tri-Band Wi-Fi 6E (Out-of-the-Box):**
  - **2.4 GHz:** 2x2 802.11ax (HE40) via IPQ6018 internal radio (`QCN5022`).
  - **5 GHz:** 2x2 802.11ax (HE80) via IPQ6018 internal radio (`QCN5052`).
  - **6 GHz Wi-Fi 6E:** 4x4 802.11ax (**HE160, 160 MHz width**) via PCIe `QCN9074` with mandatory Opportunistic Wireless Encryption (OWE) / WPA3 and Protected Management Frames (PMF).
  - All radios utilize per-unit factory RF calibration data (`0:ART`) with zero calibration degradation.
- **Safe Dual-Boot Architecture:** Flashes into **Slot 1** while leaving **Slot 2** (OEM Stock Firmware) 100% untouched for guaranteed instant rollback.
- **Web Interface:** Includes `luci-ssl`, `luci-app-sqm` with `sqm-scripts-nss` for hardware-accelerated CAKE/FQ_CoDel bandwidth shaping.

---

## Hardware Specifications

| Component | Specification |
|---|---|
| **SoC** | Qualcomm IPQ6018 (4x ARM Cortex-A53 @ 1.8 GHz) |
| **RAM** | 512 MB DDR3L (~129 MB available at idle) |
| **Flash** | 512 MB Hynix SLC NAND (`0` bad blocks) with dual A/B layout |
| **Switch / LAN** | 4x 1GbE LAN ports (`dp1`..`dp4`) via Qualcomm QCA8075 PHY |
| **WAN** | 1x 5GbE Multi-Gigabit port (`dp5_syn`) via Marvell/Aquantia AQR114C-B0 |
| **Wi-Fi 2.4 GHz** | Qualcomm QCN5022 (2x2 802.11ax up to 574 Mbps) |
| **Wi-Fi 5 GHz** | Qualcomm QCN5052 (2x2 802.11ax up to 1201 Mbps) |
| **Wi-Fi 6 GHz** | Qualcomm QCN9074 (4x4 802.11ax 160 MHz up to 4804 Mbps) |
| **USB** | 1x USB 3.0 Type-A port (SuperSpeed 5 Gbps host mode) |
| **LEDs / Keys** | Front PWM RGB LED, USB LED, WPS button, Reset button |

---

## Step-by-Step Build Guide

Any user running **Ubuntu 22.04 LTS, 24.04 LTS, or 26.04 LTS** can build this firmware from source.

### 1. Install Build Prerequisites

Run the automated environment setup script:
```bash
git clone https://github.com/SanjayRavindran/Linksys-MR7500-NSS.git
cd Linksys-MR7500-NSS
chmod +x scripts/*.sh

./scripts/setup_env.sh
```

### 2. Extract the Aquantia AQR114C PHY Firmware Blob

The 5GbE WAN port requires the Marvell/Aquantia PHY firmware (`AQR114C.cld`, v5.6.5). To avoid redistributing proprietary binary blobs in git, this repository provides a 1-click script that downloads the official Linksys MR7500 stock firmware and extracts the verified blob:

```bash
./scripts/extract_stock_blobs.sh
```
* **Source:** Official Linksys Firmware `FW_MR7500_1.1.12.216943_prod.img`
* **Target:** `files/lib/firmware/marvell/AQR114C.cld` (`393,218` bytes)
* **SHA-256 Checksum:** `8a0e88cf738a0b07e602495d43be6c13fe6272551527efd04b6df00d3cb12eb6`

### 3. Build the Firmware

Run the automated build script:
```bash
./scripts/build.sh
```

The script will:
1. Clone the verified base repository (`qosmio/openwrt-ipq` at commit `92a2d10`).
2. Update and install all OpenWrt feeds (including Qualcomm NSS packages).
3. Apply Device Tree, kernel timing, and offloading patches from `patches/`.
4. Copy the default offload configuration and auto-initializers from `files/`.
5. Compile the images using all available CPU cores.

Once finished, the compiled images will be located in `~/openwrt-mr7500-build/bin/targets/qualcommax/ipq60xx/`:
* `openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb`: RAM-boot testing image (zero NAND writes).
* `openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-factory.bin`: Factory installation image.
* `openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin`: Sysupgrade image for persistent flash.

---

## Flashing & Installation Guide

> [!IMPORTANT]
> **Backup First:** Before flashing custom firmware, always backup your factory partitions (`0:ART` RF calibration in `mtd8` and `devinfo` in `mtd12` are unique to your unit and irreplaceable). Use `./scripts/backup_partitions.sh` to take a full backup.

### Safe Trial: Zero-Flash RAM Boot (Recommended First Step)
You can boot OpenWrt entirely in RAM using U-Boot TFTP without touching the router's NAND flash:
1. Connect an Ethernet cable between your computer and **LAN Port 4**.
2. Configure your computer's IP address statically to `10.143.1.17` (netmask `255.255.255.0`).
3. Set up a TFTP server hosting `openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb` renamed as `mr7500-initramfs.itb`.
4. Connect a 3.3V USB-UART cable to the internal serial header (`115200 8N1`).
5. Power cycle the router and press any key to enter U-Boot:
   ```text
   IPQ6018# setenv ipaddr 10.143.1.1
   IPQ6018# setenv serverip 10.143.1.17
   IPQ6018# tftp 0x44000000 mr7500-initramfs.itb
   IPQ6018# bootm 0x44000000
   ```
The router will boot OpenWrt in RAM. Rebooting power-cycles cleanly back into stock firmware.

### Permanent Installation to Slot 1 (Preserving Stock Fallback)
Once verified in RAM:
1. Copy `openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin` to `/tmp/sysupgrade.bin` on the router:
   ```bash
   scp openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin root@10.143.1.1:/tmp/sysupgrade.bin
   ```
2. Flash to **Slot 1** using the `-s` flag (preserves Slot 2 stock firmware):
   ```bash
   sysupgrade -s -n /tmp/sysupgrade.bin
   ```
3. The router will flash Slot 1 (`mtd13`/`mtd14`), configure U-Boot to boot Slot 1 (`boot_part=1`), and reboot automatically.

---

## Dual-Boot Rollback to Stock Firmware

The stock Linksys firmware remains untouched in **Slot 2 (`alt_kernel` / `alt_rootfs`)**.
To return to factory firmware at any time:

* **From OpenWrt Terminal:**
  ```bash
  fw_setenv boot_part 2
  reboot
  ```
* **From U-Boot Serial Console:**
  ```text
  IPQ6018# setenv boot_part 2
  IPQ6018# saveenv
  IPQ6018# reset
  ```

---

## Post-Install Access & Defaults

* **Web UI (LuCI):** `https://10.143.1.1/` (Accept self-signed certificate, user `root`, no password by default).
* **SSH:** `ssh root@10.143.1.1`
* **Default LAN Subnet:** `10.143.1.1/24` (matches factory Linksys subnet to avoid upstream `192.168.1.0/24` collisions).
* **Wi-Fi Networks (Active out-of-the-box):**
  * `Linksys-MR7500-2.4G` (Channel 6, HE40)
  * `Linksys-MR7500-5G` (Channel 40, HE80)
  * `Linksys-MR7500-6G` (Channel 37, HE160, OWE Encryption)

---

## Hardware Offloading Verification Commands

Run these commands on the router to verify NSS acceleration:

```bash
# 1. Verify NSS Core 0 firmware version
cat /sys/kernel/debug/qca-nss-drv/strings/fw_ver
# Expected: NSS fw version: NSS.FW.12.5-210-CP.R

# 2. Check ath11k Wi-Fi NSS offload
cat /sys/module/ath11k/parameters/nss_offload
# Expected: 1

# 3. Check ECM acceleration engine
uci get ecm.global.acceleration_engine
# Expected: nss

# 4. Check active hardware-accelerated connections during traffic
cat /sys/kernel/debug/ecm/ecm_nss_ipv4/accelerated_count

# 5. Monitor NSS hardware packet forwarding statistics
cat /sys/kernel/debug/qca-nss-drv/stats/ipv4
```

---

## Documentation & Runbooks

Comprehensive technical documentation is organized in [`docs/`](docs/):
* [`docs/SKILL.md`](docs/SKILL.md) — Technical runbook and project knowledge base.
* [`docs/hardware-and-dts-audit.md`](docs/hardware-and-dts-audit.md) — Complete MTD partition table, memory carveouts, GPIO map, and DTS diffs.
* [`docs/test-cases-matrix.md`](docs/test-cases-matrix.md) — Detailed post-build validation matrix (`TC-01` through `TC-10`).
* [`docs/dual-boot-and-recovery.md`](docs/dual-boot-and-recovery.md) — In-depth guide to Linksys dual A/B slots and recovery methods.
* [`docs/benchmark-nss-performance.md`](docs/benchmark-nss-performance.md) — Throughput benchmark logs and CPU idle telemetry.

---

## Reference Repositories & Upstream Acknowledgements

This port builds upon the foundational work of the OpenWrt and Qualcomm NSS open-source communities:

1. **`qosmio/openwrt-ipq` (Base Repository):**
   * GitHub: [https://github.com/qosmio/openwrt-ipq](https://github.com/qosmio/openwrt-ipq)
   * Branch: `main-nss` (Linux 6.12.92 + Qualcomm NSS 12.5 integration)
2. **OpenWrt Project (Upstream):**
   * Website: [https://openwrt.org](https://openwrt.org)
   * Git: [https://github.com/openwrt/openwrt](https://github.com/openwrt/openwrt)
3. **OpenWrt Wiki — Linksys MR7500 (Hydra Pro 6E):**
   * Wiki: [https://openwrt.org/toh/linksys/mr7500](https://openwrt.org/toh/linksys/mr7500)
4. **Qualcomm NSS Packages Feed (`qosmio/nss-packages`):**
   * GitHub: [https://github.com/qosmio/nss-packages](https://github.com/qosmio/nss-packages)
5. **Linux Kernel Firmware Repository:**
   * Git: [https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)
6. **Official Linksys Stock Firmware (v1.1.12.216943):**
   * Download: [https://downloads.linksys.com/support/assets/firmware/FW_MR7500_1.1.12.216943_prod.img](https://downloads.linksys.com/support/assets/firmware/FW_MR7500_1.1.12.216943_prod.img)

---

## License

All DTS additions, configuration overlays, helper scripts, and documentation in this repository are licensed under the **GNU General Public License v2.0 (GPL-2.0)** to match upstream OpenWrt.
