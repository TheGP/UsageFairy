$ErrorActionPreference = 'Stop'

$widgetPath = Join-Path $PSScriptRoot 'TaskbarAllowances.ps1'
if (-not (Test-Path -LiteralPath $widgetPath -PathType Leaf)) {
    throw "UsageFairy script not found: $widgetPath"
}

$startupDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
[void][System.IO.Directory]::CreateDirectory($startupDirectory)
$shortcutPath = Join-Path $startupDirectory 'UsageFairy.lnk'
$powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shell = New-Object -ComObject WScript.Shell

$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powerShellPath
$shortcut.Arguments = '-NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $widgetPath + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'UsageFairy weekly allowance badges'
$shortcut.Save()

# Retire the previous shortcut only when it belongs to this checkout.
$previousPath = Join-Path $startupDirectory 'Widget Allowances.lnk'
if (Test-Path -LiteralPath $previousPath -PathType Leaf) {
    $previous = $shell.CreateShortcut($previousPath)
    if ($previous.TargetPath -ieq $powerShellPath -and
        $previous.WorkingDirectory -ieq $PSScriptRoot -and
        $previous.Arguments.Contains($widgetPath)) {
        Remove-Item -LiteralPath $previousPath
    }
}

Write-Output "UsageFairy starts with Windows: $shortcutPath"
