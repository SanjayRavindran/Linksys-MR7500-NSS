# Sources, Attributions, Licenses & Disclaimers

This repository contains OpenWrt build patches, Device Tree (`.dts`) fixes, configuration overlays, regression/CI test suites, clean-room reverse-engineering documentation, and host helper utilities for the **Linksys MR7500 (Hydra Pro 6E / IPQ6018 + QCN9074 + AQR114C)**.

No proprietary or third-party non-redistributable binary firmware blobs are stored in or distributed by this Git repository.

---

## 1. Upstream Open-Source & Community Sources

| Source / Project | Role in This Port | License | Upstream Link |
|---|---|---|---|
| **OpenWrt Project** | Core build system, target scaffolding (`qualcommax/ipq60xx`), networking & `mac80211` scripts (`qca-nss-pbuf.init`), base Linux patch queue | **GPL-2.0-only** | https://github.com/openwrt/openwrt |
| **Linux Kernel (`6.12.92`)** | Kernel core, `phylib`, `aquantia` PHY driver, `ath11k`, `dwc3`, and IPQ6018 Device Tree bindings | **GPL-2.0-only** (DTS also dual `GPL-2.0-or-later OR MIT`) | https://kernel.org |
| **`qosmio/openwrt-ipq` (`main-nss` @ `92a2d104145c8d265851c4b388a41bd8e9c21cd9`)** | Foundational Qualcomm IPQ60xx Linux 6.12 + NSS 12.5 integration tree and baseline MR7500 DTS/image definitions | **GPL-2.0-only** | https://github.com/qosmio/openwrt-ipq |
| **`qosmio/nss-packages`** | OpenWrt packages for Qualcomm `qca-nss-drv`, `qca-nss-ecm`, `qca-nss-dp`, `qca-nss-clients`, `qca-nss-crypto`, `sqm-scripts-nss` | **ISC / BSD-3-Clause / GPL-2.0** | https://github.com/qosmio/nss-packages |
| **`openwrt/qca-ssdk`** | Qualcomm Switch Driver (`qca-ssdk.ko`) for PPE / CPPE GMAC/XGMAC and UNIPHY SerDes control | **ISC / Dual BSD-GPL-2.0** | https://github.com/openwrt/qca-ssdk |
| **OpenWrt Wiki (Linksys MR7500)** | Initial hardware pinout, partition layout, UART header, and flash reference documentation | **CC BY-SA 4.0** | https://openwrt.org/toh/linksys/mr7500 |

---

## 2. Reverse Engineering & Verification Toolchain

Static reverse-engineering analysis ([`docs/MR7500_REA_BINARY_WORKFLOW_ANALYSIS.md`](docs/MR7500_REA_BINARY_WORKFLOW_ANALYSIS.md)) was conducted in a clean-room educational/interoperability workflow using:

| Tool / Framework | Purpose | License | Reference |
|---|---|---|---|
| **`morluto/rea` (`rea-agents`)** | Multi-backend headless RE orchestration and entropy/string/symbol workflow | Open Source (per upstream repo) | https://github.com/morluto/rea |
| **NSA Ghidra (`12.1.4_PUBLIC`)** | Decompilation of ARM/ARMv7/ARM64 ELF/raw binaries (`qca-ssdk.ko`, `aq-fw-download`, `APPSBL`, `QSEE`, `RPM`, `qrfs.ko`, etc.) | **Apache-2.0** | https://github.com/NationalSecurityAgency/ghidra |
| **LLVM (`llvm-objdump`)** | Hexagon (`EM_QDSP6`) disassembly of internal IPQ6018 Wi-Fi DSP firmware | **Apache-2.0 WITH LLVM-exception** | https://llvm.org |
| **GNU Binutils & SquashFS Tools** | ARM/Thumb-2 disassembly (`objdump`), container parsing, and `unsquashfs` verification | **GPL-3.0-or-later / GPL-2.0+** | https://www.gnu.org/software/binutils/ |

---

## 3. Proprietary Firmware Reference & Non-Redistribution Policy

Certain runtime hardware components on the Linksys MR7500 require proprietary binary firmware distributed by hardware vendors / OEMs:

1. **Marvell / Aquantia `AQR114C.cld` (`v5.6.5 Cybertan Divo`):**
   * Loaded dynamically by the user/CI build host via [`scripts/extract_stock_blobs.sh`](scripts/extract_stock_blobs.sh) from the official Linksys OEM download (`FW_MR7500_1.1.12.216943_prod.img`, SHA-256 `06e2b41c...` -> extracted `.cld` SHA-256 `32bc96c20351d7981d2d905b843899834e6dd620844218d6f3e1ecb9691745f3`).
   * Copyright Marvell Technology / Aquantia Corp. & Linksys/Belkin. **Not included in Git.**
2. **Qualcomm NSS 12.5 (`qca-nss0-retail.bin`), EIP-197 Microcode (`ifpp`/`ipue`/`ofpp`/`opue.bin`), & `ath11k` Wi-Fi Firmware (`WLAN.HK.2.12` / BDFs):**
   * Fetched at build time from upstream Qualcomm/OpenWrt firmware feeds / `linux-firmware` (`LICENSE.qcom`). Copyright Qualcomm Technologies, Inc. **Not stored in this repository.**
3. **SoC Bootloader / TrustZone (`0:SBL1`, `0:QSEE`, `0:DEVCFG`, `0:RPM`, `0:CDT`, `0:APPSBL`):**
   * Documented strictly at the metadata/workflow level in [`docs/MR7500_REA_BINARY_WORKFLOW_ANALYSIS.md`](docs/MR7500_REA_BINARY_WORKFLOW_ANALYSIS.md); binaries remain on the user's device and in private local backups.

**Private CI Output Policy:** Compiled firmware images (`.bin`, `.itb`) bundle these vendor blobs and are therefore excluded from Git (`.gitignore` + `ci_test.sh`) and published strictly as **owner-only GitHub Draft Releases** (or GPG-encrypted CI artifacts if `BUILD_ENCRYPTION_KEY` is configured), never as public downloads.

---

## 4. Disclaimers

* **Repository License:** Original patches, scripts, configuration overlays, tests, and documentation in this repository are provided under the **GNU General Public License v2.0 only (`GPL-2.0-only`)** (see [`LICENSE`](LICENSE)) to remain compatible with OpenWrt and the Linux kernel.
* **No Warranty & Hardware Risk:** Flashing custom firmware, altering U-Boot environments, or modifying flash partitions carries inherent risk of permanent hardware damage or data loss. Always maintain verified local backups of `0:ART` and boot partitions before flashing. All materials are provided **"AS IS"** without warranty of any kind; proceed strictly at your own risk.
* **Reverse-Engineering Scope:** All reverse-engineering analysis published here was performed for interoperability, hardware bring-up, bug diagnosis (such as AQR114C Clause 37 USXGMII AN, probe/attach serialization, PPE GMAC `IPGT`, and CSR8811 GPIO reset polarity), security study, and educational purposes. Trademarks belong to their respective owners.
