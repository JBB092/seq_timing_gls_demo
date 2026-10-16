<#
.SYNOPSIS
    Windows entry point for the demo.
.DESCRIPTION
    Thin wrapper around the shared scripts in scripts/; the Linux Makefile
    offers the same targets. New targets are added as the demo grows.
.EXAMPLE
    .\run.ps1 help
.EXAMPLE
    .\run.ps1 clean
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'clean')]
    [string]$Target = 'help'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Everything generated lives in build/; the quartus/ folders only appear
# if the project is opened from the Quartus GUI
$CleanDirs = @('build', 'quartus\db', 'quartus\incremental_db', 'quartus\output_files')

function Show-Help {
    Write-Host 'Usage: .\run.ps1 <target>'
    Write-Host ''
    Write-Host 'Targets:'
    Write-Host '  help    Show this message (default)'
    Write-Host '  clean   Remove build/ and any Quartus output folders'
}

function Invoke-Clean {
    foreach ($dir in $CleanDirs) {
        if (Test-Path $dir) {
            Remove-Item -Recurse -Force $dir
            Write-Host "Removed $dir"
        }
    }
    Write-Host 'Clean done'
}

switch ($Target) {
    'help'  { Show-Help }
    'clean' { Invoke-Clean }
}
