param([switch]$ShowDetailsOnStart)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class AllowanceWindowDrag
{
    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);

    public static void Begin(IntPtr hwnd)
    {
        ReleaseCapture();
        SendMessage(hwnd, 0xA1, new IntPtr(2), IntPtr.Zero);
    }
}

public sealed class TaskbarAllowanceBadge : Form
{
    private string badgeText = "--";
    private bool isStale;

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr handle);

    public TaskbarAllowanceBadge()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(24, 16);
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
    }

    public string BadgeText
    {
        get { return badgeText; }
        set { if (badgeText != value) { badgeText = value; Invalidate(); } }
    }

    public bool IsStale
    {
        get { return isStale; }
        set { if (isStale != value) { isStale = value; Invalidate(); } }
    }

    public bool KeepAboveTaskbar()
    {
        return SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0013);
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams p = base.CreateParams;
            p.ExStyle |= 0x00000020 | 0x00000080 | 0x08000000;
            return p;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.None;
        e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.SingleBitPerPixelGridFit;
        using (Brush background = new SolidBrush(Color.FromArgb(24, 24, 24)))
        {
            e.Graphics.FillRectangle(background, 3, 0, 18, 16);
            e.Graphics.FillRectangle(background, 0, 3, 24, 10);
        }
        int size = badgeText.Length > 2 ? 9 : 11;
        using (Font font = new Font("Segoe UI", size, FontStyle.Bold, GraphicsUnit.Pixel))
        using (Brush text = new SolidBrush(Color.White))
        using (StringFormat format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            e.Graphics.DrawString(badgeText, font, text, new RectangleF(0, 0, 24, 16), format);
        if (isStale)
        {
            using (Brush marker = new SolidBrush(Color.Orange))
                e.Graphics.FillRectangle(marker, 21, 1, 2, 2);
        }
    }
}

public sealed class AllowanceBar : Control
{
    private int valuePercent;
    private bool hasValue;
    private string displayText = "--";
    private Color fillColor = Color.FromArgb(42, 112, 148);
    private int segmentCount = 1;

    public AllowanceBar()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        Height = 23;
        Font = new Font("Segoe UI", 8, FontStyle.Bold);
    }

    public int ValuePercent
    {
        get { return valuePercent; }
        set { valuePercent = Math.Max(0, Math.Min(100, value)); Invalidate(); }
    }

    public bool HasValue
    {
        get { return hasValue; }
        set { hasValue = value; Invalidate(); }
    }

    public string DisplayText
    {
        get { return displayText; }
        set { displayText = value ?? "--"; Invalidate(); }
    }

    public Color FillColor
    {
        get { return fillColor; }
        set { fillColor = value; Invalidate(); }
    }

    public int SegmentCount
    {
        get { return segmentCount; }
        set { segmentCount = Math.Max(1, value); Invalidate(); }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (Width < 2 || Height < 2) return;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Color.FromArgb(30, 30, 30));
        using (GraphicsPath shape = RoundedPath(new Rectangle(0, 0, Width - 1, Height - 1), 5))
        using (Brush track = new SolidBrush(Color.FromArgb(54, 59, 65)))
        using (Brush fill = new SolidBrush(fillColor))
        using (Pen tick = new Pen(Color.FromArgb(110, 20, 24, 30)))
        using (Pen border = new Pen(Color.FromArgb(77, 82, 89)))
        {
            e.Graphics.FillPath(track, shape);
            GraphicsState clipped = e.Graphics.Save();
            e.Graphics.SetClip(shape);
            if (hasValue && valuePercent > 0)
                e.Graphics.FillRectangle(fill, 0, 0, (float)(Width * valuePercent / 100.0), Height);
            for (int index = 1; index < segmentCount; index++)
            {
                float x = Width * index / (float)segmentCount;
                e.Graphics.DrawLine(tick, x, 2, x, Height - 3);
            }
            e.Graphics.Restore(clipped);
            e.Graphics.DrawPath(border, shape);
        }
        using (Brush text = new SolidBrush(Color.White))
        using (StringFormat format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            e.Graphics.DrawString(displayText, Font, text, new RectangleF(2, 0, Width - 4, Height), format);
    }

    private static GraphicsPath RoundedPath(Rectangle rect, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int diameter = radius * 2;
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}
'@

function Get-TaskbarRectangles {
    $found = @{}
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Shell_TrayWnd')
    $taskbar = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    if ($null -eq $taskbar) { return $found }
    $buttons = $taskbar.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($button in $buttons) {
        try {
            if ($button.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
            $name = $button.Current.Name
            foreach ($app in @('Codex', 'Claude', 'ZCode')) {
                if ($name -match "^$app - .*running window") {
                    $found[$app] = $button.Current.BoundingRectangle
                }
            }
        } catch { }
    }
    return $found
}

function New-DetailLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [bool]$Bold = $false)
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X, $Y)
    $label.Size = [System.Drawing.Size]::new($Width, $Height)
    $label.ForeColor = [System.Drawing.Color]::White
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    if ($Bold) {
        $label.Font = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    }
    return $label
}

function Format-LocalTime {
    param($Milliseconds)
    if ($null -eq $Milliseconds -or "$Milliseconds" -eq '') { return 'Unknown' }
    try {
        return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Milliseconds).ToLocalTime().ToString('d MMM, HH:mm')
    } catch { return 'Unknown' }
}

function Get-WeekPassedPercent {
    param($ResetMilliseconds)
    if ($null -eq $ResetMilliseconds -or "$ResetMilliseconds" -eq '') { return $null }
    try {
        $remaining = [long]$ResetMilliseconds - [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $passed = [Math]::Round(100 * (1 - $remaining / [TimeSpan]::FromDays(7).TotalMilliseconds))
        return [int][Math]::Max(0, [Math]::Min(100, $passed))
    } catch { return $null }
}

function Update-TrayDetails {
    $summary = @()
    $notes = @()
    $openCount = 0
    foreach ($app in $apps) {
        $reading = if ($null -ne $data) { $data.($app.ToLowerInvariant()) } else { $null }
        $hasValue = $null -ne $reading -and $null -ne $reading.remainingPercent
        $cached = $hasValue -and [bool]$reading.stale
        $left = if ($hasValue) { "$($reading.remainingPercent)%" } else { '--' }
        $row = $detailRows[$app]
        $row.Remaining.HasValue = $hasValue
        $row.Remaining.ValuePercent = if ($hasValue) { [int]$reading.remainingPercent } else { 0 }
        $row.Remaining.DisplayText = if ($hasValue) { "$left left" } else { '--' }

        $passed = if ($null -ne $reading) { Get-WeekPassedPercent $reading.resetsAt } else { $null }
        $row.Week.HasValue = $null -ne $passed
        $row.Week.ValuePercent = if ($null -ne $passed) { [int]$passed } else { 0 }
        $row.Week.DisplayText = if ($null -ne $passed) {
            "$passed% - $(Format-LocalTime $reading.resetsAt)"
        } else { 'Reset time unavailable' }

        if (-not $badges[$app].Visible) { continue }
        $openCount++
        $summary += "$app $left"
        if (-not $hasValue) { $notes += "$app unavailable" }
        elseif ($cached) { $notes += "$app cached: $(Format-LocalTime $reading.sampledAt)" }
        if ($app -eq 'Claude' -and $null -eq $reading.resetsAt) {
            $notes += 'Claude reset unknown'
        }
    }
    $statusLabel.Text = if ($openCount -eq 0) { 'No tracked apps open.' }
        elseif ($notes.Count) { $notes -join '  |  ' }
        else { 'All readings live.' }
    $tooltip = if ($summary.Count) { $summary -join ' | ' } else { 'No tracked apps open' }
    if ($trayIcon.Text -ne $tooltip) { $trayIcon.Text = $tooltip }
}

function Update-DetailRows {
    $visibleIndex = 0
    foreach ($app in $apps) {
        $row = $detailRows[$app]
        $isOpen = [bool]$badges[$app].Visible
        $row.Label.Visible = $isOpen
        $row.Remaining.Visible = $isOpen
        $row.Week.Visible = $isOpen
        if (-not $isOpen) { continue }

        $y = 41 + $visibleIndex * 36
        $row.Label.Location = [System.Drawing.Point]::new(15, $y)
        $row.Remaining.Location = [System.Drawing.Point]::new(80, $y)
        $row.Week.Location = [System.Drawing.Point]::new(230, $y)
        $visibleIndex++
    }

    $footerY = 41 + $visibleIndex * 36
    $statusLabel.Location = [System.Drawing.Point]::new(15, $footerY)
    $refreshLabel.Location = [System.Drawing.Point]::new(338, $footerY)
    $height = $footerY + 33
    if ($details.ClientSize.Height -ne $height) {
        $oldBottom = $details.Bottom
        $details.ClientSize = [System.Drawing.Size]::new(435, $height)
        if ($details.Visible) {
            $details.Top = $oldBottom - $details.Height
            Save-DetailsPosition
        }
    }
}

function Show-TrayDetails {
    Update-TrayDetails
    if ($details.Visible) { Save-DetailsPosition }
    $details.Location = Get-DetailsStartPosition
    if (-not $details.Visible) { $details.Show() }
    Save-DetailsPosition
    $details.Activate()
}

function Save-DetailsPosition {
    if (-not $details.Visible) { return }
    try {
        [void][System.IO.Directory]::CreateDirectory($dataDirectory)
        $position = @{ x = $details.Left; y = $details.Top; height = $details.Height } | ConvertTo-Json -Compress
        $tempFile = "$detailsPositionFile.tmp"
        [System.IO.File]::WriteAllText($tempFile, $position)
        if (Test-Path -LiteralPath $detailsPositionFile) {
            $backupFile = "$detailsPositionFile.bak"
            [System.IO.File]::Replace($tempFile, $detailsPositionFile, $backupFile)
            [System.IO.File]::Delete($backupFile)
        } else {
            [System.IO.File]::Move($tempFile, $detailsPositionFile)
        }
    } catch { }
}

function Get-DetailsStartPosition {
    $saved = $null
    try {
        if (Test-Path -LiteralPath $detailsPositionFile) {
            $saved = Get-Content -LiteralPath $detailsPositionFile -Raw | ConvertFrom-Json
            if ($null -eq $saved.x -or $null -eq $saved.y) { throw 'Incomplete saved position' }
            $x = [int]$saved.x
            $y = [int]$saved.y
            if ($null -ne $saved.height) { $y += [int]$saved.height - $details.Height }
        }
    } catch { $saved = $null }

    if ($null -eq $saved) {
        $area = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
        return [System.Drawing.Point]::new(
            $area.Right - $details.Width - 12, $area.Bottom - $details.Height - 12)
    }

    $savedRect = [System.Drawing.Rectangle]::new($x, $y, $details.Width, $details.Height)
    $bestScreen = $null
    $visibleArea = 0
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $intersection = [System.Drawing.Rectangle]::Intersect($savedRect, $screen.WorkingArea)
        $area = $intersection.Width * $intersection.Height
        if ($area -gt $visibleArea) {
            $visibleArea = $area
            $bestScreen = $screen
        }
    }
    if ($null -eq $bestScreen) { $bestScreen = [System.Windows.Forms.Screen]::PrimaryScreen }
    $work = $bestScreen.WorkingArea
    if ($visibleArea -eq 0) {
        return [System.Drawing.Point]::new(
            $work.Right - $details.Width - 12, $work.Bottom - $details.Height - 12)
    }
    return [System.Drawing.Point]::new(
        [Math]::Max($work.Left, [Math]::Min($x, $work.Right - $details.Width)),
        [Math]::Max($work.Top, [Math]::Min($y, $work.Bottom - $details.Height)))
}

$dataDirectory = Join-Path $PSScriptRoot 'data'
[void][System.IO.Directory]::CreateDirectory($dataDirectory)
$dataFile = Join-Path $dataDirectory 'allowances.json'
$detailsPositionFile = Join-Path $dataDirectory 'window-position.json'
$pollerPath = Join-Path $PSScriptRoot 'TaskbarAllowancesData.js'
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
$apps = @('Codex', 'Claude', 'ZCode')
$badges = @{}
$misses = @{}
foreach ($app in $apps) {
    $badges[$app] = [TaskbarAllowanceBadge]::new()
    $badges[$app].Hide()
    $misses[$app] = 0
}

$details = [System.Windows.Forms.Form]::new()
$details.Text = 'UsageFairy'
$details.ClientSize = [System.Drawing.Size]::new(435, 182)
$details.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$details.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$details.ShowInTaskbar = $false
$details.TopMost = $true
$details.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$details.ForeColor = [System.Drawing.Color]::White
$details.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$closeButton = [System.Windows.Forms.Button]::new()
$closeButton.Text = [string][char]0x00D7
$closeButton.AccessibleName = 'Close details'
$closeButton.Location = [System.Drawing.Point]::new(405, 7)
$closeButton.Size = [System.Drawing.Size]::new(22, 22)
$closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$closeButton.FlatAppearance.BorderSize = 0
$closeButton.BackColor = $details.BackColor
$closeButton.ForeColor = [System.Drawing.Color]::FromArgb(205, 205, 205)
$closeButton.TabStop = $false
$closeButton.add_MouseEnter({ $closeButton.BackColor = [System.Drawing.Color]::FromArgb(92, 40, 40) })
$closeButton.add_MouseLeave({ $closeButton.BackColor = $details.BackColor })
$closeButton.add_Click({ Save-DetailsPosition; $details.Hide() })
$details.Controls.Add($closeButton)
$beginDetailsDrag = {
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [AllowanceWindowDrag]::Begin($details.Handle)
        Save-DetailsPosition
    }
}
$details.add_MouseDown({
    param($sender, $eventArgs)
    if ($eventArgs.Y -lt 35 -and $eventArgs.X -lt 405) {
        & $beginDetailsDrag $sender $eventArgs
    }
})
$headerLabels = @(
    (New-DetailLabel 'App' 15 13 58 18 $true),
    (New-DetailLabel 'Remaining' 80 13 136 18 $true),
    (New-DetailLabel 'Week elapsed / reset' 230 13 170 18 $true)
)
foreach ($header in $headerLabels) {
    $header.add_MouseDown($beginDetailsDrag)
    $details.Controls.Add($header)
}
$detailRows = @{}
for ($index = 0; $index -lt $apps.Count; $index++) {
    $app = $apps[$index]
    $y = 41 + $index * 36
    $appLabel = New-DetailLabel $app 15 $y 58 23 $true
    $details.Controls.Add($appLabel)
    $remainingBar = [AllowanceBar]::new()
    $remainingBar.Location = [System.Drawing.Point]::new(80, $y)
    $remainingBar.Size = [System.Drawing.Size]::new(136, 23)
    $remainingBar.SegmentCount = 10
    $weekBar = [AllowanceBar]::new()
    $weekBar.Location = [System.Drawing.Point]::new(230, $y)
    $weekBar.Size = [System.Drawing.Size]::new(190, 23)
    $weekBar.SegmentCount = 7
    $weekBar.FillColor = [System.Drawing.Color]::FromArgb(102, 91, 143)
    $details.Controls.Add($remainingBar)
    $details.Controls.Add($weekBar)
    $detailRows[$app] = @{ Label = $appLabel; Remaining = $remainingBar; Week = $weekBar }
}
$statusLabel = New-DetailLabel '' 15 149 310 25
$statusLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(205, 205, 205)
$statusLabel.AutoEllipsis = $true
$details.Controls.Add($statusLabel)
$refreshLabel = New-DetailLabel '30s refresh' 338 149 82 25
$refreshLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8)
$refreshLabel.ForeColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
$refreshLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$details.Controls.Add($refreshLabel)

$iconBitmap = [System.Drawing.Bitmap]::new(16, 16)
$iconGraphics = [System.Drawing.Graphics]::FromImage($iconBitmap)
$iconGraphics.Clear([System.Drawing.Color]::FromArgb(30, 30, 30))
$iconBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
$iconFont = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$iconGraphics.DrawString('%', $iconFont, $iconBrush, 1, 0)
$iconHandle = $iconBitmap.GetHicon()
$iconImage = [System.Drawing.Icon]::FromHandle($iconHandle).Clone()
[void][TaskbarAllowanceBadge]::DestroyIcon($iconHandle)
$iconFont.Dispose()
$iconBrush.Dispose()
$iconGraphics.Dispose()
$iconBitmap.Dispose()

$trayIcon = [System.Windows.Forms.NotifyIcon]::new()
$trayIcon.Icon = $iconImage
$trayIcon.Text = 'UsageFairy - click for details'
$trayMenu = [System.Windows.Forms.ContextMenuStrip]::new()
$openItem = $trayMenu.Items.Add('Show weekly allowances')
$exitItem = $trayMenu.Items.Add('Exit widget')
$trayIcon.ContextMenuStrip = $trayMenu
$running = $true
$trayIcon.add_MouseClick({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-TrayDetails }
})
$openItem.add_Click({ Show-TrayDetails })
$exitItem.add_Click({ $script:running = $false })
$details.add_FormClosing({
    param($sender, $eventArgs)
    if ($script:running) {
        Save-DetailsPosition
        $eventArgs.Cancel = $true
        $sender.Hide()
    }
})
$trayIcon.Visible = $true

$nextPollerCheck = Get-Date
$pollProcess = $null
$data = $null
$lastDataWrite = [DateTime]::MinValue
$pendingDetails = [bool]$ShowDetailsOnStart

try {
    while ($running) {
        $time = Get-Date
        if ($time -ge $nextPollerCheck) {
            $nextPollerCheck = $time.AddSeconds(30)
            $pollerAlive = $null -ne $pollProcess -and
                $null -ne (Get-Process -Id $pollProcess.Id -ErrorAction SilentlyContinue)
            if (-not $pollerAlive) {
                if ($null -ne $pollProcess) { $pollProcess.Dispose() }
                $pollProcess = Start-Process -FilePath $nodePath `
                    -ArgumentList @($pollerPath, '--loop', [string]$PID) `
                    -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru `
                    -RedirectStandardOutput (Join-Path $dataDirectory 'allowances-poll.stdout.log') `
                    -RedirectStandardError (Join-Path $dataDirectory 'allowances-poll.stderr.log')
            }
        }

        try {
            if (Test-Path -LiteralPath $dataFile) {
                $modified = [System.IO.File]::GetLastWriteTimeUtc($dataFile)
                if ($modified -gt $lastDataWrite) {
                    $data = Get-Content -LiteralPath $dataFile -Raw | ConvertFrom-Json
                    $lastDataWrite = $modified
                }
            }
        } catch { }

        try { $rectangles = Get-TaskbarRectangles } catch { $rectangles = @{} }
        foreach ($app in $apps) {
            $badge = $badges[$app]
            $reading = if ($null -ne $data) { $data.($app.ToLowerInvariant()) } else { $null }
            $hasReading = $null -ne $reading -and $null -ne $reading.remainingPercent -and
                $null -ne $reading.sampledAt -and
                ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$reading.sampledAt) -lt 45 * 60 * 1000
            $cachedClaude = $app -eq 'Claude' -and $null -ne $reading -and
                $null -ne $reading.remainingPercent -and [bool]$reading.stale -and
                $null -ne $reading.sampledAt -and
                ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$reading.sampledAt) -lt 12 * 60 * 60 * 1000
            $badge.BadgeText = if ($hasReading -or $cachedClaude) { [string]$reading.remainingPercent } else { '--' }
            $badge.IsStale = $cachedClaude

            $rect = $rectangles[$app]
            if ($null -ne $rect -and -not $rect.IsEmpty) {
                $misses[$app] = 0
                $badge.Location = [System.Drawing.Point]::new(
                    [int]$rect.X + [int](($rect.Width - 24) / 2),
                    [int]$rect.Y + [int]$rect.Height - 17)
                if (-not $badge.Visible) { $badge.Show() }
                [void]$badge.KeepAboveTaskbar()
            } else {
                $misses[$app]++
                if ($misses[$app] -ge 10 -and $badge.Visible) { $badge.Hide() }
            }
        }
        Update-DetailRows
        Update-TrayDetails
        if ($pendingDetails) {
            Show-TrayDetails
            $pendingDetails = $false
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 700
    }
} finally {
    $running = $false
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    $trayMenu.Dispose()
    $details.Close()
    $details.Dispose()
    $iconImage.Dispose()
    if ($null -ne $pollProcess) {
        Stop-Process -Id $pollProcess.Id -ErrorAction SilentlyContinue
        $pollProcess.Dispose()
    }
    foreach ($app in $apps) {
        $badges[$app].Close()
        $badges[$app].Dispose()
    }
}
