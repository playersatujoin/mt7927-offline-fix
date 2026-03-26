#Requires -Version 5.1
<#
.SYNOPSIS
    MT7927 Offline Fix - Download Script (Windows)
    Download semua file yang dibutuhkan untuk fix WiFi MT7927 di CachyOS

.USAGE
    Klik kanan > Run with PowerShell
    Atau: powershell -ExecutionPolicy Bypass -File download.ps1
#>

$ErrorActionPreference = "Stop"
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  MT7927 Offline Fix - Download Tool" -ForegroundColor Cyan
Write-Host "  Untuk: MediaTek Wi-Fi 7 MT7927 (PCI 14c3:6639)" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# --- Helper ---
function Download-File {
    param([string]$Url, [string]$Output)
    $name = Split-Path -Leaf $Output
    Write-Host "  Downloading $name ... " -NoNewline
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url, $Output)
        Write-Host "OK" -ForegroundColor Green
    } catch {
        Write-Host "GAGAL: $_" -ForegroundColor Red
        return $false
    }
    return $true
}

# ===== 1. Download WiFi Firmware =====
Write-Host "[1/4] Downloading WiFi firmware..." -ForegroundColor Yellow
$fwDir = Join-Path $BaseDir "firmware\mt7925"
New-Item -ItemType Directory -Force -Path $fwDir | Out-Null

$wifiFirmwareFiles = @(
    @{
        Url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7925/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin"
        Out = Join-Path $fwDir "WIFI_MT7925_PATCH_MCU_1_1_hdr.bin"
    },
    @{
        Url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7925/WIFI_RAM_CODE_MT7925_1_1.bin"
        Out = Join-Path $fwDir "WIFI_RAM_CODE_MT7925_1_1.bin"
    }
)

foreach ($fw in $wifiFirmwareFiles) {
    Download-File -Url $fw.Url -Output $fw.Out
}

# ===== 2. Download Bluetooth Firmware =====
Write-Host ""
Write-Host "[2/4] Downloading Bluetooth firmware..." -ForegroundColor Yellow
$btDir = Join-Path $BaseDir "firmware\mt6639"
New-Item -ItemType Directory -Force -Path $btDir | Out-Null

# BT firmware dari linux-firmware repo
$btFirmwareFiles = @(
    @{
        Url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin"
        Out = Join-Path $btDir "BT_RAM_CODE_MT6639_2_1_hdr.bin"
    }
)

$btSuccess = $true
foreach ($fw in $btFirmwareFiles) {
    $result = Download-File -Url $fw.Url -Output $fw.Out
    if (-not $result) { $btSuccess = $false }
}

if (-not $btSuccess) {
    Write-Host ""
    Write-Host "  [!] BT firmware gagal didownload dari kernel.org." -ForegroundColor DarkYellow
    Write-Host "  [!] Alternatif: Download driver WiFi/BT dari website motherboard kamu (ASUS/Lenovo/MSI)" -ForegroundColor DarkYellow
    Write-Host "  [!] Ekstrak dan cari file 'BT_RAM_CODE_MT6639_2_1_hdr.bin'" -ForegroundColor DarkYellow
    Write-Host "  [!] Lalu copy ke folder: firmware\mt6639\" -ForegroundColor DarkYellow
}

# ===== 3. Download DKMS Driver Source =====
Write-Host ""
Write-Host "[3/4] Downloading DKMS driver source..." -ForegroundColor Yellow
$dkmsDir = Join-Path $BaseDir "dkms-source"

# Download as zip from GitHub
$zipUrl = "https://github.com/jetm/mediatek-mt7927-dkms/archive/refs/heads/main.zip"
$zipFile = Join-Path $BaseDir "dkms-source.zip"

$dlOk = Download-File -Url $zipUrl -Output $zipFile

if ($dlOk) {
    Write-Host "  Extracting..." -NoNewline
    try {
        if (Test-Path $dkmsDir) { Remove-Item -Recurse -Force $dkmsDir }
        Expand-Archive -Path $zipFile -DestinationPath $BaseDir -Force
        Rename-Item -Path (Join-Path $BaseDir "mediatek-mt7927-dkms-main") -NewName "dkms-source" -Force
        Remove-Item $zipFile -Force
        Write-Host " OK" -ForegroundColor Green
    } catch {
        Write-Host " GAGAL: $_" -ForegroundColor Red
    }
}

# ===== 4. Buat info file =====
Write-Host ""
Write-Host "[4/4] Membuat file info..." -ForegroundColor Yellow

# ===== Summary =====
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  DOWNLOAD SELESAI!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Isi folder:" -ForegroundColor White

# List downloaded files
Write-Host ""
Write-Host "  firmware/mt7925/" -ForegroundColor Gray
Get-ChildItem (Join-Path $BaseDir "firmware\mt7925") -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "    - $($_.Name) ($([math]::Round($_.Length/1KB)) KB)" -ForegroundColor Gray
}
Write-Host "  firmware/mt6639/" -ForegroundColor Gray
Get-ChildItem (Join-Path $BaseDir "firmware\mt6639") -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "    - $($_.Name) ($([math]::Round($_.Length/1KB)) KB)" -ForegroundColor Gray
}
Write-Host "  dkms-source/" -ForegroundColor Gray
if (Test-Path $dkmsDir) {
    Write-Host "    - (driver source code)" -ForegroundColor Gray
}
Write-Host "  scripts/" -ForegroundColor Gray
Write-Host "    - install.sh" -ForegroundColor Gray

Write-Host ""
Write-Host "LANGKAH SELANJUTNYA:" -ForegroundColor Yellow
Write-Host "  1. Copy seluruh folder 'mt7927-offline-fix' ke USB drive" -ForegroundColor White
Write-Host "  2. Install CachyOS (gunakan Ethernet jika perlu, atau tanpa internet)" -ForegroundColor White
Write-Host "  3. Boot ke CachyOS, mount USB, lalu jalankan:" -ForegroundColor White
Write-Host ""
Write-Host "     cd /mnt/usb/mt7927-offline-fix" -ForegroundColor Green
Write-Host "     sudo bash scripts/install.sh" -ForegroundColor Green
Write-Host ""
Write-Host "  4. Reboot dan WiFi + Bluetooth harusnya sudah jalan!" -ForegroundColor White
Write-Host ""

Read-Host "Tekan Enter untuk keluar"
