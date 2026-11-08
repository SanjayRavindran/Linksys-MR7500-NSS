# Linksys MR7500 Dual-Boot A/B Architecture & Recovery Guide

The Linksys MR7500 (Hydra Pro 6E) features hardware-assisted dual-boot A/B firmware slots in its 512 MiB NAND flash. This ensures zero risk of bricking when flashing custom firmware, as the alternate slot remains completely untouched.

---

## 1. NAND Flash Partition Layout

| MTD Partition | NAND Offset | Size | Name | Purpose |
|---|---|---|---|---|
| `mtd10` | `0x00a80000` | 512 KiB | `u_env` | Primary U-Boot environment (`boot_part`, MAC, etc.) |
| `mtd11` | `0x00b00000` | 256 KiB | `s_env` | Linksys boot state and failure counter |
| `mtd13` | `0x00b80000` | 8 MiB | `kernel` | **Slot 1 Kernel (FIT image)** |
| `mtd14` | `0x01380000` | 74 MiB | `rootfs` | **Slot 1 Rootfs (SquashFS + UBIFS)** |
| `mtd15` | `0x05d80000` | 8 MiB | `alt_kernel` | **Slot 2 Kernel (FIT image)** |
| `mtd16` | `0x06580000` | 74 MiB | `alt_rootfs` | **Slot 2 Rootfs (SquashFS + UBIFS)** |

---

## 2. Recommended Partition Allocation Strategy

To ensure safe testing and seamless recovery:
* **Slot 1 (`kernel` / `rootfs`):** Flashed with custom **OpenWrt + Qualcomm NSS** firmware.
* **Slot 2 (`alt_kernel` / `alt_rootfs`):** Kept with the untouched factory **Linksys Stock Firmware** (e.g. `1.1.12.216943`).

---

## 3. How to Switch Boot Slots

### Method A: From OpenWrt Terminal (SSH or Serial)
To switch back to Stock Firmware in Slot 2:
```sh
fw_setenv boot_part 2
reboot
```
To switch back to OpenWrt in Slot 1:
```sh
fw_setenv boot_part 1
reboot
```

### Method B: From U-Boot Serial Console (UART 115200 8N1)
Interrupt autoboot by pressing Space or Enter when prompted:
```text
Hit any key to stop autoboot:  2
IPQ6018# setenv boot_part 2
IPQ6018# saveenv
IPQ6018# reset
```

### Method C: Hardware Power-Cycle Recovery (Linksys 3-Reboot Rule)
If a newly flashed image fails to boot or kernel-panics, the Linksys bootloader automatically increments a failure counter in `s_env`. After 3 consecutive failed boots, U-Boot automatically switches `boot_part` to the alternate slot.

---

## 4. Sysupgrade Best Practice

When booted into OpenWrt on Slot 1 (`boot_part=1`), running a standard `sysupgrade` will default to upgrading the *alternate* slot.
To re-flash or update the **current slot** without touching your stock fallback slot, use the `-s` flag:

```sh
sysupgrade -s -n /tmp/openwrt-squashfs-sysupgrade.bin
```
* `-s`: Upgrade current active partition (`use_curr_part: true`).
* `-n`: Do not save existing configuration (clean first boot).
