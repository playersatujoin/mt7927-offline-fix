<!-- Generated: 2026-03-26 | Updated: 2026-03-26 -->

# mt7927-offline-fix

## Purpose
100% offline toolkit to enable MediaTek Wi-Fi 7 MT7927 (Filogic 380) WiFi + Bluetooth on CachyOS/Arch Linux. Prepared on Windows, transferred via USB, executed on Linux with no internet required.

## Key Files

| File | Description |
|------|-------------|
| `download.ps1` | PowerShell script to download WiFi/BT firmware from Windows DriverStore |
| `download-packages.py` | Python script to download CachyOS/Arch .pkg.tar.zst packages for offline install |
| `README.md` | English documentation and user guide |
| `README.id.md` | Indonesian documentation and user guide |
| `CONTRIBUTING.md` | Contribution guidelines |
| `LICENSE` | MIT License |
| `.gitignore` | Excludes firmware binaries, packages, and build artifacts |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `scripts/` | Bash installer and live-test scripts (see `scripts/AGENTS.md`) |
| `firmware/` | Firmware destination directories - files downloaded by `download.ps1` |
| `firmware-extracted/` | Raw firmware extracted from Windows `mtkwlan.dat` |
| `packages/` | Offline CachyOS .pkg.tar.zst packages downloaded by `download-packages.py` |
| `dkms-source/` | Git clone of jetm/mediatek-mt7927-dkms with 15 kernel patches |

## For AI Agents

### Working In This Directory
- This is a **user-facing toolkit** — scripts must be beginner-friendly with clear output
- All user messages in scripts should be in **Indonesian** (target audience)
- README exists in **two languages**: English (README.md) and Indonesian (README.id.md)
- Firmware binaries and .pkg.tar.zst files are NOT committed to git (in .gitignore)
- The `dkms-source/` directory is a git submodule/clone of an external repo

### Testing Requirements
- `bash -n scripts/install.sh` — must pass syntax check
- `bash -n scripts/test-live.sh` — must pass syntax check
- `python -m py_compile download-packages.py` — must compile
- PowerShell scripts tested with `powershell -Command "& { }"` syntax check
- Actual hardware testing requires a machine with MT7927 chip

### Common Patterns
- Scripts use colored output: `log()`, `ok()`, `warn()`, `err()` helper functions
- `set -euo pipefail` for strict error handling
- Firmware paths follow kernel convention: `/lib/firmware/mediatek/{chip}/`
- DKMS handles module rebuild on kernel updates automatically

### Critical Constraints
- **Offline-first**: everything must work without internet on the Linux side
- **Kernel version sensitivity**: headers must match running kernel exactly
- **BT requires WiFi init first**: MT6639 Bluetooth USB device only appears after MT7927 WiFi driver initializes CONNINFRA
- **Power cycle for BT**: regular reboot insufficient, must cut power for MT6639 firmware reset

## Dependencies

### Internal
- `scripts/install.sh` depends on `firmware/`, `firmware-extracted/`, `packages/`, `dkms-source/`
- `scripts/test-live.sh` depends on same directories but is non-destructive
- `download.ps1` populates `firmware/` and `firmware-extracted/`
- `download-packages.py` populates `packages/`

### External
- [jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms) — DKMS driver source
- CachyOS/Arch package mirrors — for offline package downloads
- kernel.org firmware repository — for WiFi firmware
- Windows MediaTek driver (mtkwlan.dat) — for BT firmware extraction

<!-- MANUAL: -->
