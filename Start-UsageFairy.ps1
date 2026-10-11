$ErrorActionPreference = 'Stop'

$dataDirectory = Join-Path $PSScriptRoot 'data'
$logPath = Join-Path $dataDirectory 'startup.log'
try { [void][System.IO.Directory]::CreateDirectory($dataDirectory) } catch { }

function Write-StartupLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) PID $PID $Message"
    } catch { }
}

Write-StartupLog 'started'
try {
    & (Join-Path $PSScriptRoot 'TaskbarAllowances.ps1') -ShowDetailsOnStart
    Write-StartupLog 'stopped'
} catch {
    Write-StartupLog "failed: $($_.Exception.Message); $($_.ScriptStackTrace)"
    throw
}
