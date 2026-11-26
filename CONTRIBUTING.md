# Contributing

Keep this launcher small and compatible with Windows PowerShell 5.1. Do not read, copy, replace, log or transmit credentials. Do not add remote installation, token switching, or automatic profile deletion.

Run the regression suite before committing:

```powershell
.\tests\Regression.ps1
```

The suite uses synthetic profile directories and does not launch ChatGPT or access existing session data. For the additional integration checks, see [docs/VALIDATION.md](docs/VALIDATION.md).
