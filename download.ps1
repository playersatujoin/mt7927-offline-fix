#Requires -Version 5.1
<#
.SYNOPSIS
    MT7927 Offline Fix - Downloads everything needed
    Firmware + CachyOS Packages + Driver Source

.USAGE
    Right-click > Run with PowerShell
    Or: powershell -ExecutionPolicy Bypass -File download.ps1
#>

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  MT7927 Offline Fix - Download Tool" -ForegroundColor Cyan
Write-Host "  MediaTek Wi-Fi 7 MT7927 (PCI 14c3:6639)" -ForegroundColor Cyan
Write-Host "  One script, downloads EVERYTHING you need" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

$totalSteps = 5
$errors = 0

# ── Helper ──
function Download-File {
    param([string]$Url, [string]$Output, [string]$Label)
    if (-not $Label) { $Label = Split-Path -Leaf $Output }
    Write-Host "  Downloading $Label ... " -NoNewline
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc.DownloadFile($Url, $Output)
        $size = [math]::Round((Get-Item $Output).Length / 1KB)
        Write-Host "OK ($size KB)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host "    $_" -ForegroundColor DarkGray
        return $false
    }
}

function Extract-FirmwareBlob {
    param([byte[]]$Data, [string]$Name, [string]$OutputPath)
    # Find firmware name inside mtkwlan.dat binary container
    $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($Name)
    $idx = -1
    for ($i = 0; $i -lt ($Data.Length - $nameBytes.Length); $i++) {
        $match = $true
        for ($j = 0; $j -lt $nameBytes.Length; $j++) {
            if ($Data[$i + $j] -ne $nameBytes[$j]) { $match = $false; break }
        }
        if ($match) { $idx = $i; break }
    }
    if ($idx -eq -1) {
        Write-Host "  [!] $Name not found in mtkwlan.dat" -ForegroundColor Yellow
        return $false
    }

    $pos = $idx + $nameBytes.Length
    # Skip null padding
    while ($pos -lt $Data.Length -and $Data[$pos] -eq 0) { $pos++ }
    # Skip 14-digit timestamp if present
    $isTimestamp = $true
    for ($t = 0; $t -lt 14 -and ($pos + $t) -lt $Data.Length; $t++) {
        if ($Data[$pos + $t] -lt 48 -or $Data[$pos + $t] -gt 57) { $isTimestamp = $false; break }
    }
    if ($isTimestamp) { $pos += 14 }
    # Align to 4-byte boundary
    $pos = [int](([math]::Ceiling($pos / 4)) * 4)

    # Read offset and size (little-endian uint32)
    $offset = [BitConverter]::ToUInt32($Data, $pos)
    $size = [BitConverter]::ToUInt32($Data, $pos + 4)

    if ($offset + $size -gt $Data.Length) {
        Write-Host "  [!] $Name: invalid size (offset=$offset, size=$size)" -ForegroundColor Yellow
        return $false
    }

    $outDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

    $blob = New-Object byte[] $size
    [Array]::Copy($Data, $offset, $blob, 0, $size)
    [System.IO.File]::WriteAllBytes($OutputPath, $blob)

    $sizeKB = [math]::Round($size / 1KB)
    Write-Host "  [+] $Name ($sizeKB KB)" -ForegroundColor Green
    return $true
}

# ════════════════════════════════════════════════════════
# STEP 1: WiFi Firmware from kernel.org
# ════════════════════════════════════════════════════════
Write-Host "[1/$totalSteps] Downloading WiFi firmware from kernel.org..." -ForegroundColor Yellow
$fwDir = Join-Path $BaseDir "firmware\mt7925"
New-Item -ItemType Directory -Force -Path $fwDir | Out-Null

$wifiFiles = @(
    @{ Url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7925/WIFI_MT7925_PATCH_MCU_1_1_hdr.bin"; Name = "WIFI_MT7925_PATCH_MCU_1_1_hdr.bin" },
    @{ Url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7925/WIFI_RAM_CODE_MT7925_1_1.bin"; Name = "WIFI_RAM_CODE_MT7925_1_1.bin" }
)
foreach ($fw in $wifiFiles) {
    $ok = Download-File -Url $fw.Url -Output (Join-Path $fwDir $fw.Name)
    if (-not $ok) { $errors++ }
}
Write-Host ""

# ════════════════════════════════════════════════════════
# STEP 2: Extract firmware from Windows driver (mtkwlan.dat)
# ════════════════════════════════════════════════════════
Write-Host "[2/$totalSteps] Extracting firmware from Windows driver..." -ForegroundColor Yellow

$mtkwlanPath = $null
$searchPaths = @(
    "C:\Windows\System32\DriverStore\FileRepository"
)
foreach ($searchPath in $searchPaths) {
    $found = Get-ChildItem -Path $searchPath -Recurse -Filter "mtkwlan.dat" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $mtkwlanPath = $found.FullName; break }
}

if ($mtkwlanPath) {
    Write-Host "  Found: $mtkwlanPath" -ForegroundColor Gray
    $sizeMB = [math]::Round((Get-Item $mtkwlanPath).Length / 1MB)
    Write-Host "  Size: $sizeMB MB - reading..." -ForegroundColor Gray

    $data = [System.IO.File]::ReadAllBytes($mtkwlanPath)

    # Extract firmware blobs
    $extractDir = Join-Path $BaseDir "firmware-extracted"
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

    $fwBlobs = @(
        @{ Name = "BT_RAM_CODE_MT6639_2_1_hdr.bin"; Out = (Join-Path $extractDir "BT_RAM_CODE_MT6639_2_1_hdr.bin") },
        @{ Name = "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"; Out = (Join-Path $extractDir "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin") },
        @{ Name = "WIFI_RAM_CODE_MT6639_2_1.bin"; Out = (Join-Path $extractDir "WIFI_RAM_CODE_MT6639_2_1.bin") }
    )

    foreach ($blob in $fwBlobs) {
        $ok = Extract-FirmwareBlob -Data $data -Name $blob.Name -OutputPath $blob.Out
        if (-not $ok) { $errors++ }
    }

    # Copy BT firmware to firmware/mt6639
    $btDir = Join-Path $BaseDir "firmware\mt6639"
    New-Item -ItemType Directory -Force -Path $btDir | Out-Null
    $btSrc = Join-Path $extractDir "BT_RAM_CODE_MT6639_2_1_hdr.bin"
    if (Test-Path $btSrc) {
        Copy-Item $btSrc -Destination $btDir -Force
        Write-Host "  [+] BT firmware copied to firmware\mt6639\" -ForegroundColor Green
    }

    # Copy WiFi MT6639 firmware to firmware/mt7925
    $wifiExtracted = @("WIFI_MT6639_PATCH_MCU_2_1_hdr.bin", "WIFI_RAM_CODE_MT6639_2_1.bin")
    foreach ($wf in $wifiExtracted) {
        $src = Join-Path $extractDir $wf
        if (Test-Path $src) {
            Copy-Item $src -Destination $fwDir -Force
        }
    }
    Write-Host "  [+] WiFi MT6639 firmware copied to firmware\mt7925\" -ForegroundColor Green
} else {
    Write-Host "  [!] mtkwlan.dat NOT FOUND in DriverStore" -ForegroundColor Yellow
    Write-Host "  [!] Make sure MediaTek MT7927 Windows driver is installed" -ForegroundColor Yellow
    Write-Host "  [!] Download from your motherboard website (ASUS/MSI/Lenovo)" -ForegroundColor Yellow
    $errors++
}
Write-Host ""

# ════════════════════════════════════════════════════════
# STEP 3: Download DKMS driver source
# ════════════════════════════════════════════════════════
Write-Host "[3/$totalSteps] Downloading DKMS driver source..." -ForegroundColor Yellow
$dkmsDir = Join-Path $BaseDir "dkms-source"

if (Test-Path $dkmsDir) {
    Write-Host "  [SKIP] dkms-source/ already exists" -ForegroundColor Gray
} else {
    # Try git clone first
    $hasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
    if ($hasGit) {
        Write-Host "  Cloning via git..." -ForegroundColor Gray
        & git clone --depth 1 "https://github.com/jetm/mediatek-mt7927-dkms.git" $dkmsDir 2>&1 | Out-Null
        if (Test-Path (Join-Path $dkmsDir "dkms.conf")) {
            Remove-Item (Join-Path $dkmsDir ".git") -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] DKMS source cloned" -ForegroundColor Green
        } else {
            Write-Host "  git clone failed, trying ZIP download..." -ForegroundColor Yellow
            $hasGit = $false
        }
    }

    if (-not $hasGit) {
        $zipUrl = "https://github.com/jetm/mediatek-mt7927-dkms/archive/refs/heads/main.zip"
        $zipFile = Join-Path $BaseDir "_dkms-source.zip"
        $ok = Download-File -Url $zipUrl -Output $zipFile -Label "dkms-source.zip"
        if ($ok) {
            Write-Host "  Extracting..." -NoNewline
            try {
                Expand-Archive -Path $zipFile -DestinationPath $BaseDir -Force
                $extracted = Join-Path $BaseDir "mediatek-mt7927-dkms-main"
                if (Test-Path $extracted) {
                    Rename-Item $extracted -NewName "dkms-source" -Force
                }
                Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
                Write-Host " OK" -ForegroundColor Green
            } catch {
                Write-Host " FAILED: $_" -ForegroundColor Red
                $errors++
            }
        } else {
            $errors++
        }
    }
}
Write-Host ""

# ════════════════════════════════════════════════════════
# STEP 4: Download CachyOS packages for offline install
# ════════════════════════════════════════════════════════
Write-Host "[4/$totalSteps] Downloading CachyOS packages (offline install)..." -ForegroundColor Yellow

$pkgDir = Join-Path $BaseDir "packages"
New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null

# Direct package URLs — update these when new versions are released
$packages = @(
    @{
        Name = "dkms"
        Url  = "https://mirror.cachyos.org/repo/x86_64/cachyos/dkms-3.3.0-2-any.pkg.tar.zst"
        File = "dkms-3.3.0-2-any.pkg.tar.zst"
    },
    @{
        Name = "pahole"
        Url  = "https://geo.mirror.pkgbuild.com/extra/os/x86_64/pahole-1%3A1.31-2-x86_64.pkg.tar.zst"
        File = "pahole-1.31-2-x86_64.pkg.tar.zst"
    },
    @{
        Name = "linux-cachyos-headers (6.19)"
        Url  = "https://mirror.cachyos.org/repo/x86_64/cachyos/linux-cachyos-headers-6.19.6-1-x86_64.pkg.tar.zst"
        File = "linux-cachyos-headers-6.19.6-1-x86_64.pkg.tar.zst"
    },
    @{
        Name = "linux-cachyos-lts-headers (6.18)"
        Url  = "https://mirror.cachyos.org/repo/x86_64/cachyos/linux-cachyos-lts-headers-6.18.16-1-x86_64.pkg.tar.zst"
        File = "linux-cachyos-lts-headers-6.18.16-1-x86_64.pkg.tar.zst"
    },
    @{
        Name = "linux-cachyos-bore-headers (6.19)"
        Url  = "https://mirror.cachyos.org/repo/x86_64/cachyos/linux-cachyos-bore-headers-6.19.6-1-x86_64.pkg.tar.zst"
        File = "linux-cachyos-bore-headers-6.19.6-1-x86_64.pkg.tar.zst"
    }
)

foreach ($pkg in $packages) {
    $dest = Join-Path $pkgDir $pkg.File
    if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 1000) {
        $sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Write-Host "  [SKIP] $($pkg.Name) ($sizeMB MB, already exists)" -ForegroundColor Gray
    } else {
        $ok = Download-File -Url $pkg.Url -Output $dest -Label $pkg.Name
        if (-not $ok) { $errors++ }
    }
}
Write-Host ""

# ════════════════════════════════════════════════════════
# STEP 5: Verify
# ════════════════════════════════════════════════════════
Write-Host "[5/$totalSteps] Verifying..." -ForegroundColor Yellow

$checks = @(
    @{ Path = "firmware\mt7925\WIFI_MT7925_PATCH_MCU_1_1_hdr.bin"; Label = "WiFi firmware (MT7925)" },
    @{ Path = "firmware\mt7925\WIFI_RAM_CODE_MT7925_1_1.bin";      Label = "WiFi firmware (MT7925 RAM)" },
    @{ Path = "firmware\mt6639\BT_RAM_CODE_MT6639_2_1_hdr.bin";    Label = "Bluetooth firmware (MT6639)" },
    @{ Path = "firmware-extracted\WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"; Label = "WiFi firmware (MT6639)" },
    @{ Path = "dkms-source\dkms.conf";                             Label = "DKMS driver source" },
    @{ Path = "packages\dkms-3.3.0-2-any.pkg.tar.zst";            Label = "Package: dkms" },
    @{ Path = "packages\linux-cachyos-lts-headers-6.18.16-1-x86_64.pkg.tar.zst"; Label = "Package: headers 6.18 LTS" },
    @{ Path = "packages\linux-cachyos-headers-6.19.6-1-x86_64.pkg.tar.zst"; Label = "Package: headers 6.19" },
    @{ Path = "scripts\install.sh";                                Label = "Installer script" },
    @{ Path = "scripts\test-live.sh";                              Label = "Live test script" }
)

$passed = 0
$failed = 0
foreach ($check in $checks) {
    $fullPath = Join-Path $BaseDir $check.Path
    if ((Test-Path $fullPath) -and (Get-Item $fullPath).Length -gt 0) {
        Write-Host "  [OK]   $($check.Label)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  [MISS] $($check.Label)" -ForegroundColor Red
        $failed++
    }
}

# Total size
$totalSize = 0
Get-ChildItem $BaseDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $totalSize += $_.Length }
$totalMB = [math]::Round($totalSize / 1MB)

# ════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
if ($failed -eq 0) {
    Write-Host "  ALL DONE! ($passed/$($passed + $failed) OK)" -ForegroundColor Green
} else {
    Write-Host "  DONE: $passed OK, $failed FAILED" -ForegroundColor Yellow
}
Write-Host "  Total size: $totalMB MB" -ForegroundColor Gray
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Copy 'mt7927-offline-fix' folder to USB drive" -ForegroundColor White
Write-Host ""
Write-Host "  2. Boot CachyOS Live USB, then TEST first:" -ForegroundColor White
Write-Host "     sudo mount /dev/sda1 /mnt" -ForegroundColor Green
Write-Host "     cd /mnt/mt7927-offline-fix" -ForegroundColor Green
Write-Host "     sudo bash scripts/test-live.sh" -ForegroundColor Green
Write-Host ""
Write-Host "  3. After installing CachyOS, run PERMANENT install:" -ForegroundColor White
Write-Host "     sudo mount /dev/sda1 /mnt" -ForegroundColor Green
Write-Host "     cd /mnt/mt7927-offline-fix" -ForegroundColor Green
Write-Host "     sudo bash scripts/install.sh" -ForegroundColor Green
Write-Host "     sudo reboot" -ForegroundColor Green
Write-Host ""

Read-Host "Press Enter to exit"
