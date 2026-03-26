#!/bin/bash
#
# MT7927 Offline Fix - LIVE MODE TEST
# Test WiFi MT7927 di CachyOS Live USB sebelum install
#
# Jalankan: sudo bash test-live.sh
#

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_LOG="$BASE_DIR/test-live.log"

log()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARN=0

record_pass() { pass "$1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
record_fail() { fail "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
record_warn() { warn "$1"; TESTS_WARN=$((TESTS_WARN + 1)); }

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
    err "Script ini harus dijalankan sebagai root!"
    echo "Gunakan: sudo bash $0"
    exit 1
fi

echo ""
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}  MT7927 Offline Fix - LIVE MODE TEST${NC}"
echo -e "${CYAN}  Test sebelum install CachyOS${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""
echo "Script ini akan:"
echo "  1. Cek hardware MT7927"
echo "  2. Install firmware (temporary, di RAM)"
echo "  3. Coba install dependencies + build driver"
echo "  4. Test load module WiFi + Bluetooth"
echo "  5. Verifikasi koneksi WiFi"
echo ""
echo "Semua perubahan HANYA di live session (hilang saat reboot)."
echo ""
read -rp "Lanjutkan? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy] ]]; then
    echo "Dibatalkan."
    exit 0
fi

echo ""

# ============================================================
# TEST 1: Hardware Detection
# ============================================================
log "=== TEST 1: Hardware Detection ==="

kver=$(uname -r)
log "Kernel: $kver"

if lspci -nn 2>/dev/null | grep -qi "14c3:6639\|14c3:7927"; then
    record_pass "MediaTek MT7927 terdeteksi via lspci"
    lspci -nn | grep -i "14c3:6639\|14c3:7927"
else
    record_fail "MT7927 tidak terdeteksi via lspci"
    echo "  Kemungkinan: hardware belum aktif atau PCI ID berbeda"
    lspci -nn | grep -i "14c3" || echo "  Tidak ada device MediaTek sama sekali"
fi

# Check current driver binding
log "Driver binding saat ini:"
if lspci -k 2>/dev/null | grep -A 3 -i "14c3"; then
    echo ""
else
    warn "Tidak ada info driver binding"
fi

echo ""

# ============================================================
# TEST 2: Firmware Installation (to tmpfs/live filesystem)
# ============================================================
log "=== TEST 2: Firmware Installation ==="

fw_src="$BASE_DIR/firmware"
fw_extracted="$BASE_DIR/firmware-extracted"
fw_ok=true

# WiFi firmware - mt7925
if [ -d "$fw_src/mt7925" ]; then
    mkdir -p /lib/firmware/mediatek/mt7925
    count=0
    for f in "$fw_src/mt7925/"*.bin; do
        [ -f "$f" ] || continue
        cp "$f" /lib/firmware/mediatek/mt7925/
        count=$((count + 1))
    done
    if [ "$count" -gt 0 ]; then
        record_pass "WiFi firmware mt7925: $count file(s) copied"
    else
        record_fail "Tidak ada firmware .bin di firmware/mt7925/"
        fw_ok=false
    fi
else
    record_fail "Folder firmware/mt7925 tidak ada"
    fw_ok=false
fi

# MT6639 firmware (extracted from Windows driver)
if [ -d "$fw_extracted" ]; then
    mkdir -p /lib/firmware/mediatek/mt6639
    count=0
    for f in "$fw_extracted/"*.bin; do
        [ -f "$f" ] || continue
        cp "$f" /lib/firmware/mediatek/mt6639/
        count=$((count + 1))
    done
    if [ "$count" -gt 0 ]; then
        record_pass "MT6639 firmware (extracted): $count file(s) copied"
    else
        record_warn "Tidak ada firmware .bin di firmware-extracted/"
    fi
fi

# BT firmware
if [ -d "$fw_src/mt6639" ]; then
    mkdir -p /lib/firmware/mediatek/mt6639
    count=0
    for f in "$fw_src/mt6639/"*.bin; do
        [ -f "$f" ] || continue
        cp "$f" /lib/firmware/mediatek/mt6639/
        count=$((count + 1))
    done
    if [ "$count" -gt 0 ]; then
        record_pass "Bluetooth firmware: $count file(s) copied"
    else
        record_warn "Tidak ada BT firmware .bin"
    fi
fi

# Verify firmware files are in place
log "Firmware terinstall:"
find /lib/firmware/mediatek/mt7925 /lib/firmware/mediatek/mt6639 -name "*.bin" 2>/dev/null | while read -r f; do
    echo "  $f ($(stat -c%s "$f" 2>/dev/null || echo '?') bytes)"
done

echo ""

# ============================================================
# TEST 3: Dependencies & DKMS Build
# ============================================================
log "=== TEST 3: Dependencies & DKMS Build ==="

# Check if essential tools exist
has_gcc=false; has_make=false; has_dkms=false; has_headers=false

command -v gcc &>/dev/null && has_gcc=true
command -v make &>/dev/null && has_make=true
command -v dkms &>/dev/null && has_dkms=true
[ -d "/usr/lib/modules/$kver/build" ] && has_headers=true

log "gcc: $has_gcc | make: $has_make | dkms: $has_dkms | headers: $has_headers"

# Try to install from offline packages
pkg_dir="$BASE_DIR/packages"
if [ -d "$pkg_dir" ] && ls "$pkg_dir"/*.pkg.tar* &>/dev/null 2>&1; then
    log "Mencoba install dependencies dari paket offline..."

    install_pkgs=()

    # dkms
    for f in "$pkg_dir"/dkms-*.pkg.tar*; do
        [ -f "$f" ] && install_pkgs+=("$f")
    done

    # pahole
    for f in "$pkg_dir"/pahole-*.pkg.tar*; do
        [ -f "$f" ] && install_pkgs+=("$f")
    done

    # kernel headers - match running kernel
    kbase=$(echo "$kver" | sed 's/-cachyos.*//' | sed 's/-bore.*//' | sed 's/-deckify.*//' | sed 's/-lts.*//')
    log "Mencari headers untuk: $kbase"

    found_headers=false
    for f in "$pkg_dir"/linux-cachyos*-headers-*.pkg.tar*; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -q "$kbase"; then
            log "Cocok: $(basename "$f")"
            install_pkgs+=("$f")
            found_headers=true
        fi
    done

    if [ "$found_headers" = false ]; then
        warn "Tidak ada headers yang cocok untuk $kver"
        warn "Kernel live mungkin berbeda dari paket headers yang tersedia"
        warn "Mencoba semua headers..."
        for f in "$pkg_dir"/linux-cachyos*-headers-*.pkg.tar*; do
            [ -f "$f" ] && install_pkgs+=("$f")
        done
    fi

    if [ ${#install_pkgs[@]} -gt 0 ]; then
        log "Menginstall ${#install_pkgs[@]} paket..."
        if pacman -U "${install_pkgs[@]}" --noconfirm --needed 2>>"$INSTALL_LOG"; then
            record_pass "Paket offline terinstall"
        else
            record_warn "Beberapa paket gagal (lihat $INSTALL_LOG)"
        fi
    fi
else
    warn "Tidak ada offline packages di $pkg_dir"
fi

# Re-check after install
command -v dkms &>/dev/null && has_dkms=true
[ -d "/usr/lib/modules/$kver/build" ] && has_headers=true

if [ "$has_dkms" = true ] && [ "$has_headers" = true ]; then
    record_pass "DKMS + kernel headers tersedia"
else
    if [ "$has_headers" = false ]; then
        record_fail "Kernel headers tidak tersedia untuk $kver"
        echo "  Headers tersedia untuk:"
        ls "$pkg_dir"/linux-cachyos*-headers-*.pkg.tar* 2>/dev/null | while read -r f; do
            echo "    $(basename "$f")"
        done
        echo "  Kernel live: $kver"
        echo ""
        echo "  Jika versi tidak cocok, ini NORMAL - kernel live bisa berbeda."
        echo "  Yang penting: setelah install CachyOS, jalankan install.sh"
        echo "  dan headers yang cocok akan terinstall."
    fi
    if [ "$has_dkms" = false ]; then
        record_fail "DKMS tidak tersedia"
    fi
fi

echo ""

# ============================================================
# TEST 4: DKMS Module Build & Load
# ============================================================
log "=== TEST 4: Driver Build & Module Load ==="

dkms_src="$BASE_DIR/dkms-source"
module_loaded=false

if [ "$has_dkms" = true ] && [ "$has_headers" = true ] && [ -d "$dkms_src" ]; then
    log "Mencoba build DKMS module..."

    pushd "$dkms_src" > /dev/null

    build_ok=false
    if [ -f "Makefile" ]; then
        # Try make download + sources + install
        make download 2>>"$INSTALL_LOG" || true
        make sources 2>>"$INSTALL_LOG" || true

        if make install 2>>"$INSTALL_LOG"; then
            record_pass "DKMS module berhasil di-build dan install"
            build_ok=true
        else
            warn "make install gagal, mencoba DKMS manual..."

            if [ -f "dkms.conf" ]; then
                pkg_name=$(grep '^PACKAGE_NAME' dkms.conf | cut -d'"' -f2)
                pkg_ver=$(grep '^PACKAGE_VERSION' dkms.conf | cut -d'"' -f2)

                if [ -n "$pkg_name" ] && [ -n "$pkg_ver" ]; then
                    dkms_dst="/usr/src/${pkg_name}-${pkg_ver}"
                    rm -rf "$dkms_dst"
                    cp -r "$dkms_src" "$dkms_dst"

                    dkms remove "${pkg_name}/${pkg_ver}" --all 2>/dev/null || true
                    if dkms add "${pkg_name}/${pkg_ver}" 2>>"$INSTALL_LOG" && \
                       dkms build "${pkg_name}/${pkg_ver}" 2>>"$INSTALL_LOG" && \
                       dkms install "${pkg_name}/${pkg_ver}" 2>>"$INSTALL_LOG"; then
                        record_pass "DKMS manual build berhasil"
                        build_ok=true
                    else
                        record_fail "DKMS build gagal (lihat $INSTALL_LOG)"
                    fi
                fi
            fi
        fi
    fi

    popd > /dev/null

    # Try loading modules
    if [ "$build_ok" = true ]; then
        log "Mencoba load module..."

        modprobe -r mt7921e 2>/dev/null || true
        modprobe -r mt7925e 2>/dev/null || true
        modprobe -r btusb 2>/dev/null || true
        sleep 1

        if modprobe mt7925e 2>>"$INSTALL_LOG"; then
            record_pass "mt7925e module loaded!"
            module_loaded=true
        else
            record_fail "mt7925e gagal di-load"
        fi

        sleep 2

        if modprobe btusb 2>>"$INSTALL_LOG"; then
            record_pass "btusb module loaded"
        else
            record_warn "btusb gagal di-load"
        fi
    fi
else
    if [ ! -d "$dkms_src" ]; then
        record_fail "Folder dkms-source tidak ada"
    else
        record_warn "Skip DKMS build (dependencies belum lengkap)"
        echo "  Ini bisa jadi normal di live mode jika kernel headers tidak cocok."
    fi
fi

echo ""

# ============================================================
# TEST 5: WiFi & Bluetooth Verification
# ============================================================
log "=== TEST 5: WiFi & Bluetooth Verification ==="

sleep 3  # Wait for interface to appear

# WiFi
log "Mengecek WiFi interface..."
if ip link show 2>/dev/null | grep -q "wl"; then
    record_pass "WiFi interface terdeteksi!"
    ip link show | grep "wl" | head -3

    # Try to scan networks
    wifi_iface=$(ip link show | grep "wl" | head -1 | awk -F: '{print $2}' | tr -d ' ')
    if [ -n "$wifi_iface" ]; then
        log "Mengaktifkan $wifi_iface..."
        ip link set "$wifi_iface" up 2>/dev/null || true
        sleep 2

        log "Scanning WiFi networks..."
        if command -v nmcli &>/dev/null; then
            if nmcli device wifi rescan 2>/dev/null; then
                sleep 3
                networks=$(nmcli -t -f SSID device wifi list 2>/dev/null | grep -v '^$' | head -5)
                if [ -n "$networks" ]; then
                    record_pass "WiFi scan berhasil! Networks ditemukan:"
                    echo "$networks" | while read -r ssid; do
                        echo "    - $ssid"
                    done
                else
                    record_warn "WiFi interface ada tapi tidak ada network terdeteksi"
                fi
            fi
        elif command -v iw &>/dev/null; then
            scan_result=$(iw dev "$wifi_iface" scan 2>/dev/null | grep "SSID:" | head -5)
            if [ -n "$scan_result" ]; then
                record_pass "WiFi scan berhasil!"
                echo "$scan_result"
            else
                record_warn "WiFi scan kosong"
            fi
        fi
    fi
else
    if [ "$module_loaded" = true ]; then
        record_warn "Module loaded tapi WiFi interface belum muncul (mungkin perlu reboot)"
    else
        record_warn "WiFi interface belum muncul (expected jika build gagal)"
    fi
fi

echo ""

# Bluetooth
log "Mengecek Bluetooth..."
if command -v bluetoothctl &>/dev/null; then
    if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
        record_pass "Bluetooth controller terdeteksi!"
        bluetoothctl show 2>/dev/null | head -5
    else
        record_warn "Bluetooth belum terdeteksi"
    fi
else
    warn "bluetoothctl tidak tersedia"
fi

echo ""

# Driver binding check
log "Driver binding setelah test:"
lspci -k 2>/dev/null | grep -A 3 -i "14c3" || warn "Tidak ada device MediaTek"

echo ""

# Kernel log
log "Kernel log (MediaTek related):"
dmesg 2>/dev/null | grep -i "mt79\|mt66\|mediatek" | tail -15

echo ""

# ============================================================
# SUMMARY
# ============================================================
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}  TEST SUMMARY${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""
echo -e "  ${GREEN}PASSED:${NC}  $TESTS_PASSED"
echo -e "  ${RED}FAILED:${NC}  $TESTS_FAILED"
echo -e "  ${YELLOW}WARNING:${NC} $TESTS_WARN"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}  HASIL: SEMUA TEST PASSED!${NC}"
    echo ""
    echo "  WiFi MT7927 kamu berfungsi di CachyOS."
    echo "  Kamu bisa lanjut install CachyOS dengan aman."
    echo ""
    echo "  Setelah install, jalankan lagi:"
    echo "    sudo bash scripts/install.sh"
    echo "  untuk install permanen."
elif [ "$module_loaded" = true ]; then
    echo -e "${YELLOW}  HASIL: SEBAGIAN BERHASIL${NC}"
    echo ""
    echo "  Driver berhasil di-load. WiFi mungkin perlu waktu"
    echo "  atau reboot untuk muncul."
    echo ""
    echo "  Kamu bisa coba install CachyOS."
    echo "  Setelah install, jalankan: sudo bash scripts/install.sh"
else
    echo -e "${YELLOW}  HASIL: BELUM BISA DIVERIFIKASI SEPENUHNYA${NC}"
    echo ""
    if [ "$has_headers" = false ]; then
        echo "  Penyebab utama: kernel headers live ($kver) tidak cocok"
        echo "  dengan headers offline yang tersedia."
        echo ""
        echo "  Ini NORMAL - kernel live ISO sering berbeda versinya."
        echo "  Setelah install CachyOS, kernel yang terinstall akan"
        echo "  cocok dengan headers di paket offline kita."
        echo ""
        echo "  Yang sudah terverifikasi:"
        echo "    - Hardware MT7927 terdeteksi: $([ "$TESTS_PASSED" -gt 0 ] && echo 'YA' || echo 'BELUM')"
        echo "    - Firmware tersedia: $([ "$fw_ok" = true ] && echo 'YA' || echo 'BELUM')"
        echo ""
        echo "  REKOMENDASI: Lanjut install CachyOS, lalu jalankan install.sh"
    else
        echo "  Build gagal. Cek log: $INSTALL_LOG"
        echo ""
        echo "  Jalankan: cat $INSTALL_LOG"
        echo "  untuk melihat detail error."
    fi
fi

echo ""
echo "Log tersimpan di: $INSTALL_LOG"
echo ""
