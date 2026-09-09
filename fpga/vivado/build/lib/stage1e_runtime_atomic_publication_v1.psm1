Set-StrictMode -Version Latest

$canonicalModule = Join-Path $PSScriptRoot 'stage1e_runtime_canonical_json_v1.psm1'
Import-Module -Name $canonicalModule -Force -ErrorAction Stop

$script:Stage1EAtomicPublicationInterface =
    'stage1e-runtime-atomic-publication-interface-v1'

function Get-Stage1EAtomicPublicationInterfaceVersion {
    return $script:Stage1EAtomicPublicationInterface
}

function Test-Stage1EPathContained {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Boundary
    )

    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    $boundaryFull = [System.IO.Path]::GetFullPath($Boundary)
    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    $prefix = $boundaryFull.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    return ($candidateFull.Equals($boundaryFull,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($prefix,
            [System.StringComparison]::OrdinalIgnoreCase))
}

function Assert-Stage1EAtomicPath {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$BoundaryPath
    )

    if (-not [System.IO.Path]::IsPathRooted($LiteralPath) -or
        -not [System.IO.Path]::IsPathRooted($BoundaryPath)) {
        throw [System.IO.IOException]::new(
            'Atomic publication paths must be absolute.')
    }
    foreach ($wildcard in @('*', '?', '[', ']')) {
        if ($LiteralPath.IndexOf($wildcard) -ge 0 -or
            $BoundaryPath.IndexOf($wildcard) -ge 0) {
            throw [System.IO.IOException]::new(
                'Atomic publication paths must be literal.')
        }
    }
    $final = [System.IO.Path]::GetFullPath($LiteralPath)
    $boundary = [System.IO.Path]::GetFullPath($BoundaryPath)
    $parent = [System.IO.Path]::GetDirectoryName($final)
    if ([string]::IsNullOrEmpty($parent) -or
        -not [System.IO.Directory]::Exists($parent)) {
        throw [System.IO.DirectoryNotFoundException]::new(
            "Final parent directory does not exist: $parent")
    }
    if (-not [System.IO.Directory]::Exists($boundary)) {
        throw [System.IO.DirectoryNotFoundException]::new(
            "Publication boundary does not exist: $boundary")
    }
    if (-not (Test-Stage1EPathContained $final $boundary)) {
        throw [System.IO.IOException]::new(
            'Final publication path is outside the qualified boundary.')
    }
    return [ordered]@{
        final = $final
        parent = $parent
        boundary = $boundary
    }
}

function Invoke-Stage1EByteVerifier {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [scriptblock]$Verifier
    )

    if ($null -ne $Verifier) {
        $accepted = & $Verifier $Bytes
        if ($accepted -is [bool] -and -not $accepted) {
            throw [System.IO.InvalidDataException]::new(
                'Publication verifier rejected canonical bytes.')
        }
    }
}

function Publish-Stage1EAtomicBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$BoundaryPath,
        [scriptblock]$Verifier,
        [scriptblock]$TemporaryLeafNameProvider,
        [scriptblock]$AfterTemporaryClose,
        [scriptblock]$AfterRename
    )

    $paths = Assert-Stage1EAtomicPath $LiteralPath $BoundaryPath
    if ([System.IO.File]::Exists($paths.final) -or
        [System.IO.Directory]::Exists($paths.final)) {
        throw [System.IO.IOException]::new(
            "Final publication path already exists: $($paths.final)")
    }

    if ($null -eq $TemporaryLeafNameProvider) {
        $leaf = ".$([System.IO.Path]::GetFileName($paths.final)).stage1e-tmp-$(
            [System.Guid]::NewGuid().ToString('N'))"
    }
    else {
        $leaf = [string](& $TemporaryLeafNameProvider)
    }
    if ([string]::IsNullOrWhiteSpace($leaf) -or
        [System.IO.Path]::GetFileName($leaf) -cne $leaf -or
        $leaf.IndexOf([System.IO.Path]::DirectorySeparatorChar) -ge 0 -or
        $leaf.IndexOf([System.IO.Path]::AltDirectorySeparatorChar) -ge 0) {
        throw [System.IO.IOException]::new(
            'Temporary publication name must be one literal sibling leaf.')
    }
    $temporary = Join-Path $paths.parent $leaf
    if ([System.IO.Path]::GetFullPath($temporary).Equals(
            $paths.final, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.IO.IOException]::new(
            'Temporary and final publication paths must differ.')
    }

    $createdTemporary = $false
    $renamedFinal = $false
    try {
        $stream = [System.IO.FileStream]::new(
            $temporary,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            4096,
            [System.IO.FileOptions]::WriteThrough)
        $createdTemporary = $true
        try {
            $stream.Write($Bytes, 0, $Bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }

        if ($null -ne $AfterTemporaryClose) {
            & $AfterTemporaryClose $temporary
        }
        $temporaryBytes = [System.IO.File]::ReadAllBytes($temporary)
        if (-not (Compare-Stage1EBytes $Bytes $temporaryBytes)) {
            throw [System.IO.InvalidDataException]::new(
                'Temporary publication bytes differ after close and reopen.')
        }
        Invoke-Stage1EByteVerifier $temporaryBytes $Verifier

        if ([System.IO.File]::Exists($paths.final) -or
            [System.IO.Directory]::Exists($paths.final)) {
            throw [System.IO.IOException]::new(
                "Final publication path collided before rename: $($paths.final)")
        }
        [System.IO.File]::Move($temporary, $paths.final)
        $createdTemporary = $false
        $renamedFinal = $true

        if ($null -ne $AfterRename) {
            & $AfterRename $paths.final
        }
        $finalBytes = [System.IO.File]::ReadAllBytes($paths.final)
        if (-not (Compare-Stage1EBytes $Bytes $finalBytes)) {
            throw [System.IO.InvalidDataException]::new(
                'Final publication bytes differ after atomic rename.')
        }
        Invoke-Stage1EByteVerifier $finalBytes $Verifier

        return [ordered]@{
            interface_version = $script:Stage1EAtomicPublicationInterface
            publication_state = 'SEALED'
            final_path = $paths.final
            byte_count = [int64]$finalBytes.Length
            byte_sha256 = Get-Stage1ESha256Hex -Bytes $finalBytes
            overwrite_performed = $false
        }
    }
    catch {
        if ($createdTemporary -and [System.IO.File]::Exists($temporary)) {
            [System.IO.File]::Delete($temporary)
        }
        if ($renamedFinal -and [System.IO.File]::Exists($paths.final)) {
            [System.IO.File]::Delete($paths.final)
        }
        throw
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EAtomicPublicationInterfaceVersion'
    'Publish-Stage1EAtomicBytes'
)
