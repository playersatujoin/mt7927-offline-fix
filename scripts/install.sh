#!/bin/bash
#
# MT7927 Offline Fix - Installer Script untuk CachyOS
# Jalankan: sudo bash install.sh
#
# Mendukung: MediaTek Wi-Fi 7 MT7927 (PCI 14c3:6639)
# WiFi + Bluetooth (MT6639)
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

log()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }

header() {
    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  MT7927 Offline Fix - CachyOS Installer${NC}"
    echo -e "${CYAN}  WiFi + Bluetooth untuk MediaTek MT7927${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""
}

# --- Root check ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Script ini harus dijalankan sebagai root!"
        echo "Gunakan: sudo bash $0"
        exit 1
    fi
}

# --- Detect hardware ---
check_hardware() {
    log "Mengecek hardware MT7927..."
    if lspci -nn 2>/dev/null | grep -qi "14c3:6639\|14c3:7927"; then
        ok "MediaTek MT7927 terdeteksi!"
        lspci -nn | grep -i "14c3:6639\|14c3:7927" | head -3
    else
        warn "MT7927 tidak terdeteksi via lspci."
        warn "Melanjutkan instalasi (mungkin belum di-bind driver)..."
    fi
    echo ""
}

# --- Check kernel version ---
check_kernel() {
    local kver
    kver=$(uname -r)
    log "Kernel: $kver"

    local major minor
    major=$(echo "$kver" | cut -d. -f1)
    minor=$(echo "$kver" | cut -d. -f2)

    if [ "$major" -lt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -lt 17 ]; }; then
        err "Kernel $kver terlalu lama! Minimal kernel 6.17+"
        err "Update kernel CachyOS dulu: sudo pacman -Syu"
        exit 1
    fi
    ok "Kernel $kver OK (>= 6.17)"
    echo ""
}

# --- Step 1: Install firmware ---
install_firmware() {
    log "[1/5] Menginstall firmware..."

    local fw_src="$BASE_DIR/firmware"

    # WiFi firmware (mt7925 - untuk driver mt7925e)
    if [ -d "$fw_src/mt7925" ]; then
        mkdir -p /lib/firmware/mediatek/mt7925
        local count=0
        for f in "$fw_src/mt7925/"*.bin; do
            [ -f "$f" ] || continue
            cp -v "$f" /lib/firmware/mediatek/mt7925/
            count=$((count + 1))
        done
        if [ "$count" -gt 0 ]; then
            ok "WiFi firmware (mt7925): $count file(s) terinstall"
        else
            warn "Tidak ada file .bin di firmware/mt7925/"
        fi
    else
        warn "Folder firmware/mt7925 tidak ditemukan, skip WiFi firmware (mt7925)"
    fi

    # WiFi firmware (mt6639 variant - untuk MT7927 spesifik)
    local fw_extracted="$BASE_DIR/firmware-extracted"
    if [ -d "$fw_extracted" ]; then
        mkdir -p /lib/firmware/mediatek/mt6639
        local count=0
        for f in "$fw_extracted/"*.bin; do
            [ -f "$f" ] || continue
            cp -v "$f" /lib/firmware/mediatek/mt6639/
            count=$((count + 1))
        done
        if [ "$count" -gt 0 ]; then
            ok "MT6639 firmware (extracted): $count file(s) terinstall"
        else
            warn "Tidak ada file .bin di firmware-extracted/"
        fi
    else
        warn "Folder firmware-extracted tidak ditemukan, skip MT6639 firmware"
    fi

    # Bluetooth firmware
    if [ -d "$fw_src/mt6639" ]; then
        mkdir -p /lib/firmware/mediatek/mt6639
        local count=0
        for f in "$fw_src/mt6639/"*.bin; do
            [ -f "$f" ] || continue
            cp -v "$f" /lib/firmware/mediatek/mt6639/
            count=$((count + 1))
        done
        if [ "$count" -gt 0 ]; then
            ok "Bluetooth firmware: $count file(s) terinstall"
        else
            warn "Tidak ada file .bin di firmware/mt6639/"
            warn "Bluetooth mungkin tidak berfungsi tanpa firmware"
        fi
    else
        warn "Folder firmware/mt6639 tidak ditemukan, skip BT firmware"
    fi

    echo ""
}

# --- Step 2: Install dependencies ---
install_deps() {
    log "[2/5] Mengecek dependencies..."

    local missing=()
    local deps=(dkms make gcc)

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    # Check kernel headers
    local kver
    kver=$(uname -r)
    if [ ! -d "/usr/lib/modules/$kver/build" ]; then
        warn "Kernel headers tidak ditemukan untuk $kver"

        # Detect which kernel package
        local header_pkg=""
        if pacman -Q linux-cachyos &>/dev/null; then
            header_pkg="linux-cachyos-headers"
        elif pacman -Q linux-cachyos-lts &>/dev/null; then
            header_pkg="linux-cachyos-lts-headers"
        elif pacman -Q linux-cachyos-bore &>/dev/null; then
            header_pkg="linux-cachyos-bore-headers"
        elif pacman -Q linux-cachyos-deckify &>/dev/null; then
            header_pkg="linux-cachyos-deckify-headers"
        elif pacman -Q linux &>/dev/null; then
            header_pkg="linux-headers"
        fi

        if [ -n "$header_pkg" ]; then
            missing+=("$header_pkg")
        else
            missing+=("linux-cachyos-headers")
        fi
    else
        ok "Kernel headers tersedia"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        warn "Dependencies belum terinstall: ${missing[*]}"

        # Try offline install from local packages
        local pkg_dir="$BASE_DIR/packages"
        if [ -d "$pkg_dir" ] && ls "$pkg_dir"/*.pkg.tar* &>/dev/null 2>&1; then
            log "Mencoba install dari paket offline..."

            # Collect matching packages to install
            local install_pkgs=()

            # Find dkms package
            for f in "$pkg_dir"/dkms-*.pkg.tar*; do
                [ -f "$f" ] && install_pkgs+=("$f")
            done

            # Find pahole package
            for f in "$pkg_dir"/pahole-*.pkg.tar*; do
                [ -f "$f" ] && install_pkgs+=("$f")
            done

            # Find matching kernel headers for running kernel
            kver=$(uname -r)
            log "Kernel berjalan: $kver"
            # Extract base version (e.g., 6.19.6-1 from 6.19.6-1-cachyos)
            local kbase
            kbase=$(echo "$kver" | sed 's/-cachyos.*//' | sed 's/-bore.*//' | sed 's/-deckify.*//' | sed 's/-lts.*//')
            log "Mencari headers untuk versi: $kbase"

            local found_headers=false
            for f in "$pkg_dir"/linux-cachyos*-headers-*.pkg.tar*; do
                [ -f "$f" ] || continue
                if echo "$f" | grep -q "$kbase"; then
                    log "Cocok: $(basename "$f")"
                    install_pkgs+=("$f")
                    found_headers=true
                fi
            done

            # If no exact match, try installing all headers (pacman will pick compatible one)
            if [ "$found_headers" = false ]; then
                warn "Tidak ada headers yang cocok persis untuk $kver"
                warn "Mencoba install semua headers yang tersedia..."
                for f in "$pkg_dir"/linux-cachyos*-headers-*.pkg.tar*; do
                    [ -f "$f" ] && install_pkgs+=("$f")
                done
            fi

            # Install all collected packages at once (resolves cross-deps)
            if [ ${#install_pkgs[@]} -gt 0 ]; then
                log "Menginstall ${#install_pkgs[@]} paket offline..."
                if pacman -U "${install_pkgs[@]}" --noconfirm --needed; then
                    ok "Paket offline terinstall!"
                else
                    warn "Beberapa paket gagal diinstall offline"
                fi
            fi
        else
            warn "Folder packages/ tidak ditemukan atau kosong"
        fi

        # Check again
        local still_missing=()
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" &>/dev/null; then
                still_missing+=("$dep")
            fi
        done

        kver=$(uname -r)
        if [ ! -d "/usr/lib/modules/$kver/build" ]; then
            still_missing+=("kernel-headers")
        fi

        if [ ${#still_missing[@]} -gt 0 ]; then
            warn "Beberapa dependencies masih belum ada: ${still_missing[*]}"
            echo ""
            warn "Kamu perlu internet untuk install sisa dependencies."
            warn "Opsi:"
            warn "  1. Colok kabel Ethernet"
            warn "  2. USB tethering dari HP"
            warn "  3. USB WiFi adapter"
            echo ""
            read -rp "Apakah kamu sudah punya koneksi internet sekarang? (y/n): " has_inet

            if [[ "$has_inet" =~ ^[Yy] ]]; then
                log "Menginstall dependencies via pacman..."
                pacman -Sy --needed --noconfirm base-devel dkms "${header_pkg:-linux-cachyos-headers}"
            else
                err "Tidak bisa melanjutkan tanpa dependencies."
                err "Sambungkan internet lalu jalankan ulang script ini."
                echo ""
                echo "Atau install manual:"
                echo "  sudo pacman -S base-devel dkms ${header_pkg:-linux-cachyos-headers}"
                echo "  sudo bash $0"
                exit 1
            fi
        fi
    else
        ok "Semua dependencies tersedia"
    fi

    echo ""
}

# --- Step 3: Build & install DKMS module ---
install_dkms() {
    log "[3/5] Building & installing DKMS driver..."

    local dkms_src="$BASE_DIR/dkms-source"

    if [ ! -d "$dkms_src" ]; then
        err "Folder dkms-source tidak ditemukan!"
        err "Pastikan kamu sudah menjalankan download.ps1 di Windows"
        exit 1
    fi

    local install_log="$BASE_DIR/install.log"

    # Work inside dkms-source without polluting global cwd
    pushd "$dkms_src" > /dev/null

    # Run make download (fetches kernel source patches) - might fail offline
    if [ -f "Makefile" ]; then
        log "Menjalankan make download (mengambil source)..."
        if make download 2>>"$install_log"; then
            ok "Source downloaded"
        else
            warn "make download gagal (mungkin offline), mencoba cara manual..."
        fi

        log "Menjalankan make sources (menyiapkan source)..."
        if make sources 2>>"$install_log"; then
            ok "Source disiapkan"
        else
            warn "make sources gagal, mencoba install manual..."
        fi
    fi

    # Try the standard DKMS install via Makefile
    log "Menginstall via DKMS..."
    if make install 2>>"$install_log"; then
        ok "DKMS install berhasil via Makefile!"
    else
        warn "make install gagal, mencoba DKMS manual..."

        # Manual DKMS approach
        # Find dkms.conf to get version
        if [ -f "dkms.conf" ]; then
            local pkg_name pkg_ver
            pkg_name=$(grep '^PACKAGE_NAME' dkms.conf | cut -d'"' -f2)
            pkg_ver=$(grep '^PACKAGE_VERSION' dkms.conf | cut -d'"' -f2)

            if [ -n "$pkg_name" ] && [ -n "$pkg_ver" ]; then
                local dkms_dst="/usr/src/${pkg_name}-${pkg_ver}"
                log "Copying source ke $dkms_dst"
                rm -rf "$dkms_dst"
                cp -r "$dkms_src" "$dkms_dst"

                dkms remove "${pkg_name}/${pkg_ver}" --all 2>/dev/null || true
                dkms add "${pkg_name}/${pkg_ver}"
                dkms build "${pkg_name}/${pkg_ver}"
                dkms install "${pkg_name}/${pkg_ver}"
                ok "DKMS module terinstall: ${pkg_name}/${pkg_ver}"
            else
                err "Tidak bisa parse dkms.conf"
                popd > /dev/null
                exit 1
            fi
        else
            err "dkms.conf tidak ditemukan di dkms-source/"
            popd > /dev/null
            exit 1
        fi
    fi

    popd > /dev/null
    echo ""
}

# --- Step 4: Configure boot ---
configure_boot() {
    log "[4/5] Mengkonfigurasi boot..."

    # Ensure mt7925e loads at boot
    echo "mt7925e" > /etc/modules-load.d/mt7927-wifi.conf
    ok "mt7925e akan di-load saat boot"

    # Blacklist conflicting modules (if any)
    if [ ! -f /etc/modprobe.d/mt7927-fix.conf ]; then
        cat > /etc/modprobe.d/mt7927-fix.conf << 'MODCONF'
# MT7927 fix: ensure correct driver loads
# Blacklist mt7921e to prevent conflict (mt7925e handles MT7927)
blacklist mt7921e
MODCONF
        ok "Blacklist mt7921e (prevent conflict)"
    fi

    # Create systemd service for BT USB rescan (BT needs WiFi to init first)
    if [ ! -f /etc/systemd/system/mt7927-bt-rescan.service ]; then
        cat > /etc/systemd/system/mt7927-bt-rescan.service << 'SVCEOF'
[Unit]
Description=Rescan USB bus for MT7927/MT6639 Bluetooth
After=network-pre.target systemd-modules-load.service
Wants=network-pre.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 5
ExecStart=/bin/bash -c 'for dev in /sys/bus/usb/devices/*/idVendor; do dir=$(dirname "$dev"); vid=$(cat "$dir/idVendor" 2>/dev/null); if [ "$vid" = "13d3" ] || [ "$vid" = "0489" ] || [ "$vid" = "0e8d" ]; then echo 0 > "$dir/authorized"; sleep 1; echo 1 > "$dir/authorized"; fi; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF
        systemctl daemon-reload
        systemctl enable mt7927-bt-rescan.service
        ok "Systemd service untuk BT rescan terinstall & enabled"
    else
        ok "BT rescan service sudah ada"
    fi

    # Rebuild initramfs to include firmware
    log "Rebuilding initramfs (agar firmware ikut masuk)..."
    if command -v mkinitcpio &>/dev/null; then
        mkinitcpio -P
        ok "Initramfs rebuilt"
    else
        warn "mkinitcpio tidak ditemukan, skip rebuild initramfs"
    fi

    echo ""
}

# --- Step 5: Load modules now ---
load_modules() {
    log "[5/5] Mencoba load module sekarang..."

    # Remove conflicting modules
    modprobe -r mt7921e 2>/dev/null || true
    modprobe -r mt7925e 2>/dev/null || true
    modprobe -r btusb 2>/dev/null || true

    sleep 1

    # Load patched modules
    if modprobe mt7925e 2>/dev/null; then
        ok "mt7925e loaded!"
    else
        warn "mt7925e gagal di-load (akan coba saat reboot)"
    fi

    sleep 2

    if modprobe btusb 2>/dev/null; then
        ok "btusb loaded!"
    else
        warn "btusb gagal di-load (akan coba saat reboot)"
    fi

    echo ""
}

# --- Verify ---
verify() {
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  VERIFIKASI${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""

    # Check WiFi interface
    log "WiFi interface:"
    if ip link show 2>/dev/null | grep -q "wl"; then
        ip link show | grep "wl" | head -3
        ok "WiFi interface terdeteksi!"
    else
        warn "WiFi interface belum muncul (coba reboot)"
    fi
    echo ""

    # Check driver binding
    log "Driver binding:"
    lspci -k 2>/dev/null | grep -A 3 -i "14c3" || warn "Tidak ada device MediaTek terdeteksi"
    echo ""

    # Check Bluetooth
    log "Bluetooth:"
    if command -v bluetoothctl &>/dev/null; then
        if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
            bluetoothctl show 2>/dev/null | head -5
            ok "Bluetooth controller terdeteksi!"
        else
            warn "Bluetooth belum terdeteksi (coba reboot)"
        fi
    fi
    echo ""

    # Check DKMS status
    log "DKMS status:"
    dkms status 2>/dev/null || warn "DKMS tidak tersedia"
    echo ""

    # Check kernel log for errors
    log "Kernel log (MT7927 related):"
    dmesg 2>/dev/null | grep -i "mt79\|mt66\|mediatek" | tail -10
    echo ""
}

# --- Main ---
main() {
    header
    check_root
    check_hardware
    check_kernel
    install_firmware
    install_deps
    install_dkms
    configure_boot
    load_modules
    verify

    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  INSTALASI SELESAI!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "Jika WiFi/BT belum muncul, REBOOT dulu:"
    echo "  sudo reboot"
    echo ""
    echo "Setelah reboot, cek dengan:"
    echo "  nmcli device status        # WiFi"
    echo "  bluetoothctl show           # Bluetooth"
    echo "  dmesg | grep mt79           # Kernel log"
    echo ""
    echo "Jika BT tetap tidak muncul setelah reboot:"
    echo "  Shutdown > cabut kabel power 10 detik > nyalakan lagi"
    echo ""

    read -rp "Reboot sekarang? (y/n): " do_reboot
    if [[ "$do_reboot" =~ ^[Yy] ]]; then
        reboot
    fi
}

main "$@"
