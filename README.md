# MT7927 Linux WiFi Fix

100% Offline toolkit — MediaTek Wi-Fi 7 MT7927 on CachyOS / Arch Linux.

> MT7927 has no mainline Linux kernel support yet. This toolkit fixes WiFi + Bluetooth with no internet needed on the Linux side.

## Supported Hardware

| Chip | PCI ID | Info |
|------|--------|------|
| MT7927 | `14c3:6639` / `14c3:7927` | WiFi 7 (2.4/5/6 GHz) |
| MT6639 | USB `13d3:3588` | Bluetooth 5.4 |

## Usage

### 1. On Windows — Run `download.ps1`

```powershell
# Right-click download.ps1 > "Run with PowerShell"
# Or:
powershell -ExecutionPolicy Bypass -File download.ps1
```

This script automatically downloads:
- WiFi & Bluetooth firmware
- CachyOS packages (dkms, kernel headers)
- Driver source + patches

### 2. Copy to USB Drive

Copy the `mt7927-offline-fix` folder to a USB drive.

### 3. On CachyOS — Run `install.sh`

```bash
sudo mount /dev/sda1 /mnt        # check your device: lsblk
cd /mnt/mt7927-offline-fix
sudo bash scripts/install.sh
sudo reboot
```

Done. WiFi + Bluetooth should work after reboot.

### Test on Live USB (optional)

```bash
sudo mount /dev/sda1 /mnt
cd /mnt/mt7927-offline-fix
sudo bash scripts/test-live.sh
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| WiFi not showing | `dmesg \| grep mt79` — check errors, try `sudo modprobe mt7925e` |
| Headers mismatch | Re-run `download.ps1` on Windows to update packages |
| DKMS error after kernel update | `sudo dkms autoinstall` |

## Credits

- [jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms) — DKMS patches
- [Javier Tia](https://jetm.github.io/blog/posts/mt7927-wifi-the-missing-piece/) — MT7927 research
- [openwrt/mt76#927](https://github.com/openwrt/mt76/issues/927) — Upstream tracking

## License

MIT
