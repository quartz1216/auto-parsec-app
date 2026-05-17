$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerScript = Join-Path $repoRoot "installer\AutoParsec.iss"

$isccCommand = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
if ($isccCommand -ne $null) {
    $isccPath = $isccCommand.Source
}
else {
    $candidate = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (Test-Path $candidate) {
        $isccPath = $candidate
    }
}

if ([string]::IsNullOrWhiteSpace($isccPath)) {
    throw "Inno Setup 6 was not found. Install it, or open installer\AutoParsec.iss in Inno Setup."
}

& $isccPath $installerScript
