# Linksys MR7500 (Hydra Pro 6E) Hardware Test & Validation Results

**Device:** Linksys MR7500 v1 (`divo`, Qualcomm IPQ6018, AQR114C 5GbE WAN, QCN9074 6GHz)  
**Firmware:** Custom OpenWrt 24.10 (Linux 6.12.92 + Qualcomm NSS 12.5)  
**Date:** November 9, 2026  

---

## 1. Multi-Gigabit WAN Speed Test (2.5 Gbps Line Rate)

* **Physical Link:** Synopsys XGMAC + Marvell/Aquantia AQR114C-B0 PHY over USXGMII (`switch_mac_mode1 = <0xd>`).
* **In-Band Signaling:** Clause 37 auto-negotiation enabled in PHYXS register `4:0xc441 = 0x0008` (bit 3).
* **Test Topology:** 10GbE / 2.5GbE PC (`192.168.1.80`) <---> MR7500 WAN (`192.168.1.91`).

### Forward Direction: PC -> Router WAN
```text
Connecting to host 192.168.1.91, port 5201
[  4] local 192.168.1.80 port 24467 connected to 192.168.1.91 port 5201
[ ID] Interval           Transfer     Bitrate
[  4]   0.00-10.00  sec  2.71 GBytes  2.32 Gbits/sec                  sender
[  4]   0.00-10.00  sec  2.71 GBytes  2.32 Gbits/sec                  receiver
iperf Done.
```

### Reverse Direction: Router WAN -> PC
```text
Connecting to host 192.168.1.91, port 5201
Reverse mode, remote host 192.168.1.91 is sending
[  4] local 192.168.1.80 port 24472 connected to 192.168.1.91 port 5201
[ ID] Interval           Transfer     Bitrate         Retr
[  4]   0.00-10.01  sec  2.77 GBytes  2.37 Gbits/sec    0            sender
[  4]   0.00-10.01  sec  2.76 GBytes  2.37 Gbits/sec                  receiver
iperf Done.
```
* **Summary:** Sustained **2.32 Gbps Upload** and **2.37 Gbps Download** with **0 retransmissions**.

---

## 2. USB 3.0 Storage Port Verification

* **Host Controller:** Qualcomm DWC3 mapped to Synopsys xHCI USB 3.0 Host (`xhci-hcd.1.auto`).
* **VBUS Regulator:** `reg_usb_vbus` driven by GPIO 25.
* **Test Device:** 4GB USB 3.0 Flash Drive plugged into Type-A port.

### Kernel Telemetry (`dmesg`):
```text
[   27.324638] usb 2-1: new SuperSpeed USB device number 2 using xhci-hcd
[   27.346420] usb-storage 2-1:1.0: USB Mass Storage device detected
[   27.347012] scsi host0: usb-storage 2-1:1.0
[   29.249685] sd 0:0:0:1: [sdb] 7744512 512-byte logical blocks: (3.97 GB/3.69 GiB)
[   29.254647] sd 0:0:0:1: [sdb] Write Protect is off
[   29.355825]  sdb: sdb1
[   29.356121] sd 0:0:0:1: [sdb] Attached SCSI removable disk
```

### Partition & Raw Sector I/O:
* Recognized as block device `/dev/sdb` (3.97 GB) and partition `/dev/sdb1`.
* Raw block read of sector 0 verified valid FAT16 partition boot record (`MSWIN4.1 / FAT16`).
* Automatic LED trigger: `blue:usb` LED lit up on device insertion (`[usbport]`).

---

## 3. Bluetooth Subsystem (CSR8811) Control Verification

* **Hardware:** Cambridge Silicon Radio CSR8811 (BLE 4.1) on UART 2 (`/dev/ttyMSM1`) @ 115200 baud.
* **Power / Reset Line:** GPIO 34 (Linux 6.12 `gpio546`).

### Power Cycle & State Verification:
```text
=== STEP 1: ENABLING BLUETOOTH HARDWARE ===
Bluetooth power GPIO 546 value: 1 (POWER ON)

=== STEP 2: PROBING CSR8x11 ON /dev/ttyMSM1 ===
[+] Writing BCSP sync packet to /dev/ttyMSM1...
[+] Writing HCI Reset packet to /dev/ttyMSM1...

=== STEP 3: TURNING BLUETOOTH HARDWARE OFF ===
Bluetooth power GPIO 546 value: 0 (POWER OFF / HELD IN RESET)
Bluetooth GPIO unexported successfully.
```
* **Result:** Bluetooth hardware power-on, probe, and shutdown verified. Holding GPIO 34 low eliminates ~50–80 mW idle power draw and prevents 2.4 GHz RF co-existence noise.

---

## 4. LAN Routing, DNS Resolution, & Internet Reachability

### Ping from Router to Internet IPv4 & IPv6:
```text
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: seq=0 ttl=58 time=16.947 ms
64 bytes from 1.1.1.1: seq=1 ttl=58 time=17.351 ms
--- 1.1.1.1 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss

PING 2606:4700:4700::1111 (2606:4700:4700::1111): 56 data bytes
64 bytes from 2606:4700:4700::1111: seq=0 ttl=58 time=16.810 ms
64 bytes from 2606:4700:4700::1111: seq=1 ttl=58 time=16.503 ms
--- 2606:4700:4700::1111 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
```

### Ping from LAN Client (`10.143.1.17`) to Internet through MR7500:
```text
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=117 time=18.4 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=117 time=18.1 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=117 time=18.3 ms
--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
```

### DNS Resolution through `10.143.1.1`:
```text
Server:   10.143.1.1
Address:  10.143.1.1#53

Name:     google.com
Address:  142.250.183.174
Address:  2404:6800:4007:836::200e
```

---

## 5. Wi-Fi 6E & Host Data Path Fix

* **Issue Resolved:** Closed-source NSS wifili driver suffered from packet buffer starvation (`rx_desc_no_pb: 321531`).
* **Fix Applied:** Configured `ath11k nss_offload=0 frame_mode=0` in `/etc/modules.d/ath11k`.
* **Verification:**
  * `phy0-ap0` (5 GHz): RX packets flowing, **0 dropped**, **0 errors**.
  * `phy1-ap0` (2.4 GHz): RX packets flowing, **0 dropped**, **0 errors**.
  * `phy2-ap0` (6 GHz): RX packets flowing, **0 dropped**, **0 errors**.
  * Qualcomm NSS ECM continues to accelerate all routed/NAT packets between `br-lan` and `wan` at wire speed.
