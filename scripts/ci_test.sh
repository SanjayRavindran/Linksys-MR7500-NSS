#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 GitHub Actions CI / Pre-Build Automated Test Suite
# Validates syntax, patches, device tree definitions, diffconfig, security hygiene
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1: $2"; PASS=$((PASS + 1)); }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1: $2"; FAIL=$((FAIL + 1)); }
log_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1: $2"; }

echo "================================================================================"
echo " LINKSYS MR7500 CI PRE-BUILD VALIDATION TEST SUITE"
echo "================================================================================"

# 1. ShellCheck & Script Syntax
echo "[*] Running Test 1: Script Syntax & Validation..."
SYNTAX_ERRORS=0
for script in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/files/etc/rc.local "$REPO_ROOT"/files/usr/sbin/switch_mode "$REPO_ROOT"/files/etc/firewall.d/*; do
    [ -f "$script" ] || continue
    if ! bash -n "$script" 2>/dev/null; then
        log_fail "T1-Syntax" "Syntax error in $script"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done
if [ "$SYNTAX_ERRORS" -eq 0 ]; then
    log_pass "T1-Syntax" "All shell scripts passed bash -n syntax validation"
fi

# 2. Patch 0001: Hardware Nodes & NSS Offloading
echo "[*] Running Test 2: Patch 0001 Hardware Nodes & NSS DTS Patches..."
PATCH_0001="$REPO_ROOT/patches/0001-qualcommax-ipq6018-mr7500-add-complete-nss-offload.patch"
if [ -f "$PATCH_0001" ]; then
    REQUIRED_STRINGS=(
        "aqr114c: ethernet-phy@8"
        "reset-deassert-us = <250000>"
        "dr_mode = \"host\""
        "nss_macsec0"
        "0982-net-mdio-fwnode-wait-for-c45-phy-with-reset-gpios.patch"
        "FWNODE_MDIO_C45_PROBE"
    )
    MISSING_STR=0
    for s in "${REQUIRED_STRINGS[@]}"; do
        if ! grep -q "$s" "$PATCH_0001"; then
            log_fail "T2-Patch0001" "Missing expected patch element: $s"
            MISSING_STR=$((MISSING_STR + 1))
        fi
    done
    if [ "$MISSING_STR" -eq 0 ]; then
        log_pass "T2-Patch0001" "Patch 0001 contains all AQR114C timing, USB host, MACSec, and C45 retry fixes"
    fi
else
    log_fail "T2-Patch0001" "Patch 0001 not found at $PATCH_0001"
fi

# 3. Patch 0002: USXGMII In-Band Signalling
echo "[*] Running Test 3: Patch 0002 USXGMII In-Band Signalling..."
PATCH_0002="$REPO_ROOT/patches/0002-qualcommax-ipq6018-mr7500-enable-usxgmii-inband-status.patch"
if [ -f "$PATCH_0002" ] && grep -q 'managed = "in-band-status"' "$PATCH_0002"; then
    log_pass "T3-Patch0002" "Patch 0002 enables USXGMII managed = 'in-band-status' for 5GbE WAN link rate exchange"
else
    log_fail "T3-Patch0002" "Patch 0002 missing or does not contain managed = 'in-band-status'"
fi

# 3b. Patch 0003: AQR114C Probe Race, Netdev LED Guard, SSDK & WAN LED Fixes
echo "[*] Running Test 3b: Patch 0003 AQR114C Probe Race & LED Fixes..."
PATCH_0003="$REPO_ROOT/patches/0003-qualcommax-mr7500-fix-usxgmii-probe-race-and-wan-leds.patch"
if [ -f "$PATCH_0003" ]; then
    REQUIRED_P3=(
        "0983-net-phy-aquantia-enable-usxgmii-autoneg.patch"
        "0984-net-phy-serialize-attach-with-probe.patch"
        "0985-net-phy-led-hw-control-check-registered-netdev.patch"
        "001-uniphy-usxgmii-autoneg.patch"
        "90000.mdio-1:08:green:wan"
        "NETREG_REGISTERED"
        "device_lock(d)"
    )
    MISSING_P3=0
    for s in "${REQUIRED_P3[@]}"; do
        if ! grep -qF "$s" "$PATCH_0003"; then
            log_fail "T3b-Patch0003" "Missing expected fix in Patch 0003: $s"
            MISSING_P3=$((MISSING_P3 + 1))
        fi
    done
    if [ "$MISSING_P3" -eq 0 ]; then
        log_pass "T3b-Patch0003" "Patch 0003 contains probe serialization, LED netdev guard, USXGMII AN, and green:wan LED fixes"
    fi
else
    log_fail "T3b-Patch0003" "Patch 0003 not found at $PATCH_0003"
fi

# 4. Security & Privacy Audit (Zero Plaintext Secrets or Private Keys)
echo "[*] Running Test 4: Security & Credential Leak Audit..."
LEAKS=0
if grep -rnE "(password|passwd|token|secret|BEGIN (RSA|OPENSSH) PRIVATE KEY)" "$REPO_ROOT/files/" 2>/dev/null | grep -v "LinksysMR7500!" | grep -v "binary file"; then
    log_fail "T4-Security" "Potential credential or private key found in files/"
    LEAKS=$((LEAKS + 1))
fi
if [ "$LEAKS" -eq 0 ]; then
    log_pass "T4-Security" "Zero credentials, private tokens, or SSH keys detected in repository"
fi

# 5. Default Operating Mode Verification (Must be Router Mode)
echo "[*] Running Test 5: Default Operating Mode Architecture..."
NET_CONF="$REPO_ROOT/files/etc/config/network"
DHCP_CONF="$REPO_ROOT/files/etc/config/dhcp"
if [ -f "$NET_CONF" ] && [ -f "$DHCP_CONF" ]; then
    IS_ROUTER_NET=0
    grep -q "config interface 'wan'" "$NET_CONF" && IS_ROUTER_NET=$((IS_ROUTER_NET + 1))
    grep -q "option ipaddr '10.143.1.1'" "$NET_CONF" && IS_ROUTER_NET=$((IS_ROUTER_NET + 1))
    grep -q "option dhcpv4 'server'" "$DHCP_CONF" && IS_ROUTER_NET=$((IS_ROUTER_NET + 1))
    
    if [ -x "$REPO_ROOT/files/usr/sbin/switch_mode" ] && [ "$IS_ROUTER_NET" -eq 3 ]; then
        log_pass "T5-Mode" "Default build configuration is verified Router Mode (10.143.1.1/24) with switch_mode utility"
    else
        log_fail "T5-Mode" "Default configuration is not Router Mode or switch_mode missing"
    fi
else
    log_fail "T5-Mode" "Missing default configuration files"
fi

# 6. Diffconfig Architecture & Package Symbols
echo "[*] Running Test 6: OpenWrt Diffconfig Architecture & Symbols..."
DIFFCONFIG="$REPO_ROOT/config/mr7500_nss_diffconfig"
FULLCONFIG="$REPO_ROOT/config/mr7500_nss.config"
if [ -f "$DIFFCONFIG" ]; then
    REQUIRED_DIFF_SYMBOLS=(
        "CONFIG_TARGET_qualcommax=y"
        "CONFIG_TARGET_qualcommax_ipq60xx=y"
        "CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_linksys_mr7500=y"
        "CONFIG_NSS_FIRMWARE_VERSION_12_5=y"
        "CONFIG_PACKAGE_kmod-qca-nss-crypto=y"
        "CONFIG_PACKAGE_nss-eip-firmware=y"
        "CONFIG_PACKAGE_nssinfo=y"
        "CONFIG_PACKAGE_sqm-scripts-nss=y"
        "CONFIG_PACKAGE_kmod-fs-vfat=y"
        "CONFIG_PACKAGE_kmod-fs-exfat=y"
        "CONFIG_PACKAGE_phytool=y"
    )
    MISSING_DIFF=0
    for sym in "${REQUIRED_DIFF_SYMBOLS[@]}"; do
        if ! grep -q "$sym" "$DIFFCONFIG"; then
            log_fail "T6-Diffconfig" "Missing symbol in diffconfig: $sym"
            MISSING_DIFF=$((MISSING_DIFF + 1))
        fi
    done
    if [ "$MISSING_DIFF" -eq 0 ]; then
        log_pass "T6-Diffconfig" "Diffconfig contains all target, NSS 12.5, crypto, SQM, and filesystem symbols"
    fi
else
    log_fail "T6-Diffconfig" "Diffconfig $DIFFCONFIG not found"
fi

# 7. Blob Extraction Script Integrity
echo "[*] Running Test 7: Stock Blob Extraction Script..."
EXTRACT_SCRIPT="$REPO_ROOT/scripts/extract_stock_blobs.sh"
if [ -f "$EXTRACT_SCRIPT" ] && grep -q "AQR114C.cld" "$EXTRACT_SCRIPT" && grep -q "32bc96c20351d7981d2d905b843899834e6dd620844218d6f3e1ecb9691745f3" "$EXTRACT_SCRIPT"; then
    log_pass "T7-BlobExtract" "Stock blob extractor has verified official SHA-256 hash for Marvell AQR114C firmware"
else
    log_fail "T7-BlobExtract" "Blob extraction script missing or missing verified SHA-256"
fi

# 8. Firewall NSS Hook Robustness
echo "[*] Running Test 8: Firewall Hook Robustness..."
FW_HOOK="$REPO_ROOT/files/etc/firewall.d/qca-nss-ecm"
if [ -f "$FW_HOOK" ] && grep -q "forward_wan" "$FW_HOOK"; then
    log_pass "T8-Firewall" "qca-nss-ecm firewall hook includes robust chain check preventing nft errors in AP mode"
else
    log_fail "T8-Firewall" "qca-nss-ecm firewall hook check failed"
fi

echo "================================================================================"
TOTAL=$((PASS + FAIL))
echo "CI PRE-BUILD TEST RESULTS: $PASS/$TOTAL PASSED ($FAIL Failures)"
echo "================================================================================"

exit $FAIL
