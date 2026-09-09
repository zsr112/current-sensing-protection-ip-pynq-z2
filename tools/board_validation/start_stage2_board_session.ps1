[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackageZip,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSHA256,
    [ValidatePattern('^[a-zA-Z0-9.-]+$')][string]$BoardHost = '192.168.2.99',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$BoardUser = 'xilinx',
    [ValidateRange(1024, 65535)][int]$LocalPort = 18765
)
$ErrorActionPreference = 'Stop'
$packagePath = (Resolve-Path -LiteralPath $PackageZip).Path
if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedSHA256.ToLowerInvariant()) {
    throw 'Local package SHA256 mismatch'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    $entry = $archive.GetEntry('session_manifest.json')
    if ($null -eq $entry) { throw 'Session manifest missing from ZIP' }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
} finally { $archive.Dispose() }
$executionId = [string]$manifest.execution_id
if ($executionId -notmatch '^[A-Za-z0-9._-]{1,120}$') { throw 'Invalid execution identity' }
$remoteRoot = "/tmp/csip-$executionId"
$remoteZip = "$remoteRoot.zip"
$remoteEvidence = "$remoteRoot-evidence"
$destination = "${BoardUser}@${BoardHost}"
Write-Host "Transferring execution $executionId to $destination. Enter passwords only at SSH/sudo prompts."
& scp -o StrictHostKeyChecking=yes -o ConnectTimeout=10 $packagePath "${destination}:$remoteZip"
if ($LASTEXITCODE -ne 0) { throw "SCP failed with exit code $LASTEXITCODE" }
$remoteCommand = "printf '%s  %s\n' '$ExpectedSHA256' '$remoteZip' | sha256sum -c - && test ! -e '$remoteRoot' && mkdir -m 0700 '$remoteRoot' && /usr/local/share/pynq-venv/bin/python3 -m zipfile -e '$remoteZip' '$remoteRoot' && sudo env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 '$remoteRoot/runtime/stage2_board_session.py' --package-root '$remoteRoot' --output-root '$remoteEvidence' --board-model PYNQ-Z2 --port $LocalPort"
Write-Host 'Opening the authenticated loopback tunnel. Keep this window open until the session ends.'
& ssh -tt -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ConnectTimeout=10 -L "127.0.0.1:${LocalPort}:127.0.0.1:${LocalPort}" $destination $remoteCommand
if ($LASTEXITCODE -ne 0) { throw "Board session failed with exit code $LASTEXITCODE" }
