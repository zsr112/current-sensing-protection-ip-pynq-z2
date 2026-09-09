[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RequestPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedRequestIdentity
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$exitResultPublished = 0
$exitInvocationBlocked = 20
$exitResultPublicationFailed = 21
$exitEntrypointTerminated = 22

function ConvertTo-Stage1EEntryCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).Replace(
        [System.IO.Path]::DirectorySeparatorChar, '/')
}

function Test-Stage1EEntrySha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value.Length -ne 64 -or $Value -ceq ('0' * 64)) { return $false }
    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character
        if (-not (($code -ge 0x30 -and $code -le 0x39) -or
                ($code -ge 0x61 -and $code -le 0x66))) {
            return $false
        }
    }
    return $true
}

function Test-Stage1EEntryContained {
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

function Test-Stage1EEntryBytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function New-Stage1EEntryFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Component,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$CausalReferences = @()
    )

    return [ordered]@{
        terminal_status = 'BLOCKED'
        failure_category = $Category
        failure_code = $Code
        failure_component = $Component
        failure_phase = $Phase
        first_failure_ordinal = 1
        authorization_effect = 'NOT_TOUCHED'
        process_effect = 'NOT_STARTED'
        evidence_state = 'PARTIAL_PRESERVED'
        retry_disposition = 'RETRY_PROHIBITED_PENDING_RUNTIME_FIX'
        candidate_effect = 'NOT_CREATED'
        message = $Message
        causal_evidence_references = [object[]]@($CausalReferences)
    }
}

function New-Stage1EEntryException {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $exception = [System.IO.InvalidDataException]::new($Message)
    $exception.Data['stage1e_category'] = $Category
    $exception.Data['stage1e_code'] = $Code
    return $exception
}

function New-Stage1EMissingReference {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaVersion,
        [Parameter(Mandatory = $true)][string]$Producer,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Request
    )

    return [ordered]@{
        schema_version = $SchemaVersion
        status = 'MISSING'
        path = 'NONE'
        component_identity = 'NONE'
        producer = $Producer
        execution_id = [string]$Request.execution_id
        workspace_identity = [string]$Request.workspace_identity
        missing_reason = 'DEPENDENCY_NOT_IMPLEMENTED'
    }
}

function Add-Stage1ELoadRecord {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Ledger,
        [Parameter(Mandatory = $true)][string]$Component,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$InterfaceVersion,
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $Ledger.Add([ordered]@{
        component = $Component
        path = $Path
        interface_version = $InterfaceVersion
        load_state = $State
        reason = $Reason
    })
}

$entryPath = [System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
$entryInterfaceVersion =
    'stage1e-production-runtime-entry-point-contract-v1'
$repositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../../../../..'))
$libraryRoot = Join-Path $repositoryRoot 'fpga/vivado/build/lib'
$loadLedger = [System.Collections.Generic.List[object]]::new()
$declaredComponents = [object[]]@(
    'ENTRY_POINT',
    'CANONICAL_JSON_POWERSHELL',
    'HASH_PROVIDER_POWERSHELL',
    'ENVELOPE_CONTRACT_POWERSHELL',
    'ATOMIC_PUBLICATION_POWERSHELL',
    'REQUEST_SCHEMA',
    'RESULT_SCHEMA',
    'FAILURE_SCHEMA',
    'PRODUCTION_CONTROLLER'
)
Add-Stage1ELoadRecord $loadLedger 'ENTRY_POINT' `
    (ConvertTo-Stage1EEntryCanonicalPath $entryPath) $entryInterfaceVersion `
    'LOADED' 'UNIQUE_ASSEMBLY_ROOT'

$moduleSpecifications = @(
    [ordered]@{
        component = 'CANONICAL_JSON_POWERSHELL'
        filename = 'stage1e_runtime_canonical_json_v1.psm1'
        interface_command = 'Get-Stage1ECanonicalJsonInterfaceVersion'
        expected_interface = 'stage1e-runtime-canonical-json-interface-v1'
    }
    [ordered]@{
        component = 'ENVELOPE_CONTRACT_POWERSHELL'
        filename = 'stage1e_runtime_envelope_contract_v1.psm1'
        interface_command = 'Get-Stage1EEnvelopeContractInterfaceVersion'
        expected_interface = 'stage1e-runtime-envelope-contract-interface-v1'
    }
    [ordered]@{
        component = 'ATOMIC_PUBLICATION_POWERSHELL'
        filename = 'stage1e_runtime_atomic_publication_v1.psm1'
        interface_command = 'Get-Stage1EAtomicPublicationInterfaceVersion'
        expected_interface =
            'stage1e-runtime-atomic-publication-interface-v1'
    }
)

try {
    foreach ($specification in $moduleSpecifications) {
        $modulePath = [System.IO.Path]::GetFullPath(
            (Join-Path $libraryRoot $specification.filename))
        $canonicalModulePath = ConvertTo-Stage1EEntryCanonicalPath $modulePath
        Add-Stage1ELoadRecord $loadLedger $specification.component `
            $canonicalModulePath $specification.expected_interface `
            'ATTEMPTED' 'CONTROLLED_LITERAL_LOAD_ATTEMPT'
        if (-not [System.IO.File]::Exists($modulePath)) {
            throw [System.IO.FileNotFoundException]::new(
                "Controlled runtime module is missing: $modulePath", $modulePath)
        }
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $observedInterface = [string](& $specification.interface_command)
        if ($observedInterface -cne $specification.expected_interface) {
            throw [System.IO.InvalidDataException]::new(
                "Runtime module interface mismatch: $($specification.component)")
        }
        Add-Stage1ELoadRecord $loadLedger $specification.component `
            $canonicalModulePath $observedInterface 'LOADED' `
            'INTERFACE_VERSION_CONFIRMED'
        if ($specification.component -ceq 'CANONICAL_JSON_POWERSHELL') {
            $expectedHashInterface =
                'stage1e-runtime-sha256-provider-interface-v1'
            Add-Stage1ELoadRecord $loadLedger 'HASH_PROVIDER_POWERSHELL' `
                $canonicalModulePath $expectedHashInterface 'ATTEMPTED' `
                'INTEGRATED_PROVIDER_INTERFACE_ATTEMPT'
            $observedHashInterface = [string](
                Get-Stage1ESha256ProviderInterfaceVersion)
            if ($observedHashInterface -cne $expectedHashInterface) {
                throw [System.IO.InvalidDataException]::new(
                    'Runtime SHA-256 provider interface mismatch.')
            }
            Add-Stage1ELoadRecord $loadLedger 'HASH_PROVIDER_POWERSHELL' `
                $canonicalModulePath $observedHashInterface 'LOADED' `
                'INTERFACE_VERSION_CONFIRMED'
        }
    }
    $contract = Import-Stage1EEnvelopeContract -SchemaRoot $libraryRoot
    foreach ($schemaSpecification in @(
            [ordered]@{
                component = 'FAILURE_SCHEMA'
                role = 'failure'
                interface = 'stage1e-runtime-failure-record-v1'
            },
            [ordered]@{
                component = 'REQUEST_SCHEMA'
                role = 'request'
                interface = 'stage1e-production-runtime-request-envelope-v1'
            },
            [ordered]@{
                component = 'RESULT_SCHEMA'
                role = 'result'
                interface = 'stage1e-production-runtime-result-envelope-v1'
            })) {
        $schemaPath = ConvertTo-Stage1EEntryCanonicalPath (
            $contract.schema_paths[$schemaSpecification.role])
        Add-Stage1ELoadRecord $loadLedger $schemaSpecification.component `
            $schemaPath $schemaSpecification.interface 'ATTEMPTED' `
            'CONTROLLED_SCHEMA_LOAD_ATTEMPT'
        Add-Stage1ELoadRecord $loadLedger $schemaSpecification.component `
            $schemaPath $schemaSpecification.interface 'LOADED' `
            'SCHEMA_META_CONTRACT_CONFIRMED'
    }
}
catch {
    [Console]::Error.WriteLine(
        "ENTRYPOINT_TERMINATED: controlled assembly failed: $($_.Exception.Message)")
    exit $exitEntrypointTerminated
}

try {
    if (-not (Test-Stage1EEntrySha256 $ExpectedRequestIdentity)) {
        throw [System.IO.InvalidDataException]::new(
            'Expected request identity is not canonical lowercase SHA-256.')
    }
    if (-not [System.IO.Path]::IsPathRooted($RequestPath)) {
        throw [System.IO.InvalidDataException]::new(
            'Request path must be absolute.')
    }
    foreach ($wildcard in @('*', '?', '[', ']')) {
        if ($RequestPath.IndexOf($wildcard) -ge 0) {
            throw [System.IO.InvalidDataException]::new(
                'Request path must be literal.')
        }
    }
    $resolvedRequestPath = [System.IO.Path]::GetFullPath($RequestPath)
    $requestItem = Get-Item -LiteralPath $resolvedRequestPath -Force
    if ($requestItem.PSIsContainer -or
        (($requestItem.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw [System.IO.InvalidDataException]::new(
            'Request path must select a regular file without redirection.')
    }
    if (Test-Stage1EEntryContained $resolvedRequestPath $repositoryRoot) {
        throw [System.IO.InvalidDataException]::new(
            'Request envelope must be outside the repository source tree.')
    }
    $requestBytes = [System.IO.File]::ReadAllBytes($resolvedRequestPath)
    $request = ConvertFrom-Stage1ERequestEnvelopeBytes `
        -Bytes $requestBytes -Contract $contract `
        -ExpectedRequestIdentity $ExpectedRequestIdentity
}
catch {
    [Console]::Error.WriteLine(
        "INVOCATION_BLOCKED: request intake failed: $($_.Exception.Message)")
    exit $exitInvocationBlocked
}

$firstFailure = $null
$secondaryFailures = [System.Collections.Generic.List[object]]::new()
$canonicalRequestPath = ConvertTo-Stage1EEntryCanonicalPath $resolvedRequestPath
$canonicalRepositoryRoot = ConvertTo-Stage1EEntryCanonicalPath $repositoryRoot

try {
    $resultNativePath = [System.IO.Path]::GetFullPath(
        ([string]$request.evidence_contract.final_result_path).Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar))
    $evidenceNativeRoot = [System.IO.Path]::GetFullPath(
        ([string]$request.launch_contract.evidence_root).Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar))
    if (Test-Stage1EEntryContained $resultNativePath $repositoryRoot) {
        throw (New-Stage1EEntryException 'FORBIDDEN_BOUNDARY' `
            'REPOSITORY_RESULT_PATH_PROHIBITED' `
            'Runtime result path must be outside the repository source tree.')
    }
    $resultIsContained = Test-Stage1EEntryContained `
        -Candidate $resultNativePath -Boundary $evidenceNativeRoot
    if (-not $resultIsContained) {
        throw (New-Stage1EEntryException 'REQUEST_ENVELOPE' `
            'RESULT_PATH_OUTSIDE_EVIDENCE_ROOT' `
            'Runtime result path is outside the sealed evidence root.')
    }

    if ([string]$request.evidence_contract.request_path -cne
        $canonicalRequestPath) {
        throw (New-Stage1EEntryException 'IDENTITY_BINDING' `
            'REQUEST_PATH_BINDING_MISMATCH' `
            'Request path differs from its sealed evidence binding.')
    }
    if (-not ([string]$request.launch_contract.source_root).Equals(
            $canonicalRepositoryRoot,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw (New-Stage1EEntryException 'IDENTITY_BINDING' `
            'SOURCE_ROOT_BINDING_MISMATCH' `
            'Controlled repository root differs from the sealed request.')
    }
    $reopenedBytes = [System.IO.File]::ReadAllBytes($resolvedRequestPath)
    if (-not (Test-Stage1EEntryBytesEqual $requestBytes $reopenedBytes)) {
        throw (New-Stage1EEntryException 'REQUEST_ENVELOPE' `
            'REQUEST_CHANGED_BETWEEN_READS' `
            'Request bytes changed between controlled observations.')
    }
    $null = ConvertFrom-Stage1ERequestEnvelopeBytes `
        -Bytes $reopenedBytes -Contract $contract `
        -ExpectedRequestIdentity $ExpectedRequestIdentity

    $expectedVersions = [ordered]@{
        entry_point = $entryInterfaceVersion
        request_envelope =
            'stage1e-production-runtime-request-envelope-v1'
        result_envelope =
            'stage1e-production-runtime-result-envelope-v1'
        failure_record = 'stage1e-runtime-failure-record-v1'
        canonicalization = 'stage1e-runtime-canonical-json-interface-v1'
        atomic_publication =
            'stage1e-runtime-atomic-publication-interface-v1'
        hash_provider = 'stage1e-runtime-sha256-provider-interface-v1'
    }
    foreach ($name in $expectedVersions.Keys) {
        if ([string]$request.interface_contracts[$name].contract_version -cne
            [string]$expectedVersions[$name]) {
            throw (New-Stage1EEntryException 'DEPENDENCY_CLOSURE' `
                'REQUEST_INTERFACE_VERSION_MISMATCH' `
                "Request interface version mismatch for $name.")
        }
    }
}
catch {
    $category = [string]$_.Exception.Data['stage1e_category']
    $code = [string]$_.Exception.Data['stage1e_code']
    if ([string]::IsNullOrEmpty($category)) {
        $category = 'INTERNAL_RUNTIME'
        $code = 'ENTRY_VALIDATION_EXCEPTION'
    }
    $firstFailure = New-Stage1EEntryFailure $category $code `
        'ENTRY_POINT' 'REQUEST_VALIDATION' $_.Exception.Message `
        @($canonicalRequestPath)
}

if ($null -eq $firstFailure) {
    Add-Stage1ELoadRecord $loadLedger 'PRODUCTION_CONTROLLER' 'NONE' `
        'stage1e-production-controller-interface-v1' 'MISSING' `
        'DOWNSTREAM_COMPONENT_NOT_IMPLEMENTED_IN_PRT02_A'
    $firstFailure = New-Stage1EEntryFailure 'DEPENDENCY_CLOSURE' `
        'PRODUCTION_CONTROLLER_NOT_IMPLEMENTED' 'PRODUCTION_CONTROLLER' `
        'ENTRY_ASSEMBLY' `
        'Production controller and downstream runtime components are not implemented in PRT02-A.' `
        @($canonicalRequestPath)
}

$missingComponent = 'NONE'
if ($firstFailure.failure_code -ceq
    'PRODUCTION_CONTROLLER_NOT_IMPLEMENTED') {
    $missingComponent = 'PRODUCTION_CONTROLLER'
}
$resultPayload = [ordered]@{
    schema_version = 'stage1e-production-runtime-result-envelope-v1'
    result_state = 'SEALED'
    request_identity = [string]$request.request_identity
    execution_id = [string]$request.execution_id
    attempt_id = [string]$request.attempt_id
    runtime_backend_identity = [string]$request.runtime_backend_identity
    terminal_status = 'BLOCKED'
    first_failure = $firstFailure
    authorization_observation = [ordered]@{
        authorization_effect = 'NOT_TOUCHED'
        consumption_record_state = 'MISSING'
        consumption_record_path = 'NONE'
        consumption_record_identity = 'NONE'
    }
    assembly_result = [ordered]@{
        schema_version = 'stage1e-production-runtime-assembly-result-v1'
        status = 'BLOCKED'
        dependency_closure_state = 'PARTIAL_FOUNDATION'
        declared_component_set = $declaredComponents
        load_ledger = [object[]]$loadLedger.ToArray()
        missing_component = $missingComponent
        secondary_failures = [object[]]$secondaryFailures.ToArray()
    }
    host_result = New-Stage1EMissingReference `
        'stage1e-production-host-result-reference-v1' `
        'HOST_RUNTIME_NOT_IMPLEMENTED' $request
    vivado_capability_result = New-Stage1EMissingReference `
        'stage1e-production-vivado-capability-reference-v1' `
        'VIVADO_RUNTIME_NOT_IMPLEMENTED' $request
    operation_ledger = [object[]]@()
    report_ledger = [object[]]@()
    parser_result = New-Stage1EMissingReference `
        'stage1e-production-parser-result-reference-v1' `
        'PARSER_RUNTIME_NOT_IMPLEMENTED' $request
    evidence_set = [object[]]@(
        [ordered]@{
            role = 'REQUEST_ENVELOPE'
            status = 'PRESENT'
            path = $canonicalRequestPath
            identity = [string]$request.request_identity
        }
    )
    forbidden_boundary_result = [ordered]@{
        status = 'NOT_EVALUATED'
        operation_authority = 'NONE'
        output_authority = 'NONE'
        artifact_authority = 'NONE'
        hardware_manager_authority = 'NONE'
        board_authority = 'NONE'
    }
    evidence_completeness = 'PARTIAL'
    acceptance_boundary = [ordered]@{
        acceptance_owner = 'CONTROLLER_POLICY_REVIEW'
        acceptance_decision = 'NOT_EVALUATED_BY_RUNTIME'
        implementation_result_identity = 'NOT_CREATED_BY_RUNTIME'
        warning_drc_methodology_timing_authority = 'NONE'
    }
    authority_boundary = [ordered]@{
        qualification_decision = 'NONE'
        authorization_issue = 'NONE'
        engineering_acceptance = 'CONTROLLER_POLICY_REVIEW_ONLY'
        bitstream_xsa_generation = 'NONE'
        artifact_collection = 'NONE'
        publication = 'NONE'
        hardware_manager = 'NONE'
        board_access = 'NONE'
    }
}

try {
    $result = Add-Stage1EResultIdentity -Payload $resultPayload `
        -Contract $contract
    $resultBytes = ConvertTo-Stage1EResultEnvelopeBytes -Record $result `
        -Contract $contract
    $resultVerifier = {
        param([byte[]]$CandidateBytes)
        $null = ConvertFrom-Stage1EResultEnvelopeBytes `
            -Bytes $CandidateBytes -Contract $contract `
            -ExpectedResultIdentity $result.result_identity
        return $true
    }.GetNewClosure()
    $null = Publish-Stage1EAtomicBytes -LiteralPath $resultNativePath `
        -Bytes $resultBytes -BoundaryPath $evidenceNativeRoot `
        -Verifier $resultVerifier
    $publishedBytes = [System.IO.File]::ReadAllBytes($resultNativePath)
    $null = ConvertFrom-Stage1EResultEnvelopeBytes `
        -Bytes $publishedBytes -Contract $contract `
        -ExpectedResultIdentity $result.result_identity
}
catch {
    [Console]::Error.WriteLine(
        "RESULT_PUBLICATION_FAILED: $($_.Exception.Message)")
    exit $exitResultPublicationFailed
}

Write-Output 'exit_class=RESULT_PUBLISHED'
Write-Output "result_path=$resultNativePath"
Write-Output "expected_result_identity=$($result.result_identity)"
exit $exitResultPublished
