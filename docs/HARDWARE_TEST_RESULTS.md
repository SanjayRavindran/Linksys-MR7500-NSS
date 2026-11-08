
## Marvell/Aquantia AQR114C 5GbE WAN Verification
- **Link State:** 2500 Mb/s Full Duplex confirmed live.
- **USXGMII In-Band Clause 37 Auto-Negotiation:**
  - Standard USXGMII requires Clause 37 in-band signaling over SerDes to communicate speed and duplex between Aquantia PHYXS and IPQ6018 UNIPHY XPCS.
  - Enabled via register `MDIO_MMD_PHYXS` (`0x04`), offset `0xc441` = `0x0008` and DTS `managed = "in-band-status"`.
  - Automated persistently at boot via `/etc/rc.local` and `/etc/hotplug.d/iface/10-wan-aqr`.
  - WAN DHCP client (`udhcpc`) verified acquiring IP and default route from upstream gateway.
  - Line-rate NAT internet routing active and verified across all LAN and Wi-Fi clients.
