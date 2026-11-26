# ChatGPT Switcher Secure (Windows)

A small, source-only PowerShell launcher for separate local ChatGPT Desktop profiles. It uses the installed, signed Microsoft Store application and leaves the existing login untouched. No installer, external packages, credential switching, or background service.

## Requirements

- Windows 10 or 11, Windows PowerShell 5.1.
- Official ChatGPT Desktop from the Microsoft Store.
- An NTFS E: drive.

## Usage

From the checkout, in Windows PowerShell:

```powershell
.\ChatGPT-Switcher.ps1 -Diagnose
.\ChatGPT-Switcher.ps1 -Add dot-1
.\ChatGPT-Switcher.ps1 -Add dot-2
.\ChatGPT-Switcher.ps1 -Launch dot-1
.\ChatGPT-Switcher.ps1 -Launch dot-2
.\ChatGPT-Switcher.ps1 -Status dot-1
.\ChatGPT-Switcher.ps1 -List
```

Sign in separately inside each official ChatGPT window, using accounts and workspace access you are authorized to use. IDs are 1–32 ASCII letters, digits or hyphens. They are normalized to lowercase.

Profile data lives under `E:\ChatGPT-Accounts-Secure`, outside the checkout. The launcher never deletes profile directories, and it does not modify the existing default ChatGPT profile.

## Documentation

If the official Windows app reports "Local Work executor failed to start" because its bundled plugin files cannot be copied, see [Local Work recovery](docs/LOCAL-WORK-RECOVERY.md).

- [Security model](docs/SECURITY.md)
- [Tests and integration validation](docs/VALIDATION.md)
- [Contributing](CONTRIBUTING.md)

This is an unofficial project derived from ChatGPT Switcher under the [MIT license](LICENSE). Separate local directories are not a security sandbox; application compatibility can change after updates.
