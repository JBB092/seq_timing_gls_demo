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
    .\run.ps1 gls_udp -Depths 8,16,24,32 -Corner typ
.EXAMPLE
    .\run.ps1 build -Depth 24
.EXAMPLE
    .\run.ps1 build_sweep -Depths 8,16,24
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
    [ValidateSet('help', 'rtl', 'gls_udp', 'build', 'build_sweep', 'sta_export', 'program', 'report', 'clean')]
    [string]$Target = 'help',

    # Chain depth; 0 means the default in rtl/chain_cfg.svh
    [ValidateRange(0, 1024)]
    [int]$Depth = 0,

    # Depth list: simulations run once per depth, build_sweep compiles each one
    [int[]]$Depths = @(),

    # Delay corner for gls_udp
    [ValidateSet('min', 'typ', 'max')]
    [string]$Corner = 'max'
)

$ErrorActionPreference = 'Stop'

# Everything generated lives in build/; the quartus/ folders only appear
# if the project is opened from the Quartus GUI
$CleanDirs = @('build', 'quartus\db', 'quartus\incremental_db', 'quartus\output_files')

function Show-Help {
    Write-Host 'Usage: .\run.ps1 <target> [-Depth <k>] [-Depths <k1,k2,...>] [-Corner min|typ|max]'
    Write-Host ''
    Write-Host 'Targets:'
    Write-Host '  help    Show this message (default)'
    Write-Host '  rtl     Zero-delay RTL simulation of core'
    Write-Host '  gls_udp Approach A: UDP cells with delays from the STA'
    Write-Host '  build   Quartus compile of the board project'
    Write-Host '  build_sweep  Compile several depths and summarize their slack'
    Write-Host '  sta_export   Export the critical path of the builds to build/sta/ (CSV)'
    Write-Host '  program Load the .sof of that depth into the FPGA (JTAG device 2)'
    Write-Host '  report  Summarize all simulation logs (k x T table)'
    Write-Host '  clean   Remove build/ and any Quartus output folders'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -Depth  Chain depth k (default: CHAIN_DEPTH in rtl/chain_cfg.svh)'
    Write-Host '  -Depths Depth list: rtl and gls_udp simulate each one, build_sweep'
    Write-Host '          compiles each one (default: list in scripts/build.tcl),'
    Write-Host '          sta_export exports each one (default: every build found)'
    Write-Host '  -Corner Delay corner for gls_udp: min, typ or max (default max)'
}

function Invoke-Sim([string]$Mode) {
    $depthArg = if ($Depths.Count -gt 0) { $Depths -join ' ' } elseif ($Depth -gt 0) { "$Depth" } else { '' }
    vsim -c -nolog -do "set MODE $Mode; set CORNER $Corner; set DEPTH {$depthArg}; source scripts/sim.tcl"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# build/timing_cfg.svh comes from the STA export; regenerate it when the
# export is newer
function Update-TimingCfg {
    $cfg = 'build\timing_cfg.svh'
    $csv = 'build\sta\board_summary.csv'
    if (-not (Test-Path $csv)) {
        if (Test-Path $cfg) { return }
        Write-Host "$csv not found. Run build_sweep and sta_export first."
        exit 2
    }
    if ((Test-Path $cfg) -and ((Get-Item $cfg).LastWriteTime -ge (Get-Item $csv).LastWriteTime)) { return }
    python scripts/gen_timing_cfg.py
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Quartus([string]$Action) {
    $quartusArgs = @('-t', 'scripts/build.tcl', $Action, 'board')
    if ($Depth -gt 0) { $quartusArgs += "$Depth" }
    quartus_sh @quartusArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Sweep {
    $quartusArgs = @('-t', 'scripts/build.tcl', 'sweep', 'board')
    if ($Depths.Count -gt 0) { $quartusArgs += ($Depths -join ' ') }
    quartus_sh @quartusArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-StaExport {
    $staArgs = @('-t', 'scripts/sta_export.tcl', 'board')
    if ($Depths.Count -gt 0) { $staArgs += ($Depths -join ' ') }
    quartus_sta @staArgs
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
        'help'        { Show-Help }
        'rtl'         { Invoke-Sim 'rtl' }
        'gls_udp'     { Update-TimingCfg; Invoke-Sim 'gls_udp' }
        'build'       { Invoke-Quartus 'compile' }
        'build_sweep' { Invoke-Sweep }
        'sta_export'  { Invoke-StaExport }
        'program'     { Invoke-Quartus 'program' }
        'report'      { Invoke-Report }
        'clean'       { Invoke-Clean }
    }
} finally {
    Pop-Location
}
