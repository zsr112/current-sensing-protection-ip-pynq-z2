param([string]$RepositoryRoot, [string]$ManifestHash, [string]$Mode)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../fpga/vivado/build/runtime/entrypoint/v3/stage1e_execution_request_v1.psm1') -Force
$source = @{ expected_commit = ('a' * 40); expected_tree = ('b' * 40); export_manifest_sha256 = $ManifestHash }
try {
    Assert-Stage1EExportSource -RepositoryRoot $RepositoryRoot -Source $source
    if ($Mode -ne 'valid') { throw 'Invalid fixture was accepted' }
    Write-Output 'EXPORT_FIXTURE=PASS'
} catch {
    if ($Mode -eq 'valid' -or $_.Exception.Message -notmatch 'EXPORT_') { throw }
    Write-Output 'EXPORT_REJECTION=PASS'
}
