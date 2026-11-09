#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 (Hydra Pro 6E) Automated OpenWrt + NSS Firmware Builder
# Base: qosmio/openwrt-ipq (main-nss @ commit 92a2d10)
# Kernel: 6.12.92 | NSS: 12.5-210 | Crypto: EIP-197 | Multi-Gig: AQR114C
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$HOME/openwrt-mr7500-build}"
BASE_GIT="https://github.com/qosmio/openwrt-ipq.git"
BASE_COMMIT="92a2d10b78c41db1b4020a1eb9753177dc7eb91c"

# Optional GCC 14 wrapper
HOSTCC_DIR="$HOME/.local/openwrt-hostcc"
if [ -d "$HOSTCC_DIR" ]; then
    export PATH="$HOSTCC_DIR:$PATH"
fi

echo "======================================================================"
echo " Building Linksys MR7500 OpenWrt + Qualcomm NSS Firmware"
echo " Build directory: $BUILD_DIR"
echo "======================================================================"

# 1. Check AQR114C PHY firmware blob
AQR_BLOB="$REPO_ROOT/files/lib/firmware/marvell/AQR114C.cld"
if [ ! -f "$AQR_BLOB" ]; then
    echo "[!] AQR114C.cld not found. Attempting automatic extraction..."
    "$SCRIPT_DIR/extract_stock_blobs.sh"
    if [ ! -f "$AQR_BLOB" ]; then
        echo "[-] Error: AQR114C.cld is required for multi-gigabit WAN functionality."
        echo "    Run ./scripts/extract_stock_blobs.sh first."
        exit 1
    fi
fi

# 2. Clone or update base repository
if [ ! -d "$BUILD_DIR/.git" ]; then
    echo "[*] Cloning qosmio/openwrt-ipq..."
    git clone "$BASE_GIT" "$BUILD_DIR"
    cd "$BUILD_DIR"
    git checkout "$BASE_COMMIT"
else
    echo "[*] Using existing build directory at $BUILD_DIR..."
    cd "$BUILD_DIR"
fi

# 3. Update and install feeds
echo "[*] Updating and installing feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# 4. Apply MR7500 NSS patches
echo "[*] Applying Linksys MR7500 NSS patches..."
for patch in "$REPO_ROOT/patches/"*.patch; do
    [ -f "$patch" ] || continue
    echo "    Applying $(basename "$patch")..."
    git apply --check "$patch" 2>/dev/null && git apply "$patch" || {
        echo "    Patch already applied or conflict detected; verifying status..."
    }
done

# 5. Copy files overlay
echo "[*] Copying rootfs overlay files..."
mkdir -p "$BUILD_DIR/files"
cp -r "$REPO_ROOT/files/"* "$BUILD_DIR/files/"

# 6. Apply configuration
echo "[*] Applying minimal MR7500 NSS diffconfig..."
cp "$REPO_ROOT/config/mr7500_nss_diffconfig" "$BUILD_DIR/.config"
make defconfig

# 7. Compile firmware
NPROC=$(nproc 2>/dev/null || echo 4)
echo "[*] Compiling firmware using $NPROC CPU threads..."
make -j"$NPROC"

# 8. Summary & Post-Build Validation
OUT_TARGET="$BUILD_DIR/bin/targets/qualcommax/ipq60xx"
echo "======================================================================"
echo " Build Complete! Built images in $OUT_TARGET:"
echo "======================================================================"
ls -lh "$OUT_TARGET"/*mr7500* "$OUT_TARGET"/sha256sums 2>/dev/null || true

# Run binary artifact verification
if [ -x "$SCRIPT_DIR/validate_build_artifacts.sh" ]; then
    echo "[*] Running post-build artifact integrity checks..."
    "$SCRIPT_DIR/validate_build_artifacts.sh" "$OUT_TARGET"
fi

echo ""
echo "Factory install:   openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-factory.bin"
echo "Sysupgrade:        openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin"
echo "TFTP RAM-boot:     openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb"
echo "======================================================================"
