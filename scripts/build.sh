#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 (Hydra Pro 6E) Automated OpenWrt + NSS Firmware Builder
# Base: qosmio/openwrt-ipq (main-nss @ 92a2d104145c8d265851c4b388a41bd8e9c21cd9)
# Kernel: 6.12.92 | NSS: 12.5-210 | Crypto: EIP-197 | Multi-Gig: AQR114C
# Supports: --profile router | switch-ap | all
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$HOME/openwrt-mr7500-build}"
BASE_GIT="https://github.com/qosmio/openwrt-ipq.git"
BASE_COMMIT="92a2d104145c8d265851c4b388a41bd8e9c21cd9"
BUILD_PROFILE="${BUILD_PROFILE:-router}"
SKIP_FEED_UPDATE="${SKIP_FEED_UPDATE:-0}"
SKIP_DEFCONFIG="${SKIP_DEFCONFIG:-0}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile) BUILD_PROFILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--profile router|switch-ap|all]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

case "$BUILD_PROFILE" in
    router|switch-ap|all) ;;
    *) echo "[-] Invalid profile '$BUILD_PROFILE'. Expected router, switch-ap, or all."; exit 1 ;;
esac

# Optional GCC 14 wrapper
HOSTCC_DIR="$HOME/.local/openwrt-hostcc"
if [ -d "$HOSTCC_DIR" ]; then
    export PATH="$HOSTCC_DIR:$PATH"
fi

echo "======================================================================"
echo " Building Linksys MR7500 OpenWrt + Qualcomm NSS Firmware"
echo " Build directory: $BUILD_DIR"
echo " Target profile:  $BUILD_PROFILE"
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
if [ "$SKIP_FEED_UPDATE" != "1" ]; then
    echo "[*] Updating and installing feeds..."
    ./scripts/feeds update -a
    ./scripts/feeds install -a
else
    echo "[*] SKIP_FEED_UPDATE=1 set; keeping existing feeds."
fi

# 4. Apply MR7500 NSS patches (strict on clean tree; verify reverse-stack on already-patched tree)
echo "[*] Applying Linksys MR7500 NSS patches..."
PATCH_LIST=("$REPO_ROOT"/patches/*.patch)
FIRST_PATCH="${PATCH_LIST[0]}"
if [ -n "$FIRST_PATCH" ] && [ -f "$FIRST_PATCH" ]; then
    if git apply --check "$FIRST_PATCH" 2>/dev/null; then
        for patch in "${PATCH_LIST[@]}"; do
            [ -f "$patch" ] || continue
            pname="$(basename "$patch")"
            echo "    [apply] $pname..."
            git apply --check "$patch"
            git apply "$patch"
        done
    else
        echo "    Existing patched workspace detected; verifying full reverse-stack consistency..."
        CHK_DIR="$(mktemp -d /tmp/mr7500_pchk_XXXXXX)"
        python3 - "$BUILD_DIR" "$CHK_DIR" "${PATCH_LIST[@]}" << 'PY_PCHK'
import os, re, shutil, subprocess, sys
bdir, cdir, *patches = sys.argv[1:]
files = set()
for p in patches:
    txt = open(p, "r", encoding="utf-8").read()
    for m in re.finditer(r"^\+\+\+ (?:b/)?(.+)$", txt, re.M):
        rel = m.group(1).strip()
        if rel != "/dev/null":
            files.add(rel)
    for m in re.finditer(r"^--- (?:a/)?(.+)$", txt, re.M):
        rel = m.group(1).strip()
        if rel != "/dev/null":
            files.add(rel)
for rel in files:
    src = os.path.join(bdir, rel)
    if os.path.exists(src):
        dst = os.path.join(cdir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
subprocess.run(["git", "init", "-q"], cwd=cdir, check=True)
subprocess.run(["git", "add", "."], cwd=cdir, check=True)
subprocess.run(["git", "-c", "user.name=chk", "-c", "user.email=chk@local", "commit", "-q", "-m", "state"], cwd=cdir, check=True)
for p in reversed(patches):
    res = subprocess.run(["git", "apply", "--reverse", p], cwd=cdir, text=True, capture_output=True)
    if res.returncode != 0:
        sys.stderr.write(f"[-] Reverse-stack verify failed at {os.path.basename(p)}:\n{res.stderr}\n")
        sys.exit(1)
    print(f"    [verified] {os.path.basename(p)} cleanly applied in workspace.")
PY_PCHK
        rm -rf "$CHK_DIR"
    fi
fi

stage_profile_files() {
    local prof="$1"
    echo "[*] Staging rootfs overlay for profile '$prof'..."
    rm -rf "$BUILD_DIR/files"
    mkdir -p "$BUILD_DIR/files"
    cp -a "$REPO_ROOT/files/." "$BUILD_DIR/files/"
    if [ "$prof" = "switch-ap" ]; then
        if [ ! -d "$REPO_ROOT/config/profiles/switch-ap/files" ]; then
            echo "[-] Missing config/profiles/switch-ap/files!"
            exit 1
        fi
        cp -a "$REPO_ROOT/config/profiles/switch-ap/files/." "$BUILD_DIR/files/"
    else
        # Remove switch-ap-only uci-defaults hook if switching an incremental build back to router
        rm -f "$BUILD_DIR"/build_dir/target-*/root-qualcommax/etc/uci-defaults/98-mr7500-switch-ap 2>/dev/null || true
    fi
}

NPROC=$(nproc 2>/dev/null || echo 4)
OUT_TARGET="$BUILD_DIR/bin/targets/qualcommax/ipq60xx"
PROFILES_OUT="$BUILD_DIR/bin/targets/qualcommax/ipq60xx-profiles"
mkdir -p "$PROFILES_OUT"

run_profile_build() {
    local prof="$1"
    local is_first="$2"
    local dest_sub="router-mode"
    [ "$prof" = "switch-ap" ] && dest_sub="switch-ap-mode"

    stage_profile_files "$prof"

    if [ "$is_first" = "1" ] && [ "$SKIP_DEFCONFIG" != "1" ]; then
        echo "[*] Applying minimal MR7500 NSS diffconfig..."
        cp "$REPO_ROOT/config/mr7500_nss_diffconfig" "$BUILD_DIR/.config"
        make defconfig
    fi

    echo "[*] Compiling firmware ($prof) using $NPROC CPU threads..."
    if [ -d "$BUILD_DIR"/build_dir/target-*/root-qualcommax ]; then
        make package/install -j"$NPROC"
    fi
    make -j"$NPROC"

    rm -rf "$PROFILES_OUT/$dest_sub"
    mkdir -p "$PROFILES_OUT/$dest_sub"
    cp -a "$OUT_TARGET"/*mr7500* "$OUT_TARGET/sha256sums" "$PROFILES_OUT/$dest_sub/"
    (cd "$PROFILES_OUT/$dest_sub" && grep linksys_mr7500 sha256sums > sha256sums.txt || true)

    if [ -x "$SCRIPT_DIR/validate_build_artifacts.sh" ]; then
        echo "[*] Running post-build artifact integrity checks for $prof..."
        "$SCRIPT_DIR/validate_build_artifacts.sh" "$PROFILES_OUT/$dest_sub" "$prof"
    fi
}

if [ "$BUILD_PROFILE" = "all" ]; then
    run_profile_build "router" "1"
    run_profile_build "switch-ap" "0"
    cp -f "$SCRIPT_DIR/flash_mr7500_tftp_ubuntu.sh" "$PROFILES_OUT/"
    chmod +x "$PROFILES_OUT/flash_mr7500_tftp_ubuntu.sh"
    # Restore default Router Mode files/ overlay cleanly in build workspace
    stage_profile_files "router"
else
    run_profile_build "$BUILD_PROFILE" "1"
fi

echo "======================================================================"
echo " Build Complete! Images validated in:"
ls -lh "$PROFILES_OUT"/*/*mr7500* 2>/dev/null || ls -lh "$OUT_TARGET"/*mr7500* 2>/dev/null || true
echo "======================================================================"
