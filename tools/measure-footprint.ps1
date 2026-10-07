#requires -Version 5.1
<#
Measures GamerTune's footprint -- the numbers the README and docs/PERFORMANCE.md
quote. Run it against every build that is about to ship.

Phase 1, tray only: starts the build in the tray (no window), lets it settle,
then samples it for a few minutes.
Phase 2, settings window: restarts the build with --show-settings, clicks
through every sidebar page the way a user browsing the app would, records the
peak, closes the window, and samples the tray again.

For each phase it prints:
  - Working set: median / min / max. The app trims itself every 5 polling
    ticks (~2.5 min at the default 30 s interval) by pushing its pages out of
    RAM, so working set rises and falls between trims; the median over several
    trim cycles is the honest "idle" figure, not one reading.
  - Private memory (committed): what the app has reserved, whether or not it is
    in RAM right now. Trimming does not reduce this; it is the closest single
    number to the app's real memory cost.
  - CPU time per polling tick: all of the app's CPU in the window divided by
    the number of fast ticks in it -- an upper bound on the cost of one tick.

Only one GamerTune can run at a time (single-instance mutex), so any running
copy is stopped first and restarted (in the tray) afterwards. Phase 2 moves the
mouse to click the sidebar: leave the mouse alone while it runs.

Run from repo root:
    powershell -ExecutionPolicy Bypass -File tools/measure-footprint.ps1
    powershell -ExecutionPolicy Bypass -File tools/measure-footprint.ps1 -Exe publish\GamerTune.exe
#>

param(
    [string]$Exe = "$env:LOCALAPPDATA\Programs\GamerTune\GamerTune.exe",
    [int]$WarmupSeconds = 60,
    [int]$SampleMinutes = 6,
    [int]$AfterSettingsMinutes = 4,
    [int]$SampleSeconds = 5,
    [int]$PollSeconds = 30,
    [switch]$SkipSettingsPhase
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Error "Build not found: $Exe"; exit 1 }
$Exe = (Resolve-Path $Exe).Path

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FpInput {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
"@
[FpInput]::SetProcessDPIAware() | Out-Null

function Get-Median([double[]]$values) {
    $s = @($values | Sort-Object)
    $n = $s.Count
    if ($n -eq 0) { return 0 }
    if ($n % 2) { return $s[($n - 1) / 2] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

# Samples the process for $minutes and summarises working set, private memory
# and CPU per polling tick.
function Measure-Window([System.Diagnostics.Process]$proc, [double]$minutes) {
    $ws = New-Object System.Collections.Generic.List[double]
    $priv = New-Object System.Collections.Generic.List[double]
    $proc.Refresh()
    $cpuStart = $proc.TotalProcessorTime
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalMinutes -lt $minutes) {
        $proc.Refresh()
        if ($proc.HasExited) { throw 'The app exited while being measured.' }
        $ws.Add($proc.WorkingSet64 / 1MB)
        $priv.Add($proc.PrivateMemorySize64 / 1MB)
        Start-Sleep -Seconds $SampleSeconds
    }
    $proc.Refresh()
    $cpuMs = ($proc.TotalProcessorTime - $cpuStart).TotalMilliseconds
    $ticks = [math]::Max(1, [math]::Floor($clock.Elapsed.TotalSeconds / $PollSeconds))
    $w = $ws.ToArray(); $pr = $priv.ToArray()
    [pscustomobject]@{
        WsMedianMB      = [math]::Round((Get-Median $w), 1)
        WsMinMB         = [math]::Round(($w | Measure-Object -Minimum).Minimum, 1)
        WsMaxMB         = [math]::Round(($w | Measure-Object -Maximum).Maximum, 1)
        PrivateMedianMB = [math]::Round((Get-Median $pr), 1)
        CpuMsPerTick    = [math]::Round($cpuMs / $ticks, 1)
        Ticks           = $ticks
    }
}

function Start-App([string]$arguments) {
    Get-Process -Name 'GamerTune' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    return Start-Process -FilePath $Exe -ArgumentList $arguments -PassThru
}

# The sidebar items expose no Invoke pattern; click the centre of each one.
function Click-NavItem([System.Windows.Automation.AutomationElement]$window, [string]$name) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    foreach ($el in $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
        if ($el.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text) { continue }
        $r = $el.Current.BoundingRectangle
        if ($r.IsEmpty -or $r.Width -le 0) { continue }
        [FpInput]::SetCursorPos([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2)) | Out-Null
        [FpInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        [FpInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        return $true
    }
    return $false
}

$previous = @(Get-Process -Name 'GamerTune' -ErrorAction SilentlyContinue |
              ForEach-Object { $_.Path } | Where-Object { $_ } | Select-Object -Unique)
$version = (Get-Item $Exe).VersionInfo.ProductVersion
$exeMB = [math]::Round((Get-Item $Exe).Length / 1MB, 1)
Write-Host "Measuring $Exe ($version, $exeMB MB on disk)"

$p = $null
try {
    # ---- Phase 1: tray only ----
    Write-Host "Phase 1: tray only -- warm-up ${WarmupSeconds}s, then ${SampleMinutes} min of samples..."
    $p = Start-App '--tray'
    Start-Sleep -Seconds $WarmupSeconds
    $tray = Measure-Window $p $SampleMinutes

    $settingsPeakWs = $null; $settingsPeakPriv = $null; $after = $null
    if (-not $SkipSettingsPhase) {
        # ---- Phase 2: settings window ----
        Write-Host "Phase 2: settings window -- opening and clicking through every page (leave the mouse alone)..."
        $p = Start-App '--show-settings'
        Start-Sleep -Seconds 10
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
        $win = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
            [System.Windows.Automation.TreeScope]::Children, $cond)
        if (-not $win) { throw 'The settings window did not open.' }
        [FpInput]::SetForegroundWindow([IntPtr]$win.Current.NativeWindowHandle) | Out-Null
        $peakWs = 0.0; $peakPriv = 0.0
        foreach ($page in 'Status', 'Gaming', 'Display', 'CPU and power', 'Telemetry', 'Windows AI',
                          'Network', 'Debloat', 'Services', 'BIOS', 'General') {
            Click-NavItem $win $page | Out-Null
            Start-Sleep -Milliseconds 1500
            $p.Refresh()
            $peakWs = [math]::Max($peakWs, $p.WorkingSet64 / 1MB)
            $peakPriv = [math]::Max($peakPriv, $p.PrivateMemorySize64 / 1MB)
        }
        $settingsPeakWs = [math]::Round($peakWs, 1); $settingsPeakPriv = [math]::Round($peakPriv, 1)

        # Close the window (the X button); the app stays in the tray.
        $wp = $win.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
        $wp.Close()
        Start-Sleep -Seconds 15
        $after = Measure-Window $p $AfterSettingsMinutes
    }

    $result = [ordered]@{
        Version                     = $version
        ExeSizeMB                   = $exeMB
        TrayWsMedianMB              = $tray.WsMedianMB
        TrayWsRangeMB               = "$($tray.WsMinMB)-$($tray.WsMaxMB)"
        TrayPrivateMedianMB         = $tray.PrivateMedianMB
        TrayCpuMsPerTick            = $tray.CpuMsPerTick
    }
    if ($after) {
        $result.SettingsPeakWsMB          = $settingsPeakWs
        $result.SettingsPeakPrivateMB     = $settingsPeakPriv
        $result.AfterSettingsWsMedianMB   = $after.WsMedianMB
        $result.AfterSettingsPrivateMB    = $after.PrivateMedianMB
        $result.AfterSettingsCpuMsPerTick = $after.CpuMsPerTick
    }
    [pscustomobject]$result | Format-List
}
finally {
    Get-Process -Name 'GamerTune' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    foreach ($path in $previous) {
        Start-Process -FilePath $path -ArgumentList '--tray' | Out-Null
        Write-Host "Restarted: $path"
    }
}
