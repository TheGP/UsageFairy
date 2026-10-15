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
        using (Brush background = new SolidBrush(Color.FromArgb(24, 24, 24)))
        {
            e.Graphics.FillRectangle(background, 3, 0, 18, 16);
            e.Graphics.FillRectangle(background, 0, 3, 24, 10);
        }
        int size = badgeText.Length > 2 ? 11 : 14;
        using (Font font = new Font("Tahoma", size, FontStyle.Bold, GraphicsUnit.Pixel))
            TextRenderer.DrawText(e.Graphics, badgeText, font, new Rectangle(0, 0, 24, 16),
                Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
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

function Get-AppLogo {
    param([string]$App)
    try {
        $path = switch ($App) {
            'Codex' {
                $package = Get-AppxPackage -Name 'OpenAI.Codex' | Select-Object -First 1
                if ($package) {
                    $logoPath = Join-Path $package.InstallLocation 'assets\Square44x44Logo.png'
                    if (Test-Path -LiteralPath $logoPath -PathType Leaf) {
                        $logo = [System.Drawing.Image]::FromFile($logoPath)
                        try { return [System.Drawing.Bitmap]::new($logo) } finally { $logo.Dispose() }
                    }
                    Join-Path $package.InstallLocation 'app\ChatGPT.exe'
                }
                else {
                    $process = Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue |
                        Where-Object { $_.Path } | Select-Object -First 1
                    if ($process) { $process.Path }
                }
            }
            'Claude' {
                $package = Get-AppxPackage -Name 'Claude' | Select-Object -First 1
                if ($package) { Join-Path $package.InstallLocation 'app\Claude.exe' }
                else {
                    $process = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue |
                        Where-Object { $_.Path } | Select-Object -First 1
                    if ($process) { $process.Path }
                }
            }
            'ZCode' {
                $process = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path } | Select-Object -First 1
                if ($process) { $process.Path }
            }
        }
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
        if ($null -eq $icon) { return $null }
        try { return $icon.ToBitmap() } finally { $icon.Dispose() }
    } catch { return $null }
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

function Read-Settings {
    $current = @{ numberMode = 'used'; barMode = 'used'; minimalPopup = $false }
    try {
        if (Test-Path -LiteralPath $settingsFile) {
            $saved = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
            if ($saved.numberMode -in @('used', 'remaining')) { $current.numberMode = $saved.numberMode }
            if ($saved.barMode -in @('used', 'remaining')) { $current.barMode = $saved.barMode }
            if ($saved.minimalPopup -is [bool]) { $current.minimalPopup = $saved.minimalPopup }
        }
    } catch { }
    return $current
}

function Save-Settings {
    try {
        $tempFile = "$settingsFile.tmp"
        [System.IO.File]::WriteAllText($tempFile, ($settings | ConvertTo-Json -Compress))
        if (Test-Path -LiteralPath $settingsFile) {
            $backupFile = "$settingsFile.bak"
            [System.IO.File]::Replace($tempFile, $settingsFile, $backupFile)
            [System.IO.File]::Delete($backupFile)
        } else {
            [System.IO.File]::Move($tempFile, $settingsFile)
        }
    } catch { }
}

function Apply-Settings {
    $numberUsedItem.Checked = $settings.numberMode -eq 'used'
    $numberRemainingItem.Checked = $settings.numberMode -eq 'remaining'
    $barUsedItem.Checked = $settings.barMode -eq 'used'
    $barRemainingItem.Checked = $settings.barMode -eq 'remaining'
    $minimalItem.Checked = [bool]$settings.minimalPopup

    $minimal = [bool]$settings.minimalPopup
    $details.TransparencyKey = if ($minimal) { [System.Drawing.Color]::FromArgb(1, 1, 1) }
        else { [System.Drawing.Color]::Empty }
    $details.BackColor = if ($minimal) { [System.Drawing.Color]::FromArgb(1, 1, 1) } else {
        [System.Drawing.Color]::FromArgb(30, 30, 30)
    }
    $closeButton.BackColor = $details.BackColor
    $closeButton.Visible = -not $minimal
    foreach ($row in $detailRows.Values) {
        $row.Logo.BackColor = if ($minimal) { [System.Drawing.Color]::FromArgb(42, 42, 42) }
            else { [System.Drawing.Color]::Transparent }
    }
    foreach ($header in $headerLabels) { $header.Visible = -not $minimal }
    $statusLabel.Visible = -not $minimal
    $refreshLabel.Visible = -not $minimal
    Update-DetailRows
    Update-TrayDetails
}

function Update-TrayDetails {
    $summary = @()
    $notes = @()
    $openCount = 0
    foreach ($app in $apps) {
        $reading = if ($null -ne $data) { $data.($app.ToLowerInvariant()) } else { $null }
        $hasValue = $null -ne $reading -and $null -ne $reading.remainingPercent
        $cached = $hasValue -and [bool]$reading.stale
        $usedPercent = if ($hasValue) { 100 - [int]$reading.remainingPercent } else { $null }
        $numberPercent = if ($settings.numberMode -eq 'used') { $usedPercent }
            elseif ($hasValue) { [int]$reading.remainingPercent } else { $null }
        $barPercent = if ($settings.barMode -eq 'used') { $usedPercent }
            elseif ($hasValue) { [int]$reading.remainingPercent } else { $null }
        $display = if ($hasValue) {
            if ($settings.numberMode -eq 'used') { "$numberPercent% used" }
            else { "$numberPercent% left" }
        } else { '--' }
        $row = $detailRows[$app]
        $row.Remaining.HasValue = $hasValue
        $row.Remaining.ValuePercent = if ($hasValue) { [int]$barPercent } else { 0 }
        $row.Remaining.DisplayText = $display

        $passed = if ($null -ne $reading) { Get-WeekPassedPercent $reading.resetsAt } else { $null }
        $row.Week.HasValue = $null -ne $passed
        $row.Week.ValuePercent = if ($null -ne $passed) { [int]$passed } else { 0 }
        $row.Week.DisplayText = if ($null -ne $passed) {
            "$passed% - $(Format-LocalTime $reading.resetsAt)"
        } else { 'Reset time unavailable' }

        if (-not $badges[$app].Visible) { continue }
        $openCount++
        $summary += "$app $display"
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

        if ($isOpen -and $null -eq $row.Logo.Image -and
            (Get-Date) -ge $row.LastLogoAttempt.AddMinutes(1)) {
            $row.LastLogoAttempt = Get-Date
            $row.Logo.Image = Get-AppLogo $app
        }
        $row.Label.Visible = $isOpen -and $null -eq $row.Logo.Image
        $row.Logo.Visible = $isOpen -and $null -ne $row.Logo.Image
        $row.Remaining.Visible = $isOpen
        $row.Week.Visible = $isOpen
        if (-not $isOpen) { continue }

        $y = if ($settings.minimalPopup) { 8 + $visibleIndex * 30 }
            else { 41 + $visibleIndex * 36 }
        $row.Label.Location = [System.Drawing.Point]::new(15, $y)
        $row.Logo.Location = [System.Drawing.Point]::new(32, $y + 1)
        $row.Remaining.Location = [System.Drawing.Point]::new(80, $y)
        $row.Week.Location = [System.Drawing.Point]::new(230, $y)
        $visibleIndex++
    }

    $footerY = if ($settings.minimalPopup) { 8 + $visibleIndex * 30 }
        else { 41 + $visibleIndex * 36 }
    $statusLabel.Location = [System.Drawing.Point]::new(15, $footerY)
    $refreshLabel.Location = [System.Drawing.Point]::new(338, $footerY)
    $height = if ($settings.minimalPopup) { [Math]::Max(24, $footerY + 7) }
        else { $footerY + 33 }
    if ($details.ClientSize.Height -ne $height) {
        $oldBottom = $details.Bottom
        $details.ClientSize = [System.Drawing.Size]::new(435, $height)
        if ($details.Visible) {
            $workArea = [System.Windows.Forms.Screen]::FromRectangle($details.Bounds).WorkingArea
            $left = [Math]::Max($workArea.Left, [Math]::Min($details.Left, $workArea.Right - $details.Width))
            $top = [Math]::Max($workArea.Top, [Math]::Min($oldBottom - $details.Height, $workArea.Bottom - $details.Height))
            $details.Location = [System.Drawing.Point]::new($left, $top)
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

function Toggle-TrayDetails {
    if ($details.Visible) {
        Save-DetailsPosition
        $details.Hide()
    } else {
        Show-TrayDetails
    }
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
$settingsFile = Join-Path $dataDirectory 'settings.json'
$settings = Read-Settings
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
$beginMinimalBarDrag = {
    param($sender, $eventArgs)
    if ($settings.minimalPopup) { & $beginDetailsDrag $sender $eventArgs }
}
$details.add_MouseDown({
    param($sender, $eventArgs)
    $dragHeight = if ($settings.minimalPopup) { 8 } else { 35 }
    $dragWidth = if ($settings.minimalPopup) { 435 } else { 405 }
    if ($eventArgs.Y -lt $dragHeight -and $eventArgs.X -lt $dragWidth) {
        & $beginDetailsDrag $sender $eventArgs
    }
})
$headerLabels = @(
    (New-DetailLabel 'App' 15 13 58 18 $true),
    (New-DetailLabel 'Allowance' 80 13 136 18 $true),
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
    $appLabel.add_MouseDown($beginDetailsDrag)
    $details.Controls.Add($appLabel)
    $appLogo = [System.Windows.Forms.PictureBox]::new()
    $appLogo.Image = Get-AppLogo $app
    $appLogo.Location = [System.Drawing.Point]::new(32, $y + 1)
    $appLogo.Size = [System.Drawing.Size]::new(20, 20)
    $appLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $appLogo.BackColor = [System.Drawing.Color]::Transparent
    $appLogo.AccessibleName = "$app logo"
    $appLogo.add_MouseDown($beginDetailsDrag)
    $details.Controls.Add($appLogo)
    $remainingBar = [AllowanceBar]::new()
    $remainingBar.Location = [System.Drawing.Point]::new(80, $y)
    $remainingBar.Size = [System.Drawing.Size]::new(136, 23)
    $remainingBar.SegmentCount = 10
    $remainingBar.add_MouseDown($beginMinimalBarDrag)
    $weekBar = [AllowanceBar]::new()
    $weekBar.Location = [System.Drawing.Point]::new(230, $y)
    $weekBar.Size = [System.Drawing.Size]::new(190, 23)
    $weekBar.SegmentCount = 7
    $weekBar.FillColor = [System.Drawing.Color]::FromArgb(102, 91, 143)
    $weekBar.add_MouseDown($beginMinimalBarDrag)
    $details.Controls.Add($remainingBar)
    $details.Controls.Add($weekBar)
    $detailRows[$app] = @{
        Label = $appLabel; Logo = $appLogo; Remaining = $remainingBar; Week = $weekBar
        LastLogoAttempt = [DateTime]::MinValue
    }
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
$openItem = $trayMenu.Items.Add('Show or hide details')
$settingsItem = $trayMenu.Items.Add('Settings')
$numberMenu = $settingsItem.DropDownItems.Add('Number on badges and bars')
$numberUsedItem = $numberMenu.DropDownItems.Add('Used')
$numberRemainingItem = $numberMenu.DropDownItems.Add('Remaining')
$barMenu = $settingsItem.DropDownItems.Add('Allowance bar fill')
$barUsedItem = $barMenu.DropDownItems.Add('Used')
$barRemainingItem = $barMenu.DropDownItems.Add('Remaining')
$minimalItem = $settingsItem.DropDownItems.Add('Minimal popup (transparent, no headings or footer)')
$exitItem = $trayMenu.Items.Add('Exit widget')
$trayIcon.ContextMenuStrip = $trayMenu
$running = $true
$trayIcon.add_MouseClick({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Toggle-TrayDetails }
})
$openItem.add_Click({ Toggle-TrayDetails })
$numberUsedItem.add_Click({ $settings.numberMode = 'used'; Save-Settings; Apply-Settings })
$numberRemainingItem.add_Click({ $settings.numberMode = 'remaining'; Save-Settings; Apply-Settings })
$barUsedItem.add_Click({ $settings.barMode = 'used'; Save-Settings; Apply-Settings })
$barRemainingItem.add_Click({ $settings.barMode = 'remaining'; Save-Settings; Apply-Settings })
$minimalItem.add_Click({ $settings.minimalPopup = -not $settings.minimalPopup; Save-Settings; Apply-Settings })
$exitItem.add_Click({ $script:running = $false })
$details.add_FormClosing({
    param($sender, $eventArgs)
    if ($script:running) {
        Save-DetailsPosition
        $eventArgs.Cancel = $true
        $sender.Hide()
    }
})
Apply-Settings
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
            $badge.BadgeText = if ($hasReading -or $cachedClaude) {
                if ($settings.numberMode -eq 'used') { [string](100 - [int]$reading.remainingPercent) }
                else { [string]$reading.remainingPercent }
            } else { '--' }
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
        if ($null -ne $detailRows[$app].Logo.Image) { $detailRows[$app].Logo.Image.Dispose() }
        $badges[$app].Close()
        $badges[$app].Dispose()
    }
}
