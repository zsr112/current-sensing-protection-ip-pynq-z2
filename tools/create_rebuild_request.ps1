[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputJson,
    [Parameter(Mandatory = $true)][string]$OutputJson
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$build = Join-Path $root 'fpga/vivado/build'
Import-Module (Join-Path $build 'lib/stage1e_runtime_canonical_json_v1.psm1') -Force
$request = Get-Content -LiteralPath $InputJson -Raw | ConvertFrom-Json -AsHashtable
$schema = Get-Content (Join-Path $build 'config/stage1e_execution_request_schema_v2.json') -Raw | ConvertFrom-Json -AsHashtable
$registry = [ordered]@{ 'stage1e-execution-request-v2' = $schema }
$bytes = ConvertTo-Stage1ECanonicalJsonBytes -Value $request -Schema $schema -SchemaRegistry $registry -OmitProperty 'request_identity'
$request.request_identity = Get-Stage1ECanonicalDigest -Bytes $bytes
$sealed = ConvertTo-Stage1ECanonicalJsonBytes -Value $request -Schema $schema -SchemaRegistry $registry
[IO.File]::WriteAllBytes($OutputJson, $sealed)
Write-Output $request.request_identity
