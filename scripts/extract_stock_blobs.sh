#!/usr/bin/env bash
# ==============================================================================
# Extract Marvell AQR114C PHY Firmware Blob from Official Linksys Stock Firmware
# Target: Linksys MR7500 (Hydra Pro 6E) v1
# Official Image: FW_MR7500_1.1.12.216943_prod.img
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$REPO_ROOT/files/lib/firmware/marvell"
TARGET_FILE="$TARGET_DIR/AQR114C.cld"

EXPECTED_IMG_SHA256="06e2b41c77f2722e2cec8164def1c8476f519211d9bb83a9e5c097e2f1df1a49"
EXPECTED_CLD_SHA256="8a0e88cf738a0b07e602495d43be6c13fe6272551527efd04b6df00d3cb12eb6"
STOCK_FW_URL="https://downloads.linksys.com/support/assets/firmware/FW_MR7500_1.1.12.216943_prod.img"

DOWNLOAD_DIR="${1:-$HOME/mr7500_stock_dl}"
mkdir -p "$DOWNLOAD_DIR" "$TARGET_DIR"

IMG_PATH="$DOWNLOAD_DIR/FW_MR7500_1.1.12.216943_prod.img"

if [ -f "$TARGET_FILE" ]; then
    CURRENT_SHA256=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
    if [ "$CURRENT_SHA256" = "$EXPECTED_CLD_SHA256" ]; then
        echo "[+] $TARGET_FILE is already present with verified SHA-256."
        exit 0
    fi
fi

if [ ! -f "$IMG_PATH" ]; then
    echo "[*] Downloading official Linksys MR7500 stock firmware (v1.1.12.216943)..."
    curl -L --retry 3 --progress-bar -o "$IMG_PATH" "$STOCK_FW_URL"
fi

echo "[*] Verifying downloaded firmware image SHA-256..."
IMG_SHA256=$(sha256sum "$IMG_PATH" | awk '{print $1}')
if [ "$IMG_SHA256" != "$EXPECTED_IMG_SHA256" ]; then
    echo "[-] Error: Firmware SHA-256 mismatch!"
    echo "    Expected: $EXPECTED_IMG_SHA256"
    echo "    Actual:   $IMG_SHA256"
    exit 1
fi
echo "[+] Firmware SHA-256 verified."

echo "[*] Extracting SquashFS root filesystem from UBI container..."
TMP_WORK=$(mktemp -d /tmp/mr7500_blob_XXXXXX)
trap 'rm -rf "$TMP_WORK"' EXIT

python3 - "$IMG_PATH" "$TMP_WORK" << 'PYEOF'
import os, struct, sys
img_path, out_dir = sys.argv[1], sys.argv[2]
PEB = 128 * 1024

with open(img_path, 'rb') as f:
    data = f.read()

# UBI partition starts at 8 MiB (0x800000)
ubi = data[0x800000:]
vols = {}
for i in range(len(ubi) // PEB):
    peb = ubi[i * PEB:(i + 1) * PEB]
    if peb[:4] != b'UBI#':
        continue
    _, _ver, _pad, ec, vid_off, data_off = struct.unpack('>4sB3sQII', peb[:24])
    vid = peb[vid_off:vid_off + 64]
    if vid[:4] != b'UBI!':
        continue
    _m, _v, vtype, _cf, _cp, vol_id, lnum, _p, data_size, used_ebs, data_pad, data_crc, _p2, sqnum = \
        struct.unpack('>4sBBBBIIIIIIIIQ', vid[:48])
    if vol_id >= 0x7fffefff:
        continue
    size = data_size if data_size else PEB - data_off
    leb = peb[data_off:data_off + (size if vtype == 2 else PEB - data_off)]
    old = vols.setdefault(vol_id, {}).get(lnum)
    if old is None or sqnum > old[0]:
        vols[vol_id][lnum] = (sqnum, leb)

for vid_id, lebs in vols.items():
    if vid_id == 0:  # vol 0 is rootfs (squashfs)
        vpath = os.path.join(out_dir, 'rootfs.sqfs')
        with open(vpath, 'wb') as vf:
            for lnum in range(max(lebs) + 1):
                vf.write(lebs[lnum][1] if lnum in lebs else b'\xff' * (PEB - 4096))
        break
PYEOF

if [ ! -f "$TMP_WORK/rootfs.sqfs" ]; then
    echo "[-] Error: Failed to extract rootfs.sqfs from UBI."
    exit 1
fi

echo "[*] Extracting AQR114C.cld from SquashFS..."
unsquashfs -no-xattrs -f -d "$TMP_WORK/unpacked" "$TMP_WORK/rootfs.sqfs" etc/AQR114C.cld >/dev/null

EXTRACTED="$TMP_WORK/unpacked/etc/AQR114C.cld"
if [ ! -f "$EXTRACTED" ]; then
    echo "[-] Error: etc/AQR114C.cld not found in extracted rootfs."
    exit 1
fi

CLD_SHA256=$(sha256sum "$EXTRACTED" | awk '{print $1}')
if [ "$CLD_SHA256" != "$EXPECTED_CLD_SHA256" ]; then
    echo "[-] Error: AQR114C.cld SHA-256 mismatch!"
    echo "    Expected: $EXPECTED_CLD_SHA256"
    echo "    Actual:   $CLD_SHA256"
    exit 1
fi

cp "$EXTRACTED" "$TARGET_FILE"
echo "[+] Successfully extracted $TARGET_FILE ($(wc -c < "$TARGET_FILE") bytes)"
echo "[+] Verified SHA-256: $CLD_SHA256 (v5.6.5 Cybertan Divo)"
