# Contributing

Thanks for your interest in improving MT7927 Linux support!

## Ways to Contribute

### Report Your Hardware
If you tested this toolkit on your motherboard, please open an issue with:
- Motherboard model
- MT7927 variant (check with `lspci -nn | grep 14c3`)
- CachyOS/Arch version and kernel
- Result: working / partially working / not working
- Any relevant `dmesg` output

### Bug Reports
Open an issue with:
- Steps to reproduce
- Expected vs actual behavior
- Output of `dmesg | grep -i "mt79\|mt66\|mediatek"`
- Output of `dkms status`
- Kernel version (`uname -r`)

### Code Contributions

1. Fork the repository
2. Create a feature branch: `git checkout -b fix/my-fix`
3. Make your changes
4. Test on actual hardware if possible
5. Submit a pull request

### Guidelines
- Keep scripts POSIX-compatible where possible
- Test with `bash -n script.sh` before committing
- Keep the toolkit beginner-friendly — avoid unnecessary complexity
- Update both README.md (English) and README.id.md (Indonesian) for user-facing changes
- Don't commit firmware binaries or large package files

## Testing Checklist

Before submitting changes to scripts:
- [ ] `bash -n scripts/install.sh` passes
- [ ] `bash -n scripts/test-live.sh` passes
- [ ] `python -m py_compile download-packages.py` passes
- [ ] PowerShell syntax: `powershell -Command "Get-Content download.ps1 | Out-Null"`
- [ ] Tested on CachyOS with MT7927 hardware (if possible)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
