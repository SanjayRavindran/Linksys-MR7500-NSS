# Linksys MR7500 (Hydra Pro 6E) — Known Issues, Root Cause Analyses & Fixes

This document compiles all major engineering challenges, bugs, timing races, and architectural hurdles encountered during the development and porting of OpenWrt with Qualcomm NSS hardware acceleration on the **Linksys MR7500 v1 (Qualcomm IPQ6018, Aquantia AQR114C, QCN9074)**, along with their root causes, diagnostic signatures, and permanent fixes.

---

## Index of Issues

1. [Issue 1: AQR114C Multi-Gigabit PHY Cold-Boot Probe Timing Race](#issue-1-aqr114c-multi-gigabit-phy-cold-boot-probe-timing-race)
2. [Issue 2: Aquantia AQR114C USXGMII Clause 37 In-Band Auto-Negotiation Failure](#issue-2-aquantia-aqr114c-usxgmii-clause-37-in-band-auto-negotiation-failure)
3. [Issue 3: Closed-Source NSS Wi-Fi Driver RX Descriptor Pool Starvation (`rx_desc_no_pb`)](#issue-3-closed-source-nss-wi-fi-driver-rx-descriptor-pool-starvation-rx_desc_no_pb)
4. [Issue 4: OpenWrt First-Boot Netmask Bug Resulting in `/32` Host Route](#issue-4-openwrt-first-boot-netmask-bug-resulting-in-32-host-route)
5. [Issue 5: Apple iOS / iPadOS IPv6 SLAAC Address Assignment Failure](#issue-5-apple-ios--ipados-ipv6-slaac-address-assignment-failure)
6. [Issue 6: Off-Subnet LAN Gateway Contamination Dropping Client Default Routes](#issue-6-off-subnet-lan-gateway-contamination-dropping-client-default-routes)
7. [Issue 7: NSS 802.1Q VLAN Hardware Offload Binding Constraint](#issue-7-nss-8021q-vlan-hardware-offload-binding-constraint)
8. [Issue 8: USB 3.0 VBUS Power Regulator & Missing Filesystem Modules](#issue-8-usb-30-vbus-power-regulator--missing-filesystem-modules)
9. [Issue 9: CSR8811 Bluetooth Subsystem Power Management & RF Co-existence](#issue-9-csr8811-bluetooth-subsystem-power-management--rf-co-existence)
10. [Issue 10: Dual A/B Slot Flash Integrity & Safe Sysupgrade Protocol](#issue-10-dual-ab-slot-flash-integrity--safe-sysupgrade-protocol)
11. [Issue 11: AQR114C Slow Probe vs `phy_attach_direct()` Boot Race (`PHY_READY` Freeze & Null `dev_name` Oops)](#issue-11-aqr114c-slow-probe-vs-phy_attach_direct-boot-race-phy_ready-freeze--null-dev_name-oops)
12. [Issue 12: 5G WAN LED Offload Blocking & Switch+AP `uci-defaults` Sysupgrade Clobber](#issue-12-5g-wan-led-offload-blocking--switchap-uci-defaults-sysupgrade-clobber)
13. [Issue 13: `qca-nss-pbuf` Early Exit With `ath11k nss_offload=0`, CPU 0 IRQ Saturation, & SSDK GMAC `IPGT`](#issue-13-qca-nss-pbuf-early-exit-with-ath11k-nss_offload0-cpu-0-irq-saturation--ssdk-gmac-ipgt)
14. [Issue 14: Dead `&nss_macsec0`, Unused CSR8811 `blsp1_uart2`, & AQR114C DTS NVMEM Downgrade Guard](#issue-14-dead-nss_macsec0-unused-csr8811-blsp1_uart2--aqr114c-dts-nvmem-downgrade-guard)
15. [Issue 15: Aquantia AQR114C 5GbE Port Link Failure on Boot & Hotplug (`USXGMII` C37 AN Drop)](#issue-15-aquantia-aqr114c-5gbe-port-link-failure-on-boot--hotplug-usxgmii-c37-an-drop)
16. [Issue 16: `ath11k_ahb` Copy Engine `ce3` Edge-IRQ Freeze (`-105`/`-ENOBUFS` WMI Timeout & `D`-State Hang)](#issue-16-ath11k_ahb-copy-engine-ce3-edge-irq-freeze--105-enobufs-wmi-timeout--d-state-hang)
17. [Issue 17: Aquantia AQR114C Volatile Firmware Loss on Hotplug & Zero LED Blink Stretch (`Patch 0007`)](#issue-17-aquantia-aqr114c-volatile-firmware-loss-on-hotplug--zero-led-blink-stretch-patch-0007)
18. [Issue 18: QCA8075 1GbE LAN Ports Dead RX (`rx=0`) After Boot (`QSGMII` vs `PSGMII` Mismatch)](#issue-18-qca8075-1gbe-lan-ports-dead-rx-rx0-after-boot-qsgmii-vs-psgmii-mismatch)

---

### Issue 1: AQR114C Multi-Gigabit PHY Cold-Boot Probe Timing Race

* **Severity:** **CRITICAL** (Loss of WAN Interface on Cold Boot).
* **Symptom:** On cold boot or power cycling, the 5GbE WAN interface failed to probe (`dp5_syn: PHY [mdio@1:08] not found`). The router required manual rebooting or reloading drivers to discover the PHY.
* **Root Cause:** In Linux `drivers/net/mdio/fwnode_mdio.c`, the kernel queries the Clause 45 PHY ID registers (`devices_in_package` MMD registers `0x0005` / `0x0006`) immediately upon bus registration. The Marvell/Aquantia AQR114C PHY contains an internal Synopsys ARC processor that boots from internal ROM/flash, requiring ~260 ms after power-up/reset deassertion to respond over the MDIO bus. Because Linux probed at ~10 ms, the query timed out and the driver abandoned PHY registration.
* **Diagnostic Telemetry:**
  ```text
  [    2.312015] mdio_bus 1:08: PHY ID read failed (-ETIMEDOUT)
  [    2.312500] qcom-ess-edma 3a000000.ess-edma dp5_syn: could not attach to PHY
  ```
* **Permanent Fix:** Created kernel patch `0982-net-mdio-fwnode-wait-for-c45-phy-with-reset-gpios.patch` in `target/linux/qualcommax/patches-6.12/`. The patch inserts a retry loop with 15x 20ms delays (up to 300 ms) when probing Clause 45 PHYs associated with reset GPIOs:
  ```text
  [    2.571420] fwnode_mdiobus_register_phy: C45 PHY at address 8 became ready after 260 ms
  [    2.571810] mdio_bus 1:08: attached PHY driver [Aquantia AQR114C] (mii_bus:phy_addr=1:08)
  ```

---

### Issue 2: Aquantia AQR114C USXGMII Clause 37 In-Band Auto-Negotiation Failure

* **Severity:** **CRITICAL** (Physical Link Up, Zero Throughput).
* **Symptom:** The WAN port indicated physical link carrier (`Link is Up - 2.5Gbps/Full`), but zero Ethernet frames crossed the interface (`rx_frame: 0`). The WAN DHCP client (`udhcpc`) never received DHCP offers.
* **Root Cause:** Standard USXGMII operation requires Clause 37 in-band signaling over SerDes between the AQR114C PHYXS and the IPQ6018 UNIPHY XPCS. The PHY transmits speed/duplex negotiation words inside the USXGMII stream. On stock firmware, Linksys configured bit 3 of PHYXS register `0xc441` (`4:0xc441 = 0x0008`) to enable in-band auto-negotiation. Under standard Linux, this register remained at `0x0000`, causing the Synopsys XGMAC to discard incoming SerDes data.
* **Diagnostic Telemetry:**
  ```bash
  phytool read eth5/4/0xc441
  # Output was: 0x0000 (Clause 37 in-band autoneg disabled)
  ethtool -S wan | grep rx_frame
  # Output: rx_frame: 0 (No packets passing SerDes)
  ```
* **Permanent Fix:**
  1. Enabled Clause 37 auto-negotiation in PHYXS register `4:0xc441 = 0x0008`.
  2. Added `managed = "in-band-status";` in `&dp5_syn` in `ipq6018-mr7500.dts`.
  3. Automated persistently on boot and interface events via `/etc/rc.local` and `/etc/hotplug.d/iface/10-wan-aqr`.
  4. Line rate immediately restored: sustained **2.32 Gbps Upload / 2.37 Gbps Download** with 0 retransmissions.

---

### Issue 3: Closed-Source NSS Wi-Fi Driver RX Descriptor Pool Starvation (`rx_desc_no_pb`)

* **Severity:** **HIGH** (Wi-Fi Clients Cannot Connect or Route Traffic).
* **Symptom:** Wireless devices (iPads, smartphones, laptops) authenticated and associated with SSIDs, but failed to acquire DHCP leases or transmit data. Serial console and dmesg showed heavy frame drops.
* **Root Cause:** When `ath11k` loaded with NSS offload mode (`nss_offload=1 frame_mode=2`), the closed-source `qca-nss-wifili` kernel module attempted to handle raw 802.11 frames in hardware. On devices with 512MB RAM running Linux 6.12 with NSS 12.5, the driver exhausted its pre-allocated RX buffer pool (`rx_desc_no_pb`), silently discarding every single incoming Wi-Fi frame (DHCP Discover, ARP Requests, DNS queries).
* **Diagnostic Telemetry:**
  ```bash
  cat /sys/kernel/debug/qca-nss-drv/stats/wifili
  # rx_desc_no_pb: 321531 (Every incoming Wi-Fi frame dropped due to pool exhaustion!)
  ```
* **Permanent Fix:** Configured `ath11k` to use native Linux `mac80211` host processing (`nss_offload=0 frame_mode=0`) in `/etc/modules.d/ath11k`. Wi-Fi frames are processed directly by the Linux kernel network stack with zero packet loss (`rx_desc_no_pb == 0`), while Qualcomm NSS ECM continues to accelerate all routed/NAT packets between `br-lan` and `wan` at wire speed (944+ Mbps).

---

### Issue 4: OpenWrt First-Boot Netmask Bug Resulting in `/32` Host Route

* **Severity:** **HIGH** (No LAN Subnet Routing on Fresh Flash).
* **Symptom:** LAN clients received IP `10.143.1.100`, but could not ping `10.143.1.1` or access LuCI/SSH.
* **Root Cause:** In OpenWrt 24.10 / 25.x, network configuration templates transitioned from separate `ipaddr` and `netmask` options to CIDR notation (`list ipaddr '192.168.1.1/24'`). The initial UCI default script used `set network.lan.ipaddr='10.143.1.1'`. Without explicitly deleting the prior list or passing CIDR, the kernel assigned `10.143.1.1/32`, destroying the local broadcast and subnet route.
* **Permanent Fix:** Updated `files/etc/uci-defaults/99-mr7500-nss-defaults` to execute `uci delete network.lan.ipaddr` before configuring `set network.lan.ipaddr='10.143.1.1'` and `set network.lan.netmask='255.255.255.0'`.

---

### Issue 5: Apple iOS / iPadOS IPv6 SLAAC Address Assignment Failure

* **Severity:** **MEDIUM** (Apple Devices Drop IPv6 Internet Reachability).
* **Symptom:** iPads and iPhones connected to Wi-Fi failed to acquire IPv6 addresses, reporting "No Internet" or falling back to IPv4 only.
* **Root Cause:** In `/etc/config/dhcp`, `ra_flags` was set to `'managed-config'`. This flag commands clients to request IPv6 addresses via stateful DHCPv6 (IA_NA). Apple iOS, iPadOS, and macOS deliberately do not implement stateful DHCPv6 by design (they mandate RFC 4862 SLAAC). When told to use DHCPv6, iOS aborted IPv6 auto-configuration.
* **Permanent Fix:** Configured RFC 4862 SLAAC with RFC 8106 RDNSS in `/etc/config/dhcp`:
  ```uci
  set dhcp.lan.ra_flags='other-config'
  set dhcp.lan.ra_slaac='1'
  set dhcp.lan.ra_default='1'
  set firewall.@defaults[0].masq6='1'
  ```
  All iOS, Android, and Windows devices immediately receive global IPv6 addresses and 100% IPv6 test scores.

---

### Issue 6: Off-Subnet LAN Gateway Contamination Dropping Client Default Routes

* **Severity:** **HIGH** (Clients Randomly Lose Default Gateway).
* **Symptom:** Windows and macOS clients connected to LAN intermittently showed "No Internet Access" despite active link.
* **Root Cause:** The `network.lan` interface had an erroneous `option gateway '192.168.1.1'`. When `dnsmasq` advertised this off-subnet gateway to clients in `10.143.1.0/24`, modern operating system routing stacks detected that the default gateway was not reachable within the local subnet and discarded the route.
* **Permanent Fix:** Removed `option gateway` from `network.lan`. Default gateway belongs strictly on `network.wan` via DHCP. Added explicit DHCP Options `3,10.143.1.1` (Router) and `6,10.143.1.1` (DNS Server) in `/etc/config/dhcp`.

---

### Issue 7: NSS 802.1Q VLAN Hardware Offload Binding Constraint

* **Severity:** **MEDIUM** (VLAN Hardware Offload Rejection).
* **Symptom:** Configuring 802.1Q tagged VLANs on the Linux bridge (`br-lan.100`) caused Qualcomm NSS driver to reject offloading with error `-EINVAL`.
* **Root Cause:** Qualcomm NSS `qca-nss-vlan` driver requires a direct physical switch port identifier (e.g. `dp1`..`dp4` or `lan1`..`lan4`) to program the hardware VLAN translation tables in the switch fabric. It cannot bind to virtual bridge netdevices.
* **Permanent Fix:** VLANs must be created directly on the physical interface (e.g., `lan4.100`), which can then be bridged if necessary.

---

### Issue 8: USB 3.0 VBUS Power Regulator & Missing Filesystem Modules

* **Severity:** **LOW** (USB Storage Devices Inactive).
* **Symptom:** Plugging a USB 3.0 flash drive into the router resulted in no power (drive LED unlit, no `usb 2-1` dmesg events).
* **Root Cause:** The Qualcomm DWC3 host controller requires an external VBUS power regulator driven by GPIO 25 (`tlmm 25 GPIO_ACTIVE_LOW`). Because the regulator was not active, no power reached the port. Furthermore, stock OpenWrt images lacked FAT/exFAT filesystem modules.
* **Permanent Fix:**
  1. Configured `reg_usb_vbus` with GPIO 25 active-low drive.
  2. Verified live USB 3.0 connection: device detected at 5 Gbps SuperSpeed (`sd 0:0:0:1: [sdb] Attached SCSI removable disk`).
  3. Added `kmod-fs-vfat`, `kmod-fs-exfat`, `kmod-nls-*`, and `usbutils` to `mr7500_nss_diffconfig`.

---

### Issue 9: CSR8811 Bluetooth Subsystem Power Management & RF Co-existence

* **Severity:** **LOW** (Parasitic Power Drain & Potential 2.4GHz RF Degradation).
* **Symptom:** Unmanaged Bluetooth chip on UART 2 floating in unknown state.
* **Root Cause:** The Cambridge Silicon Radio CSR8811 BLE 4.1 chip is connected to QUP UART 2 (`blsp1_uart2`) and powered via **GPIO 34** (`gpio546`). Stock OEM firmware only used Bluetooth for initial mobile app pairing. Leaving the chip powered on consumes ~50–80 mW of power and introduces RF noise in the 2.4 GHz spectrum.
* **Permanent Fix:** Documented and configured GPIO 34 to be held in reset (`echo 0 > /sys/class/gpio/gpio546/value`). This powers down the radio, cuts parasitic draw, and improves 2.4 GHz Wi-Fi SNR.

---

### Issue 10: Dual A/B Slot Flash Integrity & Safe Sysupgrade Protocol

* **Severity:** **CRITICAL** (Risk of Permanent Device Bricking).
* **Symptom:** Flashing OpenWrt to flash partitions without slot awareness could overwrite the factory OEM fallback in Slot 2 (`mtd15`/`mtd16`), eliminating disaster recovery.
* **Root Cause:** The Linksys MR7500 utilizes dual-boot A/B partitioning:
  * Slot 1: `mtd13` (`kernel`), `mtd14` (`rootfs`).
  * Slot 2: `mtd15` (`alt_kernel`), `mtd16` (`alt_rootfs`).
* **Permanent Fix:**
  1. Preserved Slot 2 untouched as verified against factory backup pass1.
  2. Mandated the use of `sysupgrade -s -n /tmp/sysupgrade.bin` when booted from Slot 1 (`boot_part=1`), which restricts writes exclusively to Slot 1 partitions and guarantees rollback to OEM stock firmware via U-Boot `setenv boot_part 2; saveenv; reset`.

---

### Issue 11: AQR114C Slow Probe vs `phy_attach_direct()` Boot Race (`PHY_READY` Freeze & Null `dev_name` Oops)

* **Severity:** **CRITICAL** (Complete 5G Ethernet Port Failure & Post-Probe Kernel Oops).
* **Symptom:**
  1. On cold boot, the Marvell/Aquantia 5G port (`wan` / `dp5-syn`) stayed permanently link-down (`carrier=0`, `Speed: Unknown!`, `tx_frame: 0`, `br-lan` port 5 `disabled`) and unreachable from an upstream 2.5G switch even though copper autonegotiation completed at `2500Mb/s Full` (`7/0xc800=0x0009`). Running `ip link set wan down` triggered a kernel `WARN` in `phy_stop` (`called from state READY`).
  2. Once `phy_attach_direct()` was serialized behind `phy_probe()`, boot hit a second race: a `strlen(NULL)` Kernel Oops in `netdev_trig_activate()` triggered by the `led` hotplug event (`/etc/hotplug.d/leds/00-init`), causing Linksys `auto_recovery` to fall back to Slot 2.
* **Root Cause:**
  1. **Probe vs Attach Race:** Early `kmodloader` (`18-phy-aquantia`) starts `phy_probe()` -> `aqr107_probe()` -> `aqr_firmware_load()` (`v5.6.5 Cybertan Divo 090221 14:43:44`), which holds `device_lock(d)` and sets `d->driver`, then spends ~29 seconds loading 384 KB `AQR114C.cld` over MDIO. During that window, `S10boot` loads `qca-nss-dp` (`nss_dp_probe()`), calling `of_phy_connect()` -> `phy_attach_direct()`. Because `phy_attach_direct()` checked `d->driver` without acquiring `device_lock(d)`, it attached prematurely (`PHY_UP`), configured `4:0xc441`, and then had `aqr_fw_boot()` reset stall registers (wiping `4:0xc441` back to `0x0000`) and `phy_probe()` overwrite `phydev->state = PHY_READY`—freezing phylib's state machine forever.
  2. **Unregistered Netdev LED Hotplug Race:** `nss_dp_probe()` calls `of_phy_connect()` before `register_netdev()`. When `phy_probe()` finishes and registers `of_phy_leds()`, the LED `add` uevent runs `netdev_trig_activate()` -> `phy_led_hw_control_get_device()` on an `attached_dev` whose `dev_name()` is still `NULL` (`reg_state != NETREG_REGISTERED`).
* **Permanent Fix:**
  1. Added `0984-net-phy-serialize-attach-with-probe.patch`: acquires `device_lock(d)` / `device_unlock(d)` in `phy_attach_direct()` around the driver check and bind so `nss-dp` cleanly waits until `aqr_firmware_load()` and `of_phy_leds()` complete.
  2. Added `0985-net-phy-led-hw-control-check-registered-netdev.patch`: requires `phydev->attached_dev->reg_state == NETREG_REGISTERED` in `phy_led_hw_control_get_device()` and checks `if (name)` in `netdev_trig_activate()`.
  3. Bundled both patches along with `0983-net-phy-aquantia-enable-usxgmii-autoneg.patch` and `package/kernel/qca-ssdk/patches/001-uniphy-usxgmii-autoneg.patch` in `patches/0003-qualcommax-mr7500-fix-usxgmii-probe-race-and-wan-leds.patch`, removed the redundant `/etc/rc.local` polling loop, and added `CONFIG_PACKAGE_phytool=y`.

---

### Issue 12: 5G WAN LED Offload Blocking & Switch+AP `uci-defaults` Sysupgrade Clobber

* **Severity:** **Medium** (Dead/Un-offloaded 5G Link LED & Config Overwrite on Sysupgrade).
* **Symptom:** The 5G port's green link LED never turned on/offloaded (`offloaded=0`, `0x1e/0xc431=0000`) and orange activity LED fell back to software triggering (`offloaded=0`, `0x1e/0xc430=0000`). Separately, Switch+AP mode settings (`192.168.1.91`, `dhcp.lan.ignore=1`, removed `10.143.1.1`) were overwritten to Router defaults after `sysupgrade`.
* **Root Cause:**
  1. `target/linux/qualcommax/ipq60xx/base-files/etc/board.d/01_leds` (`linksys,mr7500`) specified non-existent sysfs LED `90000.mdio-1:08:green:lan` instead of DTS `90000.mdio-1:08:green:wan`, and configured `link_10` in both `wan-port-link` and `wan-port-traffic`, which `aquantia_leds.c` does not list in `supported_triggers` (`-EOPNOTSUPP`).
  2. `files/etc/uci-defaults/99-mr7500-nss-defaults` unconditionally reapplied `10.143.1.1` LAN/DHCP defaults on every first boot after `sysupgrade`.
* **Permanent Fix:**
  1. Updated `01_leds` (captured in `patches/0003-qualcommax-mr7500-fix-usxgmii-probe-race-and-wan-leds.patch`) to use `90000.mdio-1:08:green:wan` and omit unsupported `link_10`, enabling hardware LED offload (`offloaded=1`, `0x1e/0xc431=0xc060`, `0x1e/0xc430=0xc06c`).
  2. Guarded `files/etc/uci-defaults/99-mr7500-nss-defaults` with `system.@system[0].mr7500_defaults_applied` and Switch+AP detection so preserved Switch+AP configurations survive `sysupgrade` intact.

---

### Issue 13: `qca-nss-pbuf` Early Exit With `ath11k nss_offload=0`, CPU 0 IRQ Saturation, & SSDK GMAC `IPGT`

* **Severity:** **High** (Starved NSS N2H Pool, Disabled NSS RPS, CPU 0 Saturation, & Sub-Optimal GMAC IPG).
* **Symptom:** `S95qca-nss-pbuf` logged `Module parameter 'nss_offload=0'. Skipping applying wifi nss configs` and executed `exit 1`, leaving `dev.nss.n2hcfg.extra_pbuf_core0=0`, `n2h_high_water_core0=8704`, and `dev.nss.rps.hash_bitmap=0`, accumulating `n2h_payload_alloc_fails`. Separately, `nss_empty_buf_sos`, `nss_empty_buf_queue`, internal `ath11k_ahb`, and PCIe `QCN9074` MSIs shared CPU 0 alongside `nss_queue0`, and SSDK left PPE GMAC0..3 `MAC_CTRL0.IPGT` at `0x60` instead of Linksys OEM's `0x70`.
* **Root Cause:** `qca-nss-pbuf.init` treated `ath11k.nss_offload != 1` as fatal for the entire init script rather than only gating `n2h_wifi_pool_buf` and `reload_wifi`; no IRQ affinity service pinned NSS/Wi-Fi IRQs off CPU 0; and `qca-ssdk` left `hppe_mac_ctrl0_ipgt_set` unused.
* **Permanent Fix (bundled in `patches/0004-qualcommax-mr7500-optimize-pbuf-ipgt-and-cleanup-dts.patch` + rootfs overlay):**
  1. Patched `package/kernel/mac80211/files/qca-nss-pbuf.init` so `nss_offload=0` logs cleanly and only skips `n2h_wifi_pool_buf` / `wifi up`, allowing `auto_scale=1`, `extra_pbuf_core0=3100000`, `n2h_high_water_core0=30624`, and `dev.nss.rps.hash_bitmap=15` to apply natively on every boot (still controllable via `pbuf.opt.memory_profile='off'`).
  2. Added standalone reversible `/etc/init.d/mr7500-irq-tune` (`START=96`, toggleable via `uci set nss.general.mr7500_irq_tune=0`) enabled by `99-mr7500-nss-defaults` to pin `nss_queue0..3` (`1,2,4,8`), offload `nss_empty_buf_*` to CPUs 1–2, and round-robin `ath11k_ahb` + `QCN9074` `DW-PCI-MSI` IRQs across CPUs 1–3 (`2,4,8`).
  3. Added `package/kernel/qca-ssdk/patches/002-hppe-gmac-ipgt-0x70.patch` setting `GMAC_IPGT_VAL=0x70` via `hppe_mac_ctrl0_ipgt_set()` in `_adpt_gmac_port_max_frame_size_set()` for `CPPE_TYPE` (IPQ6018 GMAC0..3).

---

### Issue 14: Dead `&nss_macsec0`, Unused CSR8811 `blsp1_uart2`, & AQR114C DTS NVMEM Downgrade Guard

* **Severity:** **Low / Rebase Guard**.
* **Symptom:** `ipq6018-mr7500.dts` carried non-functional `&nss_macsec0 { phy_addr = <0x8>; };` (whereas `qca-nss-macsec` only supports QCA808x at `0x18`, not AQR114C at `0x8`) and active `blsp1_uart2` with broken `csr,8811 { enable-gpios = <&tlmm 34 GPIO_ACTIVE_LOW>; }` leaving GPIO 34 floating `in high` while registering unused `/dev/ttyMSM1`.
* **Root Cause & Fix:** Removed `&nss_macsec0`, `serial1` alias, `hsuart_pins`/`btcoex_pins`, and disabled `&blsp1_uart2` while adding `&tlmm bt_reset_hog` (`gpios = <34 GPIO_ACTIVE_HIGH>; output-low;`) in `0004` to hold CSR8811 physically in reset.
* **AQR114C DTS NVMEM Guard:** `mtd9` (`0:ethphyfw`) is an SMEM-partitioned flash region outside OpenWrt `kernel`/`rootfs` and retains factory `v5.4.B` even after stock firmware is completely removed. Never re-add `nvmem-cells = <&aqr_fw>` when rebasing against upstream OpenWrt DTS (`ci_test.sh` enforces this), ensuring AQR114C always loads `/lib/firmware/marvell/AQR114C.cld` (`v5.6.5 Cybertan Divo`).
---

### Issue 15: Aquantia AQR114C 5GbE Port Link Failure on Boot & Hotplug (`USXGMII` C37 AN Drop)

* **Severity:** **Critical** (5GbE Port Unusable Until Repeated Interface Flaps or Unplug/Replug).
* **Symptom:** When plugged into a 2.5GbE/5GbE switch at boot or hot-plugged after running, the `wan` port (`dp5-syn` / `AQR114C-B0`) either remained `Link detected: no` or silently dropped USXGMII Clause 37 auto-negotiation (`4/0xe812=0xb419` with `4/0xc441=0x0000` instead of `0x0008`), causing `uniphy autoneg time out` and total loss of forwarding.
* **Root Cause:**
  1. `aqr107_config_init()` / `aqr107_resume()` raced with the AQR114C microprocessor finishing firmware provisioning / processor-intensive operations (`MDIO_STAT1` / `VEND1_GLOBAL_SYS_CONFIG`), dropping writes to `VEND1_GLOBAL_CFG_100M` / `MDIO_PHYXS_VEND_PROV2` (`0xc441` USXGMII AN bit `0x0008`).
  2. `aqr107_chip_info` / `aqr_config_aneg()` and `aqr107_read_status()` did not re-arm USXGMII Clause 37 auto-negotiation on hotplug or link-down transitions (`0xc441` cleared on copper renegotiation / sleep).
* **Permanent Fix (`patches/0005-qualcommax-mr7500-harden-aqr114c-usxgmii-hotplug.patch`):**
  1. Added `aqr_wait_fw_provisioning()` and `aqr_enable_usxgmii_autoneg()` polling readiness around AQR114C firmware boot, `config_init()`, `aqr107_resume()`, and `aqr_config_aneg()`.
  2. Verified `VEND1_GLOBAL_CFG_*` (`VEND1_GLOBAL_CFG_100M`, etc.) and `MDIO_PHYXS_VEND_PROV2` (`0xc441=0x0008`) consistency across both cold boot and `wan` hotplugs (`2500Mb/s Full`).

---

### Issue 16: `ath11k_ahb` Copy Engine `ce3` Edge-IRQ Freeze (`-105`/`-ENOBUFS` WMI Timeout & `D`-State Hang)

* **Severity:** **Critical** (Router Management/LuCI `/ubus` & Wi-Fi `hostapd` Hang After Extended Uptime).
* **Symptom:** After ~23 hours of uptime, `ath11k c000000.wifi` logged `ce desc not available for wmi command ... (-105)` while Q6 remoteproc stayed running, leaving `rpcd` (`wchan=ath11k_wmi_cmd_send`) and `hostapd` (`wchan=rtnl_lock` / `cfg80211_ft_event`) hung in `D` state and timing out all LuCI `/ubus` wireless RPCs (`getWirelessDevices`, `iwinfo`). Edge-triggered `GIC-0 343 Edge ce3` froze completely (`65324` IRQs).
* **Root Cause:** `ath11k_ahb_ce_interrupt_handler()` (hard IRQ) called `ath11k_ahb_ce_irq_disable()` and `ath11k_ahb_ce_tasklet()` (softirq) called `ath11k_ahb_ce_irq_enable()`, both doing unlocked read-modify-writes on shared `CE_HOST_IE_1/2/3` interrupt enable registers (`ie1_reg_addr`) across CEs while `mr7500-irq-tune` spread `ce0..ce3` across CPUs 1–3. Concurrent RMWs lost the `ce3` enable bit permanently on an edge-triggered GIC line.
* **Permanent Fix (`patches/0006-qualcommax-mr7500-serialize-ath11k-ahb-ce-irq.patch` + `files/etc/init.d/mr7500-irq-tune`):**
  1. Added dedicated `spinlock_t ce_irq_lock;` in `struct ath11k_ahb` (`ahb.h`), initialized in `ath11k_ahb_probe()`, and serialized all CE IE RMWs in `ahb.c` (`ath11k_ahb_ce_irq_set()` / `ath11k_ahb_modbit32()`) under `spin_lock_irqsave`/`spin_unlock_irqrestore`. (Avoids `ab->base_lock`, which uses `_bh` locks and would deadlock inside hard IRQ context.)
  2. Updated `files/etc/init.d/mr7500-irq-tune` to pin `GIC-0 ce[0-9]` IRQs onto CPU 1 (`smp_affinity=2`) while still spreading high-rate `QCN9074` PCIe MSIs and DP IRQs across CPUs 1–3.
  3. Added `files/etc/init.d/mr7500-persist-log` and `files/usr/sbin/mr7500-log-watch` (at `/etc/init.d/mr7500-persist-log` & `/usr/sbin/mr7500-log-watch`) for unbuffered 3-boot rotating persistent logs + crash/hang snapshots (`/root/boot-logs/`).

---

### Issue 17: Aquantia AQR114C Volatile Firmware Loss on Hotplug & Zero LED Blink Stretch (`Patch 0007`)

* **Severity:** **CRITICAL** (Permanent 5GbE Port Outage Until Reboot After Hotplug/Transients + Non-Blinking Activity LEDs).
* **Symptom:**
  1. After passing traffic (`~3.5 GB`) or unplugging/replugging the 5GbE cable on `wan`, `wan` went permanently `carrier=0` (`Link is down`) while LAN ports kept working; reboots or interface restarts could not recover link once the internal PHY firmware exited unless cold-restarted.
  2. Even while linked and passing gigabits of traffic, `wan` port LEDs (`90000.mdio-1:08:orange:wan` / `green:wan`) stayed solid and never blinked on TX/RX frames despite `ledtrig-netdev` reporting `offloaded=1`.
* **Root Cause:**
  1. **Volatile Flashless Firmware Loss:** Because AQR114C has no active SPI flash attached (`mtd9` OEM `v5.4.B` is intentionally bypassed via DT so Linux loads `/lib/firmware/marvell/AQR114C.cld` `v5.6.5` over MDIO), its IRAM (`0x40000000`) and DRAM (`0x3FFE0000`) firmware is **volatile**. On hotplug transients or internal resets, the ARC microprocessor falls back to boot-ROM/low-power state and Linux `aquantia_main.c` only loaded firmware once during initial `aqr107_probe()`. By contrast, Linksys stock firmware explicitly ran `/etc/init.d/service_wan/wan_AQR_monitor.sh` polling the 1 Hz firmware heartbeat `30:0xc886` (`VEND1_GLOBAL_RSVD_STAT2`) and triggering `30:0x2680=0x1` + MDIO reload.
  2. **Inverted `ACT_STRETCH` Bitmask + Unrestored LED Rules:** In upstream Linux `6.12.92`, `drivers/net/phy/aquantia/aquantia.h` defined `VEND1_GLOBAL_LED_PROV_ACT_STRETCH GENMASK(0, 1)` (inverted bit order!) instead of `GENMASK(1, 0)`, and `aqr_phy_led_hw_control_set()` never programmed bits `[1:0]`. Because `AQR114C.cld` boots with `30:0xc430=0x0000`, `ledtrig-netdev` wrote `0xc06c` (`ACT_STRETCH=0` -> `0 ms` pulse stretch, invisible on 2.5G/5G links), whereas OEM/SSDK write `0xc0ef` (`ACT_STRETCH=0x3` -> `100 ms`). Any PHY firmware reset also wiped `30:0xc430..c43a`.
* **Diagnostic Telemetry (Live Dead-ROM vs Live Healthy Signature):**
  ```text
  # Dead boot-ROM state on live router during 5GbE outage:
  30:0x0020 (FW_ID)      = 0x0000   (healthy v5.6.5: 0x0506)
  30:0x0000 (GLOBAL_SC)  = 0x8000   (healthy: 0x0000)
  30:0xc001 (CONTROL2)   = 0x0020   (healthy: 0x0062)
  30:0xc886 (HEARTBEAT)  = 0x0000   (healthy: increments 1 Hz both linked AND unplugged)
  1:0 / 3:0 / 4:0 / 7:0  = 0xa040 / 0xa040 / 0xa040 / 0xb000
  30:0xc430..c432        = 0x0003   (healthy TX/RX LED0: 0xc06f, Link LED1: 0xc060)
  30:0xc438..c43a        = 0x0001
  # Note on thermal register 30:0xc830: reads 0x5000 (BIT(14) set) at ~64.5-70.2C while
  # 30:0xc420 == 0 (no shutdown); do NOT gate FW reload on 30:0xc830 BIT(14).
  ```
* **Live No-Reboot Recovery Verification:** Over UART, streaming `AQR114C.cld` via MDIO C45 ioctls (`SIOCGMIIREG`/`SIOCSMIIREG` with `wan` UP since `ndo_eth_ioctl` is `phy_do_ioctl_running`) using `30:0x2680=0x1`, mailbox `0x0200..0x0205`, restoring `4:0xc441=0x0008`, `30:0xc430=0xc0ef`, `30:0xc431=0xc0e0`, and restarting AN (`7:0x0000`) immediately recovered `2500Mb/s Full`, visible LED blinking, and internet reachability without rebooting.
* **Permanent Hardened Kernel Fix (`patches/0007-qualcommax-mr7500-aqr114c-fw-watchdog-and-led-stretch.patch` -> `0986-net-phy-aquantia-fw-watchdog-and-led-stretch.patch`):**
  1. **LED Blink Stretch & Restore (`aquantia.h`, `aquantia_leds.c`):** Fixed `VEND1_GLOBAL_LED_PROV_ACT_STRETCH` to `GENMASK(1, 0)`, enabled `VEND1_GLOBAL_LED_PROV_ACT_STRETCH_100MS` (`0x3`) when TX/RX offload is configured (producing `30:0xc430=0xc06f`), cached `led_hw_ctrl`/`led_rules[]`, and restored both polarity and HW rules via `aqr_phy_led_restore()` across `config_init()`, `resume()`, and firmware reload.
  2. **Async Lock-Safe Watchdog (`system_unbound_wq`):** `aqr107_check_fw_health()` monitors `30:0x0020` (`FW_ID == 0` for 2 polls) and `30:0xc886` (frozen heartbeat for 6 polls) inside `aqr107_read_status()` and `aqr107_resume()`, queuing `aqr107_fw_reload_work()` on `system_unbound_wq`.
  3. **Concurrency, Deadlock, & Overload Protections (v2 Hardening):**
     * **Zero `rtnl_lock` / `phydev->lock` stall:** Phase 1 briefly locks `phydev->lock` to verify state (`phy_is_started`, `!suspended`, `!fw_reload_abort`), Phase 2 runs the ~29s MDIO upload **completely unlocked** (never holding `rtnl_lock` or `phydev->lock` against `ledtrig-netdev`'s `rtnl_lock -> trigger_data->lock -> phydev->lock`), and Phase 3 re-acquires `phydev->lock` to restore `config_init`/`config_intr`/`__aqr_config_aneg`/AN and calls `phy_trigger_machine()` after unlocking.
     * **Callback Fencing & Clean Teardown:** `atomic_t fw_reloading` fences `config_aneg`, `handle_interrupt`, `get_stats`, `get/set_tunable`, `aqr_hwmon_read/write`, and `aqr_phy_led_*`. `aqr107_suspend()` and `aqr107_remove()` (wired on all 13 `aqr107_probe` `phy_driver` entries) set `fw_reload_abort = 1` and run `cancel_work_sync()` outside `phydev->lock`.
     * **Scheduler / RCU / Bounded Retries:** `aqr_fw_load_memory()` checks all MDIO write/read errors immediately and calls `cond_resched()` + `fw_reload_abort` check every 256 words (safe on `CONFIG_PREEMPT_NONE=y`). `aqr107_read_status()` never returns `< 0` from reload errors (prevents permanent `phy_error_precise()` -> `PHY_HALTED` latch). Consecutive reloads apply exponential backoff (`30s -> 60s -> 120s -> 240s -> 300s`) and stop at `AQR_FW_RELOAD_MAX_FAILS` (`5`) until 60s of sustained ticking health or interface restart (`aqr107_resume()`).
* **Dual-Slot Verification (2026-11-20 / 2026-11-21):** Verified live on both **Slot 1 (`boot_part=1`)** and **Slot 2 (`boot_part=2`)** with Switch+AP `sysupgrade.bin` (SHA-256 `0740664d8dd3302ea3e1e891f5623c42cb6372ac8b7a5fbab2215d253e19ed54`), confirming identical `/lib/modules/6.12.92/aquantia.ko` (`79d2eb1bf853b40e6a45f9bccb264a6bc892c4b83b297907a85815661b56b217`), `2500Mb/s Full`, `4:0xc441=0x0008`, `30:0xc430=0xc06f`, blinking activity LEDs, and 1 Hz `30:0xc886` heartbeat both linked and unplugged.

---

### Issue 18: QCA8075 1GbE LAN Ports Dead RX (`rx=0`) After Boot (`QSGMII` vs `PSGMII` Mismatch)

* **Severity:** **CRITICAL** (Complete Loss of All 4 Built-in 1GbE LAN Ports `lan1`..`lan4`).
* **Symptom:** Devices connected to `lan1`..`lan4` (verified with both an Intel I218-V NIC on `lan1` and a Raspberry Pi 4B on `lan3`) established physical `1000Mb/s Full` Ethernet link (`reg1=0x796d`, `reg10=0x7800/0x7c00`), and `MR7500` incremented `tx_packets` on the port, yet `rx_packets` remained `0` on both `MR7500` and the attached client with zero bridge FDB MACs learned (`OpenWrt #25746`). Meanwhile `wan` (`dp5-syn` / `AQR114C` over `USXGMII`) operated normally.
* **Root Cause:** Upstream `ipq6018-mr7500.dts` configured the 4-port `QCA8075` LAN PHY package and `dp1`..`dp4` in `qsgmii` mode (`qcom,package-mode = "qsgmii"`, `switch_mac_mode = <MAC_MODE_QSGMII>` = `0x0b`), whereas the Linksys MR7500 hardware and stock OEM DTB use **PSGMII** (`switch_mac_mode = <0x0>` = `MAC_MODE_PSGMII`).
* **Permanent Fix (`patches/0008-qualcommax-mr7500-use-psgmii-for-qca8075.patch`):**
  1. Changed `&mdio/ethernet-phy-package` `qcom,package-mode` from `"qsgmii"` to `"psgmii"`.
  2. Changed `&dp1`..`&dp4` `phy-mode` from `"qsgmii"` to `"psgmii"`.
  3. Changed `&switch` `switch_mac_mode` from `<MAC_MODE_QSGMII>` (`0x0b`) to `<MAC_MODE_PSGMII>` (`0x00`).
* **Dual-Slot Verification (2026-11-26):** Rebuilt FIT `fdt-1` DTB with `psgmii` (`switch_mac_mode=00000000`, FIT SHA-256 `c4a7d0f8b2e4e034ce832936978ea3be1ee6495bd5a8d4a2baf2fb05b5594395`), flashed cleanly to **both Slot 1 (`mtd13`/`mtd14`) and Slot 2 (`mtd15`/`mtd16`)**, verified identical `mtd13`/`mtd15` SHA-256, `lan3` `1000Mb/s Full` with bidirectional `rx_packets`/`tx_packets` and FDB MAC learning (`dc:a6:32:f9:d3:c4` on port 3), `ip link set lan3 down/up` recovery, `wan` `2500Mb/s Full` (`4:0xc441=0x0008`), and all 3 Wi-Fi radios up.
