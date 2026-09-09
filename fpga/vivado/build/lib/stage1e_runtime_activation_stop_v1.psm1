Set-StrictMode -Version Latest

$script:Stage1EActivationStopInterface =
    'stage1e-runtime-activation-stop-interface-v1'
$script:Stage1EActivationStopBuildRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
$script:Stage1EActivationStopDependencyPath = Join-Path `
    $script:Stage1EActivationStopBuildRoot `
    'dependency/stage1e_runtime_dependency_closure_v1.psm1'
$script:Stage1EActivationStopAtomicPath = Join-Path `
    $script:Stage1EActivationStopBuildRoot `
    'lib/stage1e_runtime_atomic_publication_v1.psm1'
$script:Stage1EActivationStopDependencyInterface =
    'stage1e-runtime-dependency-closure-interface-v1'
$script:Stage1EActivationStopAtomicInterface =
    'stage1e-runtime-atomic-publication-interface-v1'

Microsoft.PowerShell.Core\Import-Module -Name `
    $script:Stage1EActivationStopDependencyPath -ErrorAction Stop
Microsoft.PowerShell.Core\Import-Module -Name `
    $script:Stage1EActivationStopAtomicPath -ErrorAction Stop
if ([string](Get-Stage1EDependencyClosureInterfaceVersion) -cne
        $script:Stage1EActivationStopDependencyInterface -or
    [string](Get-Stage1EAtomicPublicationInterfaceVersion) -cne
        $script:Stage1EActivationStopAtomicInterface) {
    throw 'Activation-stop accepted closure interface differs.'
}

$script:Stage1EActivationStopFields = @(
    'schema_version', 'interface_version', 'request_identity', 'execution_id',
    'attempt_id', 'terminal_status', 'failure_category', 'failure_code',
    'outer_phase', 'outer_phase_semantics', 'activation_subphase',
    'authorization_effect', 'process_effect', 'candidate_effect',
    'causal_host_ledger_reference', 'missing_activation_object',
    'publication_state')
$script:Stage1EActivationStopReceiptFields = @(
    'schema_version', 'interface_version', 'record_path',
    'publication_state', 'record_byte_count', 'record_sha256',
    'request_identity', 'execution_id', 'attempt_id')

function Get-Stage1EActivationStopInterfaceVersion {
    return $script:Stage1EActivationStopInterface
}

function ConvertTo-Stage1EActivationStopCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).Replace('\','/')
}

function Assert-Stage1EActivationStopExactFields {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $actual = @($Record.Keys | ForEach-Object { [string]$_ })
    if (($actual -join '|') -cne ($Fields -join '|')) {
        throw "$Label has an incorrect exact field set/order."
    }
}

function ConvertTo-Stage1EActivationStopValue {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    return $Value.Replace('\','\\').Replace('|','\p').
        Replace("`t",'\t').Replace("`r",'\r').Replace("`n",'\n')
}

function ConvertFrom-Stage1EActivationStopValue {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        if ($Value[$index] -ne '\') {
            $null = $builder.Append($Value[$index])
            continue
        }
        if ($index + 1 -ge $Value.Length) { throw 'Truncated stop escape.' }
        $index++
        switch ($Value[$index]) {
            '\' { $null = $builder.Append('\') }
            'p' { $null = $builder.Append('|') }
            't' { $null = $builder.Append("`t") }
            'r' { $null = $builder.Append("`r") }
            'n' { $null = $builder.Append("`n") }
            default { throw 'Unknown stop escape.' }
        }
    }
    return $builder.ToString()
}

function ConvertTo-Stage1EActivationStopLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record
    )
    return (($Record.Keys | ForEach-Object {
                "$_=$(ConvertTo-Stage1EActivationStopValue ([string]$Record[$_]))"
            }) -join '|')
}

function ConvertFrom-Stage1EActivationStopLine {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Line)
    if ($Line.Contains("`r") -or $Line.Contains("`n")) {
        $Line = $Line.TrimEnd("`r", "`n")
    }
    $record = [ordered]@{}
    foreach ($field in $Line.Split('|')) {
        $separator = $field.IndexOf('=')
        if ($separator -lt 1) { throw 'Activation-stop field is malformed.' }
        $name = $field.Substring(0, $separator)
        if ($record.Contains($name)) {
            throw "Activation-stop field is duplicated: $name"
        }
        $record[$name] = ConvertFrom-Stage1EActivationStopValue `
            $field.Substring($separator + 1)
    }
    return $record
}

function New-Stage1EActivationStopRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$AssemblyRequest,
        [Parameter(Mandatory = $true)]$HostAssemblyResult,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$StopContract
    )
    $record = [ordered]@{
        schema_version = 'stage1e-runtime-activation-stop-record-v1'
        interface_version = $script:Stage1EActivationStopInterface
        request_identity = [string]$AssemblyRequest.request_identity
        execution_id = [string]$AssemblyRequest.execution_id
        attempt_id = [string]$AssemblyRequest.attempt_id
        terminal_status = [string]$StopContract.terminal_status
        failure_category = [string]$StopContract.failure_category
        failure_code = [string]$StopContract.failure_code
        outer_phase = [string]$StopContract.outer_phase
        outer_phase_semantics = 'V1_COMPATIBLE_OUTER_PHASE'
        activation_subphase = [string]$StopContract.activation_subphase
        authorization_effect = [string]$StopContract.authorization_effect
        process_effect = [string]$StopContract.process_effect
        candidate_effect = [string]$StopContract.candidate_effect
        causal_host_ledger_reference =
            [string]$HostAssemblyResult.sealed_ledger_path
        missing_activation_object =
            [string]$StopContract.missing_activation_object
        publication_state = 'SEALED'
    }
    $null = Assert-Stage1EActivationStopRecord $record
    return $record
}

function Assert-Stage1EActivationStopRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record
    )
    Assert-Stage1EActivationStopExactFields $Record `
        $script:Stage1EActivationStopFields 'Structured activation stop'
    if ([string]$Record.schema_version -cne
            'stage1e-runtime-activation-stop-record-v1' -or
        [string]$Record.interface_version -cne
            $script:Stage1EActivationStopInterface -or
        [string]$Record.terminal_status -cne 'BLOCKED' -or
        [string]$Record.failure_category -cne 'IDENTITY_BINDING' -or
        [string]$Record.failure_code -cne
            'RUNTIME_BACKEND_IDENTITY_V2_NOT_CREATED' -or
        [string]$Record.outer_phase -cne 'ENTRY_ASSEMBLY' -or
        [string]$Record.outer_phase_semantics -cne
            'V1_COMPATIBLE_OUTER_PHASE' -or
        [string]$Record.activation_subphase -cne 'ACTIVATION_PRECHECK' -or
        [string]$Record.authorization_effect -cne 'NOT_TOUCHED' -or
        [string]$Record.process_effect -cne 'NOT_STARTED' -or
        [string]$Record.candidate_effect -cne 'NOT_CREATED' -or
        [string]$Record.missing_activation_object -cne
            'RUNTIME_BACKEND_IDENTITY_V2' -or
        [string]$Record.publication_state -cne 'SEALED') {
        throw 'Structured activation-stop identity, phase, or effect differs.'
    }
    foreach ($field in @('request_identity', 'execution_id', 'attempt_id',
            'causal_host_ledger_reference')) {
        if ([string]::IsNullOrWhiteSpace([string]$Record[$field])) {
            throw "Structured activation stop has an empty $field."
        }
    }
    return $true
}

function Publish-Stage1EActivationStopRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )
    $null = Assert-Stage1EActivationStopRecord $Record
    $root = [System.IO.Path]::GetFullPath($EvidenceRoot)
    if (-not [System.IO.Directory]::Exists($root)) {
        throw 'Activation-stop evidence root does not exist.'
    }
    $recordPath = Join-Path $root 'stage1e-prt03-activation-stop.record'
    $receiptPath = Join-Path $root 'stage1e-prt03-activation-stop.receipt'
    $recordBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        (ConvertTo-Stage1EActivationStopLine $Record) + "`n")
    $recordPublication = Publish-Stage1EAtomicBytes `
        -LiteralPath $recordPath -Bytes $recordBytes -BoundaryPath $root
    $reopened = ConvertFrom-Stage1EActivationStopLine `
        ([System.Text.UTF8Encoding]::new($false, $true).GetString(
            [System.IO.File]::ReadAllBytes($recordPath)))
    $null = Assert-Stage1EActivationStopRecord $reopened
    $receipt = [ordered]@{
        schema_version = 'stage1e-runtime-activation-stop-receipt-v1'
        interface_version = $script:Stage1EActivationStopInterface
        record_path = ConvertTo-Stage1EActivationStopCanonicalPath $recordPath
        publication_state = 'PUBLISHED'
        record_byte_count = [int64]$recordPublication.byte_count
        record_sha256 = [string]$recordPublication.byte_sha256
        request_identity = [string]$Record.request_identity
        execution_id = [string]$Record.execution_id
        attempt_id = [string]$Record.attempt_id
    }
    $receiptBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        (ConvertTo-Stage1EActivationStopLine $receipt) + "`n")
    $receiptPublication = Publish-Stage1EAtomicBytes `
        -LiteralPath $receiptPath -Bytes $receiptBytes -BoundaryPath $root
    return [ordered]@{
        schema_version = 'stage1e-runtime-activation-stop-publication-v1'
        record = $reopened
        record_path = ConvertTo-Stage1EActivationStopCanonicalPath $recordPath
        record_byte_count = [int64]$recordPublication.byte_count
        record_sha256 = [string]$recordPublication.byte_sha256
        receipt_path = ConvertTo-Stage1EActivationStopCanonicalPath $receiptPath
        receipt_byte_count = [int64]$receiptPublication.byte_count
        receipt_sha256 = [string]$receiptPublication.byte_sha256
        publication_state = 'PUBLISHED_NO_OVERWRITE'
    }
}

function Read-Stage1EActivationStopPublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RecordPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath
    )
    $recordFull = [System.IO.Path]::GetFullPath($RecordPath)
    $receiptFull = [System.IO.Path]::GetFullPath($ReceiptPath)
    $recordBytes = [System.IO.File]::ReadAllBytes($recordFull)
    $record = ConvertFrom-Stage1EActivationStopLine `
        ([System.Text.UTF8Encoding]::new($false, $true).GetString($recordBytes))
    $null = Assert-Stage1EActivationStopRecord $record
    $receipt = ConvertFrom-Stage1EActivationStopLine `
        ([System.Text.UTF8Encoding]::new($false, $true).GetString(
            [System.IO.File]::ReadAllBytes($receiptFull)))
    Assert-Stage1EActivationStopExactFields $receipt `
        $script:Stage1EActivationStopReceiptFields `
        'Structured activation-stop receipt'
    $digest = Get-Stage1EDependencySha256Hex -Bytes $recordBytes
    if ([string]$receipt.schema_version -cne
            'stage1e-runtime-activation-stop-receipt-v1' -or
        [string]$receipt.interface_version -cne
            $script:Stage1EActivationStopInterface -or
        [string]$receipt.record_path -cne
            (ConvertTo-Stage1EActivationStopCanonicalPath $recordFull) -or
        [string]$receipt.publication_state -cne 'PUBLISHED' -or
        [int64]$receipt.record_byte_count -ne $recordBytes.Length -or
        [string]$receipt.record_sha256 -cne $digest -or
        [string]$receipt.request_identity -cne
            [string]$record.request_identity -or
        [string]$receipt.execution_id -cne [string]$record.execution_id -or
        [string]$receipt.attempt_id -cne [string]$record.attempt_id) {
        throw 'Structured activation-stop receipt does not bind the record.'
    }
    return [ordered]@{
        record = $record
        receipt = $receipt
        comparison_state = 'MATCH'
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EActivationStopInterfaceVersion'
    'ConvertFrom-Stage1EActivationStopLine'
    'New-Stage1EActivationStopRecord'
    'Assert-Stage1EActivationStopRecord'
    'Publish-Stage1EActivationStopRecord'
    'Read-Stage1EActivationStopPublication'
)
