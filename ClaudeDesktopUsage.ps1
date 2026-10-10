param([switch]$PeekIfIdle)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClaudePeekGuard
{
    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo { public uint Size; public uint Tick; }

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LastInputInfo info);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    public static uint LastInputTick()
    {
        var info = new LastInputInfo { Size = (uint)Marshal.SizeOf(typeof(LastInputInfo)) };
        return GetLastInputInfo(ref info) ? info.Tick : 0;
    }

    public static uint IdleMilliseconds()
    {
        var last = LastInputTick();
        return last == 0 ? 0 : unchecked((uint)Environment.TickCount) - last;
    }

    public static bool MouseButtonDown()
    {
        return GetAsyncKeyState(1) < 0 || GetAsyncKeyState(2) < 0 || GetAsyncKeyState(4) < 0;
    }
}
'@

function Read-ClaudeUsage {
    param([System.Windows.Automation.AutomationElement]$Window)

    $elements = $Window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    $names = [System.Collections.Generic.List[string]]::new()
    $used = $null
    foreach ($element in $elements) {
        try {
            if ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text) {
                $names.Add($element.Current.Name)
            }
            if ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::ProgressBar -and
                $element.Current.Name -match '^Weekly.*all models$') {
                $range = $element.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
                $used = [double]$range.Current.Value
            }
        } catch { }
    }

    $resetLabel = $null
    if ($null -ne $used) {
        foreach ($name in $names) {
            if ($name -match '^Resets (Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d{1,2}:\d{2} [AP]M$') {
                $resetLabel = $name
                break
            }
        }
    } elseif ($names -contains 'Your usage') {
        for ($index = 0; $index -lt $names.Count; $index++) {
            $name = $names[$index]
            if ($name -match '(\d+(?:\.\d+)?)% of your weekly limit used') {
                $used = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
            }
            if ($name -match '^Resets (Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) \d{1,2}:\d{2} [AP]M$') {
                $resetLabel = $name
                if ($null -eq $used -and $index + 1 -lt $names.Count) {
                    foreach ($candidate in $names[($index + 1)..([Math]::Min($index + 5, $names.Count - 1))]) {
                        if ($candidate -match '^(\d+(?:\.\d+)?)% used$') {
                            $used = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
                            break
                        }
                    }
                }
            }
        }
    }
    if ($null -eq $used) { return $null }
    return @{ usedPercent = $used; resetLabel = $resetLabel }
}

try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::NameProperty, 'Claude')
    $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    if ($null -eq $window) { exit 1 }

    $reading = Read-ClaudeUsage $window
    $peekAttempted = $false
    if ($null -eq $reading -and $PeekIfIdle -and
        [ClaudePeekGuard]::GetForegroundWindow() -eq [IntPtr]$window.Current.NativeWindowHandle -and
        [ClaudePeekGuard]::IdleMilliseconds() -ge 15000 -and
        -not [ClaudePeekGuard]::MouseButtonDown()) {
        $elements = $window.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($element in $elements) {
            try {
                if ($element.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button -or
                    $element.Current.Name -notlike 'Usage: Context*') { continue }
                $popover = $element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                if ($popover.Current.ExpandCollapseState -ne
                    [System.Windows.Automation.ExpandCollapseState]::Collapsed) { break }
                $lastInput = [ClaudePeekGuard]::LastInputTick()
                $peekAttempted = $true
                try {
                    $popover.Expand()
                    Start-Sleep -Milliseconds 300
                    if ([ClaudePeekGuard]::LastInputTick() -eq $lastInput -and
                        [ClaudePeekGuard]::GetForegroundWindow() -eq [IntPtr]$window.Current.NativeWindowHandle) {
                        $reading = Read-ClaudeUsage $window
                    }
                } finally {
                    if ([ClaudePeekGuard]::LastInputTick() -eq $lastInput -and
                        [ClaudePeekGuard]::GetForegroundWindow() -eq [IntPtr]$window.Current.NativeWindowHandle) {
                        try { $popover.Collapse() } catch { }
                    }
                }
                break
            } catch { break }
        }
    }

    if ($null -eq $reading -and -not $peekAttempted) { exit 1 }
    $usedPercent = if ($null -ne $reading) { $reading.usedPercent } else { $null }
    $resetLabel = if ($null -ne $reading) { $reading.resetLabel } else { $null }
    @{ usedPercent = $usedPercent; resetLabel = $resetLabel
       sampledAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
       autoPeeked = $peekAttempted } | ConvertTo-Json -Compress
} catch { exit 1 }
