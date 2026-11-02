<#
.SYNOPSIS
    Remove the logon watchdog installed by install-logon-watchdog.ps1.

.DESCRIPTION
    Unregisters the scheduled task. The fix script and its log are left in
    place so you can still run the repair by hand.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall-logon-watchdog.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host 'Needs administrator. Re-launching elevated...' -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    return
}

$taskName = 'MuxSwitchDisplayWatchdog'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if (-not $task) {
    Write-Host 'Watchdog is not installed - nothing to remove.' -ForegroundColor DarkGray
    return
}

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
Write-Host ''
Write-Host 'Watchdog removed.' -ForegroundColor Green
Write-Host 'The repair script still works if you run it manually:' -ForegroundColor DarkGray
Write-Host '  powershell -ExecutionPolicy Bypass -File .\fix-display-after-mux-switch.ps1'
Write-Host 'Log kept at C:\ProgramData\MuxSwitchFix\fix.log' -ForegroundColor DarkGray
