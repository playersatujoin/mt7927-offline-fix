#!/usr/bin/env python3
"""
MT7927 Offline Fix - Package Downloader
Downloads CachyOS/Arch packages for 100% offline DKMS install.

Usage: python download-packages.py
"""

import os
import sys
import tarfile
import io
import urllib.request
import ssl
from pathlib import Path

try:
    import pyzstd
except ImportError:
    print("ERROR: pyzstd belum terinstall!")
    print("Jalankan: pip install pyzstd")
    sys.exit(1)

BASE_DIR = Path(__file__).parent
PKG_DIR = BASE_DIR / "packages"

# Repository definitions: (name, db_url, pkg_base_url, db_format)
REPOS = [
    (
        "cachyos",
        "https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos.db",
        "https://mirror.cachyos.org/repo/x86_64/cachyos",
        "zst",
    ),
    (
        "cachyos-v3",
        "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/cachyos-v3.db",
        "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3",
        "zst",
    ),
    (
        "extra",
        "https://geo.mirror.pkgbuild.com/extra/os/x86_64/extra.db.tar.gz",
        "https://geo.mirror.pkgbuild.com/extra/os/x86_64",
        "gz",
    ),
]

# Packages to download (exact name match)
WANTED = [
    "dkms",
    "linux-cachyos-headers",
    "linux-cachyos-bore-headers",
    "pahole",
]


def make_ssl_context():
    ctx = ssl.create_default_context()
    return ctx


def download_bytes(url, timeout=60):
    ctx = make_ssl_context()
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return resp.read()
    except Exception as e:
        return None


def download_to_file(url, filepath, timeout=300):
    ctx = make_ssl_context()
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            with open(filepath, "wb") as f:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total > 0:
                        pct = downloaded * 100 // total
                        bar = "#" * (pct // 5) + "-" * (20 - pct // 5)
                        mb_done = downloaded / (1024 * 1024)
                        mb_total = total / (1024 * 1024)
                        print(
                            f"\r    [{bar}] {pct}% ({mb_done:.1f}/{mb_total:.1f} MB)",
                            end="",
                            flush=True,
                        )
            print()
            return True
    except Exception as e:
        print(f"\n    GAGAL: {e}")
        return False


def decompress_db(raw_data, fmt):
    """Decompress repo database to tar bytes."""
    if fmt == "zst":
        return pyzstd.decompress(raw_data)
    else:
        # gz - return as-is, tarfile can handle it
        return raw_data


def parse_repo_db(raw_data, fmt, repo_name):
    """Parse a pacman repo database and return {name: info} dict."""
    packages = {}
    try:
        if fmt == "zst":
            tar_bytes = pyzstd.decompress(raw_data)
            tar_fobj = io.BytesIO(tar_bytes)
            tar = tarfile.open(fileobj=tar_fobj, mode="r:")
        else:
            tar_fobj = io.BytesIO(raw_data)
            tar = tarfile.open(fileobj=tar_fobj, mode="r:gz")

        for member in tar.getmembers():
            if member.name.endswith("/desc"):
                f = tar.extractfile(member)
                if f:
                    content = f.read().decode("utf-8", errors="replace")
                    info = parse_desc(content)
                    if info.get("name"):
                        packages[info["name"]] = info
        tar.close()
    except Exception as e:
        print(f"  Warning: parse error for {repo_name}: {e}")
    return packages


def parse_desc(content):
    """Parse a pacman desc file into dict."""
    sections = {}
    current_key = None
    for line in content.split("\n"):
        line = line.strip()
        if line.startswith("%") and line.endswith("%"):
            current_key = line[1:-1].lower()
            sections[current_key] = []
        elif line and current_key is not None:
            sections[current_key].append(line)

    return {
        "name": sections.get("name", [""])[0],
        "version": sections.get("version", [""])[0],
        "filename": sections.get("filename", [""])[0],
        "csize": sections.get("csize", ["0"])[0],
        "desc": " ".join(sections.get("desc", [""])),
    }


def main():
    print("=" * 58)
    print("  MT7927 Offline Fix - CachyOS Package Downloader")
    print("=" * 58)
    print()

    # ── Step 1: Fetch & parse repo databases ──
    print("[1/3] Mengunduh database repositori...")
    all_packages = {}  # name -> (info, repo_name, pkg_base_url)

    for repo_name, db_url, pkg_base_url, db_fmt in REPOS:
        print(f"  {repo_name}: ", end="", flush=True)
        raw = download_bytes(db_url)
        if raw is None:
            print("GAGAL download")
            continue
        pkgs = parse_repo_db(raw, db_fmt, repo_name)
        print(f"OK ({len(pkgs)} paket)")
        for name, info in pkgs.items():
            if name not in all_packages:
                all_packages[name] = (info, repo_name, pkg_base_url)

    if not all_packages:
        print("\nERROR: Tidak ada database yang berhasil diambil!")
        sys.exit(1)

    # ── Step 2: Resolve wanted packages ──
    print(f"\n[2/3] Mencari paket yang dibutuhkan...")
    to_download = []

    for pkg_name in WANTED:
        if pkg_name in all_packages:
            info, repo, base_url = all_packages[pkg_name]
            size_mb = int(info["csize"]) / (1024 * 1024)
            print(f"  [OK]   {pkg_name} {info['version']} ({repo}) [{size_mb:.1f} MB]")
            to_download.append((info, base_url))
        else:
            print(f"  [SKIP] {pkg_name} - tidak ada di repo (mungkin kernel variant lain)")

    if not to_download:
        print("\nTidak ada paket untuk diunduh.")
        sys.exit(0)

    # ── Step 3: Download packages ──
    total_pkgs = len(to_download)
    print(f"\n[3/3] Mengunduh {total_pkgs} paket...")
    PKG_DIR.mkdir(exist_ok=True)

    ok_count = 0
    fail_count = 0

    for info, base_url in to_download:
        filename = info["filename"]
        url = f"{base_url}/{filename}"
        dest = PKG_DIR / filename

        if dest.exists():
            print(f"  [SKIP] {filename} (sudah ada)")
            ok_count += 1
            continue

        print(f"  Downloading {filename}...")
        if download_to_file(url, str(dest)):
            ok_count += 1
        else:
            fail_count += 1

    # ── Summary ──
    print()
    print("=" * 58)
    if fail_count == 0:
        print(f"  SELESAI! {ok_count} paket berhasil diunduh.")
    else:
        print(f"  SELESAI: {ok_count} OK, {fail_count} GAGAL")
    print("=" * 58)
    print()

    if PKG_DIR.exists():
        total_size = 0
        print("  Isi folder packages/:")
        for f in sorted(PKG_DIR.iterdir()):
            if f.is_file():
                sz = f.stat().st_size
                total_size += sz
                print(f"    {f.name}  ({sz / (1024*1024):.1f} MB)")
        print(f"\n  Total: {total_size / (1024*1024):.1f} MB")

    print()
    print("  Paket ini akan diinstall offline oleh: sudo bash scripts/install.sh")
    print()


if __name__ == "__main__":
    main()
