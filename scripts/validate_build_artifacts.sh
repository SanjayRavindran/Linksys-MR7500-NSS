#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 Post-Build Binary Artifacts Integrity & Sanity Checker
# Validates generated sysupgrade, factory, initramfs, AQR protection & rootfs
# ==============================================================================
set -e

TARGET_DIR="${1:-$HOME/openwrt-mr7500-build/bin/targets/qualcommax/ipq60xx}"
EXPECTED_PROFILE="${2:-}"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1: $2"; PASS=$((PASS + 1)); }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1: $2"; FAIL=$((FAIL + 1)); }
log_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1: $2"; }

echo "================================================================================"
echo " LINKSYS MR7500 POST-BUILD ARTIFACTS VALIDATION"
echo " Target Directory: $TARGET_DIR${EXPECTED_PROFILE:+ (profile: $EXPECTED_PROFILE)}"
echo "================================================================================"

SYSUPGRADE="$TARGET_DIR/openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin"
FACTORY="$TARGET_DIR/openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-factory.bin"
ITB="$TARGET_DIR/openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb"
SHA256FILE="$TARGET_DIR/sha256sums"

# 1. Existence Check
for file in "$SYSUPGRADE" "$FACTORY" "$ITB" "$SHA256FILE"; do
    if [ -f "$file" ]; then
        log_pass "EXIST" "$(basename "$file") is present"
    else
        log_fail "EXIST" "Missing expected file: $file"
    fi
done

# 2. File Size Checks
check_size() {
    local f="$1" min_mb="$2" max_mb="$3" name="$(basename "$1")"
    if [ -f "$f" ]; then
        local size_bytes size_mb
        size_bytes=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
        size_mb=$((size_bytes / 1048576))
        if [ "$size_mb" -ge "$min_mb" ] && [ "$size_mb" -le "$max_mb" ]; then
            log_pass "SIZE" "$name: ${size_mb} MB (within valid range ${min_mb}-${max_mb} MB)"
        else
            log_fail "SIZE" "$name size ${size_mb} MB is outside valid bounds (${min_mb}-${max_mb} MB)"
        fi
    fi
}

check_size "$SYSUPGRADE" 15 50
check_size "$FACTORY" 15 50
check_size "$ITB" 15 50

# 3. Sysupgrade Tar Structure, Metadata, and SquashFS Rootfs Checks
if [ -f "$SYSUPGRADE" ]; then
    TAR_CONTENTS=$(tar -tf "$SYSUPGRADE" 2>/dev/null || true)
    if echo "$TAR_CONTENTS" | grep -q "sysupgrade-linksys_mr7500/kernel" && echo "$TAR_CONTENTS" | grep -q "sysupgrade-linksys_mr7500/root"; then
        log_pass "SYSUPGRADE-TAR" "Sysupgrade tar archive contains kernel and root partitions"
    else
        log_fail "SYSUPGRADE-TAR" "Sysupgrade archive missing expected partition entries"
    fi

    CONTROL_TXT=$(tar -xOf "$SYSUPGRADE" sysupgrade-linksys_mr7500/CONTROL 2>/dev/null || true)
    if echo "$CONTROL_TXT" | grep -qi "linksys.*mr7500"; then
        log_pass "BOARD-ID" "CONTROL board tag confirmed: $CONTROL_TXT"
    else
        log_fail "BOARD-ID" "CONTROL tag does not match linksys_mr7500 (got: '$CONTROL_TXT')"
    fi

    if command -v unsquashfs >/dev/null 2>&1; then
        TMP_SQ="$(mktemp -d /tmp/mr7500_sq_chk_XXXXXX)"
        trap 'rm -rf "$TMP_SQ"' EXIT
        tar -xOf "$SYSUPGRADE" sysupgrade-linksys_mr7500/root > "$TMP_SQ/root.sqfs" 2>/dev/null || true
        unsquashfs -no-xattrs -f -d "$TMP_SQ/out" "$TMP_SQ/root.sqfs" \
            etc/init.d/qca-nss-pbuf \
            etc/init.d/mr7500-irq-tune \
            etc/uci-defaults/99-mr7500-nss-defaults \
            etc/uci-defaults/98-mr7500-switch-ap \
            etc/config/network \
            etc/config/dhcp \
            etc/config/firewall \
            lib/firmware/marvell/AQR114C.cld >/dev/null 2>&1 || true

        OUT="$TMP_SQ/out"
        if grep -q "enable_nss_offload" "$OUT/etc/init.d/qca-nss-pbuf" 2>/dev/null && \
           [ -x "$OUT/etc/init.d/mr7500-irq-tune" ] && \
           grep -q "mr7500-irq-tune" "$OUT/etc/uci-defaults/99-mr7500-nss-defaults" 2>/dev/null && \
           [ -f "$OUT/lib/firmware/marvell/AQR114C.cld" ]; then
            log_pass "ROOTFS-COMMON" "SquashFS includes patched qca-nss-pbuf, mr7500-irq-tune, defaults, and AQR114C.cld"
        else
            log_fail "ROOTFS-COMMON" "SquashFS missing patched NSS pbuf, mr7500-irq-tune, defaults, or AQR114C.cld"
        fi

        if [ "$EXPECTED_PROFILE" = "router" ]; then
            if grep -q "10.143.1.1" "$OUT/etc/config/network" 2>/dev/null && \
               grep -q "config interface 'wan'" "$OUT/etc/config/network" 2>/dev/null && \
               grep -q "option dhcpv4 'server'" "$OUT/etc/config/dhcp" 2>/dev/null && \
               [ ! -e "$OUT/etc/uci-defaults/98-mr7500-switch-ap" ]; then
                log_pass "ROOTFS-PROFILE" "SquashFS verified as Router Mode (10.143.1.1/24, WAN DHCP, LAN DHCP server)"
            else
                log_fail "ROOTFS-PROFILE" "SquashFS does not match Router Mode profile"
            fi
        elif [ "$EXPECTED_PROFILE" = "switch-ap" ]; then
            if grep -q "192.168.1.91" "$OUT/etc/config/network" 2>/dev/null && \
               grep -q "list ports 'wan'" "$OUT/etc/config/network" 2>/dev/null && \
               grep -q "option ignore '1'" "$OUT/etc/config/dhcp" 2>/dev/null && \
               ! grep -q "10.143.1.1" "$OUT/etc/config/network" 2>/dev/null && \
               [ -x "$OUT/etc/uci-defaults/98-mr7500-switch-ap" ]; then
                log_pass "ROOTFS-PROFILE" "SquashFS verified as Switch+AP Mode (192.168.1.91/24, 5 ports bridged, DHCP disabled)"
            else
                log_fail "ROOTFS-PROFILE" "SquashFS does not match Switch+AP Mode profile"
            fi
        fi
    fi
fi

# 4. Factory & ITB FIT Image Magic Header Check + AQR114C Guard
check_fit() {
    local f="$1" name="$(basename "$1")"
    if [ -f "$f" ]; then
        local magic
        magic=$(od -An -N4 -tx1 "$f" 2>/dev/null | tr -d ' \n')
        if [ "$magic" = "d00dfeed" ]; then
            log_pass "FIT-MAGIC" "$name contains valid FIT/FDT magic header (0xd00dfeed)"
        else
            log_fail "FIT-MAGIC" "$name invalid FIT magic header: $magic (expected d00dfeed)"
        fi
    fi
}

check_fit "$FACTORY"
check_fit "$ITB"

if [ -f "$ITB" ]; then
    if grep -qa "aqr_fw" "$ITB" 2>/dev/null; then
        log_fail "AQR-PROTECTION" "Built FIT DTB contains forbidden aqr_fw NVMEM cell (risks v5.4.B downgrade)"
    elif grep -qa "marvell/AQR114C.cld" "$ITB" 2>/dev/null; then
        log_pass "AQR-PROTECTION" "Built FIT DTB omits aqr_fw NVMEM cell and uses filesystem marvell/AQR114C.cld"
    else
        log_fail "AQR-PROTECTION" "Built FIT DTB missing marvell/AQR114C.cld firmware-name property"
    fi
fi

# 5. Checksum File Verification
if [ -f "$SHA256FILE" ]; then
    cd "$TARGET_DIR"
    if grep -E 'linksys_mr7500' sha256sums | sha256sum -c --status 2>/dev/null; then
        log_pass "SHA256" "Cryptographic sha256sums match MR7500 binaries exactly"
    else
        log_fail "SHA256" "sha256sum verification failed for MR7500 images"
    fi
fi

echo "================================================================================"
TOTAL=$((PASS + FAIL))
echo "ARTIFACT VALIDATION RESULTS: $PASS/$TOTAL PASSED ($FAIL Failures)"
echo "================================================================================"

exit $FAIL
