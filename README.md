# auto-parsec
[![Powershell 5.1](https://github.com/Borgotto/quick-parsec-deploy/actions/workflows/powershell-test.yml/badge.svg)](https://github.com/Borgotto/quick-parsec-deploy/actions/workflows/powershell-test.yml)&nbsp;

A simple PowerShell tray app intended to be used with [Parsec](https://parsec.app/) to automate stuff on the host computer when a client connects to it.

It can be used to start a game, launch a program, automatically accept connection requests or anything else you can think of.

##

### Usage:

1. Clone the repo or install it with the installer.
2. Run `AutoParsecTray.vbs`, or use the Start Menu shortcut created by the installer.
3. Use the tray icon to start/stop monitoring, open `settings.json`, edit the automation script, reload settings, or toggle Windows startup.

`AutoParsecTray.vbs` launches the PowerShell tray app without leaving a terminal window open. `AutoParsecTray.ps1` is the app body and is still useful for debugging.

On first launch, Auto Parsec creates:

- `%APPDATA%\AutoParsec\settings.json`
- `%APPDATA%\AutoParsec\auto-parsec.user.ps1`

Edit `auto-parsec.user.ps1` for your `OnConnect`, `OnDisconnect`, and `OnConnectAttempt` hooks. The tray app runs that script hidden in the background.

`settings.json` supports:

- `StartWithWindows`: registers/unregisters the tray app in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- `AutoStartMonitor`: starts monitoring automatically when the tray app opens.
- `ScriptPath`: automation script path. Environment variables such as `%APPDATA%` are supported.
- `LogFile`: optional Parsec log path override. Leave empty to auto-detect.
- `PowerShellExe` and `PowerShellArguments`: runtime used for the hidden automation process.

If your automation script needs the bundled modules, use `$env:AUTO_PARSEC_HOME`:

```powershell
Import-Module "$env:AUTO_PARSEC_HOME\modules\key_presses.psm1"
```

### Installer:

Inno Setup 6 is used for the installer. Build it with:

```powershell
.\tools\build-installer.ps1
```

The generated installer is written to `output\AutoParsecSetup.exe`.

##

### Contributing:

I've implemented a few scripts that I use myself, but feel free to make your own and create a pull request to add them to the repository.

Ideally they're all going to have one or more [modules](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules) and a working `example.ps1` script
