---
name: mr7500-nss-openwrt
description: >-
  Comprehensive project runbook, hardware specification, stock firmware analysis,
  DTS patch checklist, backup verification protocol, and build/test workflow for
  porting Qualcomm NSS hardware offloading to OpenWrt on the Linksys MR7500
  (Hydra Pro 6E, IPQ6018). Activate this skill whenever working on the Linksys
  MR7500 OpenWrt NSS build, UART/COM4 debugging, flash backups, blob extraction,
  or Ubuntu VM compilation.
---

# Linksys MR7500 (Hydra Pro 6E) OpenWrt + NSS Porting Skill

This skill documents the hardware architecture, verified stock firmware state, required Device Tree (`.dts`) and kernel patches, triple-read backup verification rules, and OpenWrt + NSS build/test procedures for the **Linksys MR7500 v1 (codename `divo`)**.

## 1. Environment & Access Topology

* **Windows Host (`192.168.1.80`):**
  * **Workspace:** `c:\Users\Sanjay\Desktop\Mr7500`
  * **Router UART (`COM4`):** FT232 USB-UART connected at `115200 8N1` (3.3V logic). Driven via [tools/uart.py](../../../tools/uart.py) (`BypassSandbox: true` required on Windows for COM port access).
  * **Stock Serial Login:** Username `root`, Password `Sanjay@386` (factory default after reset is `root` / `admin`).
  * **OpenWrt Serial / SSH / LuCI Login:** Username `root`, no password by default (`10.143.1.1/24`, `https://10.143.1.1/`).
* **Ubuntu 26.04 LTS Build VM (`192.168.1.88`):**
  * **SSH Access:** User `zero`, Password `sanjay` (passwordless `sudo` configured). Driven non-interactively via [tools/vm_exec.py](../../../tools/vm_exec.py) (`BypassSandbox: true`).
  * **System Specs:** 8 vCPUs, 14 GiB RAM, 86 GiB free disk, GCC 15.2 + GCC 14.3 (`~/mr7500/hostcc-gcc14` wrapper for OpenWrt host tools) + Clang 21.1.
  * **NIC 1 (`enp1s0`, Intel I226-V `igc`):** `192.168.1.88/24` on main LAN (default route `192.168.1.1` for internet/git/apt).
  * **NIC 2 (`enp2s0`, Realtek RTL8168 `r8169`):** `10.143.1.17/24` directly connected to the Linksys MR7500 `lan4` (`dp4`) port (`10.143.1.1/24`, configured with `ConfigureWithoutCarrier=yes` and `IgnoreCarrierLoss=yes` so the IP remains bound during router reboots). Serves `/srv/tftp/mr7500-initramfs.itb` via `tftpd-hpa` for U-Boot `tftp 0x44000000 mr7500-initramfs.itb` RAM-boot testing.

---

## 2. Hardware & Live Firmware Baseline

Detailed live telemetry is stored in [work/live_stock_recon_clean.txt](../../../work/live_stock_recon_clean.txt) and [references/hardware-and-dts-audit.md](./references/hardware-and-dts-audit.md).

* **SoC:** Qualcomm IPQ6018 (`Qualcomm Technologies, Inc. IPQ6018/AP-CP01-C3`, `machid=8030002`), 4x ARM Cortex-A53 @ 1.8 GHz.
* **RAM:** 512 MB DDR3L (`386,492 kB` total in Linux 6.12 after reserved carveouts, ~129 MB free/available on persistent NAND boot).
* **Flash:** 512 MB Hynix `H27S4G8F2EDA-BC` SLC NAND (`erasesize=0x20000` / 128 KiB, `pagesize=2048`, `0` bad PEBs), dual A/B slots:
  * **Slot 1 (`boot_part=1`):** `kernel` (`mtd13`, `0xb80000`) + `rootfs` (`mtd14`) — Active OpenWrt 6.12.92 + NSS 12.5.
  * **Slot 2 (`boot_part=2`):** `alt_kernel` (`mtd15`, `0x5d80000`) + `alt_rootfs` (`mtd16`) — Untouched Stock OEM `1.1.12.216943` fallback.
* **Ethernet / Switch:**
  * **LAN 1–4 (`dp1..dp4`):** QCA8075 PHY (`MDIO 0..3`) over `QSGMII` (`switch_mac_mode = <0x0>`), factory MAC `D8:EC:5E:13:18:FC`.
  * **WAN Multi-Gigabit (`dp5_syn`):** Marvell/Aquantia **AQR114C-B0** PHY (`MDIO 8`, C45) over `USXGMII` (`switch_mac_mode1 = <0xd>`) driven by Synopsys XGMAC (`0x3a003000`), factory MAC `D8:EC:5E:13:18:FB`. Requires `AQR114C.cld` (`v5.6.5 Cybertan Divo`) and C45 probe wait patch `0982-net-mdio-fwnode-wait-for-c45-phy-with-reset-gpios.patch`. Verified linking up at **2500 Mb/s Full Duplex** out-of-the-box on cold boot.
* **Wi-Fi Radios (Tri-Band Wi-Fi 6E):**
  * **2.4 GHz (`phy1`, 2x2 ax HE40):** IPQ6018 internal (`QCN5022`, `bdwlan.b11`, MAC `D8:EC:5E:13:18:FC`).
  * **5 GHz (`phy0`, 2x2 ax HE80):** IPQ6018 internal (`QCN5052`, `bdwlan.b11`, MAC `D8:EC:5E:13:18:FD`).
  * **6 GHz (`phy2`, 4x4 ax HE160):** PCIe `0000:01:00.0` (`17cb:1104` QCN9024/QCN9074, `qcn9000/bdwlan.ba4`, MAC `D8:EC:5E:13:18:FE`, OWE encryption).

---

## 3. Completed Milestones & Verification Status

1. **Triple-Redundant Full MTD Backup (`27/27 PASS, 0 FAILURES`):**
   * Stored on Ubuntu VM (`~/mr7500/backups/{pass1,pass2,pass3,source_of_truth}/`) and mirrored locally to [backups/](../../../backups/).
   * Verified `pass1 == pass2 == pass3 == router_sha256` in [backups/SHA256_VERIFICATION_REPORT.txt](../../../backups/SHA256_VERIFICATION_REPORT.txt).
2. **Stock Firmware Blob Analysis & NSS 11.5 Fallback Archive (`DONE`):**
   * Extracted stock `FW_MR7500_1.1.12.216943_prod.img`.
   * Complete stock fallback bundle preserved in `~/mr7500/stock_nss_11_5_fallback/` and [stock_nss_11_5_fallback/](../../../stock_nss_11_5_fallback/).
3. **Custom OpenWrt 6.12.92 + NSS 12.5 Firmware Build (`DONE`):**
   * Built from `qosmio/openwrt-ipq` (`main-nss` @ `92a2d10`, branch `mr7500-nss-default`) with `NSS.FW.12.5-210-CP.R`, EIP-197 crypto, `ath11k` (`WLAN.HK.2.12-01460`, `nss_offload=1 frame_mode=2`), OEM `AQR114C.cld` (`v5.6.5 Cybertan Divo`), `luci-ssl`, `luci-app-sqm`, and `sqm-scripts-nss`.
   * Built images stored locally in [bin/](../../../bin/):
     * [openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb](../../../bin/openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb) (`18,357,504` B) — SHA-256: `2456e02566866fc4741220ee7835161af74d1c361e9bac2c025339c5ba9aa542`
     * [openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-factory.bin](../../../bin/openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-factory.bin) (`21,235,712` B) — SHA-256: `441a564149e741c1b3677e17a1d9ca6f7dd082aa8a1e72e6f7d46b83b214d66a`
     * [openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin](../../../bin/openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin) (`17,643,784` B) — SHA-256: `a896390e0af4b2fd381186335318cbab304038103b11cb96fea123092ff788b7`
     * [sha256sums](../../../bin/sha256sums) (`836` B) — SHA-256: `b4e53df08ed6e5a05ea9e95240205ebc392271a48b1afaf68e43d59cfe56efcd`
4. **Stage A & Stage B Validation (`100% PASS` across all test cases `TC-01` through `TC-08` & `TC-10`):**
   * **NSS NAT Throughput:** **944 Mbps** line rate across SNAT with **99.95% ARM Cortex-A53 CPU idle** (`0.03% %soft` sirq).
   * **Multi-Gigabit WAN:** AQR114C links up at **2500 Mb/s Full Duplex** on cold unattended boot via kernel C45 probe wait patch `0982`.
   * **Tri-Band Wi-Fi 6E:** All 3 radios broadcasting out-of-the-box (`2.4G HE40`, `5G HE80`, `6G HE160 OWE`).
   * **Dual-Slot Protection:** Slot 2 (`mtd15`/`mtd16`) verified 100% bit-for-bit identical to OEM backup pass1. Rollback to OEM `1.1.12.216943` guaranteed via `fw_setenv boot_part 2` or U-Boot `setenv boot_part 2; saveenv; reset`.

---

## 4. Key Discoveries & Implementation Reference

* **Aquantia AQR114C USXGMII In-Band Clause 37 Auto-Negotiation (OpenWrt commit `c12a451`):**
  * Standard USXGMII carries the line rate to the Synopsys XGMAC in a Clause 37 code word. Without in-band signaling enabled on the PHYXS interface, no packets cross the SerDes (`rx_frame: 0`), preventing WAN DHCP client from receiving offers.
  * Resolved by enabling Clause 37 auto-negotiation in PHYXS register `4:0xc441 = 0x0008` (bit 3) and adding `managed = "in-band-status";` in `&dp5_syn` in `ipq6018-mr7500.dts`.
  * Automated persistently on boot and interface events via `/etc/rc.local` and `/etc/hotplug.d/iface/10-wan-aqr`.
* **C45 PHY Probe Timing Fix (`0982-net-mdio-fwnode-wait-for-c45-phy-with-reset-gpios.patch`):**
  * Linux `fwnode_mdiobus_register_phy` queries Clause 45 PHY ID before executing `reset-gpios`. A cold-booted AQR114C PHY takes ~260 ms after power-on to respond on MDIO address 8. Adding a 250 ms retry loop in `fwnode_mdio.c` allows the PHY to answer reliably without race conditions on unattended boot.
* **OpenWrt 25.x First-Boot LAN Netmask:**
  * OpenWrt 25.x uses `list ipaddr '192.168.1.1/24'`. Setting only `option ipaddr '10.143.1.1'` creates `/32`. In `files/etc/uci-defaults/99-mr7500-nss-defaults`, delete `ipaddr` and set both `ipaddr='10.143.1.1'` and `netmask='255.255.255.0'`.
* **802.1Q VLAN Offload (`qca-nss-vlan`):**
  * Attach VLANs to physical data-plane ports (e.g. `lan4.100`) rather than bridge interface (`br-lan.100`), as `qca-nss-vlan` requires a valid physical switch port ID.
* **Linksys Dual-Slot `sysupgrade`:**
  * Use `sysupgrade -s -n /tmp/sysupgrade.bin` when booted from Slot 1 (`boot_part=1`) to upgrade the current active slot without touching Slot 2 fallback.
* **Wi-Fi RX Path vs NSS Offload (`ath11k nss_offload=0 frame_mode=0`):**
  * When `ath11k` is loaded with `nss_offload=1 frame_mode=2` on OpenWrt 24.10 / Linux 6.12 with NSS 12.5 on IPQ6018 (512MB RAM), the closed-source `qca-nss-wifili` driver suffers from RX descriptor pool starvation (`rx_desc_no_pb: 321531`), silently discarding all incoming Wi-Fi RX frames (DHCP discovers, ARP replies, DNS queries).
  * Resolved by configuring `ath11k nss_offload=0 frame_mode=0` in `/etc/modules.d/ath11k`. Wi-Fi frames are processed directly by Linux `mac80211`, while Qualcomm NSS ECM continues to accelerate all routed/NAT packets between `br-lan` and `wan` at full wire speed (944+ Mbps).
* **Apple iOS / iPadOS IPv6 SLAAC Compatibility:**
  * Apple devices do not support stateful DHCPv6 address assignment. Setting `ra_flags 'managed-config'` causes iOS/iPadOS to decline IPv6 address configuration.
  * Resolved by removing `managed-config` and configuring `ra_flags 'other-config'`, `ra_slaac '1'`, and `ra_default '1'` in `/etc/config/dhcp`, enabling RFC 4862 SLAAC with RFC 8106 RDNSS recursive DNS.
* **LAN Subnet & Gateway Hygiene:**
  * Interface `lan` must never have `option gateway '192.168.1.1'`. An off-subnet gateway causes modern operating systems (iOS, macOS, Windows) to discard the default router. Default route belongs solely on `wan` via DHCP.
  * DHCP option 3 (`3,10.143.1.1`) and option 6 (`6,10.143.1.1`) explicitly advertise the router's IP as default gateway and recursive DNS server to all LAN/Wi-Fi clients.
