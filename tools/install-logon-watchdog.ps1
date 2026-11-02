<#
.SYNOPSIS
    Install a logon watchdog that repairs the duplicate display path
    automatically, only when it is actually broken.

.DESCRIPTION
    Registers a scheduled task that runs 2 minutes after every logon. The task
    calls fix-display-after-mux-switch.ps1 -Quiet, which:

        * checks whether more than one monitor device is active
        * checks whether dwm.exe is burning CPU on an idle desktop
        * repairs only if something is wrong
        * writes every decision to C:\ProgramData\MuxSwitchFix\fix.log

    On a healthy machine the task finishes in a few seconds and changes nothing.

    Why logon: a MUX switch always requires a reboot, so the broken state always
    appears after a logon. Checking at logon catches it in every case.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-logon-watchdog.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

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

$taskName  = 'MuxSwitchDisplayWatchdog'
$fixScript = Join-Path $PSScriptRoot 'fix-display-after-mux-switch.ps1'

if (-not (Test-Path $fixScript)) {
    Write-Host "fix-display-after-mux-switch.ps1 not found next to this script." -ForegroundColor Red
    exit 1
}

$user = "$env:USERDOMAIN\$env:USERNAME"
$arg  = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $fixScript + '" -Quiet'

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT2M'
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

$t = Get-ScheduledTask -TaskName $taskName
Write-Host ''
Write-Host 'Watchdog installed' -ForegroundColor Green
Write-Host ('  task     : {0}' -f $t.TaskName)
Write-Host ('  state    : {0}' -f $t.State)
Write-Host ('  runs     : 2 minutes after every logon')
Write-Host ('  account  : {0} (highest privileges, no UAC prompt)' -f $user)
Write-Host ('  script   : {0}' -f $fixScript)
Write-Host ('  log      : C:\ProgramData\MuxSwitchFix\fix.log')
Write-Host ''
Write-Host 'Test it right now without rebooting:' -ForegroundColor Cyan
Write-Host ('  Start-ScheduledTask -TaskName {0}' -f $taskName)
Write-Host ('  Get-Content C:\ProgramData\MuxSwitchFix\fix.log -Tail 5')
Write-Host ''
Write-Host 'Remove it with uninstall-logon-watchdog.ps1' -ForegroundColor DarkGray
