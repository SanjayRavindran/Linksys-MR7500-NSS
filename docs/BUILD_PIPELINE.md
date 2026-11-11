# Linksys MR7500 — Automated Monthly CI/CD Build Pipeline & Private Publishing Runbook

This document describes the automated GitHub Actions CI/CD pipeline for the **Linksys MR7500 (Hydra Pro 6E)** OpenWrt + Qualcomm NSS firmware builds, detailing the pre-build automated test suite, private distribution architecture, licensing constraints, and the monthly sysupgrade procedure.

---

## 1. Pipeline Overview & Scheduling

The GitHub Actions workflow is defined in [`.github/workflows/build-monthly-snapshot.yml`](../.github/workflows/build-monthly-snapshot.yml).

### Execution Triggers
1. **Automated Monthly Schedule:**
   - Cron schedule: `0 0 1 * *` (Runs automatically on the 1st of every month at 00:00 UTC).
   - Keeps your router up to date with the latest upstream security patches, kernel updates, and OpenWrt improvements.
2. **On-Demand Manual Trigger (`workflow_dispatch`):**
   - Can be triggered manually at any time directly from the GitHub web interface:
     - Navigate to **Actions** → **Build Monthly Snapshot Firmware (Private)** → **Run workflow**.
   - Configurable inputs:
     - `encrypt_artifacts` (boolean, default `false`): Symmetric AES-256 GPG encryption.
     - `create_draft_release` (boolean, default `true`): Publishes a private Draft Release.
     - `retention_days` (number, default `90`): Actions artifact storage retention in days.

---

## 2. Privacy Architecture & Proprietary Blob Licensing

> [!IMPORTANT]
> ### WHY BUILDS ARE STRICTLY PRIVATE
> The compiled binary firmware images include proprietary firmware blobs:
> 1. **Marvell/Aquantia AQR114C PHY Firmware (`AQR114C.cld`):** Extracted from official Linksys stock firmware (`FW_MR7500_1.1.12.216943_prod.img`).
> 2. **Qualcomm NSS Core Firmware:** NSS 12.5 Ubi microcode and cryptographic accelerator drivers.
>
> These proprietary binaries are **not licensed for public redistribution**. While the source code, patches, DTS definitions, and documentation in this repository are 100% open-source under GPL-2.0, **the compiled binary images must never be published publicly**.

### Multi-Tier Privacy Enforcement:
1. **GitHub Actions Workflow Artifacts (Encrypted Only):**
   - Uploaded **only when** `BUILD_ENCRYPTION_KEY` is configured (`aes256` GPG `.tar.gz.gpg`), preventing unencrypted vendor blobs from appearing on Actions runs.
2. **Private Draft Releases:**
   - The workflow creates releases using GitHub CLI with `--draft` (`gh release create ... --draft`).
   - On GitHub, **Draft Releases are completely hidden from the public**. Anonymous visitors and normal users navigating to the releases page will see a 404 / empty page. Only the repository owner and maintainers with push permissions can view and download draft release assets.
3. **Optional Cryptographic AES-256 GPG Encryption (Zero-Knowledge):**
   - For total defense in depth, you can configure a repository secret named `BUILD_ENCRYPTION_KEY`:
     - Go to **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
     - Name: `BUILD_ENCRYPTION_KEY`
     - Value: A strong passphrase of your choice.
   - When configured (or selected via `encrypt_artifacts: true`), the workflow encrypts the compiled archive with `gpg --symmetric --cipher-algo AES256`. Even if anyone obtained the archive file, it cannot be unpacked without your passphrase.

---

## 3. Pre-Build Automated Test Suite (`scripts/ci_test.sh`)

Before a single compiler thread is spawned, the workflow executes the 17-gate pre-build test suite in [`scripts/ci_test.sh`](../scripts/ci_test.sh) plus a live upstream patch-apply check against `qosmio/openwrt-ipq` (`92a2d104`) on Ubuntu 24.04:

| Test ID | Test Name | Purpose & Verification Criteria |
|---|---|---|
| **T1** | **Script Syntax Validation** | Runs `bash -n` on all repository scripts, `/etc/rc.local`, `/usr/sbin/switch_mode`, and firewall hooks. |
| **T2** | **Patch 0001 Integrity** | Asserts AQR114C timing (`reset-deassert-us = <250000>`), USB host mode (`dr_mode = "host"`), MACSec PHY address (`0x8`), and C45 MDIO probe retry logic (`FWNODE_MDIO_C45_PROBE`). |
| **T3** | **Patch 0002 In-Band Signalling** | Verifies USXGMII `managed = "in-band-status"` DTS property for 5GbE WAN link rate negotiation. |
| **T4** | **Security & Sensitive Data Leak Audit** | Scans all files for leaked SSH private keys, API tokens, passwords, or personal credentials. |
| **T5** | **Default Operating Mode Verification** | Asserts that `files/etc/config/network` and `dhcp` configure **Router Mode** (`10.143.1.1/24`, WAN DHCP client, LAN DHCP server active), and `/usr/sbin/switch_mode` is executable. |
| **T6** | **Diffconfig Architecture & Package Symbols** | Validates target architecture (`qualcommax/ipq60xx/linksys_mr7500`), NSS 12.5 firmware, crypto offloading, SQM, and filesystem drivers (`vfat`, `exfat`). |
| **T7** | **Stock Blob Extractor Verification** | Verifies that `scripts/extract_stock_blobs.sh` checks the official SHA-256 checksum (`32bc96c20351d7981d2d905b843899834e6dd620844218d6f3e1ecb9691745f3`) for `AQR114C.cld`. |
| **T8** | **Firewall Hook Robustness** | Verifies `/etc/firewall.d/qca-nss-ecm` includes an nft chain check to prevent syntax errors when operating in Switch+AP mode. |

If any of these 17 checks fail, the workflow terminates immediately, preventing unnecessary runner usage.

---

## 4. Post-Build Binary Artifacts Validation (`scripts/validate_build_artifacts.sh`)

Once compilation finishes, [`scripts/validate_build_artifacts.sh`](../scripts/validate_build_artifacts.sh) performs 15 comprehensive structural (including `unsquashfs` profile + AQR114C DTB protection) and cryptographic checks on the generated binaries:

1. **Existence Verification:** Confirms all 3 required images and checksum files exist:
   - `openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin`
   - `openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-factory.bin`
   - `openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb`
   - `sha256sums`
2. **File Size Sanity:** Verifies images are within safe bounds (15 MB to 50 MB), protecting against truncated builds or partition overflow.
3. **Sysupgrade Tar Structure:** Modern OpenWrt IPQ6018 sysupgrade images are POSIX tar archives containing:
   - `sysupgrade-linksys_mr7500/kernel`
   - `sysupgrade-linksys_mr7500/root`
   - `sysupgrade-linksys_mr7500/CONTROL`
4. **Board Tag Identifier:** Asserts `CONTROL` metadata explicitly matches `BOARD=linksys_mr7500`.
5. **FIT Image Magic Headers:** Verifies that factory and initramfs ITB images start with the Flattened Image Tree magic bytes `0xd00dfeed`.
6. **Cryptographic SHA-256 Consistency:** Confirms that all generated hashes match the binaries bit-for-bit.

---

## 5. Monthly Sysupgrade Procedure

Follow these steps once a month to flash the newly built private firmware onto your Linksys MR7500:

### Step 1: Download Private Build Artifact
1. Go to your repository on GitHub: `https://github.com/SanjayRavindran/Linksys-MR7500-NSS`
2. Click **Actions** → Select the latest successful **Build Monthly Snapshot Firmware (Private)** run.
3. Scroll to the bottom under **Artifacts** and click `mr7500-firmware-YYYYMMDD.zip` to download.
   *(Alternatively, go to **Releases** and download from your private **Draft Release**).*

### Step 2: Extract & Decrypt (if GPG encryption was enabled)
Unzip the downloaded artifact:
```bash
unzip mr7500-firmware-YYYYMMDD.zip
```
If encrypted with GPG:
```bash
gpg -d mr7500-openwrt-nss-YYYYMMDD.tar.gz.gpg | tar -xz
```
If unencrypted:
```bash
tar -xzvf mr7500-openwrt-nss-YYYYMMDD.tar.gz
```

Verify SHA-256 checksums:
```bash
sha256sum -c sha256sums.txt
```

### Step 3: Flash Sysupgrade to Router

#### Option A: Via LuCI Web Interface
1. Open your browser and log in to LuCI:
   - If running in **Router Mode**: `https://10.143.1.1`
   - If running in **Switch + AP Mode**: `https://192.168.1.91`
2. Navigate to **System** → **Backup / Flash Firmware**.
3. Under **Flash new firmware image**, click **Flash image...**.
4. Select `openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin`.
5. Review the checksums and click **Continue**.
6. The router will flash the active slot, reboot within ~90 seconds, and come back online.

#### Option B: Via SSH Command Line
Transfer the sysupgrade binary to the router's `/tmp`:
```bash
# In Switch + AP mode:
scp openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin root@192.168.1.91:/tmp/sysupgrade.bin

# Or in Router mode:
scp openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin root@10.143.1.1:/tmp/sysupgrade.bin
```

SSH into the router and initiate sysupgrade:
```bash
ssh root@192.168.1.91  # (or 10.143.1.1)

# To preserve existing settings:
sysupgrade -v /tmp/sysupgrade.bin

# Or to restore clean default Router Mode:
sysupgrade -n -v /tmp/sysupgrade.bin
```

---

## 6. Operating Mode Management (`switch_mode`)

By default, every newly compiled image publishes in **Router Mode** (`10.143.1.1/24`, NAT, LAN DHCP server). All builds bundle the pre-installed mode switcher utility at `/usr/sbin/switch_mode`.

### To switch to Switch + AP Mode:
Connect all 5 physical ports (5GbE WAN + 4x Gigabit LAN) and Wi-Fi 6E radios into a single unified bridge with local DHCP disabled:
```bash
/usr/sbin/switch_mode ap 192.168.1.91
```

### To switch back to Router Mode:
Restore full NAT routing, WAN DHCP client, and authoritative LAN DHCP server:
```bash
/usr/sbin/switch_mode router
```
