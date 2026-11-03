<#
.SYNOPSIS
    Build brightness.exe and brightnessw.exe from brightness.cs.

.DESCRIPTION
    Uses Add-Type, which calls the C# compiler that ships with the .NET Framework.
    No SDK, no Visual Studio, no compiler install required.

    brightness.exe   console build, prints the new level (for testing)
    brightnessw.exe  windows build, no console window (use this in shortcuts)

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src  = Join-Path $here 'brightness.cs'

if (-not (Test-Path $src)) { throw "brightness.cs not found next to build.ps1" }

$targets = @(
    @{ Out = 'brightness.exe';  Type = 'ConsoleApplication' },
    @{ Out = 'brightnessw.exe'; Type = 'WindowsApplication' }
)

foreach ($t in $targets) {
    $out = Join-Path $here $t.Out
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    Add-Type -Path $src -OutputAssembly $out -OutputType $t.Type -ReferencedAssemblies System.dll
    Write-Host ('  built {0}  ({1} bytes)' -f $t.Out, (Get-Item $out).Length) -ForegroundColor Green
}

Write-Host ''
Write-Host 'Next: copy both exes to C:\ProgramData\MuxSwitchFix\ and point shortcuts at brightnessw.exe' -ForegroundColor Cyan
Write-Host 'See README.md in this folder for the shortcut setup.' -ForegroundColor DarkGray
