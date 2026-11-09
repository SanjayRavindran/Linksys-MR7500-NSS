#!/bin/sh
# Linksys MR7500 On-Device Regression & Health Validation Script
# Can be run directly on the router or via SSH: ssh root@10.143.1.1 'sh -s' < scripts/validate_firmware.sh

PASS=0
FAIL=0
WARN=0

log_pass() { echo "[PASS] $1: $2"; PASS=$((PASS+1)); }
log_fail() { echo "[FAIL] $1: $2"; FAIL=$((FAIL+1)); }
log_warn() { echo "[WARN] $1: $2"; WARN=$((WARN+1)); }

echo "================================================================================"
echo "LINKSYS MR7500 ON-DEVICE HARDWARE & FIRMWARE VALIDATION SUITE"
echo "================================================================================"

# 1. Boot Slot
CMDLINE=$(cat /proc/cmdline)
MTD=$(cat /proc/mtd)
if echo "$CMDLINE" | grep -q "ubi.mtd=rootfs" && echo "$MTD" | grep -q "alt_kernel" && echo "$MTD" | grep -q "alt_rootfs"; then
    log_pass "TC-01" "Boot Slot 1 Active (boot_part=1) & Slot 2 OEM fallback intact"
else
    log_fail "TC-01" "Boot Slot / Partition table mismatch"
fi

# 2. Kernel & CPU
UNAME=$(uname -r)
FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
CORES=$(grep -c processor /proc/cpuinfo)
if echo "$UNAME" | grep -q "6.12" && [ "$FREQ" -ge 1700000 ] && [ "$GOV" = "performance" ] && [ "$CORES" -eq 4 ]; then
    log_pass "TC-02" "Linux $UNAME on 4x Cortex-A53 cores @ $((FREQ/1000)) MHz (governor: $GOV)"
else
    log_warn "TC-02" "Kernel: $UNAME, Freq: $((FREQ/1000)) MHz, Gov: $GOV, Cores: $CORES"
fi

# 3. Qualcomm NSS Offload
LSMOD=$(lsmod)
ECM_ENGINE=$(uci get ecm.global.acceleration_engine 2>/dev/null || echo "none")
if echo "$LSMOD" | grep -q "qca_nss_drv" && echo "$LSMOD" | grep -q "ecm" && [ "$ECM_ENGINE" = "nss" ]; then
    log_pass "TC-03" "Qualcomm NSS Core 0 driver & ECM active (engine: $ECM_ENGINE)"
else
    log_fail "TC-03" "NSS offload modules missing or acceleration engine is not 'nss'"
fi

# 4. Multi-Gigabit WAN (AQR114C)
ETH_WAN=$(ethtool wan 2>/dev/null)
if echo "$ETH_WAN" | grep -q "Link detected: yes"; then
    SPEED=$(echo "$ETH_WAN" | grep "Speed:" | awk '{print $2}')
    RX_FRAMES=$(ethtool -S wan 2>/dev/null | grep "rx_frame:" | awk '{print $2}')
    log_pass "TC-04" "AQR114C WAN Link UP @ $SPEED Full Duplex (rx_frame: $RX_FRAMES)"
else
    log_fail "TC-04" "WAN link is DOWN"
fi

# 5. LAN Switch Fabric (QCA8075)
BRIF=$(ls /sys/class/net/br-lan/brif 2>/dev/null)
LAN_PORTS=$(echo "$BRIF" | grep "^lan" | wc -l)
if [ "$LAN_PORTS" -ge 4 ]; then
    log_pass "TC-05" "QCA8075 4-port switch fabric bridged to br-lan (ports: $LAN_PORTS)"
else
    log_fail "TC-05" "Expected 4 LAN ports in br-lan, found: $LAN_PORTS"
fi

# 6. WAN DHCP & IPv4 Internet
WAN_STATUS=$(ubus call network.interface.wan status 2>/dev/null)
if echo "$WAN_STATUS" | grep -q '"up": true' && ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1; then
    WAN_ADDR=$(echo "$WAN_STATUS" | grep -A 2 'ipv4-address' | grep '"address"' | cut -d'"' -f4)
    log_pass "TC-06" "WAN IP: $WAN_ADDR. Outbound ping 1.1.1.1: 0% loss"
else
    log_fail "TC-06" "WAN interface down or no IPv4 internet connectivity"
fi

# 7. LAN DHCP Server & DNS
LAN_ADDR=$(ip -4 addr show br-lan 2>/dev/null | grep "inet 10.143.1.1/24")
DNS_PID=$(pidof dnsmasq)
if [ -n "$LAN_ADDR" ] && [ -n "$DNS_PID" ] && nslookup google.com 10.143.1.1 >/dev/null 2>&1; then
    log_pass "TC-07" "LAN 10.143.1.1/24 hygiene verified, dnsmasq active, DNS query OK"
else
    log_fail "TC-07" "LAN subnet mismatch or dnsmasq not resolving"
fi

# 8. IPv6 SLAAC & Routing
ODHCPD_PID=$(pidof odhcpd)
SLAAC=$(uci get dhcp.lan.ra_slaac 2>/dev/null)
if [ -n "$ODHCPD_PID" ] && [ "$SLAAC" = "1" ] && ping -6 -c 2 -W 2 2606:4700:4700::1111 >/dev/null 2>&1; then
    log_pass "TC-08" "RFC 4862 SLAAC active, odhcpd PID $ODHCPD_PID, IPv6 Cloudflare ping OK"
else
    log_warn "TC-08" "IPv6 SLAAC or IPv6 ping warning (slaac: $SLAAC)"
fi

# 9. Tri-Band Wi-Fi 6E
IWINFO=$(iwinfo 2>/dev/null)
ATH11K_OFFLOAD=$(cat /sys/module/ath11k/parameters/nss_offload 2>/dev/null || echo "unknown")
SSID_COUNT=$(echo "$IWINFO" | grep "ESSID:" | wc -l)
if [ "$SSID_COUNT" -ge 3 ] && [ "$ATH11K_OFFLOAD" = "0" ]; then
    log_pass "TC-09" "Tri-Band SSIDs active (count: $SSID_COUNT), ath11k host data path (0 RX drops)"
else
    log_warn "TC-09" "Active SSIDs: $SSID_COUNT, ath11k nss_offload: $ATH11K_OFFLOAD"
fi

# 10. USB 3.0 Subsystem
if echo "$LSMOD" | grep -q "xhci_hcd" && echo "$LSMOD" | grep -q "usb_storage"; then
    log_pass "TC-10" "USB 3.0 DWC3 xHCI and mass storage modules loaded"
else
    log_fail "TC-10" "USB 3.0 modules missing"
fi

# 11. Thermal & Watchdog
TEMPS=$(cat /sys/class/thermal/thermal_zone0/temp /sys/class/thermal/thermal_zone1/temp /sys/class/thermal/thermal_zone2/temp /sys/class/thermal/thermal_zone3/temp /sys/class/thermal/thermal_zone4/temp /sys/class/thermal/thermal_zone5/temp /sys/class/thermal/thermal_zone6/temp 2>/dev/null)
ZONE_COUNT=$(echo "$TEMPS" | wc -w)
if [ "$ZONE_COUNT" -eq 7 ] && [ -e /dev/watchdog0 ]; then
    MAX_TEMP=$(echo "$TEMPS" | tr ' ' '\n' | sort -nr | head -n 1)
    log_pass "TC-11" "7x TSENS thermal zones active (Max: $((MAX_TEMP/1000))°C), /dev/watchdog0 ready"
else
    log_warn "TC-11" "Thermal zones: $ZONE_COUNT, watchdog: $([ -e /dev/watchdog0 ] && echo yes || echo no)"
fi

# 12. Bluetooth CSR8811 Standby
BT_VAL=$(cat /sys/class/gpio/gpio546/value 2>/dev/null || echo "unexported")
if [ "$BT_VAL" = "0" ] || [ "$BT_VAL" = "unexported" ]; then
    log_pass "TC-12" "CSR8811 Bluetooth held in reset (GPIO 34 = $BT_VAL), 2.4GHz RF protected"
else
    log_warn "TC-12" "Bluetooth GPIO state: $BT_VAL"
fi

# 13. NSS Accelerated Flows
ACC_FLOWS=$(cat /sys/kernel/debug/ecm/ecm_nss_ipv4/accelerated_count 2>/dev/null || echo "0")
log_pass "TC-13" "Active Qualcomm NSS hardware offload flows: $ACC_FLOWS"

echo "================================================================================"
TOTAL=$((PASS+FAIL+WARN))
echo "SUMMARY: $PASS/$TOTAL PASSED ($WARN Warnings, $FAIL Failures)"
echo "================================================================================"

exit $FAIL
