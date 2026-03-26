# MT7927 Linux WiFi Fix

**100% Offline toolkit to enable MediaTek Wi-Fi 7 MT7927 (Filogic 380) on CachyOS / Arch Linux.**

[Indonesian / Bahasa Indonesia](README.id.md)

---

> **The Problem:** The MediaTek MT7927 is a Wi-Fi 7 + Bluetooth 5.4 combo chip found in many modern motherboards (ASUS, MSI, Lenovo, etc.). As of early 2026, it has **no mainline Linux kernel support** — WiFi doesn't work out of the box on any Linux distribution.
>
> **This Solution:** A complete offline toolkit you prepare on Windows, copy to a USB drive, and run on CachyOS/Arch Linux. No internet connection needed on the Linux side.

## Supported Hardware

| Chip | PCI ID | Component |
|------|--------|-----------|
| MT7927 | `14c3:6639` | WiFi 7 (2.4/5/6 GHz, 320MHz, EHT) |
| MT7927 | `14c3:7927` | WiFi 7 (alternate ID) |
| MT6639 | USB `13d3:3588` | Bluetooth 5.4 |

**Common motherboards:** ASUS ROG X870E/X870, MSI MEG/MPG X870 series, Lenovo IdeaPad/Yoga with MT7927

## Quick Start

### Step 1: Prepare on Windows

```powershell
# Clone this repository
git clone https://github.com/YOUR_USERNAME/mt7927-offline-fix.git
cd mt7927-offline-fix

# Download firmware (extracts from your Windows driver automatically)
powershell -ExecutionPolicy Bypass -File download.ps1

# Download CachyOS packages for offline install
pip install pyzstd
python download-packages.py
```

### Step 2: Copy to USB Drive

Copy the entire `mt7927-offline-fix` folder to a USB drive.

### Step 3: Test on CachyOS Live USB (Optional but Recommended)

Boot CachyOS from USB, then:

```bash
# Mount your USB drive with the toolkit
sudo mkdir -p /mnt/usb
sudo mount /dev/sda1 /mnt/usb   # check your device: lsblk

# Run the live test
cd /mnt/usb/mt7927-offline-fix
sudo bash scripts/test-live.sh
```

### Step 4: Install on CachyOS

After installing CachyOS, boot into it and:

```bash
# Mount your USB drive
sudo mkdir -p /mnt/usb
sudo mount /dev/sda1 /mnt/usb   # check your device: lsblk

# Run the installer
cd /mnt/usb/mt7927-offline-fix
sudo bash scripts/install.sh

# Reboot
sudo reboot
```

That's it! WiFi and Bluetooth should work after reboot.

## What the Installer Does

The `install.sh` script performs these steps automatically:

1. **Detects** your MT7927 hardware via `lspci`
2. **Installs firmware** to `/lib/firmware/mediatek/` (WiFi + Bluetooth)
3. **Installs packages** offline: `dkms`, `linux-cachyos-headers`, `pahole`
4. **Builds the driver** via DKMS (patches `mt7925e` + `btusb` for MT7927 support)
5. **Configures boot**: auto-loads modules, blacklists conflicts, sets up BT service
6. **Rebuilds initramfs** to include firmware at boot
7. **Verifies** everything is working

## What's Included

```
mt7927-offline-fix/
  download.ps1            Windows script: downloads firmware
  download-packages.py    Windows script: downloads CachyOS packages
  scripts/
    install.sh            Main installer (run on CachyOS after install)
    test-live.sh          Test script (run on CachyOS live USB)
  firmware/
    mt7925/               WiFi firmware files
    mt6639/               Bluetooth firmware files
  firmware-extracted/     Firmware extracted from Windows driver
  packages/               Offline .pkg.tar.zst packages
  dkms-source/            DKMS driver source + 15 kernel patches
```

## Offline Package Coverage

| Package | Purpose | Kernel |
|---------|---------|--------|
| `dkms` | Dynamic Kernel Module System | all |
| `pahole` | BTF generation for modules | all |
| `linux-cachyos-lts-headers` | Kernel headers | 6.18 LTS |
| `linux-cachyos-headers` | Kernel headers | 6.19 |
| `linux-cachyos-bore-headers` | Kernel headers | 6.19-bore |

The installer automatically detects your kernel and installs the matching headers.

## Troubleshooting

### WiFi not showing after reboot
```bash
# Check kernel log
dmesg | grep -i "mt79\|mt66\|mediatek"

# Check if module is loaded
lsmod | grep mt7925

# Try manual load
sudo modprobe mt7925e

# Check DKMS status
dkms status
```

### Bluetooth not working
The MT6639 Bluetooth requires a full power cycle (not just reboot):

1. Shut down the computer
2. **Unplug the power cable** (or remove battery on laptop)
3. Wait **10 seconds**
4. Plug back in and power on

### Kernel headers mismatch
If the installer reports headers don't match your kernel:

```bash
# Check your kernel version
uname -r

# Check available headers in packages/
ls packages/linux-cachyos*-headers-*

# If versions don't match, update packages on Windows:
python download-packages.py
```

### DKMS rebuild after kernel update
DKMS automatically rebuilds modules on kernel updates. Verify with:

```bash
dkms status
```

If it didn't auto-rebuild:
```bash
sudo dkms autoinstall
```

## Requirements

### On Windows (for preparation)
- Python 3.8+ (for `download-packages.py`)
- `pyzstd` Python package: `pip install pyzstd`
- Internet connection
- MediaTek MT7927 Windows driver installed (for firmware extraction)

### On CachyOS/Arch Linux
- CachyOS March 2026+ ISO or equivalent Arch with kernel 6.17+
- USB drive with the toolkit
- No internet required (100% offline)

## How It Works (Technical Details)

The MT7927 is architecturally identical to the MT7925 (supported since kernel 6.7) except:
- It supports **320MHz channel width** (Wi-Fi 7 EHT)
- It needs a **different DMA firmware transfer** initialization path
- The **PCI device ID** (`0x6639`) is not in the kernel's device table

This toolkit:
1. Adds the MT7927 PCI ID to the `mt7925e` driver via DKMS
2. Patches in 320MHz/EHT support (13 WiFi patches)
3. Fixes Bluetooth `btusb` driver for MT6639 variant detection
4. Provides the correct firmware files from the Windows driver

## Credits & References

- [jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms) - DKMS package and patches
- [MT7927 WiFi on Linux](https://jetm.github.io/blog/posts/mt7927-wifi-the-missing-piece/) - Javier Tia's research
- [openwrt/mt76#927](https://github.com/openwrt/mt76/issues/927) - OpenWrt MT7927 tracking issue
- [CachyOS/linux-cachyos#688](https://github.com/CachyOS/linux-cachyos/issues/688) - CachyOS issue
- Community patches tested on 10+ hardware platforms

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Tested on a different motherboard? Please open an issue or PR to add it to the supported hardware list.

## License

MIT License - see [LICENSE](LICENSE)

> **Note:** Firmware files are extracted from vendor drivers and are subject to MediaTek's licensing terms. They are not included in this repository. The `download.ps1` script extracts them from your locally-installed Windows driver.
