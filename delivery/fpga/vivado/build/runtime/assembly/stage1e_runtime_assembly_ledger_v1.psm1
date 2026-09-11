Set-StrictMode -Version Latest

# PRT02-E pre-dispatch ledger validation is deliberately a disconnected
# review utility.  It derives its expected records from the frozen graph and
# reopens an immutable sealed ledger; callers cannot inject Expected/Actual
# arrays into the comparison.
$script:Stage1EAssemblyLedgerInterface =
    'stage1e-runtime-assembly-ledger-interface-v1'
$script:Stage1EAssemblyLedgerTypes = @(
    'HOST_ASSEMBLY_LEDGER',
    'VIVADO_ASSEMBLY_LEDGER',
    'POSTPROCESS_ASSEMBLY_LEDGER')
$script:Stage1EAssemblyLedgerFields = @(
    'role', 'source_path', 'provider', 'interface_version', 'domain',
    'load_ordinal', 'attempt_state', 'declared_edge')
$script:Stage1EAssemblyLedgerHeaderFields = @(
    'schema_version', 'ledger_type', 'publication_state',
    'request_identity', 'execution_id', 'attempt_id', 'source_identity',
    'record_count')
$script:Stage1EAssemblyLedgerRecordFields = @(
    'record_kind', 'role', 'source_path', 'provider', 'interface_version',
    'domain', 'load_ordinal', 'attempt_state', 'declared_edge')
$script:Stage1EAssemblyReceiptFields = @(
    'schema_version', 'ledger_type', 'ledger_path', 'publication_state',
    'ledger_byte_count', 'ledger_sha256')
$script:Stage1EAssemblyAttemptStates = @(
    'LOADED', 'OPTIONAL_NOT_LOADED', 'FAILED', 'BLOCKED')
$script:Stage1EAssemblyLedgerSchema =
    'stage1e-runtime-sealed-assembly-ledger-v1'
$script:Stage1EAssemblyReceiptSchema =
    'stage1e-runtime-assembly-ledger-publication-receipt-v1'

function Get-Stage1EAssemblyLedgerInterfaceVersion {
    return $script:Stage1EAssemblyLedgerInterface
}

function Get-Stage1ELedgerDependencyContracts {
    $path = Join-Path $PSScriptRoot '../../dependency/stage1e_runtime_dependency_closure_v1.psm1'
    Microsoft.PowerShell.Core\Import-Module -Name ([System.IO.Path]::GetFullPath($path)) `
        -Force -ErrorAction Stop
    $contracts = Import-Stage1EDependencyContracts
    $null = Assert-Stage1EDependencyContracts $contracts
    return $contracts
}

function Get-Stage1ELedgerScenario {
    param([Parameter(Mandatory = $true)][string]$LedgerType)
    switch ($LedgerType) {
        'HOST_ASSEMBLY_LEDGER' { return 'HOST_DISCONNECTED_SAFE_LOAD' }
        'VIVADO_ASSEMBLY_LEDGER' { return 'VIVADO_DISCONNECTED_SAFE_LOAD' }
        'POSTPROCESS_ASSEMBLY_LEDGER' { return 'POSTPROCESS_DISCONNECTED_SAFE_LOAD' }
        default { throw "Unknown assembly ledger type: $LedgerType" }
    }
}

function Get-Stage1EGraphLedgerProjection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LedgerType)
    if ($LedgerType -notin $script:Stage1EAssemblyLedgerTypes) {
        throw "Unknown assembly ledger type: $LedgerType"
    }
    $contracts = Get-Stage1ELedgerDependencyContracts
    $scenario = Get-Stage1ELedgerScenario $LedgerType
    $occurrence = $contracts.TraceExpectedOccurrences | Where-Object {
        $_.scenario -ceq $scenario } | Select-Object -First 1
    $providerOrder = $contracts.TraceProviderOrder | Where-Object {
        $_.scenario -ceq $scenario } | Select-Object -First 1
    if ($null -eq $occurrence -or $null -eq $providerOrder) {
        throw "Graph has no frozen ledger projection for $LedgerType."
    }
    $nodes = @{}
    foreach ($node in $contracts.Nodes) {
        $nodes[[string]$node.node_id] = $node
    }
    $domain = switch ($scenario) {
        'HOST_DISCONNECTED_SAFE_LOAD' { 'HOST_POWERSHELL' }
        'VIVADO_DISCONNECTED_SAFE_LOAD' { 'VIVADO_TCL' }
        default { 'HOST_POSTPROCESS_TCL' }
    }
    $records = [System.Collections.Generic.List[object]]::new()
    $ordinal = 0
    foreach ($keyText in @(ConvertFrom-Stage1ETclList -Text $occurrence.keys)) {
        $key = @(ConvertFrom-Stage1ETclList -Text $keyText)
        if ($key.Count -ne 3) {
            throw "Malformed frozen ledger occurrence in $scenario."
        }
        $target = [string]$key[1]
        if (-not $nodes.ContainsKey($target)) {
            throw "Ledger target is not a graph node: $target"
        }
        $node = $nodes[$target]
        $ordinal++
        $state = if ([string]$key[2] -eq 'DOTNET_SOURCE_PROVIDER' -or
            ($key[0] -ceq $key[1] -and [string]$key[2] -eq 'TCL_SOURCE')) {
            'OPTIONAL_NOT_LOADED'
        } else { 'LOADED' }
        $records.Add([ordered]@{
                role = [string]$node.role
                source_path = [string]$node.repository_path
                provider = 'NONE'
                interface_version = [string]$node.interface_version
                domain = $domain
                load_ordinal = $ordinal
                attempt_state = $state
                declared_edge = [string]$key[2]
            })
    }
    foreach ($providerKey in @(ConvertFrom-Stage1ETclList -Text $providerOrder.providers)) {
        $provider = $contracts.Providers | Where-Object {
            $_.provider_key -ceq $providerKey } | Select-Object -First 1
        if ($null -eq $provider) {
            throw "Frozen provider projection is undeclared: $providerKey"
        }
        $node = $contracts.Nodes | Where-Object {
            $_.repository_path -ceq [string]$provider.source_path } |
            Select-Object -First 1
        if ($null -eq $node) {
            throw "Frozen provider source has no graph node: $providerKey"
        }
        $providerDomains = @(([string]$provider.process_domains -split '\s+') |
            Where-Object { $_ -eq $domain })
        if ($providerDomains.Count -ne 1) {
            throw "Provider domain does not cover ${scenario}: $providerKey"
        }
        $ordinal++
        $records.Add([ordered]@{
                role = [string]$node.role
                source_path = [string]$provider.source_path
                provider = [string]$provider.provider_key
                interface_version = [string]$provider.interface_version
                domain = $domain
                load_ordinal = $ordinal
                attempt_state = 'LOADED'
                declared_edge = 'PROVIDER_OBSERVATION'
            })
    }
    return $records.ToArray()
}

function Assert-Stage1EAssemblyLedgerRecord {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $keys = @($Record.Keys | ForEach-Object { [string]$_ })
    if (($keys -join '|') -cne ($script:Stage1EAssemblyLedgerFields -join '|')) {
        throw "$Label has an incorrect exact field set/order."
    }
    if ([string]$Record['load_ordinal'] -notmatch '^[1-9][0-9]*$' -or
        [string]$Record['attempt_state'] -notin $script:Stage1EAssemblyAttemptStates) {
        throw "$Label has an invalid load ordinal or attempt state."
    }
    foreach ($field in $script:Stage1EAssemblyLedgerFields) {
        if ($field -ne 'load_ordinal' -and
            [string]::IsNullOrWhiteSpace([string]$Record[$field])) {
            throw "$Label has an empty $field."
        }
    }
    return $true
}

function ConvertFrom-Stage1ESealedFieldValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        if ($Value[$index] -cne '\') {
            $null = $builder.Append($Value[$index])
            continue
        }
        if ($index + 1 -ge $Value.Length) {
            throw 'Sealed-ledger field has a trailing escape.'
        }
        $index++
        switch ($Value[$index]) {
            'p' { $null = $builder.Append('|') }
            '\' { $null = $builder.Append('\') }
            'n' { $null = $builder.Append("`n") }
            'r' { $null = $builder.Append("`r") }
            't' { $null = $builder.Append("`t") }
            default { throw "Sealed-ledger field has an unsupported escape: $($Value[$index])" }
        }
    }
    return $builder.ToString()
}

function ConvertFrom-Stage1ESealedLedgerLine {
    param([Parameter(Mandatory = $true)][string]$Line)
    if ([string]::IsNullOrEmpty($Line)) { throw 'Sealed-ledger line is empty.' }
    $record = [ordered]@{}
    foreach ($field in $Line.Split('|')) {
        $separator = $field.IndexOf('=')
        if ($separator -lt 1) { throw "Malformed sealed-ledger field: $Line" }
        $key = $field.Substring(0, $separator)
        if ($key -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            throw "Invalid sealed-ledger field name: $key"
        }
        if ($record.Contains($key)) {
            throw "Duplicate sealed-ledger field: $key"
        }
        $record[$key] = ConvertFrom-Stage1ESealedFieldValue `
            $field.Substring($separator + 1)
    }
    return $record
}

function Assert-Stage1EExactFieldOrder {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $actual = @($Record.Keys | ForEach-Object { [string]$_ })
    if (($actual -join '|') -cne ($Expected -join '|')) {
        throw "$Label has an incorrect exact field set/order."
    }
}

function Read-Stage1ESealedLedgerHeader {
    param([Parameter(Mandatory = $true)][string]$Line)
    $header = ConvertFrom-Stage1ESealedLedgerLine $Line
    Assert-Stage1EExactFieldOrder $header `
        $script:Stage1EAssemblyLedgerHeaderFields 'Sealed ledger header'
    foreach ($field in $script:Stage1EAssemblyLedgerHeaderFields) {
        if ([string]::IsNullOrEmpty([string]$header[$field])) {
            throw "Sealed ledger header has an empty $field."
        }
    }
    if ([string]$header['record_count'] -notmatch '^(0|[1-9][0-9]*)$') {
        throw 'Sealed ledger header has an invalid record_count.'
    }
    return $header
}

function Read-Stage1ESealedLedgerRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Line,
        [Parameter(Mandatory = $true)][int]$Ordinal
    )
    $raw = ConvertFrom-Stage1ESealedLedgerLine $Line
    Assert-Stage1EExactFieldOrder $raw `
        $script:Stage1EAssemblyLedgerRecordFields "Sealed ledger record $Ordinal"
    if ([string]$raw['record_kind'] -cne 'RECORD') {
        throw "Sealed ledger record $Ordinal is not a RECORD line."
    }
    $payload = [ordered]@{}
    foreach ($field in $script:Stage1EAssemblyLedgerFields) {
        $payload[$field] = $raw[$field]
    }
    $null = Assert-Stage1EAssemblyLedgerRecord $payload "Sealed ledger record $Ordinal"
    if ([int]$payload['load_ordinal'] -ne $Ordinal) {
        throw "Sealed ledger record $Ordinal has a noncanonical load ordinal."
    }
    return $payload
}

function Read-Stage1ESealedAssemblyLedger {
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and
        $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        throw 'Sealed assembly ledger contains a UTF-8 BOM.'
    }
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $lines = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    if ($lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = @($lines | Select-Object -First ($lines.Count - 1))
    }
    if ($lines.Count -lt 1) { throw 'Sealed assembly ledger is empty.' }
    if (@($lines | Where-Object { $_ -eq '' }).Count -gt 0) {
        throw 'Sealed assembly ledger contains a blank line.'
    }
    $header = Read-Stage1ESealedLedgerHeader $lines[0]
    $records = [System.Collections.Generic.List[object]]::new()
    for ($index = 1; $index -lt $lines.Count; $index++) {
        $records.Add((Read-Stage1ESealedLedgerRecord $lines[$index] $index))
    }
    if ([int]$header['record_count'] -ne $records.Count) {
        throw 'Sealed ledger header record_count does not match its records.'
    }
    return [pscustomobject]@{
        Bytes = $bytes
        Header = $header
        Records = $records.ToArray()
    }
}

function Read-Stage1EAssemblyPublicationReceipt {
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and
        $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        throw 'Assembly publication receipt contains a UTF-8 BOM.'
    }
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $lines = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") })
    if ($lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = @($lines | Select-Object -First ($lines.Count - 1))
    }
    if ($lines.Count -ne 1) {
        throw 'Assembly publication receipt must contain one line.'
    }
    $receipt = ConvertFrom-Stage1ESealedLedgerLine $lines[0]
    Assert-Stage1EExactFieldOrder $receipt $script:Stage1EAssemblyReceiptFields `
        'Assembly publication receipt'
    foreach ($field in $script:Stage1EAssemblyReceiptFields) {
        if ([string]::IsNullOrEmpty([string]$receipt[$field])) {
            throw "Assembly publication receipt has an empty $field."
        }
    }
    if ([string]$receipt['ledger_byte_count'] -notmatch '^(0|[1-9][0-9]*)$' -or
        [string]$receipt['ledger_sha256'] -notmatch '^[0-9a-f]{64}$') {
        throw 'Assembly publication receipt has invalid byte-integrity metadata.'
    }
    return $receipt
}

function Assert-Stage1EPreDispatchAssemblyLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LedgerType,
        [Parameter(Mandatory = $true)][string]$LedgerPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$RequestIdentity,
        [Parameter(Mandatory = $true)][string]$ExecutionId,
        [Parameter(Mandatory = $true)][string]$AttemptId,
        [Parameter(Mandatory = $true)][string]$SourceIdentity
    )
    if ($LedgerType -notin $script:Stage1EAssemblyLedgerTypes) {
        throw "Unknown assembly ledger type: $LedgerType"
    }
    foreach ($value in @($RequestIdentity, $ExecutionId, $AttemptId,
            $SourceIdentity)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw 'Ledger binding fields must be nonempty.'
        }
    }
    $ledgerFullPath = [System.IO.Path]::GetFullPath($LedgerPath)
    $receiptFullPath = [System.IO.Path]::GetFullPath($ReceiptPath)
    if (-not [System.IO.File]::Exists($ledgerFullPath) -or
        -not [System.IO.File]::Exists($receiptFullPath)) {
        throw 'Ledger and receipt paths must identify existing files.'
    }
    foreach ($path in @($ledgerFullPath, $receiptFullPath)) {
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Ledger and receipt files must not be reparse points.'
        }
    }
    $ledger = Read-Stage1ESealedAssemblyLedger $ledgerFullPath
    $receipt = Read-Stage1EAssemblyPublicationReceipt $receiptFullPath
    if ([string]$ledger.Header['schema_version'] -cne
            $script:Stage1EAssemblyLedgerSchema -or
        [string]$ledger.Header['ledger_type'] -cne $LedgerType -or
        [string]$ledger.Header['publication_state'] -cne 'SEALED') {
        throw 'Sealed ledger header does not match its authoritative type/state.'
    }
    foreach ($binding in @('request_identity', 'execution_id', 'attempt_id',
            'source_identity')) {
        $expectedBinding = switch ($binding) {
            'request_identity' { $RequestIdentity }
            'execution_id' { $ExecutionId }
            'attempt_id' { $AttemptId }
            default { $SourceIdentity }
        }
        if ([string]$ledger.Header[$binding] -cne $expectedBinding) {
            throw "Ledger binding mismatch: $binding"
        }
    }
    $ledgerCanonicalPath = $ledgerFullPath.Replace('\', '/')
    if ([string]$receipt['schema_version'] -cne
            $script:Stage1EAssemblyReceiptSchema -or
        [string]$receipt['ledger_type'] -cne $LedgerType -or
        -not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            [string]$receipt['ledger_path'], $ledgerCanonicalPath) -or
        [string]$receipt['publication_state'] -cne 'PUBLISHED') {
        throw 'Assembly publication receipt binding/state is invalid.'
    }
    $dependencyModule = Join-Path $PSScriptRoot '../../dependency/stage1e_runtime_dependency_closure_v1.psm1'
    Microsoft.PowerShell.Core\Import-Module -Name ([System.IO.Path]::GetFullPath($dependencyModule)) `
        -Force -Global -ErrorAction Stop
    $hashCommand = Get-Command -Name Get-Stage1EDependencySha256Hex `
        -Module stage1e_runtime_dependency_closure_v1 -ErrorAction Stop
    $digest = & $hashCommand -Bytes $ledger.Bytes
    if ([int64]$receipt['ledger_byte_count'] -ne $ledger.Bytes.Length -or
        [string]$receipt['ledger_sha256'] -cne $digest) {
        throw 'Assembly publication receipt byte count or SHA-256 differs.'
    }
    $expected = @(Get-Stage1EGraphLedgerProjection $LedgerType)
    if ($ledger.Records.Count -ne $expected.Count) {
        throw "$LedgerType sealed record count differs from the frozen graph projection."
    }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        foreach ($field in $script:Stage1EAssemblyLedgerFields) {
            if ([string]$expected[$index][$field] -cne
                [string]$ledger.Records[$index][$field]) {
                throw "$LedgerType authoritative mismatch at record $($index + 1), field $field."
            }
        }
    }
    return [pscustomobject]@{
        ledger_type = $LedgerType
        comparison_state = 'MATCH'
        expected_source = 'FROZEN_DECLARED_GRAPH_DOMAIN_PROJECTION'
        actual_source = 'REOPENED_SEALED_LEDGER_RECORD'
        receipt_state = 'PUBLISHED_AND_BYTE_INTEGRITY_VERIFIED'
        record_count = $expected.Count
        ledger_sha256 = $digest
        dispatch_state = 'VALIDATED_NOT_CONNECTED'
        integration_state = 'PRE_DISPATCH_INTEGRATION_NOT_CONNECTED'
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EAssemblyLedgerInterfaceVersion',
    'Get-Stage1EGraphLedgerProjection',
    'Assert-Stage1EPreDispatchAssemblyLedger')
