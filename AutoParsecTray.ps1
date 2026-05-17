Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$script:AppName = "Auto Parsec"
$script:RunValueName = "AutoParsec"
$script:StartupRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$script:SettingsDir = Join-Path $env:APPDATA "AutoParsec"
$script:SettingsPath = Join-Path $script:SettingsDir "settings.json"
$script:DefaultUserScriptPath = Join-Path $script:SettingsDir "auto-parsec.user.ps1"
$script:TrayScriptPath = $MyInvocation.MyCommand.Path
$script:MonitorProcess = $null
$script:MonitorShouldBeRunning = $false
$script:Settings = $null
$script:NotifyIcon = $null
$script:ApplicationContext = $null
$script:ContextMenu = $null
$script:MonitorTimer = $null

$script:DefaultSettings = [ordered]@{
    StartWithWindows = $false
    AutoStartMonitor = $true
    ScriptPath = "%APPDATA%\AutoParsec\auto-parsec.user.ps1"
    LogFile = ""
    PowerShellExe = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    PowerShellArguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden"
}

function New-SettingsObject {
    $settings = New-Object PSObject
    foreach ($key in $script:DefaultSettings.Keys) {
        $settings | Add-Member -MemberType NoteProperty -Name $key -Value $script:DefaultSettings[$key]
    }
    return $settings
}

function Merge-Settings {
    param(
        [Parameter(Mandatory = $false)]
        [object]$LoadedSettings
    )

    $settings = New-SettingsObject
    if ($LoadedSettings -ne $null) {
        foreach ($property in $LoadedSettings.PSObject.Properties) {
            if ($script:DefaultSettings.Contains($property.Name)) {
                $settings.PSObject.Properties[$property.Name].Value = $property.Value
            }
        }
    }
    return $settings
}

function Save-Settings {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Settings
    )

    if (-not (Test-Path $script:SettingsDir)) {
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    }

    $Settings |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

function Test-StartWithWindows {
    try {
        $properties = Get-ItemProperty -Path $script:StartupRegPath -Name $script:RunValueName -ErrorAction Stop
        $value = $properties.PSObject.Properties[$script:RunValueName].Value
        return -not [string]::IsNullOrWhiteSpace($value)
    }
    catch {
        return $false
    }
}

function Get-PowerShellExe {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Settings
    )

    $configuredPath = Expand-PathValue $Settings.PowerShellExe
    if (-not [string]::IsNullOrWhiteSpace($configuredPath) -and (Test-Path $configuredPath)) {
        return $configuredPath
    }

    return Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
}

function Get-StartupCommand {
    $powershellExe = Get-PowerShellExe $script:Settings
    return ('"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "{1}"' -f $powershellExe, $script:TrayScriptPath)
}

function Set-StartWithWindows {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled,

        [Parameter(Mandatory = $false)]
        [switch]$SkipSave
    )

    if ($Enabled) {
        if (-not (Test-Path $script:StartupRegPath)) {
            New-Item -Path $script:StartupRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $script:StartupRegPath -Name $script:RunValueName -Value (Get-StartupCommand) | Out-Null
    }
    else {
        Remove-ItemProperty -Path $script:StartupRegPath -Name $script:RunValueName -ErrorAction SilentlyContinue
    }

    $script:Settings.StartWithWindows = $Enabled
    if (-not $SkipSave) {
        Save-Settings $script:Settings
    }
}

function Load-Settings {
    if (-not (Test-Path $script:SettingsDir)) {
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    }

    if (Test-Path $script:SettingsPath) {
        try {
            $loadedSettings = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
            $script:Settings = Merge-Settings $loadedSettings
        }
        catch {
            $backupPath = Join-Path $script:SettingsDir ("settings.invalid.{0:yyyyMMddHHmmss}.json" -f (Get-Date))
            Copy-Item -LiteralPath $script:SettingsPath -Destination $backupPath -Force
            $script:Settings = New-SettingsObject
            Save-Settings $script:Settings
            Show-Balloon "Settings reset" "settings.json was invalid. A backup was saved next to it."
        }
    }
    else {
        $script:Settings = New-SettingsObject
        $script:Settings.StartWithWindows = Test-StartWithWindows
        Save-Settings $script:Settings
    }
}

function Expand-PathValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if ([System.IO.Path]::IsPathRooted($expandedPath)) {
        return $expandedPath
    }

    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $expandedPath))
}

function Quote-Argument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Ensure-UserScript {
    $scriptPath = Expand-PathValue $script:Settings.ScriptPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = $script:DefaultUserScriptPath
        $script:Settings.ScriptPath = "%APPDATA%\AutoParsec\auto-parsec.user.ps1"
        Save-Settings $script:Settings
    }

    $scriptDirectory = Split-Path -Parent $scriptPath
    if (-not (Test-Path $scriptDirectory)) {
        New-Item -ItemType Directory -Path $scriptDirectory -Force | Out-Null
    }

    if (-not (Test-Path $scriptPath)) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "auto-parsec.ps1") -Destination $scriptPath -Force
    }

    return $scriptPath
}

function Get-MonitorIsRunning {
    return $script:MonitorProcess -ne $null -and -not $script:MonitorProcess.HasExited
}

function Show-Balloon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($script:NotifyIcon -ne $null) {
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Message
        $script:NotifyIcon.ShowBalloonTip(2500)
    }
}

function Update-MenuState {
    $isRunning = Get-MonitorIsRunning
    $script:StatusItem.Text = if ($isRunning) { "Status: running" } else { "Status: stopped" }
    $script:StartItem.Enabled = -not $isRunning
    $script:StopItem.Enabled = $isRunning
    $script:RestartItem.Enabled = $true
    $script:StartupItem.Checked = Test-StartWithWindows
    $script:NotifyIcon.Text = if ($isRunning) { "Auto Parsec - running" } else { "Auto Parsec - stopped" }
}

function Start-Monitor {
    if (Get-MonitorIsRunning) {
        Update-MenuState
        return
    }

    Load-Settings
    $scriptPath = Ensure-UserScript
    if (-not (Test-Path $scriptPath)) {
        Show-Balloon "Auto Parsec" "The automation script could not be found."
        return
    }

    $powershellExe = Get-PowerShellExe $script:Settings
    $arguments = @()
    if (-not [string]::IsNullOrWhiteSpace($script:Settings.PowerShellArguments)) {
        $arguments += $script:Settings.PowerShellArguments
    }
    $arguments += "-File"
    $arguments += (Quote-Argument $scriptPath)

    $logFile = Expand-PathValue $script:Settings.LogFile
    if (-not [string]::IsNullOrWhiteSpace($logFile)) {
        $arguments += "-LogFile"
        $arguments += (Quote-Argument $logFile)
    }

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $powershellExe
    $processInfo.Arguments = ($arguments -join " ")
    $processInfo.WorkingDirectory = Split-Path -Parent $scriptPath
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $processInfo.EnvironmentVariables["AUTO_PARSEC_HOME"] = $PSScriptRoot

    try {
        $script:MonitorProcess = [System.Diagnostics.Process]::Start($processInfo)
        $script:MonitorShouldBeRunning = $true
        Show-Balloon "Auto Parsec" "Monitoring started."
    }
    catch {
        Show-Balloon "Auto Parsec" ("Failed to start monitoring: {0}" -f $_.Exception.Message)
    }

    Update-MenuState
}

function Stop-Monitor {
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    $script:MonitorShouldBeRunning = $false
    if (Get-MonitorIsRunning) {
        try {
            $script:MonitorProcess.Kill()
            $script:MonitorProcess.WaitForExit(3000) | Out-Null
            if (-not $Silent) {
                Show-Balloon "Auto Parsec" "Monitoring stopped."
            }
        }
        catch {
            if (-not $Silent) {
                Show-Balloon "Auto Parsec" ("Failed to stop monitoring: {0}" -f $_.Exception.Message)
            }
        }
    }

    $script:MonitorProcess = $null
    Update-MenuState
}

function Restart-Monitor {
    Stop-Monitor -Silent
    Start-Monitor
}

function Open-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    Start-Process -FilePath "notepad.exe" -ArgumentList (Quote-Argument $Path)
}

function Open-SettingsFile {
    Save-Settings $script:Settings
    Open-TextFile $script:SettingsPath
}

function Open-AutomationScript {
    $scriptPath = Ensure-UserScript
    Open-TextFile $scriptPath
}

function Open-SettingsFolder {
    if (-not (Test-Path $script:SettingsDir)) {
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    }
    Start-Process -FilePath "explorer.exe" -ArgumentList (Quote-Argument $script:SettingsDir)
}

function Reload-AppSettings {
    Load-Settings
    Ensure-UserScript | Out-Null
    Set-StartWithWindows -Enabled ([bool]$script:Settings.StartWithWindows) -SkipSave
    Save-Settings $script:Settings
    Show-Balloon "Auto Parsec" "Settings reloaded."
    Update-MenuState
}

function Exit-Application {
    Stop-Monitor -Silent
    $script:NotifyIcon.Visible = $false
    $script:NotifyIcon.Dispose()
    $script:ApplicationContext.ExitThread()
}

function New-MenuItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [scriptblock]$Click,

        [Parameter(Mandatory = $false)]
        [bool]$Enabled = $true,

        [Parameter(Mandatory = $false)]
        [bool]$CheckOnClick = $false
    )

    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $Text
    $item.Enabled = $Enabled
    $item.CheckOnClick = $CheckOnClick

    if ($Click -ne $null) {
        $item.add_Click($Click)
    }

    return $item
}

function Initialize-Tray {
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $script:ApplicationContext = New-Object System.Windows.Forms.ApplicationContext
    $script:ContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon

    $script:StatusItem = New-MenuItem "Status: stopped" $null $false
    $script:StartItem = New-MenuItem "Start monitoring" { Start-Monitor }
    $script:StopItem = New-MenuItem "Stop monitoring" { Stop-Monitor }
    $script:RestartItem = New-MenuItem "Restart monitoring" { Restart-Monitor }
    $script:SettingsItem = New-MenuItem "Open settings.json" { Open-SettingsFile }
    $script:AutomationScriptItem = New-MenuItem "Edit automation script" { Open-AutomationScript }
    $script:SettingsFolderItem = New-MenuItem "Open settings folder" { Open-SettingsFolder }
    $script:StartupItem = New-MenuItem "Start with Windows" {
        Set-StartWithWindows -Enabled (-not (Test-StartWithWindows))
        Update-MenuState
    } $true $false
    $script:ReloadItem = New-MenuItem "Reload settings" { Reload-AppSettings }
    $script:ExitItem = New-MenuItem "Exit" { Exit-Application }

    [void]$script:ContextMenu.Items.Add($script:StatusItem)
    [void]$script:ContextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:ContextMenu.Items.Add($script:StartItem)
    [void]$script:ContextMenu.Items.Add($script:StopItem)
    [void]$script:ContextMenu.Items.Add($script:RestartItem)
    [void]$script:ContextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:ContextMenu.Items.Add($script:SettingsItem)
    [void]$script:ContextMenu.Items.Add($script:AutomationScriptItem)
    [void]$script:ContextMenu.Items.Add($script:SettingsFolderItem)
    [void]$script:ContextMenu.Items.Add($script:StartupItem)
    [void]$script:ContextMenu.Items.Add($script:ReloadItem)
    [void]$script:ContextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:ContextMenu.Items.Add($script:ExitItem)

    $script:ContextMenu.add_Opening({ Update-MenuState })
    $script:NotifyIcon.Text = "Auto Parsec"
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    $script:NotifyIcon.ContextMenuStrip = $script:ContextMenu
    $script:NotifyIcon.Visible = $true
    $script:NotifyIcon.add_DoubleClick({ Open-SettingsFile })

    $script:MonitorTimer = New-Object System.Windows.Forms.Timer
    $script:MonitorTimer.Interval = 3000
    $script:MonitorTimer.add_Tick({
        if ($script:MonitorProcess -ne $null -and $script:MonitorProcess.HasExited) {
            $script:MonitorProcess.Dispose()
            $script:MonitorProcess = $null
            $script:MonitorShouldBeRunning = $false
        }
        Update-MenuState
    })
    $script:MonitorTimer.Start()

    Update-MenuState
}

Load-Settings
Ensure-UserScript | Out-Null
Set-StartWithWindows -Enabled ([bool]$script:Settings.StartWithWindows) -SkipSave
Initialize-Tray

if ([bool]$script:Settings.AutoStartMonitor) {
    Start-Monitor
}

[System.Windows.Forms.Application]::Run($script:ApplicationContext)
