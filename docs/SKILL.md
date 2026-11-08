---
name: mr7500-nss-openwrt
description: >-
  Comprehensive project runbook, hardware specification, stock firmware analysis,
  DTS patch checklist, backup verification protocol, and build/test workflow for
  porting Qualcomm NSS hardware offloading to OpenWrt on the Linksys MR7500
  (Hydra Pro 6E, IPQ6018).
---

# Linksys MR7500 (Hydra Pro 6E) OpenWrt + NSS Porting Guide & Runbook

This runbook documents the hardware architecture, required Device Tree (`.dts`) and kernel patches, backup verification protocol, and OpenWrt + NSS build/test procedures for the **Linksys MR7500 v1 (codename `divo`)**.

## 1. Hardware Architecture & Specifications

* **SoC:** Qualcomm IPQ6018 (`Qualcomm Technologies, Inc. IPQ6018/AP-CP01-C3`, `machid=8030002`), 4x ARM Cortex-A53 @ 1.8 GHz.
* **RAM:** 512 MB DDR3L (`386,492 kB` usable in Linux 6.12 after hardware carveouts, ~129 MB available at idle on persistent NAND boot).
* **Flash:** 512 MB SLC NAND (Hynix `H27S4G8F2EDA-BC`, `erasesize=0x20000` / 128 KiB, `pagesize=2048`, `0` bad blocks).
  * Dual A/B boot slots:
    * **Slot 1 (`boot_part=1`):** `kernel` (`mtd13`, offset `0xb80000`, 8 MiB) + `rootfs` (`mtd14`, 74 MiB)
    * **Slot 2 (`boot_part=2`):** `alt_kernel` (`mtd15`, offset `0x5d80000`, 8 MiB) + `alt_rootfs` (`mtd16`, 74 MiB)
* **Ethernet & Switch:**
  * **LAN 1–4 (`dp1..dp4`):** QCA8075 PHY (`MDIO 0..3`) over `QSGMII`.
  * **WAN Multi-Gigabit (`dp5_syn`):** Marvell/Aquantia **AQR114C-B0** PHY (`MDIO 8`, Clause 45) over `USXGMII` driven by Synopsys XGMAC (`0x3a003000`). Requires `AQR114C.cld` firmware and C45 probe wait patch `0982`.
* **Wi-Fi Radios (Tri-Band Wi-Fi 6E):**
  * **2.4 GHz (`phy1`, 2x2 ax HE40):** IPQ6018 internal (`QCN5022`, `bdwlan.b11`).
  * **5 GHz (`phy0`, 2x2 ax HE80):** IPQ6018 internal (`QCN5052`, `bdwlan.b11`).
  * **6 GHz (`phy2`, 4x4 ax HE160):** PCIe `0000:01:00.0` (`17cb:1104` QCN9024/QCN9074, `qcn9000/bdwlan.ba4`, OWE encryption, `fw-memory-mode = 1`).

---

## 2. Key Hardware Fixes & Discoveries

1. **Aquantia AQR114C Reset & Cold-Boot Probe Timing (`0982` Patch):**
   * The reset line is TLMM GPIO 77 (`GPIO_ACTIVE_LOW`).
   * When cold booting, the AQR114C PHY internal ROM takes ~260 ms after power-on to respond to MDIO address 8. Because the Linux kernel MDIO core probes PHY ID before executing `reset-gpios`, an unpatched kernel reports `MDIO device at address 8 is missing`.
   * Patch `0982-net-mdio-fwnode-wait-for-c45-phy-with-reset-gpios.patch` adds a 250 ms retry loop for Clause 45 PHYs with `reset-gpios`, enabling 100% reliable detection on cold boot.
2. **0:ETHPHYFW (`mtd9`) vs `AQR114C.cld`:**
   * The stock `0:ETHPHYFW` partition in flash holds an older `0x5f802`-byte payload. Stock firmware `1.1.12.216943` ships the updated `0x60002`-byte (`393,218` B) `v5.6.5 Cybertan Divo` firmware in `/etc/AQR114C.cld`.
   * OpenWrt loads this firmware directly from `/lib/firmware/marvell/AQR114C.cld` via `firmware-name = "marvell/AQR114C.cld"`.
3. **Qualcomm NSS VLAN Offload Requirement (`lan4.100` vs `br-lan.100`):**
   * `qca-nss-vlan` registers dynamic NSS data-plane instances only on physical switch ports (`lan1..lan4` / `wan`). Attaching an 802.1Q VLAN to `br-lan` fails (`br-lan: 31 is not valid physical port`).
4. **OpenWrt 25.x First-Boot LAN Netmask:**
   * OpenWrt 25.x uses `list ipaddr '192.168.1.1/24'`. Changing only `ipaddr` without deleting the list results in `/32`. `files/etc/uci-defaults/99-mr7500-nss-defaults` deletes `ipaddr` and sets both `ipaddr='10.143.1.1'` and `netmask='255.255.255.0'`.

---

## 3. Mandatory Backup Protocol (Before Flashing)

Before writing to NAND flash, backup all 20 MTD partitions (`mtd0`–`mtd19`):
1. **Irreplaceable partitions:** `mtd8` (`0:ART` - per-unit RF calibration) and `mtd12` (`devinfo` - serial, factory MACs, certificates).
2. **Verification rule:** Compute SHA-256 on the router (`sha256sum /dev/mtd*`) and compare against the backed-up files. Store copies in multiple offline locations.
