# MT7927 Linux WiFi Fix

100% Offline toolkit — MediaTek Wi-Fi 7 MT7927 on CachyOS / Arch Linux.

> MT7927 belum didukung kernel Linux. Toolkit ini fix WiFi + Bluetooth tanpa perlu internet di Linux.

## Supported Hardware

| Chip | PCI ID | Info |
|------|--------|------|
| MT7927 | `14c3:6639` / `14c3:7927` | WiFi 7 (2.4/5/6 GHz) |
| MT6639 | USB `13d3:3588` | Bluetooth 5.4 |

## Cara Pakai

### 1. Di Windows — Jalankan `download.ps1`

```powershell
# Klik kanan download.ps1 > "Run with PowerShell"
# Atau:
powershell -ExecutionPolicy Bypass -File download.ps1
```

Script ini otomatis download:
- WiFi & Bluetooth firmware
- Paket CachyOS (dkms, kernel headers)
- Driver source + patches

### 2. Copy ke USB Drive

Copy folder `mt7927-offline-fix` ke USB.

### 3. Di CachyOS — Jalankan `install.sh`

```bash
sudo mount /dev/sda1 /mnt        # cek device: lsblk
cd /mnt/mt7927-offline-fix
sudo bash scripts/install.sh
sudo reboot
```

Selesai. WiFi + Bluetooth jalan setelah reboot.

### Test di Live USB (opsional)

```bash
sudo mount /dev/sda1 /mnt
cd /mnt/mt7927-offline-fix
sudo bash scripts/test-live.sh
```

## Troubleshooting

| Masalah | Solusi |
|---------|--------|
| WiFi tidak muncul | `dmesg \| grep mt79` — cek error, coba `sudo modprobe mt7925e` |
| Bluetooth tidak jalan | Shutdown, **cabut kabel power 10 detik**, nyalakan lagi |
| Headers tidak cocok | Jalankan ulang `download.ps1` di Windows untuk update paket |
| DKMS error setelah update kernel | `sudo dkms autoinstall` |

## Credits

- [jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms) — DKMS patches
- [Javier Tia](https://jetm.github.io/blog/posts/mt7927-wifi-the-missing-piece/) — MT7927 research
- [openwrt/mt76#927](https://github.com/openwrt/mt76/issues/927) — Upstream tracking

## License

MIT
