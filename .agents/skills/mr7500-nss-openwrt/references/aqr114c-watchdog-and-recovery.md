# AQR114C Firmware Watchdog, LED Blink Stretch & Live Recovery Reference

This reference preserves complete hardware diagnostics, C45 MDIO register signatures, live no-reboot recovery instructions, and Patch `0007` (`0986`) concurrency architecture for the **Marvell/Aquantia AQR114C-B0 5GbE PHY** (`MDIO 8`, `wan` / `dp5-syn`).

---

## 1. Root Cause & Register Signatures

The AQR114C runs volatile firmware (`v5.6.5 Cybertan Divo`, `/lib/firmware/marvell/AQR114C.cld`, SHA-256 `32bc96c20351d7981d2d905b843899834e6dd620844218d6f3e1ecb9691745f3`) loaded over MDIO by Linux (because `mtd9` OEM `v5.4.B` is intentionally bypassed). Hotplug transients or internal PHY resets can drop the ARC processor back to boot-ROM (`0x1e/0x0020 == 0x0000`), leaving `wan` permanently down, and firmware resets also wipe LED provisioning registers (`0x1e/0xc430..c43a`). Additionally, Linux `6.12.92` defined `VEND1_GLOBAL_LED_PROV_ACT_STRETCH` inverted as `GENMASK(0, 1)` and left activity stretch at `0 ms` (`0xc06c`).

| MMD / Reg | Name | Dead Boot-ROM | Healthy Linked (`2500M`) | Healthy Unplugged (`carrier=0`) |
|---|---|---|---|---|
| `0x1e/0x0000` | `VEND1_GLOBAL_SC` | `0x8000` | `0x0000` | `0x0000` |
| `0x1e/0x0020` | `VEND1_GLOBAL_FW_ID` | `0x0000` | `0x0506` (`v5.6.5`) | `0x0506` (`v5.6.5`) |
| `0x1e/0xc001` | `VEND1_GLOBAL_CONTROL2` | `0x0020` | `0x0062` | `0x0062` |
| `0x1e/0xc886` | `VEND1_GLOBAL_RSVD_STAT2` (HB) | `0x0000` (stuck) | Ticks **1 Hz** | Ticks **1 Hz** |
| `0x1e/0xc430` | `LED0` (Amber TX/RX Activity) | `0x0003` | `0xc06f` (`[1:0]=3` = 100 ms) | `0xc06f` |
| `0x1e/0xc431` | `LED1` (Green Link) | `0x0003` | `0xc060` | `0xc060` |
| `0x1e/0xc438..c43a` | `VEND1_GLOBAL_LED_DRIVE` | `0x0001` | Restored polarity | Restored polarity |
| `4/0xc441` | PHYXS USXGMII C37 AN | `0x0000` | `0x0008` | `0x0008` |
| `4/0xe812` | `MDIO_PHYXS_VEND_IF_STATUS` | `0xa040` / `0x0000` | `0xb419` | `0xb318` |
| `1/0`, `3/0`, `4/0`, `7/0` | Standard PMD/PCS/AN Ctrl | `0xa040`, `0xa040`, `0xa040`, `0xb000` | Normal active | Normal active |

* **Correct `phytool` C45 syntax:** `phytool read wan/8:0x1e/0x0020` (`wan/4/...` reads QCA8075 C22 PHY addr 4, not AQR114C PHYXS!).
* **Thermal Register Note:** `0x1e/0xc830` (`VEND1_GENERAL_STAT1`) can assert `BIT(14)` (`0x5000`) around `~64.5â€“70.2Â°C` while `0x1e/0xc420 == 0` (shutdown disabled). Do **not** gate watchdog recovery on `0x1e/0xc830`.
* **OEM Reference:** Stock firmware shipped `/etc/init.d/service_wan/wan_AQR_monitor.sh` polling `0x1e/0xc886` every 3s, triggering `0x1e/0x2680=0x1`, streaming `AQR114C.cld`, restarting AN, and writing `0xc430=0xc0ef` / `0xc431=0xc0e0`.

---

## 2. Live No-Reboot Recovery Over MDIO (`SIOCGMIIREG`/`SIOCSMIIREG`)

If a running unit loses AQR114C firmware without rebooting:
1. Ensure `wan` stays admin UP (`nss_dp_netdev_ops.ndo_eth_ioctl` is `phy_do_ioctl_running`, which returns `-ENODEV` if `wan` is down).
2. Trigger NVR reset `0x1e/0x2680 = 0x0001` (`msleep(100)`), stall ARC `0x1e/0xc001 = 0x0041`.
3. Stream `DRAM` (`0x3FFE0000`) and `IRAM` (`0x40000000`) from `/lib/firmware/marvell/AQR114C.cld` through mailbox `0x1e/0x0200..0x0205`, checking CRC (`0x1e/0x0201`).
4. Release ARC (`0x1e/0xc001 = 0x00c0`, sleep 1 ms, `0x0040`), clear `0x1e/0x0000` soft-reset/low-power bits, wait `0x1e/0x0020 != 0`.
5. Restore USXGMII C37 AN (`4/0xc441 |= 0x0008`), LED provisioning (`0x1e/0xc430 = 0xc0ef`, `0x1e/0xc431 = 0xc0e0`), and restart AN (`7/0x0000`).

---

## 3. Patch `0007` (`0986`) Hardened Concurrency & Overload Design

Kernel patch `0986-net-phy-aquantia-fw-watchdog-and-led-stretch.patch` (packaged in `patches/0007-qualcommax-mr7500-aqr114c-fw-watchdog-and-led-stretch.patch`) implements recovery safely:

* **Strict Lock Hierarchy:** `rtnl_lock` -> `led_netdev_data::lock` -> `phydev->lock` -> `bus->mdio_lock`.
  * `aqr107_fw_reload_work()` runs on `system_unbound_wq` in 3 phases:
    1. **Phase 1 (`phydev->lock`):** Verifies `!fw_reload_abort && attached_dev && phy_is_started(phydev) && !suspended && !fw_reload_disabled`; re-confirms `FW_ID == 0` or frozen `30:0xc886`; drops `phydev->lock`.
    2. **Phase 2 (UNLOCKED, ~29s):** Runs `aqr_firmware_reload()`, `aqr_wait_reset_complete()`, and `aqr_wait_fw_provisioning()` holding neither `rtnl_lock` nor `phydev->lock`.
    3. **Phase 3 (`phydev->lock`):** Restores `config_init()` (including `aqr_phy_led_restore()`), `aqr_config_intr()`, `__aqr_config_aneg()`, and restarts AN; clears `fw_reloading`, unlocks, and calls `phy_trigger_machine(phydev)`.
* **Concurrent Callback Fencing:** `atomic_t fw_reloading` short-circuits `aqr107_read_status`, `aqr_config_aneg`, `aqr_config_aneg_set_prot`, `aqr_handle_interrupt`, `aqr107_get_stats`, `aqr107_get/set_tunable`, `aqr_hwmon_read/write`, and `aqr_phy_led_*` (caching any new LED rules for Phase 3).
* **Safe Teardown:** `aqr107_suspend()` and `aqr107_remove()` (registered on all 13 `aqr107_probe` `phy_driver` entries) run outside `phydev->lock`, set `fw_reload_abort = 1`, and wait on `cancel_work_sync(&priv->fw_reload_work)`.
* **Scheduler & Hardware Overload Guards:**
  * `aqr_fw_load_memory()` checks all `phy_write_mmd`/`phy_read_mmd` errors and runs `fw_reload_abort` check + `cond_resched()` every 256 words (`!(pos & 0x3ff)`) for `CONFIG_PREEMPT_NONE=y`.
  * `aqr107_check_fw_health()` never returns `< 0` into `aqr107_read_status()` (avoids phylib `phy_error_precise()` -> `PHY_HALTED` permanent kill).
  * Exponential backoff (`30s -> 60s -> 120s -> 240s -> 300s`) and consecutive-failure cap (`AQR_FW_RELOAD_MAX_FAILS = 5`), resetting only after `>= 60s` of healthy ticking firmware or `aqr107_resume()`.

---

## 4. UART & Dual-Slot Flash Procedures

* **Dual-Slot Ping-Pong `sysupgrade` (No Dropbear SSH keys needed):**
  1. Serve the profile's `switch-ap-mode/` build dir over HTTP from the build host (e.g., `192.168.1.24:18080`).
  2. Over `/dev/ttyUSB1`, download to `/tmp/fw.bin` with `wget`, verify exact `sha256sum /tmp/fw.bin`, run `sysupgrade -T /tmp/fw.bin`, then `sysupgrade /tmp/fw.bin` (omit `-n` to preserve Switch+AP config and `/etc/sysupgrade.conf`).
  3. **Important UART Rule:** Never send ``/`
` while U-Boot is counting down `Hit any key to stop autoboot`; wait passively for `Linux version 6.12.92` + `procd: - init complete -`, settle ~25s, then send `Ctrl-C` and pace commands in `<= 48` byte chunks to avoid BLSP UART RX FIFO drops.
  4. Flash alternating slot twice (`boot_part=2 -> 1 -> 2`) so both **Slot 1** and **Slot 2** carry identical verified firmware.
* **GitHub Push Workflow (`.24` Build Host -> `.15` GitHub Host):**
  * Create a git bundle (`git bundle create /tmp/update.bundle <base>..HEAD`) on `.24`, copy to `.15` (which holds `gh` HTTPS PAT auth), `git pull --ff-only /tmp/update.bundle master`, run `bash scripts/ci_test.sh`, and `git push origin master` (`gh auth setup-git`).
