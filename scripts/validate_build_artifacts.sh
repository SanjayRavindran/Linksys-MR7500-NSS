#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 Post-Build Binary Artifacts Integrity & Sanity Checker
# Validates generated sysupgrade, factory, and initramfs images
# ==============================================================================
set -e

TARGET_DIR="${1:-$HOME/openwrt-mr7500-build/bin/targets/qualcommax/ipq60xx}"
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
echo " Target Directory: $TARGET_DIR"
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
    local f="$1"
    local min_mb="$2"
    local max_mb="$3"
    local name="$(basename "$f")"
    if [ -f "$f" ]; then
        local size_bytes=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)
        local size_mb=$((size_bytes / 1048576))
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

# 3. Sysupgrade Tar Structure & Metadata Check
if [ -f "$SYSUPGRADE" ]; then
    TAR_CONTENTS=$(tar -tf "$SYSUPGRADE" 2>/dev/null || true)
    if echo "$TAR_CONTENTS" | grep -q "sysupgrade-linksys_mr7500/kernel" && echo "$TAR_CONTENTS" | grep -q "sysupgrade-linksys_mr7500/root"; then
        log_pass "SYSUPGRADE-TAR" "Sysupgrade tar archive contains kernel and root partitions"
    else
        log_fail "SYSUPGRADE-TAR" "Sysupgrade archive missing expected partition entries"
    fi

    # Check CONTROL board identifier
    CONTROL_TXT=$(tar -xOf "$SYSUPGRADE" sysupgrade-linksys_mr7500/CONTROL 2>/dev/null || true)
    if echo "$CONTROL_TXT" | grep -qi "linksys.*mr7500"; then
        log_pass "BOARD-ID" "CONTROL board tag confirmed: $CONTROL_TXT"
    else
        log_fail "BOARD-ID" "CONTROL tag does not match linksys_mr7500 (got: '$CONTROL_TXT')"
    fi
fi

# 4. Factory & ITB FIT Image Magic Header Check
check_fit() {
    local f="$1"
    local name="$(basename "$f")"
    if [ -f "$f" ]; then
        local magic=$(od -An -N4 -tx1 "$f" 2>/dev/null | tr -d ' \n')
        # FIT / DTB magic is 0xd00dfeed -> in hex bytes: d00dfeed
        if [ "$magic" = "d00dfeed" ]; then
            log_pass "FIT-MAGIC" "$name contains valid FIT/FDT magic header (0xd00dfeed)"
        else
            log_fail "FIT-MAGIC" "$name invalid FIT magic header: $magic (expected d00dfeed)"
        fi
    fi
}

check_fit "$FACTORY"
check_fit "$ITB"

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
