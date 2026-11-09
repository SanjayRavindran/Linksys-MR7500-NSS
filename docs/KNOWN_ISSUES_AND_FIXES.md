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
