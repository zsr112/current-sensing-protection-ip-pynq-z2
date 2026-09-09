Set-StrictMode -Version Latest

$canonicalModule = Join-Path $PSScriptRoot 'stage1e_runtime_canonical_json_v1.psm1'
Import-Module -Name $canonicalModule -Force -ErrorAction Stop

$script:Stage1EEnvelopeContractInterface = 'stage1e-runtime-envelope-contract-interface-v1'
$script:Stage1ESupportedSchemaKeywords = @(
    '$schema', '$id', 'title', '$ref', '$defs',
    'type', 'required', 'additionalProperties',
    'x-stage1e-canonical-order', 'properties',
    'oneOf', 'const', 'enum',
    'minimum', 'maximum', 'minLength', 'maxLength',
    'items', 'minItems', 'maxItems', 'uniqueItems',
    'x-stage1e-format'
)

function Get-Stage1EEnvelopeContractInterfaceVersion {
    return $script:Stage1EEnvelopeContractInterface
}

function Assert-Stage1ESchemaStringArray {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$Unique
    )

    if ($Value -isnot [System.Collections.IList] -or $Value -is [string]) {
        throw [System.IO.InvalidDataException]::new("$Label must be an array.")
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($item in $Value) {
        if ($item -isnot [string] -or [string]::IsNullOrEmpty($item)) {
            throw [System.IO.InvalidDataException]::new(
                "$Label must contain nonempty strings.")
        }
        if ($Unique -and -not $seen.Add([string]$item)) {
            throw [System.IO.InvalidDataException]::new(
                "$Label contains a duplicate value '$item'.")
        }
    }
    return $seen
}

function Assert-Stage1ESchemaMetaNode {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Node,
        [Parameter(Mandatory = $true)][string]$Path
    )

    foreach ($keyValue in $Node.Keys) {
        $key = [string]$keyValue
        if ($script:Stage1ESupportedSchemaKeywords -cnotcontains $key) {
            throw [System.IO.InvalidDataException]::new(
                "Unsupported schema keyword '$key' at $Path.")
        }
    }

    if ($Node.Contains('type')) {
        $type = [string]$Node.type
        if (@('object', 'array', 'string', 'integer', 'boolean') -cnotcontains $type) {
            throw [System.IO.InvalidDataException]::new(
                "Unsupported schema type '$type' at $Path.")
        }
        if ($type -eq 'object') {
            foreach ($keyword in @(
                    'properties', 'required', 'additionalProperties',
                    'x-stage1e-canonical-order')) {
                if (-not $Node.Contains($keyword)) {
                    throw [System.IO.InvalidDataException]::new(
                        "Exact object schema at $Path lacks '$keyword'.")
                }
            }
            if ($Node.properties -isnot [System.Collections.IDictionary] -or
                [bool]$Node.additionalProperties) {
                throw [System.IO.InvalidDataException]::new(
                    "Object schema at $Path is not exact-field closed.")
            }
            $required = Assert-Stage1ESchemaStringArray $Node.required `
                "$Path.required" -Unique
            $order = Assert-Stage1ESchemaStringArray `
                $Node['x-stage1e-canonical-order'] `
                "$Path.x-stage1e-canonical-order" -Unique
            if ($required.Count -ne $Node.properties.Count -or
                $order.Count -ne $Node.properties.Count) {
                throw [System.IO.InvalidDataException]::new(
                    "Object schema at $Path has incomplete field metadata.")
            }
            foreach ($propertyValue in $Node.properties.Keys) {
                $property = [string]$propertyValue
                if (-not $required.Contains($property) -or
                    -not $order.Contains($property)) {
                    throw [System.IO.InvalidDataException]::new(
                        "Object schema at $Path does not require/order '$property'.")
                }
                $child = $Node.properties[$property]
                if ($child -isnot [System.Collections.IDictionary]) {
                    throw [System.IO.InvalidDataException]::new(
                        "Property schema at $Path.properties.$property is not an object.")
                }
                Assert-Stage1ESchemaMetaNode $child "$Path.properties.$property"
            }
        }
        elseif ($type -eq 'array' -and $Node.Contains('items')) {
            if ($Node.items -isnot [System.Collections.IDictionary]) {
                throw [System.IO.InvalidDataException]::new(
                    "Array item schema at $Path is not an object.")
            }
            Assert-Stage1ESchemaMetaNode $Node.items "$Path.items"
        }
    }

    if ($Node.Contains('oneOf')) {
        if ($Node.oneOf -isnot [System.Collections.IList] -or
            $Node.oneOf.Count -lt 2) {
            throw [System.IO.InvalidDataException]::new(
                "oneOf at $Path must contain at least two branches.")
        }
        for ($index = 0; $index -lt $Node.oneOf.Count; $index++) {
            if ($Node.oneOf[$index] -isnot [System.Collections.IDictionary]) {
                throw [System.IO.InvalidDataException]::new(
                    "oneOf branch at $Path[$index] is not an object.")
            }
            Assert-Stage1ESchemaMetaNode $Node.oneOf[$index] "$Path.oneOf[$index]"
        }
    }
    if ($Node.Contains('$defs')) {
        if ($Node['$defs'] -isnot [System.Collections.IDictionary]) {
            throw [System.IO.InvalidDataException]::new("$Path.`$defs must be an object.")
        }
        foreach ($nameValue in $Node['$defs'].Keys) {
            $name = [string]$nameValue
            $definition = $Node['$defs'][$name]
            if ($definition -isnot [System.Collections.IDictionary]) {
                throw [System.IO.InvalidDataException]::new(
                    "Definition at $Path.`$defs.$name is not an object.")
            }
            Assert-Stage1ESchemaMetaNode $definition "$Path.`$defs.$name"
        }
    }
}

function Import-Stage1EEnvelopeContract {
    [CmdletBinding()]
    param([string]$SchemaRoot = $PSScriptRoot)

    $root = [System.IO.Path]::GetFullPath($SchemaRoot)
    $specifications = @(
        [ordered]@{
            Role = 'failure'
            File = 'stage1e_runtime_failure_record_v1.schema.json'
            Id = 'stage1e-runtime-failure-record-v1'
        }
        [ordered]@{
            Role = 'request'
            File = 'stage1e_runtime_request_envelope_v1.schema.json'
            Id = 'stage1e-production-runtime-request-envelope-v1'
        }
        [ordered]@{
            Role = 'result'
            File = 'stage1e_runtime_result_envelope_v1.schema.json'
            Id = 'stage1e-production-runtime-result-envelope-v1'
        }
    )
    $registry = [ordered]@{}
    $byRole = [ordered]@{}
    $paths = [ordered]@{}
    foreach ($specification in $specifications) {
        $path = Join-Path $root $specification.File
        if (-not [System.IO.File]::Exists($path)) {
            throw [System.IO.FileNotFoundException]::new(
                "Required Stage 1E schema is missing: $path", $path)
        }
        $bytes = Read-Stage1EJsonFileBytes -LiteralPath $path
        $schema = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes $bytes
        Assert-Stage1ESchemaMetaNode $schema '$'
        if (-not $schema.Contains('$schema') -or
            [string]$schema['$schema'] -cne 'stage1e-schema-subset-v1') {
            throw [System.IO.InvalidDataException]::new(
                "Schema subset version mismatch in $path.")
        }
        if (-not $schema.Contains('$id') -or
            [string]$schema['$id'] -cne $specification.Id) {
            throw [System.IO.InvalidDataException]::new(
                "Schema identity mismatch in $path.")
        }
        if ($registry.Contains($specification.Id)) {
            throw [System.IO.InvalidDataException]::new(
                "Duplicate schema identity '$($specification.Id)'.")
        }
        $registry.Add($specification.Id, $schema)
        $byRole.Add($specification.Role, $schema)
        $paths.Add($specification.Role,
            [System.IO.Path]::GetFullPath($path))
    }
    return [ordered]@{
        interface_version = $script:Stage1EEnvelopeContractInterface
        schema_registry = $registry
        request_schema = $byRole.request
        result_schema = $byRole.result
        failure_schema = $byRole.failure
        schema_paths = $paths
    }
}

function Copy-Stage1EWithoutIdentity {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][string]$IdentityField
    )

    $copy = [ordered]@{}
    foreach ($nameValue in @($Schema['x-stage1e-canonical-order'])) {
        $name = [string]$nameValue
        if ($name -ceq $IdentityField) { continue }
        if (-not $Record.Contains($name)) {
            throw [System.IO.InvalidDataException]::new(
                "Identity payload lacks required property '$name'.")
        }
        $copy.Add($name, $Record[$name])
    }
    foreach ($keyValue in $Record.Keys) {
        $key = [string]$keyValue
        if ($key -cne $IdentityField -and -not $copy.Contains($key)) {
            throw [System.IO.InvalidDataException]::new(
                "Identity payload contains unknown property '$key'.")
        }
    }
    return $copy
}

function Add-Stage1EIdentityToRecord {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Payload,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Registry,
        [Parameter(Mandatory = $true)][string]$IdentityField,
        [scriptblock]$DigestProvider
    )

    if ($Payload.Contains($IdentityField)) {
        throw [System.IO.InvalidDataException]::new(
            "Identity payload must not contain '$IdentityField'.")
    }
    $bytes = ConvertTo-Stage1ECanonicalJsonBytes -Value $Payload `
        -Schema $Schema -SchemaRegistry $Registry -OmitProperty $IdentityField
    $identity = Get-Stage1ECanonicalDigest -Bytes $bytes `
        -DigestProvider $DigestProvider
    $complete = [ordered]@{}
    foreach ($nameValue in @($Schema['x-stage1e-canonical-order'])) {
        $name = [string]$nameValue
        if ($name -ceq $IdentityField) {
            $complete.Add($name, $identity)
        }
        elseif ($Payload.Contains($name)) {
            $complete.Add($name, $Payload[$name])
        }
        else {
            throw [System.IO.InvalidDataException]::new(
                "Identity payload lacks required property '$name'.")
        }
    }
    return $complete
}

function Get-Stage1ERecordIdentity {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Registry,
        [Parameter(Mandatory = $true)][string]$IdentityField,
        [scriptblock]$DigestProvider
    )

    $payload = Copy-Stage1EWithoutIdentity $Record $Schema $IdentityField
    $bytes = ConvertTo-Stage1ECanonicalJsonBytes -Value $payload `
        -Schema $Schema -SchemaRegistry $Registry -OmitProperty $IdentityField
    return Get-Stage1ECanonicalDigest -Bytes $bytes `
        -DigestProvider $DigestProvider
}

function Assert-Stage1EFailureRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract
    )

    $null = Assert-Stage1EJsonSchemaValue -Value $Record `
        -Schema $Contract.failure_schema -RootSchema $Contract.failure_schema `
        -SchemaRegistry $Contract.schema_registry
    if ($Record.terminal_status -eq 'COMPLETED') {
        if ($Record.failure_category -ne 'NONE') {
            throw [System.IO.InvalidDataException]::new(
                'A completed failure record must use category NONE.')
        }
    }
    elseif ($Record.failure_category -eq 'NONE') {
        throw [System.IO.InvalidDataException]::new(
            'A blocked or failed record must name a failure category.')
    }
    if ($Record.terminal_status -in @('BLOCKED', 'FAILED') -and
        $Record.candidate_effect -ne 'NOT_CREATED') {
        throw [System.IO.InvalidDataException]::new(
            'A blocked or failed record cannot create a candidate.')
    }
    return $true
}

function Get-Stage1EFullPathComponents {
    param([Parameter(Mandatory = $true)][string]$Path)

    $nativePath = $Path.Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar)
    $fullPath = [System.IO.Path]::GetFullPath($nativePath)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrEmpty($root)) {
        throw [System.IO.InvalidDataException]::new(
            "Path does not have a structured absolute root: $Path")
    }
    $components = [System.Collections.Generic.List[string]]::new()
    $components.Add($root.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar))
    $relative = $fullPath.Substring($root.Length).Trim(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if ($relative.Length -gt 0) {
        foreach ($component in $relative.Split(
                [char[]]@(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar),
                [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $components.Add($component)
        }
    }
    return [object[]]$components.ToArray()
}

function Test-Stage1EFullPathEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    try {
        $leftComponents = @(Get-Stage1EFullPathComponents $Left)
        $rightComponents = @(Get-Stage1EFullPathComponents $Right)
    }
    catch {
        return $false
    }
    if ($leftComponents.Count -ne $rightComponents.Count) { return $false }
    for ($index = 0; $index -lt $leftComponents.Count; $index++) {
        if (-not ([string]$leftComponents[$index]).Equals(
                [string]$rightComponents[$index],
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Test-Stage1EPathWithinBoundary {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Boundary
    )

    try {
        $candidateComponents = @(Get-Stage1EFullPathComponents $Candidate)
        $boundaryComponents = @(Get-Stage1EFullPathComponents $Boundary)
    }
    catch {
        return $false
    }
    if ($candidateComponents.Count -lt $boundaryComponents.Count) {
        return $false
    }
    for ($index = 0; $index -lt $boundaryComponents.Count; $index++) {
        if (-not ([string]$candidateComponents[$index]).Equals(
                [string]$boundaryComponents[$index],
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Test-Stage1EPathsDisjoint {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    return (-not (Test-Stage1EPathWithinBoundary $Left $Right) -and
        -not (Test-Stage1EPathWithinBoundary $Right $Left))
}

function Assert-Stage1EOperationNode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Node,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ConfiguredState,
        [Parameter(Mandatory = $true)][bool]$Authorized,
        [Parameter(Mandatory = $true)][int64]$Sequence,
        [Parameter(Mandatory = $true)][string]$Directive,
        [Parameter(Mandatory = $true)][string]$Predecessor,
        [Parameter(Mandatory = $true)][string]$InvocationPolicy
    )

    if ([string]$Node.configured_state -cne $ConfiguredState -or
        [bool]$Node.authorized -ne $Authorized -or
        [int64]$Node.sequence -ne $Sequence -or
        [string]$Node.directive -cne $Directive -or
        [string]$Node.predecessor -cne $Predecessor -or
        [string]$Node.invocation_policy -cne $InvocationPolicy) {
        throw [System.IO.InvalidDataException]::new(
            "Effective operation node differs from the frozen graph: $Name")
    }
}

function Assert-Stage1ERequestSemantics {
    param([System.Collections.IDictionary]$Record)

    $authorization = $Record.authorization
    $evidence = $Record.evidence_contract
    foreach ($field in @(
            'execution_id', 'source_identity', 'runtime_backend_identity',
            'policy_identity', 'configuration_identity',
            'qualification_identity', 'environment_identity',
            'workspace_identity', 'synthesis_result_identity')) {
        if ([string]$authorization[$field] -cne [string]$Record[$field]) {
            throw [System.IO.InvalidDataException]::new(
                "Authorization binding '$field' differs from the request.")
        }
    }
    if ([string]$evidence.execution_id -cne
        [string]$Record.execution_id -or
        [string]$evidence.workspace_identity -cne
        [string]$Record.workspace_identity) {
        throw [System.IO.InvalidDataException]::new(
            'Evidence execution/workspace bindings differ from the request.')
    }
    if ([string]$authorization.consumption_record_path -cne
        [string]$evidence.authorization_consumption_record_path) {
        throw [System.IO.InvalidDataException]::new(
            'Authorization consumption-record path differs from the evidence contract.')
    }

    $implementation = $Record.implementation_contract
    $graph = $implementation.effective_step_graph
    Assert-Stage1EOperationNode $graph.opt_design 'opt_design' 'ENABLED' `
        $true 1 ([string]$implementation.opt_design_directive) `
        'synthesis' 'REQUIRED'
    Assert-Stage1EOperationNode $graph.place_design 'place_design' 'ENABLED' `
        $true 2 ([string]$implementation.place_design_directive) `
        'opt_design' 'REQUIRED'
    Assert-Stage1EOperationNode $graph.phys_opt_design 'phys_opt_design' `
        'DISABLED' $false 0 'NONE' 'place_design' 'PROHIBITED'
    Assert-Stage1EOperationNode $graph.route_design 'route_design' 'ENABLED' `
        $true 3 ([string]$implementation.route_design_directive) `
        'place_design' 'REQUIRED'
    Assert-Stage1EOperationNode $graph.implementation_reports `
        'implementation_reports' 'ENABLED' $true 4 'READ_ONLY' `
        'route_design' 'REQUIRED'

    $total = [int64]$Record.timeout_contract.total_lifetime_seconds
    foreach ($nameValue in $Record.timeout_contract.Keys) {
        $name = [string]$nameValue
        if ($name -ne 'total_lifetime_seconds' -and
            [int64]$Record.timeout_contract[$name] -gt $total) {
            throw [System.IO.InvalidDataException]::new(
                "Timeout '$name' exceeds the total lifetime budget.")
        }
    }

    $launch = $Record.launch_contract
    $expectedXilRoot = [System.IO.Path]::Combine(
        ([string]$launch.workspace_root).Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar), '.Xil')
    if (-not (Test-Stage1EFullPathEqual $launch.cwd `
            $launch.workspace_root) -or
        -not (Test-Stage1EFullPathEqual $launch.xil_root `
            $expectedXilRoot)) {
        throw [System.IO.InvalidDataException]::new(
            'Launch cwd/workspace/.Xil bindings are inconsistent.')
    }

    $separatedRootNames = @('source_root', 'workspace_root', 'evidence_root')
    for ($leftIndex = 0; $leftIndex -lt $separatedRootNames.Count;
            $leftIndex++) {
        for ($rightIndex = $leftIndex + 1;
                $rightIndex -lt $separatedRootNames.Count; $rightIndex++) {
            $leftName = $separatedRootNames[$leftIndex]
            $rightName = $separatedRootNames[$rightIndex]
            if (-not (Test-Stage1EPathsDisjoint $launch[$leftName] `
                    $launch[$rightName])) {
                throw [System.IO.InvalidDataException]::new(
                    "Launch roots '$leftName' and '$rightName' overlap.")
            }
        }
    }

    $ownedRoots = [ordered]@{
        log_root = 'evidence_root'
        journal_root = 'evidence_root'
        temporary_root = 'workspace_root'
        cache_root = 'workspace_root'
        request_root = 'evidence_root'
    }
    foreach ($rootNameValue in $ownedRoots.Keys) {
        $rootName = [string]$rootNameValue
        $ownerName = [string]$ownedRoots[$rootName]
        if (-not (Test-Stage1EPathWithinBoundary `
                -Candidate $launch[$rootName] -Boundary $launch[$ownerName])) {
            throw [System.IO.InvalidDataException]::new(
                "Launch root '$rootName' is outside '$ownerName'.")
        }
    }
    $requestIsContained = Test-Stage1EPathWithinBoundary `
        -Candidate $evidence.request_path `
        -Boundary $launch.request_root
    if (-not $requestIsContained) {
        throw [System.IO.InvalidDataException]::new(
            'Request path is outside its declared request root.')
    }
    $seenPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($nameValue in $evidence.Keys) {
        $value = $evidence[$nameValue]
        if ($value -is [string] -and
            ($value.StartsWith('/') -or
                ($value.Length -ge 3 -and $value[1] -eq ':' -and $value[2] -eq '/'))) {
            foreach ($seenPath in $seenPaths) {
                if (Test-Stage1EFullPathEqual $value $seenPath) {
                    throw [System.IO.InvalidDataException]::new(
                        "Evidence contract reuses path '$value'.")
                }
            }
            $seenPaths.Add($value)
        }
    }
    foreach ($nameValue in $evidence.Keys) {
        $name = [string]$nameValue
        $value = $evidence[$name]
        if ($name -eq 'request_path' -or $value -isnot [string] -or
            -not ($value.StartsWith('/') -or
                ($value.Length -ge 3 -and $value[1] -eq ':' -and $value[2] -eq '/'))) {
            continue
        }
        $evidenceIsContained = Test-Stage1EPathWithinBoundary `
            -Candidate $value -Boundary $launch.evidence_root
        if (-not $evidenceIsContained) {
            throw [System.IO.InvalidDataException]::new(
                "Evidence path '$name' is outside the evidence root.")
        }
    }
    return $true
}

function Assert-Stage1ERequestEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [string]$ExpectedRequestIdentity,
        [scriptblock]$DigestProvider
    )

    $null = Assert-Stage1EJsonSchemaValue -Value $Record `
        -Schema $Contract.request_schema -RootSchema $Contract.request_schema `
        -SchemaRegistry $Contract.schema_registry
    $null = Assert-Stage1ERequestSemantics $Record
    $computed = Get-Stage1ERecordIdentity $Record $Contract.request_schema `
        $Contract.schema_registry 'request_identity' $DigestProvider
    if ([string]$Record.request_identity -cne $computed) {
        throw [System.IO.InvalidDataException]::new(
            'Embedded request identity does not match the canonical payload.')
    }
    if (-not [string]::IsNullOrEmpty($ExpectedRequestIdentity) -and
        $ExpectedRequestIdentity -cne $computed) {
        throw [System.IO.InvalidDataException]::new(
            'Caller-expected request identity does not match the canonical payload.')
    }
    return $computed
}

function Add-Stage1ERequestIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Payload,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [scriptblock]$DigestProvider
    )

    return Add-Stage1EIdentityToRecord $Payload $Contract.request_schema `
        $Contract.schema_registry 'request_identity' $DigestProvider
}

function ConvertTo-Stage1ERequestEnvelopeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [scriptblock]$DigestProvider
    )

    $null = Assert-Stage1ERequestEnvelope $Record $Contract '' $DigestProvider
    return ConvertTo-Stage1ECanonicalJsonBytes $Record `
        $Contract.request_schema $Contract.schema_registry
}

function ConvertFrom-Stage1ERequestEnvelopeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [Parameter(Mandatory = $true)][string]$ExpectedRequestIdentity,
        [scriptblock]$DigestProvider
    )

    $record = ConvertFrom-Stage1ECanonicalJsonEnvelope $Bytes `
        $Contract.request_schema $Contract.schema_registry
    $null = Assert-Stage1ERequestEnvelope $record $Contract `
        $ExpectedRequestIdentity $DigestProvider
    return $record
}

function Assert-Stage1EComponentReference {
    param([System.Collections.IDictionary]$Reference)

    if ($Reference.status -eq 'PRESENT') {
        if ($Reference.path -eq 'NONE' -or
            $Reference.component_identity -eq 'NONE' -or
            $Reference.missing_reason -ne 'NONE') {
            throw [System.IO.InvalidDataException]::new(
                'Present component reference has missing-state values.')
        }
    }
    else {
        if ($Reference.path -ne 'NONE' -or
            $Reference.component_identity -ne 'NONE' -or
            $Reference.missing_reason -eq 'NONE') {
            throw [System.IO.InvalidDataException]::new(
                'Missing component reference is not explicit.')
        }
    }
}

function Assert-Stage1EResultSemantics {
    param(
        [System.Collections.IDictionary]$Record,
        [System.Collections.IDictionary]$Contract
    )

    if ($Record.terminal_status -eq 'COMPLETED') {
        if ($Record.first_failure -ne 'NONE') {
            throw [System.IO.InvalidDataException]::new(
                'Completed result must have first_failure NONE.')
        }
    }
    else {
        if ($Record.first_failure -isnot [System.Collections.IDictionary]) {
            throw [System.IO.InvalidDataException]::new(
                'Blocked or failed result must contain a failure record.')
        }
        $null = Assert-Stage1EFailureRecord $Record.first_failure $Contract
        if ($Record.first_failure.terminal_status -ne $Record.terminal_status) {
            throw [System.IO.InvalidDataException]::new(
                'First failure terminal status differs from the result.')
        }
    }
    Assert-Stage1EComponentReference $Record.host_result
    Assert-Stage1EComponentReference $Record.vivado_capability_result
    Assert-Stage1EComponentReference $Record.parser_result
    if ($Record.assembly_result.dependency_closure_state -eq
            'PARTIAL_FOUNDATION' -and
        $Record.terminal_status -eq 'COMPLETED') {
        throw [System.IO.InvalidDataException]::new(
            'Partial foundation assembly cannot produce a completed result.')
    }
    if ($Record.forbidden_boundary_result.status -ne 'CLEAR' -and
        $Record.terminal_status -eq 'COMPLETED') {
        throw [System.IO.InvalidDataException]::new(
            'An uncleared forbidden boundary blocks candidate eligibility.')
    }
    foreach ($secondary in @($Record.assembly_result.secondary_failures)) {
        $null = Assert-Stage1EFailureRecord $secondary $Contract
    }
    return $true
}

function Assert-Stage1EResultEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [string]$ExpectedResultIdentity,
        [scriptblock]$DigestProvider
    )

    $null = Assert-Stage1EJsonSchemaValue -Value $Record `
        -Schema $Contract.result_schema -RootSchema $Contract.result_schema `
        -SchemaRegistry $Contract.schema_registry
    $null = Assert-Stage1EResultSemantics $Record $Contract
    $computed = Get-Stage1ERecordIdentity $Record $Contract.result_schema `
        $Contract.schema_registry 'result_identity' $DigestProvider
    if ([string]$Record.result_identity -cne $computed) {
        throw [System.IO.InvalidDataException]::new(
            'Embedded result identity does not match the canonical payload.')
    }
    if (-not [string]::IsNullOrEmpty($ExpectedResultIdentity) -and
        $ExpectedResultIdentity -cne $computed) {
        throw [System.IO.InvalidDataException]::new(
            'Expected result identity does not match the canonical payload.')
    }
    return $computed
}

function Add-Stage1EResultIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Payload,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [scriptblock]$DigestProvider
    )

    return Add-Stage1EIdentityToRecord $Payload $Contract.result_schema `
        $Contract.schema_registry 'result_identity' $DigestProvider
}

function ConvertTo-Stage1EResultEnvelopeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [scriptblock]$DigestProvider
    )

    $null = Assert-Stage1EResultEnvelope $Record $Contract '' $DigestProvider
    return ConvertTo-Stage1ECanonicalJsonBytes $Record `
        $Contract.result_schema $Contract.schema_registry
}

function ConvertFrom-Stage1EResultEnvelopeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [Parameter(Mandatory = $true)][string]$ExpectedResultIdentity,
        [scriptblock]$DigestProvider
    )

    $record = ConvertFrom-Stage1ECanonicalJsonEnvelope $Bytes `
        $Contract.result_schema $Contract.schema_registry
    $null = Assert-Stage1EResultEnvelope $record $Contract `
        $ExpectedResultIdentity $DigestProvider
    return $record
}

Export-ModuleMember -Function @(
    'Get-Stage1EEnvelopeContractInterfaceVersion'
    'Import-Stage1EEnvelopeContract'
    'Assert-Stage1EFailureRecord'
    'Assert-Stage1ERequestEnvelope'
    'Assert-Stage1EResultEnvelope'
    'Add-Stage1ERequestIdentity'
    'Add-Stage1EResultIdentity'
    'ConvertTo-Stage1ERequestEnvelopeBytes'
    'ConvertFrom-Stage1ERequestEnvelopeBytes'
    'ConvertTo-Stage1EResultEnvelopeBytes'
    'ConvertFrom-Stage1EResultEnvelopeBytes'
)
