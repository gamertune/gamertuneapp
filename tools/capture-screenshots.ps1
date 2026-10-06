#requires -Version 5.1
<#
Captures screenshots of the running app for the README and wiki.

Builds Debug, launches with --show-settings, waits for the FluentWindow to
render, PrintWindow's it once per page. Walks the sidebar via UI Automation
to select each page in turn.

Run from repo root:
    pwsh ./tools/capture-screenshots.ps1
or:
    powershell -ExecutionPolicy Bypass -File tools/capture-screenshots.ps1
#>

param(
    [string]$OutDir = "$PSScriptRoot/../docs/screenshots",
    [string]$Exe = "$PSScriptRoot/../src/GamerTune/bin/Debug/net8.0-windows10.0.22000.0/GamerTune.exe",
    [int]$RenderWaitSeconds = 7,
    [int]$TabRenderWaitMs = 800
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinCap {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr d, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT pvAttr, int cbAttribute);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

[WinCap]::SetProcessDPIAware() | Out-Null

# Copies the window's pixels off the screen. PrintWindow returns a blank frame
# for the software-rendered WPF window, so the window must be visible and in
# front while this runs. DWMWA_EXTENDED_FRAME_BOUNDS (9) gives the visible
# bounds without the invisible resize border / drop shadow.
function Capture-Hwnd([IntPtr]$hwnd, [string]$outPath) {
    [WinCap]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    $rect = New-Object WinCap+RECT
    if ([WinCap]::DwmGetWindowAttribute($hwnd, 9, [ref]$rect, 16) -ne 0 -and
        -not [WinCap]::GetWindowRect($hwnd, [ref]$rect)) {
        Write-Host "Could not read the window bounds for $hwnd"
        return $false
    }
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -le 1 -or $h -le 1) { return $false }

    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))

    $dir = Split-Path -Parent $outPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose(); $g.Dispose()
    Write-Host ("  saved: {0} ({1}x{2})" -f $outPath, $w, $h)
    return $true
}

function Get-AppWindows([int]$processId) {
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $processId)
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
    return @($wins)
}

function Slugify([string]$s) {
    $s = $s.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $s.Trim('-')
}

# Cleanup any prior instance
Get-Process -Name 'GamerTune' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

if (-not (Test-Path $Exe)) {
    Write-Error "Build first: dotnet build -c Debug. Missing: $Exe"
    exit 1
}

Write-Host "Launching app with --show-settings..."
$p = Start-Process -FilePath $Exe -ArgumentList '--show-settings' -PassThru
Start-Sleep -Seconds $RenderWaitSeconds

$wins = Get-AppWindows $p.Id
if ($wins.Count -eq 0) {
    Write-Error "No windows found for pid $($p.Id)"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

$settingsWindow = $null
foreach ($w in $wins) {
    if ($w.Current.Name -like '*Settings*') {
        $settingsWindow = $w
        break
    }
}

if (-not $settingsWindow) {
    Write-Error "No Settings window found among: $($wins | ForEach-Object { $_.Current.Name } | Sort-Object | Get-Unique)"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

$hwnd = [IntPtr]$settingsWindow.Current.NativeWindowHandle
[WinCap]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

# The settings window navigates with a sidebar (WPF-UI NavigationView), one
# page per item. Select each page by its sidebar label and capture it.
$pages = @('Status', 'Gaming', 'Display', 'CPU and power', 'Telemetry', 'Windows AI',
           'Network', 'Debloat', 'Services', 'BIOS', 'General')

function Find-NavItem([System.Windows.Automation.AutomationElement]$root, [string]$name) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    foreach ($el in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
        if ($el.Current.ControlType -ne [System.Windows.Automation.ControlType]::Text) { return $el }
    }
    return $null
}

# NavigationView items expose no Invoke/SelectionItem pattern, so click the
# centre of the item with the mouse.
function Select-NavItem([System.Windows.Automation.AutomationElement]$el) {
    $r = $el.Current.BoundingRectangle
    if ($r.IsEmpty -or $r.Width -le 0) { return $false }
    [WinCap]::SetCursorPos([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2)) | Out-Null
    [WinCap]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)  # left down
    [WinCap]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)  # left up
    return $true
}

# The scrollable content area of the current page: the first element with a
# Scroll pattern under the page Frame (the sidebar has its own scroller).
function Get-PageScroller([System.Windows.Automation.AutomationElement]$root) {
    $frameCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Frame')
    $frame = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $frameCond)
    if (-not $frame) { return $null }
    $scrollCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::IsScrollPatternAvailableProperty, $true)
    $sv = $frame.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $scrollCond)
    if (-not $sv) { return $null }
    return $sv.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
}

# Captures the page top as settings-<page>.png, then one screenful at a time
# down to the bottom as settings-<page>-2.png, -3, ... so long pages are covered.
function Capture-Page([string]$slug) {
    Capture-Hwnd $hwnd (Join-Path $OutDir "settings-$slug.png") | Out-Null
    $scroll = Get-PageScroller $settingsWindow
    if (-not $scroll -or -not $scroll.Current.VerticallyScrollable) { return }
    $n = 2
    while ($scroll.Current.VerticalScrollPercent -lt 99.5 -and $n -le 20) {
        $before = $scroll.Current.VerticalScrollPercent
        $scroll.ScrollVertical([System.Windows.Automation.ScrollAmount]::LargeIncrement)
        Start-Sleep -Milliseconds 400
        if ($scroll.Current.VerticalScrollPercent -le $before) { break }
        Capture-Hwnd $hwnd (Join-Path $OutDir "settings-$slug-$n.png") | Out-Null
        $n++
    }
    $scroll.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll, 0)
}

# Expands the first "Learn more" panel on the current page and captures it, so
# the docs show what the per-setting explanation looks like.
function Capture-LearnMore([string]$slug) {
    $item = Find-NavItem $settingsWindow 'Learn more'
    if (-not $item) { return }
    $p = $null
    if ($item.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$p)) {
        $p.Expand()
    } elseif (-not (Select-NavItem $item)) { return }
    Start-Sleep -Milliseconds 600
    Capture-Hwnd $hwnd (Join-Path $OutDir "settings-$slug-learn-more.png") | Out-Null
}

foreach ($page in $pages) {
    $item = Find-NavItem $settingsWindow $page
    if (-not $item -or -not (Select-NavItem $item)) {
        Write-Host ("  skip page '{0}' (not found or not selectable)" -f $page)
        continue
    }
    Start-Sleep -Milliseconds $TabRenderWaitMs
    $slug = Slugify $page
    Capture-Page $slug
    if ($page -eq 'Gaming') { Capture-LearnMore $slug }
}

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Host "Done."
