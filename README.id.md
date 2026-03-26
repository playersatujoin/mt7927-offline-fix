# MT7927 Linux WiFi Fix

**Toolkit 100% offline untuk mengaktifkan MediaTek Wi-Fi 7 MT7927 (Filogic 380) di CachyOS / Arch Linux.**

[English Version](README.md)

---

> **Masalahnya:** MediaTek MT7927 adalah chip Wi-Fi 7 + Bluetooth 5.4 yang ada di banyak motherboard modern (ASUS, MSI, Lenovo, dll). Per awal 2026, chip ini **belum didukung kernel Linux** — WiFi tidak akan jalan di distro Linux manapun.
>
> **Solusinya:** Toolkit offline lengkap yang kamu siapkan di Windows, copy ke USB drive, lalu jalankan di CachyOS/Arch Linux. Tidak perlu koneksi internet di sisi Linux.

## Hardware yang Didukung

| Chip | PCI ID | Komponen |
|------|--------|----------|
| MT7927 | `14c3:6639` | WiFi 7 (2.4/5/6 GHz, 320MHz, EHT) |
| MT7927 | `14c3:7927` | WiFi 7 (ID alternatif) |
| MT6639 | USB `13d3:3588` | Bluetooth 5.4 |

**Motherboard umum:** ASUS ROG X870E/X870, MSI MEG/MPG X870 series, Lenovo IdeaPad/Yoga dengan MT7927

## Cara Pakai (Cepat)

### Langkah 1: Siapkan di Windows

```powershell
# Clone repository ini
git clone https://github.com/YOUR_USERNAME/mt7927-offline-fix.git
cd mt7927-offline-fix

# Download firmware (otomatis ekstrak dari driver Windows kamu)
powershell -ExecutionPolicy Bypass -File download.ps1

# Download paket CachyOS untuk install offline
pip install pyzstd
python download-packages.py
```

### Langkah 2: Copy ke USB Drive

Copy seluruh folder `mt7927-offline-fix` ke USB drive.

### Langkah 3: Test di CachyOS Live USB (Opsional, Disarankan)

Boot CachyOS dari USB, lalu:

```bash
# Mount USB drive yang berisi toolkit
sudo mkdir -p /mnt/usb
sudo mount /dev/sda1 /mnt/usb   # cek device kamu: lsblk

# Jalankan test
cd /mnt/usb/mt7927-offline-fix
sudo bash scripts/test-live.sh
```

### Langkah 4: Install di CachyOS

Setelah install CachyOS, boot ke dalamnya lalu:

```bash
# Mount USB drive kamu
sudo mkdir -p /mnt/usb
sudo mount /dev/sda1 /mnt/usb   # cek device kamu: lsblk

# Jalankan installer
cd /mnt/usb/mt7927-offline-fix
sudo bash scripts/install.sh

# Reboot
sudo reboot
```

Selesai! WiFi dan Bluetooth harusnya sudah jalan setelah reboot.

## Apa yang Dilakukan Installer

Script `install.sh` melakukan langkah-langkah ini secara otomatis:

1. **Mendeteksi** hardware MT7927 kamu via `lspci`
2. **Menginstall firmware** ke `/lib/firmware/mediatek/` (WiFi + Bluetooth)
3. **Menginstall paket** offline: `dkms`, `linux-cachyos-headers`, `pahole`
4. **Mem-build driver** via DKMS (patch `mt7925e` + `btusb` untuk support MT7927)
5. **Mengkonfigurasi boot**: auto-load module, blacklist konflik, setup BT service
6. **Rebuild initramfs** agar firmware masuk saat boot
7. **Memverifikasi** semuanya berjalan

## Isi Toolkit

```
mt7927-offline-fix/
  download.ps1            Script Windows: download firmware
  download-packages.py    Script Windows: download paket CachyOS
  scripts/
    install.sh            Installer utama (jalankan di CachyOS setelah install)
    test-live.sh          Script test (jalankan di CachyOS live USB)
  firmware/
    mt7925/               File firmware WiFi
    mt6639/               File firmware Bluetooth
  firmware-extracted/     Firmware yang diekstrak dari driver Windows
  packages/               Paket offline .pkg.tar.zst
  dkms-source/            Source driver DKMS + 15 kernel patch
```

## Paket Offline yang Tersedia

| Paket | Fungsi | Kernel |
|-------|--------|--------|
| `dkms` | Dynamic Kernel Module System | semua |
| `pahole` | Generasi BTF untuk modul | semua |
| `linux-cachyos-lts-headers` | Kernel headers | 6.18 LTS |
| `linux-cachyos-headers` | Kernel headers | 6.19 |
| `linux-cachyos-bore-headers` | Kernel headers | 6.19-bore |

Installer otomatis mendeteksi kernel kamu dan menginstall headers yang cocok.

## Troubleshooting

### WiFi tidak muncul setelah reboot
```bash
# Cek kernel log
dmesg | grep -i "mt79\|mt66\|mediatek"

# Cek apakah module sudah di-load
lsmod | grep mt7925

# Coba load manual
sudo modprobe mt7925e

# Cek status DKMS
dkms status
```

### Bluetooth tidak jalan
MT6639 Bluetooth butuh power cycle penuh (bukan sekedar reboot):

1. Matikan komputer
2. **Cabut kabel power** (atau lepas baterai di laptop)
3. Tunggu **10 detik**
4. Colok kembali dan nyalakan

### Kernel headers tidak cocok
Jika installer bilang headers tidak cocok dengan kernel kamu:

```bash
# Cek versi kernel kamu
uname -r

# Cek headers yang tersedia
ls packages/linux-cachyos*-headers-*

# Jika tidak cocok, update paket di Windows:
python download-packages.py
```

### DKMS rebuild setelah update kernel
DKMS otomatis rebuild module saat kernel update. Verifikasi dengan:

```bash
dkms status
```

Jika tidak auto-rebuild:
```bash
sudo dkms autoinstall
```

## Persyaratan

### Di Windows (untuk persiapan)
- Python 3.8+ (untuk `download-packages.py`)
- Package Python `pyzstd`: `pip install pyzstd`
- Koneksi internet
- Driver Windows MediaTek MT7927 sudah terinstall (untuk ekstraksi firmware)

### Di CachyOS/Arch Linux
- CachyOS ISO Maret 2026+ atau Arch setara dengan kernel 6.17+
- USB drive berisi toolkit ini
- Tidak perlu internet (100% offline)

## Cara Kerjanya (Detail Teknis)

MT7927 secara arsitektur identik dengan MT7925 (didukung sejak kernel 6.7) kecuali:
- Mendukung **lebar channel 320MHz** (Wi-Fi 7 EHT)
- Butuh **jalur inisialisasi DMA firmware transfer** yang berbeda
- **PCI device ID** (`0x6639`) belum ada di tabel device kernel

Toolkit ini:
1. Menambahkan PCI ID MT7927 ke driver `mt7925e` via DKMS
2. Menambahkan dukungan 320MHz/EHT (13 patch WiFi)
3. Memperbaiki driver Bluetooth `btusb` untuk deteksi varian MT6639
4. Menyediakan file firmware yang benar dari driver Windows

## Kredit & Referensi

- [jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms) - Paket DKMS dan patch
- [MT7927 WiFi on Linux](https://jetm.github.io/blog/posts/mt7927-wifi-the-missing-piece/) - Riset Javier Tia
- [openwrt/mt76#927](https://github.com/openwrt/mt76/issues/927) - Issue tracking OpenWrt
- [CachyOS/linux-cachyos#688](https://github.com/CachyOS/linux-cachyos/issues/688) - Issue CachyOS
- Patch komunitas yang sudah diuji di 10+ platform hardware

## Berkontribusi

Kontribusi sangat diterima! Lihat [CONTRIBUTING.md](CONTRIBUTING.md) untuk panduan.

Sudah test di motherboard yang berbeda? Silakan buka issue atau PR untuk menambahkannya ke daftar hardware yang didukung.

## Lisensi

MIT License - lihat [LICENSE](LICENSE)

> **Catatan:** File firmware diekstrak dari driver vendor dan tunduk pada ketentuan lisensi MediaTek. File tersebut tidak termasuk dalam repository ini. Script `download.ps1` mengekstraknya dari driver Windows yang sudah terinstall di komputer kamu.
