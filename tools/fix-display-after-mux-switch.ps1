<#
.SYNOPSIS
    Repair the duplicate display path that Windows creates after a MUX switch
    (Optimus <-> NVIDIA GPU only) on gaming laptops.

.DESCRIPTION
    After the panel changes owner, Windows can keep the OLD display path alive
    next to the new one. Device Manager then shows two monitor devices with
    status OK for a single physical panel, and Desktop Window Manager
    composites every frame twice - once per adapter.

    Symptoms: dwm.exe burns 30-50% of one CPU core on an idle desktop, typing
    lands late, scrolling and window animations feel uneven, nothing freezes.

    Fix: disable and re-enable the integrated GPU so Windows tears down the
    stale path and re-enumerates. No drivers are removed; the adapter comes
    back on its own.

.PARAMETER MeasureOnly
    Report the state and exit. Changes nothing.

.PARAMETER Quiet
    Only produce output when something is wrong or a repair was performed.
    Used by the logon watchdog.

.PARAMETER Force
    Run the repair even if the health check looks fine.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\fix-display-after-mux-switch.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\fix-display-after-mux-switch.ps1 -MeasureOnly

.NOTES
    Requires administrator. Safe to re-run. Tested on Dell G15 5530,
    Windows 11 build 26300, RTX 4060 Laptop + Intel UHD, AUO AA9F panel.
#>
[CmdletBinding()]
param(
    [switch]$MeasureOnly,
    [switch]$Quiet,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

$LogDir  = $null
$LogFile = $null
# $env:ProgramData can be empty in a non-interactive host - use the API instead.
$commonAppData = [Environment]::GetFolderPath('CommonApplicationData')
if (-not $commonAppData) { $commonAppData = 'C:\ProgramData' }
$LogDir  = Join-Path $commonAppData 'MuxSwitchFix'
$LogFile = Join-Path $LogDir 'fix.log'
try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null }
} catch {
    Write-Host ('could not create log directory: ' + $LogDir) -ForegroundColor DarkGray
}

function Write-Log {
    param([string]$Message)
    $line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    if ($LogFile) { $line | Out-File $LogFile -Append -Encoding utf8 -ErrorAction SilentlyContinue }
    if (-not $Quiet) { Write-Host $Message }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    if ($Quiet) {
        Write-Log 'Not elevated - aborting (watchdog task must run with highest privileges)'
        exit 2
    }
    Write-Host ''
    Write-Host 'This needs administrator rights. Opening an elevated window...' -ForegroundColor Yellow
    Write-Host 'If nothing happens, click Yes on the Windows prompt.' -ForegroundColor DarkGray
    Write-Host ''
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    if ($MeasureOnly) { $argList += '-MeasureOnly' }
    if ($Force)       { $argList += '-Force' }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -ErrorAction Stop | Out-Null
    } catch {
        Write-Host 'Could not open an administrator window.' -ForegroundColor Red
        Write-Host 'Either the UAC prompt was cancelled, or it never appeared.' -ForegroundColor Red
        Write-Host ''
        Write-Host 'Do this instead:' -ForegroundColor Yellow
        Write-Host '  1. press Win, type PowerShell'
        Write-Host '  2. right-click Windows PowerShell, choose "Run as administrator"'
        Write-Host '  3. paste this line and press Enter:'
        Write-Host ''
        Write-Host ('     powershell -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath) -ForegroundColor Cyan
        Write-Host ''
        Read-Host 'Press Enter to close'
        exit 5
    }
    return
}

function Wait-Close {
    # keep the window open so the result is readable, no matter how it was launched
    if ($Quiet) { return }
    try { Read-Host 'Press Enter to close' | Out-Null } catch { }
}

function Measure-Dwm {
    param([int]$Seconds = 10)
    $p1 = (Get-Process dwm -ErrorAction SilentlyContinue).CPU
    Start-Sleep -Seconds $Seconds
    $p2 = (Get-Process dwm -ErrorAction SilentlyContinue).CPU
    if ($null -eq $p1 -or $null -eq $p2) { return 0 }
    [math]::Round(($p2 - $p1) / $Seconds * 100, 1)
}

# ------------------------------------------------------------------ health
$allMonitors    = Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue
$activeMonitors = @($allMonitors | Where-Object { $_.Status -eq 'OK' }).Count
$gpus           = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue
$intel          = $gpus | Where-Object { $_.FriendlyName -match 'Intel' -and $_.Status -eq 'OK' } | Select-Object -First 1
$nvidia         = $gpus | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1

$panelOwner = 'unknown'
$smi = 'C:\Windows\System32\nvidia-smi.exe'
if (Test-Path $smi) {
    $da = (& $smi --query-gpu=display_active --format=csv,noheader 2>$null) -join ''
    if ($da -match 'Enabled') { $panelOwner = 'NVIDIA (discrete mode)' }
    elseif ($da -match 'Disabled') { $panelOwner = 'integrated GPU (Optimus)' }
}

Write-Log ("scan: active monitors={0}  panel owner={1}  intel={2}" -f $activeMonitors, $panelOwner, $(if($intel){$intel.Status}else{'absent'}))

if (-not $Quiet) {
    Write-Host ''
    Write-Host 'Display path health check' -ForegroundColor Cyan
    Write-Host ('=' * 46)
    Write-Host ("  panel owner      : {0}" -f $panelOwner)
    Write-Host ("  active monitors  : {0}" -f $activeMonitors)
    foreach ($m in $allMonitors) {
        $c = if ($m.Status -eq 'OK') { 'Green' } else { 'DarkGray' }
        Write-Host ('  {0,-10} {1}' -f $m.Status, $m.FriendlyName) -ForegroundColor $c
    }
}

# ------------------------------------------------------------------ decide
# Measure twice and take the low value: a momentary repaint (opening an app,
# a window animation) can push dwm up for a few seconds. A real duplicate
# path sits at 30 %+ persistently.
$dwmSample1 = Measure-Dwm 8
$dwmSample2 = Measure-Dwm 8
$dwmBefore  = [math]::Min($dwmSample1, $dwmSample2)

if (-not $Quiet) {
    Write-Host ''
    Write-Host ("  dwm CPU          : {0}% of one core (samples: {1}, {2})" -f $dwmBefore, $dwmSample1, $dwmSample2) -ForegroundColor Cyan
}

$broken = $false
if ($activeMonitors -gt 1) { $broken = $true }
if ($dwmBefore -ge 15)     { $broken = $true }
if ($Force)                { $broken = $true }

if (-not $broken) {
    if (-not $Quiet) {
        Write-Host ''
        Write-Host '  Healthy - nothing to do.' -ForegroundColor Green
    }
    Write-Log 'healthy, no action'
    Wait-Close
    exit 0
}

if (-not $intel) {
    Write-Log 'duplicate detected but no Intel adapter to re-enumerate - manual intervention needed'
    if (-not $Quiet) { Write-Host 'No Intel adapter found - cannot apply this fix.' -ForegroundColor Red }
    exit 3
}

if ($MeasureOnly) {
    Write-Log ("MEASURE ONLY: duplicate path detected (monitors={0}, dwm={1}%)" -f $activeMonitors, $dwmBefore)
    if (-not $Quiet) {
        Write-Host ''
        Write-Host '  -> duplicate display path detected. Run without -MeasureOnly to fix.' -ForegroundColor Yellow
    }
    Wait-Close
    exit 1
}

# ------------------------------------------------------------------ repair
Write-Log ("repairing: dwm={0}% monitors={1} -> toggling {2}" -f $dwmBefore, $activeMonitors, $intel.FriendlyName)
if (-not $Quiet) {
    Write-Host ''
    Write-Host ('  Re-enumerating {0} ...' -f $intel.FriendlyName) -ForegroundColor Yellow
    Write-Host '  the screen may blink once. do not close this window.' -ForegroundColor DarkGray
}

Disable-PnpDevice -InstanceId $intel.InstanceId -Confirm:$false -ErrorAction Continue
Start-Sleep -Seconds 6
Enable-PnpDevice  -InstanceId $intel.InstanceId -Confirm:$false -ErrorAction Continue
Start-Sleep -Seconds 18

$dwmAfter     = [math]::Min((Measure-Dwm 8), (Measure-Dwm 8))
$monitorsAfter = @(Get-PnpDevice -Class Monitor | Where-Object { $_.Status -eq 'OK' }).Count
$intelAfter   = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'Intel' } | Select-Object -First 1

Write-Log ("result: dwm {0}% -> {1}%   monitors {2} -> {3}   intel={4}/{5}" -f `
    $dwmBefore, $dwmAfter, $activeMonitors, $monitorsAfter, $intelAfter.Status, $intelAfter.Problem)

if (-not $Quiet) {
    Write-Host ''
    Write-Host ("  dwm CPU after    : {0}% of one core" -f $dwmAfter) -ForegroundColor Cyan
    Write-Host ("  active monitors  : {0}" -f $monitorsAfter) -ForegroundColor Cyan
    Write-Host ''
    if ($dwmAfter -lt $dwmBefore - 10) {
        Write-Host '  FIXED. Test it: type in a browser, scroll a long page, drag a window.' -ForegroundColor Green
    } else {
        Write-Host '  No improvement - the lag is coming from somewhere else.' -ForegroundColor Yellow
        Write-Host '  Check: refresh rate cost, NVIDIA overlay injection, browser GPU cache.' -ForegroundColor DarkGray
    }
    Write-Host ("  log: {0}" -f $LogFile) -ForegroundColor DarkGray
}

if ($dwmAfter -lt $dwmBefore - 10) { Wait-Close; exit 0 } else { Wait-Close; exit 4 }
