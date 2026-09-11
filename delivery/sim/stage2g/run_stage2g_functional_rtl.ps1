[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot,
    [switch]$XSim,
    [switch]$NoMutations,
    [switch]$FullRegression,
    [switch]$RequireClean,
    [string]$HistoricalReplayArchive,
    [string]$VivadoBin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$RunnerPath = Join-Path $RepoRoot "tools\run_stage2g_functional_rtl.py"
$arguments = @(
    $RunnerPath,
    "--output", $OutputRoot
)
if ($VivadoBin) { $arguments += @("--vivado-bin", ([IO.Path]::GetFullPath($VivadoBin))) }
if ($XSim) { $arguments += "--xsim" }
if ($NoMutations) { $arguments += "--no-mutations" }
if ($FullRegression) { $arguments += "--full-regression" }
if ($RequireClean) { $arguments += "--require-clean" }
if ($HistoricalReplayArchive) {
    $arguments += @(
        "--historical-replay-archive",
        ([IO.Path]::GetFullPath($HistoricalReplayArchive))
    )
}

& python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Stage 2G functional RTL runner failed with exit code $LASTEXITCODE"
}
