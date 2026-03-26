<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-26 | Updated: 2026-03-26 -->

# scripts

## Purpose
Bash scripts for installing and testing the MT7927 WiFi/BT driver on CachyOS/Arch Linux. These are the primary user-facing executables.

## Key Files

| File | Description |
|------|-------------|
| `install.sh` | Main installer — firmware, packages, DKMS build, boot config, verification. Run after CachyOS install. |
| `test-live.sh` | Non-destructive test script for CachyOS live USB environment. Verifies hardware, firmware, driver build. |

## For AI Agents

### Working In This Directory
- Scripts run as **root** (`sudo bash`)
- All user-facing output is in **Indonesian**
- Use `set -euo pipefail` for strict error handling
- Use helper functions: `log()`, `ok()`, `warn()`, `err()` for colored output
- Use `count=$((count + 1))` not `((count++))` (fails with `set -e` when count=0)
- Use `pushd`/`popd` not `cd` to avoid polluting global working directory
- Redirect `make` stderr to `install.log` not `/dev/null` (preserve debug info)
- The BT rescan systemd service must only target MediaTek USB vendor IDs (13d3/0489/0e8d), never reset all USB hubs

### Testing Requirements
- `bash -n install.sh` must pass (syntax check)
- `bash -n test-live.sh` must pass (syntax check)
- Both scripts are idempotent — safe to run multiple times
- `test-live.sh` makes no permanent changes (live USB is tmpfs)

### Kernel Detection Order
The installer checks kernels in this order:
1. `linux-cachyos` (default)
2. `linux-cachyos-lts` (LTS — default for March 2026 ISO)
3. `linux-cachyos-bore` (BORE scheduler)
4. `linux-cachyos-deckify` (Steam Deck)
5. `linux` (vanilla Arch)

### Script Flow: install.sh
```
check_root -> check_hardware -> check_kernel -> install_firmware
-> install_deps (offline packages) -> install_dkms (build driver)
-> configure_boot (modules, systemd, initramfs) -> load_modules
-> verify -> prompt reboot
```

### Script Flow: test-live.sh
```
hardware detection -> firmware copy (tmpfs) -> dependency install
-> DKMS build attempt -> module load -> WiFi scan -> BT check
-> summary with PASS/FAIL/WARN counts
```

## Dependencies

### Internal
- Reads firmware from `../firmware/` and `../firmware-extracted/`
- Reads packages from `../packages/`
- Reads DKMS source from `../dkms-source/`
- Writes log to `../install.log` or `../test-live.log`

### External (on target system)
- `pacman` — Arch package manager
- `dkms` — Dynamic Kernel Module System
- `mkinitcpio` — initramfs generator
- `systemctl` — systemd service management
- `lspci`, `ip`, `modprobe`, `nmcli`, `bluetoothctl` — system utilities

<!-- MANUAL: -->
