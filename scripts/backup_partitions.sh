#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 Full MTD Partition Backup Helper
# Backs up all 20 physical MTD partitions (mtd0 - mtd19) including factory 0:ART
# ==============================================================================
set -e

ROUTER_IP="${1:-10.143.1.1}"
BACKUP_DIR="${2:-./mr7500_backups}"

echo "======================================================================"
echo " Linksys MR7500 Full MTD Partition Backup"
echo " Router IP: $ROUTER_IP"
echo " Destination: $BACKUP_DIR"
echo "======================================================================"

mkdir -p "$BACKUP_DIR"

echo "[*] Checking router connectivity at $ROUTER_IP..."
ping -c 2 -W 2 "$ROUTER_IP" >/dev/null || {
    echo "[-] Error: Cannot reach router at $ROUTER_IP. Connect via Ethernet to LAN port."
    exit 1
}

echo "[*] Backing up critical factory partitions..."
# Critical partitions:
# mtd8: 0:ART (Factory RF calibration)
# mtd9: 0:ETHPHYFW (Aquantia PHY flash)
# mtd12: devinfo (Serial, MAC, certificates)
# mtd10/mtd11: u_env / s_env (U-Boot environment)
# mtd0-mtd7: Bootloaders (SBL1, MIBIB, QSEE, DEVCFG, RPM, CDT, APPSBL)

for part in $(seq 0 19); do
    echo "    Dumping /dev/mtd$part..."
    ssh -o StrictHostKeyChecking=no root@"$ROUTER_IP" "cat /dev/mtd$part" > "$BACKUP_DIR/mtd${part}.bin"
done

echo "[*] Calculating SHA-256 checksums..."
cd "$BACKUP_DIR"
sha256sum mtd*.bin > SHA256SUMS.txt
cat SHA256SUMS.txt

echo "======================================================================"
echo " Backup Complete! Keep these files in a secure offline location."
echo " Especially mtd8 (0:ART) and mtd12 (devinfo) which are irreplaceable."
echo "======================================================================"
