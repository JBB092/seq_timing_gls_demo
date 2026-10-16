<#
.SYNOPSIS
    Windows entry point for the demo.
.DESCRIPTION
    Thin wrapper around the shared scripts in scripts/; the Linux Makefile
    offers the same targets. New targets are added as the demo grows.
.EXAMPLE
    .\run.ps1 rtl
.EXAMPLE
    .\run.ps1 rtl -Depth 24
.EXAMPLE
    .\run.ps1 build -Depth 24
.EXAMPLE
    .\run.ps1 program -Depth 24
.EXAMPLE
    .\run.ps1 report
.EXAMPLE
    .\run.ps1 clean
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'rtl', 'build', 'program', 'report', 'clean')]
    [string]$Target = 'help',

    # Chain depth; 0 means the default in rtl/chain_cfg.svh
    [ValidateRange(0, 1024)]
    [int]$Depth = 0
)

$ErrorActionPreference = 'Stop'

# Everything generated lives in build/; the quartus/ folders only appear
# if the project is opened from the Quartus GUI
$CleanDirs = @('build', 'quartus\db', 'quartus\incremental_db', 'quartus\output_files')

function Show-Help {
    Write-Host 'Usage: .\run.ps1 <target> [-Depth <k>]'
    Write-Host ''
    Write-Host 'Targets:'
    Write-Host '  help    Show this message (default)'
    Write-Host '  rtl     Zero-delay RTL simulation of core'
    Write-Host '  build   Quartus compile of the board project'
    Write-Host '  program Load the .sof of that depth into the FPGA (JTAG device 2)'
    Write-Host '  report  Summarize all simulation logs (k x T table)'
    Write-Host '  clean   Remove build/ and any Quartus output folders'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -Depth  Chain depth k (default: CHAIN_DEPTH in rtl/chain_cfg.svh)'
}

function Invoke-Sim([string]$Mode) {
    $depthArg = if ($Depth -gt 0) { "$Depth" } else { '' }
    vsim -c -nolog -do "set MODE $Mode; set DEPTH {$depthArg}; source scripts/sim.tcl"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Quartus([string]$Action) {
    $quartusArgs = @('-t', 'scripts/build.tcl', $Action, 'board')
    if ($Depth -gt 0) { $quartusArgs += "$Depth" }
    quartus_sh @quartusArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Report {
    python scripts/parse_logs.py
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
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

# Run from the repo root without changing the caller's location
Push-Location $PSScriptRoot
try {
    switch ($Target) {
        'help'    { Show-Help }
        'rtl'     { Invoke-Sim 'rtl' }
        'build'   { Invoke-Quartus 'compile' }
        'program' { Invoke-Quartus 'program' }
        'report'  { Invoke-Report }
        'clean'   { Invoke-Clean }
    }
} finally {
    Pop-Location
}
