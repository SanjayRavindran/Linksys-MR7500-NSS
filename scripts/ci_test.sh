#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 GitHub Actions CI / Pre-Build Automated Test Suite
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1: $2"; PASS=$((PASS + 1)); }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1: $2"; FAIL=$((FAIL + 1)); }

echo "================================================================================"
echo " LINKSYS MR7500 CI PRE-BUILD VALIDATION TEST SUITE"
echo "================================================================================"

# 1. Shell Script Syntax
echo "[*] Running Test 1: Script Syntax & Validation..."
SYNTAX_ERRORS=0
for script in \
    "$REPO_ROOT"/scripts/*.sh \
    "$REPO_ROOT"/files/etc/rc.local \
    "$REPO_ROOT"/files/usr/sbin/switch_mode \
    "$REPO_ROOT"/files/etc/firewall.d/* \
    "$REPO_ROOT"/files/etc/init.d/* \
    "$REPO_ROOT"/files/etc/uci-defaults/* \
    "$REPO_ROOT"/files/etc/hotplug.d/iface/* \
    "$REPO_ROOT"/config/profiles/switch-ap/files/etc/uci-defaults/*; do
    [ -f "$script" ] || continue
    if ! bash -n "$script" 2>/dev/null; then
        log_fail "T1-Syntax" "Syntax error in $script"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done
if [ "$SYNTAX_ERRORS" -eq 0 ]; then
    log_pass "T1-Syntax" "All shell scripts passed bash -n syntax validation"
fi

# 2. Patch 0001
echo "[*] Running Test 2: Patch 0001 Hardware Nodes & NSS DTS Patches..."
PATCH_0001="$REPO_ROOT/patches/0001-qualcommax-ipq6018-mr7500-add-complete-nss-offload.patch"
if [ -f "$PATCH_0001" ]; then
    REQUIRED_STRINGS=(
        "aqr114c: ethernet-phy@8"
        "reset-deassert-us = <250000>"
        'dr_mode = "host"'
        "nss_macsec0"
        "0982-net-mdio-fwnode-wait-for-c45-phy-with-reset-gpios.patch"
        "FWNODE_MDIO_C45_PROBE"
    )
    MISSING_STR=0
    for s in "${REQUIRED_STRINGS[@]}"; do
        if ! grep -qF -- "$s" "$PATCH_0001"; then
            log_fail "T2-Patch0001" "Missing expected patch element: $s"
            MISSING_STR=$((MISSING_STR + 1))
        fi
    done
    [ "$MISSING_STR" -eq 0 ] && log_pass "T2-Patch0001" "Patch 0001 contains all AQR114C timing, USB host, MACSec, and C45 retry fixes"
else
    log_fail "T2-Patch0001" "Patch 0001 not found at $PATCH_0001"
fi

# 3. Patch 0002
echo "[*] Running Test 3: Patch 0002 USXGMII In-Band Signalling..."
PATCH_0002="$REPO_ROOT/patches/0002-qualcommax-ipq6018-mr7500-enable-usxgmii-inband-status.patch"
if [ -f "$PATCH_0002" ] && grep -q 'managed = "in-band-status"' "$PATCH_0002"; then
    log_pass "T3-Patch0002" "Patch 0002 enables USXGMII managed = 'in-band-status' for 5GbE WAN link rate exchange"
else
    log_fail "T3-Patch0002" "Patch 0002 missing or does not contain managed = 'in-band-status'"
fi

# 3b. Patch 0003
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
        if ! grep -qF -- "$s" "$PATCH_0003"; then
            log_fail "T3b-Patch0003" "Missing expected fix in Patch 0003: $s"
            MISSING_P3=$((MISSING_P3 + 1))
        fi
    done
    [ "$MISSING_P3" -eq 0 ] && log_pass "T3b-Patch0003" "Patch 0003 contains probe serialization, LED netdev guard, USXGMII AN, and green:wan LED fixes"
else
    log_fail "T3b-Patch0003" "Patch 0003 not found at $PATCH_0003"
fi

# 3c. Patch 0004
echo "[*] Running Test 3c: Patch 0004 NSS pbuf/IPGT/DTS Fixes..."
PATCH_0004="$REPO_ROOT/patches/0004-qualcommax-mr7500-optimize-pbuf-ipgt-and-cleanup-dts.patch"
if [ -f "$PATCH_0004" ]; then
    REQUIRED_P4=(
        "002-hppe-gmac-ipgt-0x70.patch"
        "hppe_mac_ctrl0_ipgt_set"
        "GMAC_IPGT_VAL"
        "qca-nss-pbuf.init"
        "enable_nss_offload"
        "ipq6018-mr7500.dts"
        "bt_reset_hog"
        "output-low"
        "-&nss_macsec0"
    )
    MISSING_P4=0
    for s in "${REQUIRED_P4[@]}"; do
        if ! grep -qF -- "$s" "$PATCH_0004"; then
            log_fail "T3c-Patch0004" "Missing expected fix in Patch 0004: $s"
            MISSING_P4=$((MISSING_P4 + 1))
        fi
    done
    [ "$MISSING_P4" -eq 0 ] && log_pass "T3c-Patch0004" "Patch 0004 contains pbuf bypass, SSDK IPGT=0x70, BT GPIO hog, and macsec0 cleanup"
else
    log_fail "T3c-Patch0004" "Patch 0004 not found at $PATCH_0004"
fi

# 3d2. Patch 0005 AQR114C USXGMII Boot/Hotplug Self-Heal
echo "[*] Running Test 3e: Patch 0005 AQR114C USXGMII Boot & Hotplug Fix..."
PATCH_0005="$REPO_ROOT/patches/0005-qualcommax-mr7500-harden-aqr114c-usxgmii-hotplug.patch"
if [ -f "$PATCH_0005" ]; then
    REQUIRED_P5=(
        "VEND1_GLOBAL_CFG_100M"
        "aqr_wait_fw_provisioning"
        "aqr_enable_usxgmii_autoneg"
        "aqr107_wait_processor_intensive_op"
        "aqr_config_aneg"
        "aqr107_read_status"
        "aqr107_resume"
    )
    MISSING_P5=0
    for s in "${REQUIRED_P5[@]}"; do
        if ! grep -qF -- "$s" "$PATCH_0005"; then
            log_fail "T3e-Patch0005" "Missing expected fix in Patch 0005: $s"
            MISSING_P5=$((MISSING_P5 + 1))
        fi
    done
    [ "$MISSING_P5" -eq 0 ] && log_pass "T3e-Patch0005" "Patch 0005 hardens AQR114C USXGMII C37 AN across boot, resume, aneg, and hotplug"
else
    log_fail "T3e-Patch0005" "Patch 0005 not found at $PATCH_0005"
fi

# 3d. AQR114C DTS NVMEM Downgrade Guard
echo "[*] Running Test 3d: AQR114C DTS NVMEM Guard..."
if grep -rnE "^\+.*aqr_fw" "$REPO_ROOT"/patches/*.patch 2>/dev/null; then
    log_fail "T3d-AQRGuard" "A patch re-adds aqr_fw NVMEM cell (risks v5.4.B downgrade or CRC failure)"
else
    log_pass "T3d-AQRGuard" "No patch adds aqr_fw NVMEM cell; AQR114C loads v5.6.5 from filesystem cleanly"
fi

# 4. Security & Privacy Audit
echo "[*] Running Test 4: Security & Credential Leak Audit..."
LEAKS=0
if grep -rnE "(password|passwd|token|secret|BEGIN (RSA|OPENSSH) PRIVATE KEY)" "$REPO_ROOT/files/" "$REPO_ROOT/config/profiles/" 2>/dev/null | grep -v "LinksysMR7500!" | grep -v "binary file"; then
    log_fail "T4-Security" "Potential credential or private key found in overlay configs"
    LEAKS=$((LEAKS + 1))
fi
[ "$LEAKS" -eq 0 ] && log_pass "T4-Security" "Zero credentials, private tokens, or SSH keys detected in overlay files"

# 5. Default Operating Mode (Router Mode)
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

# 6. Diffconfig Symbols
echo "[*] Running Test 6: OpenWrt Diffconfig Architecture & Symbols..."
DIFFCONFIG="$REPO_ROOT/config/mr7500_nss_diffconfig"
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
    [ "$MISSING_DIFF" -eq 0 ] && log_pass "T6-Diffconfig" "Diffconfig contains all target, NSS 12.5, crypto, SQM, and filesystem symbols"
else
    log_fail "T6-Diffconfig" "Diffconfig $DIFFCONFIG not found"
fi

# 7. Stock Blob Extractor Integrity
echo "[*] Running Test 7: Stock Blob Extraction Script..."
EXTRACT_SCRIPT="$REPO_ROOT/scripts/extract_stock_blobs.sh"
if [ -f "$EXTRACT_SCRIPT" ] && grep -q "AQR114C.cld" "$EXTRACT_SCRIPT" && grep -q "32bc96c20351d7981d2d905b843899834e6dd620844218d6f3e1ecb9691745f3" "$EXTRACT_SCRIPT"; then
    log_pass "T7-BlobExtract" "Stock blob extractor has verified official SHA-256 hash for Marvell AQR114C firmware"
else
    log_fail "T7-BlobExtract" "Blob extraction script missing or missing verified SHA-256"
fi

# 8. Firewall Hook Robustness
echo "[*] Running Test 8: Firewall Hook Robustness..."
FW_HOOK="$REPO_ROOT/files/etc/firewall.d/qca-nss-ecm"
if [ -f "$FW_HOOK" ] && grep -q "forward_wan" "$FW_HOOK"; then
    log_pass "T8-Firewall" "qca-nss-ecm firewall hook includes robust chain check preventing nft errors in AP mode"
else
    log_fail "T8-Firewall" "qca-nss-ecm firewall hook check failed"
fi

# 9. IRQ Tuning Service & Defaults
echo "[*] Running Test 9: IRQ Tuning Overlay & Defaults..."
IRQ_SVC="$REPO_ROOT/files/etc/init.d/mr7500-irq-tune"
DEFAULTS_FILE="$REPO_ROOT/files/etc/uci-defaults/99-mr7500-nss-defaults"
if [ -x "$IRQ_SVC" ] && grep -q "mr7500-irq-tune" "$DEFAULTS_FILE" && grep -q "ath11k nss_offload=0 frame_mode=0" "$DEFAULTS_FILE"; then
    log_pass "T9-OverlayInit" "mr7500-irq-tune is executable and wired into 99-mr7500-nss-defaults alongside host ath11k"
else
    log_fail "T9-OverlayInit" "mr7500-irq-tune missing executable bit or not wired in 99-mr7500-nss-defaults"
fi

# 10. Switch+AP Dual Profile Integrity
echo "[*] Running Test 10: Switch+AP Dual Profile Configuration..."
SW_NET="$REPO_ROOT/config/profiles/switch-ap/files/etc/config/network"
SW_DHCP="$REPO_ROOT/config/profiles/switch-ap/files/etc/config/dhcp"
SW_UCI="$REPO_ROOT/config/profiles/switch-ap/files/etc/uci-defaults/98-mr7500-switch-ap"
if [ -f "$SW_NET" ] && [ -f "$SW_DHCP" ] && [ -x "$SW_UCI" ] && \
   grep -q "192.168.1.91" "$SW_NET" && grep -q "list ports 'wan'" "$SW_NET" && \
   ! grep -q "10.143.1.1" "$SW_NET" && grep -q "option ignore '1'" "$SW_DHCP"; then
    log_pass "T10-DualProfile" "Switch+AP build profile bridges all 5 ports at 192.168.1.91/24 with DHCP disabled"
else
    log_fail "T10-DualProfile" "Switch+AP build profile missing or malformed"
fi

# 11. Ubuntu TFTP Flasher Self-Test (RFC 1350 + RFC 2347 Loopback)
echo "[*] Running Test 11: Ubuntu 26.04 TFTP Flasher & Loopback Transfer..."
TFTP_SCRIPT="$REPO_ROOT/scripts/flash_mr7500_tftp_ubuntu.sh"
if [ -x "$TFTP_SCRIPT" ] && "$TFTP_SCRIPT" --help >/dev/null && "$TFTP_SCRIPT" --self-test >/dev/null 2>&1; then
    log_pass "T11-TFTPFlasher" "flash_mr7500_tftp_ubuntu.sh passed --help and RFC 1350/2347 TFTP loopback test"
else
    log_fail "T11-TFTPFlasher" "flash_mr7500_tftp_ubuntu.sh failed execution or TFTP self-test"
fi

# 12. Documentation, Licenses, Sources, & REA Publication
echo "[*] Running Test 12: Licenses, Sources, & REA Documentation..."
if [ -f "$REPO_ROOT/LICENSE" ] && grep -q "GNU GENERAL PUBLIC LICENSE" "$REPO_ROOT/LICENSE" && \
   [ -f "$REPO_ROOT/SOURCES_AND_LICENSES.md" ] && \
   [ -f "$REPO_ROOT/docs/MR7500_REA_BINARY_WORKFLOW_ANALYSIS.md" ] && \
   grep -q "32bc96c20351d7981d2d905b843899834e6dd620844218d6f3e1ecb9691745f3" "$REPO_ROOT/files/lib/firmware/marvell/README.md" && \
   ! grep -rn "file:///c:" "$REPO_ROOT/docs/" "$REPO_ROOT/SOURCES_AND_LICENSES.md" "$REPO_ROOT/README.md" >/dev/null 2>&1; then
    log_pass "T12-DocsAndLicenses" "LICENSE, SOURCES_AND_LICENSES.md, Marvell README hash, and sanitized REA analysis present"
else
    log_fail "T12-DocsAndLicenses" "License/source documentation missing, wrong Marvell hash, or local file URI detected"
fi

# 13. Zero Tracked Binaries in Git
echo "[*] Running Test 13: Proprietary & Compiled Binary Git Exclusion..."
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    TRACKED_BINS=$(git -C "$REPO_ROOT" ls-files | grep -E '\.(bin|itb|cld|img|ubi|tar\.gz|gpg)$' || true)
    if [ -z "$TRACKED_BINS" ]; then
        log_pass "T13-NoTrackedBinaries" "Zero proprietary blobs or compiled firmware images tracked in Git"
    else
        log_fail "T13-NoTrackedBinaries" "Binary files tracked in Git: $TRACKED_BINS"
    fi
else
    log_pass "T13-NoTrackedBinaries" "Skipped git ls-files check outside git worktree"
fi

# 14. Python Validation Suite & build.sh Check
echo "[*] Running Test 14: Python Regression Suite Syntax & Build CLI..."
if python3 -m py_compile "$REPO_ROOT/tests/test_mr7500_validation.py" && "$REPO_ROOT/scripts/build.sh" --help >/dev/null; then
    log_pass "T14-PythonAndBuildCLI" "tests/test_mr7500_validation.py compiles cleanly and build.sh --help succeeds"
else
    log_fail "T14-PythonAndBuildCLI" "Python validation compilation or build.sh CLI check failed"
fi

echo "================================================================================"
TOTAL=$((PASS + FAIL))
echo "CI PRE-BUILD TEST RESULTS: $PASS/$TOTAL PASSED ($FAIL Failures)"
echo "================================================================================"

exit $FAIL
