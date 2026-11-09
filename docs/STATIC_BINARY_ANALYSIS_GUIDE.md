# Linksys MR7500 Firmware Blobs & Static Binary Analysis Reference Guide

> **Purpose:** This reference guide provides reverse engineers, firmware developers, and security researchers with technical specifications, architecture mappings, container formats, and static analysis methodologies for the proprietary binary blobs utilized on the **Linksys MR7500 v1 (Hydra Pro 6E / IPQ6018)**.
>
> **Scope:** Strictly for architectural study, driver interoperability research, and firmware integrity analysis.

---

## 1. Complete Firmware Blob Taxonomy & Architecture Matrix

| Blob Path | Component / Subsystem | Target Processor Core | Architecture & Endianness | Container Format | Key Functionality |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `phy/AQR114C.cld` | Marvell/Aquantia AQR114C 5GbE PHY | Synopsys DesignWare ARC (ARCv2 / ARC EM) | 32-bit RISC (Little-Endian) | Cybertan / Aquantia CLD | DSP equalization, SerDes auto-negotiation, USXGMII Clause 37/45 MDIO |
| `nss/qca-nss0-retail-12.5.bin` | Qualcomm NSS Ubi Core 0 (v12.5) | Qualcomm Ubi32 V4 Core | 32-bit Multithreaded RISC (`EM_UBICOM32` / 223) | ELF32 Executable | Hardware L3 routing, NAT44, NAT66, bridging, crypto acceleration |
| `nss/qca-nss0-stock-11.5.bin` | Qualcomm NSS Ubi Core 0 (v11.5 OEM) | Qualcomm Ubi32 V4 Core | 32-bit Multithreaded RISC (`EM_UBICOM32` / 223) | ELF32 Executable | Stock OEM hardware offloading engine |
| `nss/ifpp.bin` | NSS Input Fast Path Parser | Qualcomm NSS Coprocessor | Microcode Engine | Raw Binary Microcode | Ingress frame parsing, header classification, flow hash calculation |
| `nss/ipue.bin` | NSS Input Packet Update Engine | Qualcomm NSS Coprocessor | Microcode Engine | Raw Binary Microcode | Ingress descriptor manipulation, buffer allocation, QoS marking |
| `nss/ofpp.bin` | NSS Output Fast Path Parser | Qualcomm NSS Coprocessor | Microcode Engine | Raw Binary Microcode | Egress frame validation, checksum recalculation, MTU checking |
| `nss/opue.bin` | NSS Output Packet Update Engine | Qualcomm NSS Coprocessor | Microcode Engine | Raw Binary Microcode | Egress descriptor release, TX DMA trigger, stats accumulation |
| `wifi/IPQ6018/q6_fw.mdt` | IPQ6018 Internal WLAN Radio (2.4G/5G) | Qualcomm Hexagon DSP (QDSP6 V66) | VLIW Multithreaded DSP (Little-Endian) | Qualcomm Split MBN / ELF | Physical layer radio modem, MAC layer scheduling, beamforming |
| `wifi/IPQ6018/m3_fw.mdt` | IPQ6018 Internal WLAN Power Controller | ARM Cortex-M3 | 32-bit ARM Thumb-2 (Little-Endian) | Qualcomm Split MBN / ELF | RF power sequencing, PLL calibration, PCIe link power states |
| `wifi/IPQ6018/bdwlan.b11` | IPQ6018 Board Data File | N/A (Data structure) | Structured TLV Binary | ATH11K BDF Binary | RF power amplifier bias tables, LNA gain steps, regulatory channels |
| `wifi/IPQ6018/board-2.bin` | IPQ6018 Board Data Container | N/A (Multi-board container) | ATH11K BDF2 TLV Container | BDF2 Archive | Multi-board radio calibration lookup indexed by board-id/chip-id |
| `wifi/QCN9074/amss.bin` | QCN9074 6GHz PCIe Wi-Fi 6E Radio | Qualcomm Hexagon DSP (QDSP6 V67) | VLIW Multithreaded DSP (Little-Endian) | Qualcomm ELF / Monolithic MBN | Full MAC Wi-Fi 6E 160MHz radio firmware, 4x4 spatial streams |
| `wifi/QCN9074/m3.bin` | QCN9074 PCIe Power Management | ARM Cortex-M3 | 32-bit ARM Thumb-2 (Little-Endian) | Qualcomm MBN Binary | QCN9074 PCIe power state controller, sleep/wake sequencing |
| `wifi/QCN9074/bdwlan.ba4` | QCN9074 6GHz Board Data File | N/A (Data structure) | Structured TLV Binary | ATH11K BDF Binary | 6 GHz UNII-5..8 frequency power tables, 160 MHz channel calibration |
| `wifi/QCN9074/board-2.bin` | QCN9074 Board Data Container | N/A (Multi-board container) | ATH11K BDF2 TLV Container | BDF2 Archive | Multi-SKU QCN9074 RF calibration table |
| `boot/0_SBL1.bin` | Secondary Bootloader | ARM Cortex-A53 (APSS Core 0) | 64-bit ARMv8-A (Little-Endian) | Qualcomm MBN Flash Image | PMIC initialization, DDR3L timing setup, security fuse verification |
| `boot/0_APPSBL_uboot.bin` | U-Boot Bootloader | ARM Cortex-A53 | 64-bit ARMv8-A (Little-Endian) | Standard ELF / U-Boot binary | Flash driver, network initialization, environment parser, bootm loader |
| `boot/0_QSEE_trustzone.bin` | Qualcomm Secure Execution Environment | ARM Cortex-A53 (EL3 / Secure World) | 64-bit ARMv8-A Secure Monitor | Qualcomm MBN Signed Image | Cryptographic key management, hardware access control, secure calls |
| `boot/0_RPM.bin` | Resource Power Manager | ARM Cortex-M3 | 32-bit ARM Thumb-2 (Little-Endian) | Qualcomm MBN Signed Image | Clock gating, dynamic voltage scaling, power rail regulation |
| `boot/0_DEVCFG.bin` | TrustZone Device Configuration | N/A (Hardware config tree) | Compiled Qualcomm Device Tree | Qualcomm MBN Binary | Security permissions, peripheral access control lists (ACLs) |
| `boot/0_CDT.bin` | Configuration Data Table | N/A (Hardware descriptors) | Qualcomm CDT Binary Table | Binary Table | DDR3L timings, memory geometry, clock frequency tables |

---

## 2. In-Depth Subsystem Technical Analysis

### 2.1 Marvell/Aquantia AQR114C Multi-Gigabit PHY Firmware (`AQR114C.cld`)

#### Architectural Profile:
* **Controller Core:** Synopsys DesignWare ARC (Argonaut RISC Core) processor embedded inside the AQR114C silicon.
* **Instruction Set:** ARCv2 / ARC Compact 16/32-bit instructions (Little-Endian).
* **Firmware Version:** `v5.6.5 Cybertan Divo` (Build date ~2020/2021).
* **Binary Size:** 393,218 bytes.
* **Storage Location:** On stock firmware, stored on dedicated SPI NOR partition `mtd9` (`0:ETHPHYFW`) and loaded from `/etc/AQR114C.cld`. In OpenWrt, loaded via kernel firmware loader from `/lib/firmware/marvell/AQR114C.cld`.

#### Container Structure (Cybertan / Aquantia CLD Format):
```text
+-------------------------------------------------------------+
| Header Magic / Signature (e.g. 0x00000000 / Vendor ID)      |  Offset 0x0000 - 0x000F
+-------------------------------------------------------------+
| Firmware Version String ("5.6.5", Build Identifiers)        |  Offset 0x0010 - 0x003F
+-------------------------------------------------------------+
| Memory Map & Segment Descriptor Table                       |
|   - Segment 0: ARC Boot Code & Reset Vector Table           |
|   - Segment 1: DSP Equalizer & Filtering Microcode          |
|   - Segment 2: MDIO Clause 45 Register Service Engine       |
|   - Segment 3: SerDes USXGMII / SGMII Protocol Engine       |
+-------------------------------------------------------------+
| Data Segments & Checksums (CRC32 per segment block)         |
+-------------------------------------------------------------+
```

#### Static Analysis Workflow:
1. **Entropy & Chunk Identification:**
   ```bash
   binwalk -E AQR114C.cld
   ```
   * *Observation:* High entropy (> 0.95) across the code regions indicates densely packed ARC instructions and DSP coefficient tables.
2. **Disassembly in Ghidra / IDA Pro:**
   * **Architecture Selector:** Select `ARC` / `ARCv2` (Little Endian, 32-bit).
   * **Base Address:** The ARC code executes from internal SRAM at `0x00000000` or `0x00010000`.
   * **Key Function Signatures:**
     * Look for MDIO register read/write handler routines interacting with memory-mapped registers at address ranges `0x1E000000` / `0x1F000000` (PHYXS, PMA/PMD, PCS registers).
     * Clause 37 auto-negotiation logic: Locate references to register `0xC441` (PHYXS Auto-Negotiation Control). In stock firmware, bit 3 (`0x0008`) is written during SerDes mode switch to USXGMII.

---

### 2.2 Qualcomm NSS Network Subsystem (`qca-nss0-retail-12.5.bin`)

#### Architectural Profile:
* **Processor Architecture:** Qualcomm Ubi32 (formerly Ubicom IP3024 / IP7000 / IP8000 series RISC).
* **Format:** ELF 32-bit LSB (Little Endian) executable.
* **Machine Type:** `EM_UBICOM32` (`0x00DF` / Decimal `223`).
* **Hardware Capabilities:** Dual Ubi32 cores operating at up to 1.4976 GHz with 12 hardware execution threads per core. Contains dedicated hardware packet acceleration units (Input/Output Packet Parsers & Updaters).

#### ELF Header Analysis (`readelf -h qca-nss0-retail-12.5.bin`):
```text
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00 
  Class:                             ELF32
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           223 (Ubicom32)
  Version:                           0x1
  Entry point address:               0x40000000
  Start of program headers:          52 (bytes into file)
  Start of section headers:          861444 (bytes into file)
```

#### Memory Layout & Memory Carveouts:
* **Entry Point:** `0x40000000`.
* **Execution Location:** Loaded by Linux kernel driver (`qca-nss-drv`) into dedicated reserved DDR memory carveouts configured in Device Tree:
  * `nss@40000000`: `0x40000000` – `0x41000000` (16 MB physical DDR carveout).
  * `tcm@3a100000`: 128 KiB on-chip Tightly Coupled Memory for zero-wait-state packet descriptor rings.

---

### 2.3 ATH11K Wi-Fi 6E Firmware & Board Data Files

#### Architectural Profile:
* **Radio 1 & 2 (IPQ6018 Internal QCN5022 / QCN5052):**
  * Hexagon DSP firmware (`q6_fw.mdt` + `q6_fw.b00`..`b08`): Runs Wi-Fi MAC scheduling and rate control.
  * Power Microcontroller (`m3_fw.mdt` + `m3_fw.b00`..`b02`): ARM Cortex-M3.
  * BDF Calibration (`bdwlan.b11` / `board-2.bin`): Per-band RF calibration tables.
* **Radio 3 (PCIe QCN9074 Wi-Fi 6E):**
  * Monolithic Hexagon firmware (`amss.bin`, 4.2 MB): Full 802.11ax MAC layer.
  * PCIe Power Microcontroller (`m3.bin`, 340 KB): ARM Cortex-M3.
  * BDF Calibration (`bdwlan.ba4` / `board-2.bin`): 6 GHz UNII-5..8 frequency power tables.

---

### 2.4 Qualcomm Bootloader Chain (`0_SBL1.bin`, `0_APPSBL_uboot.bin`, `0_QSEE_trustzone.bin`)

#### Secure Boot Chain Architecture:
```text
[ ROM (PBL) in Silicon ]
          |
          v (Authenticates SBL1 via OEM Root Key Hash in eFuses)
[ MTD0: 0_SBL1 (Secondary Bootloader) ]
          |
          +---> [ MTD4: 0_RPM ] (Powers on memory & clock rails)
          |
          +---> [ MTD2: 0_QSEE ] (TrustZone EL3 Secure Monitor)
          |
          v
[ MTD7: 0_APPSBL (U-Boot APPS Bootloader) ]
          |
          v (Parses u_env / boot_part)
[ MTD13: Slot 1 OpenWrt FIT Image ] OR [ MTD15: Slot 2 OEM Fallback Image ]
```

---

## 3. Static Binary Analysis Tooling Guide

### 3.1 Recommended Tools Checklist:

| Tool | Purpose | Supported Architectures in this Target |
| :--- | :--- | :--- |
| **Ghidra (v11.x+)** | Full disassembly, decompilation, and function graphing | ARM64, ARM Cortex-M3, ARCv2 (via plugin), Ubicom32 (via plugin) |
| **readelf / objdump** | ELF section, symbol, and header inspection | ELF32 / ELF64 (Ubi32, ARM64) |
| **binwalk** | Entropy scanning, embedded signature extraction | All binary types |
| **hexdump / Kaitai Struct** | Binary structure modeling and header parsing | Custom CLD, BDF, and MBN formats |
| **strings (-a -n 6 -t x)** | ASCII/Unicode string extraction with file offsets | Identifying build dates, version tags, and debug logs |

---

## 4. Security & Educational Research Notice

* Static analysis procedures outlined in this document are strictly intended for:
  1. Hardware interoperability and device driver development in open-source operating systems.
  2. Educational analysis of heterogeneous embedded multiprocessor systems.
  3. Firmware integrity verification and defensive security posture assessment.
* Do not redistribute proprietary binary blobs without appropriate licensing or vendor permissions.
