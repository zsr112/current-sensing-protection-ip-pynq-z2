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
$entryInterfaceVersion =
    'stage1e-production-runtime-entry-point-contract-v1'
$entryImplementationVersion =
    'stage1e-production-runtime-entrypoint-implementation-v2'

function ConvertTo-Stage1EEntryV2CanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).Replace(
        [System.IO.Path]::DirectorySeparatorChar, '/')
}

function Test-Stage1EEntryV2Sha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -cmatch '^[0-9a-f]{64}$' -and $Value -cne ('0' * 64))
}

function Test-Stage1EEntryV2Contained {
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

function Test-Stage1EEntryV2BytesEqual {
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

function New-Stage1EEntryV2Failure {
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
        retry_disposition = 'REVIEW_BEFORE_NEW_LAUNCH'
        candidate_effect = 'NOT_CREATED'
        message = $Message
        causal_evidence_references = [object[]]@($CausalReferences)
    }
}

function New-Stage1EEntryV2MissingReference {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaVersion,
        [Parameter(Mandatory = $true)][string]$Producer,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Request
    )
    return [ordered]@{
        schema_version = $SchemaVersion
        status = 'MISSING'
        path = 'NONE'
        component_identity = 'NONE'
        producer = $Producer
        execution_id = [string]$Request.execution_id
        workspace_identity = [string]$Request.workspace_identity
        missing_reason = $Reason
    }
}

function Add-Stage1EEntryV2LoadRecord {
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

function Get-Stage1EEntryV2CommandSource {
    param([Parameter(Mandatory = $true)]$Command)
    $source = [string]$Command.ScriptBlock.File
    if ([string]::IsNullOrWhiteSpace($source) -and $null -ne $Command.Module) {
        $source = [string]$Command.Module.Path
    }
    return $source
}

function Get-Stage1EEntryV2ExactCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ExpectedPath
    )
    $matches = @()
    foreach ($command in @(Get-Command -Name $Name -CommandType Function `
            -All -ErrorAction Stop)) {
        $source = Get-Stage1EEntryV2CommandSource $command
        if (-not [string]::IsNullOrWhiteSpace($source) -and
            [System.StringComparer]::OrdinalIgnoreCase.Equals(
                [System.IO.Path]::GetFullPath($source), $ExpectedPath)) {
            $matches += $command
        }
    }
    if ($matches.Count -ne 1) {
        throw "Entry-point provider command is missing or substituted: $Name"
    }
    return $matches[0]
}

function Import-Stage1EEntryV2EnvelopeProviders {
    param([Parameter(Mandatory = $true)][object[]]$Specifications)
    foreach ($specification in @($Specifications | Select-Object -First 3)) {
        $path = [System.IO.Path]::GetFullPath(
            (Join-Path $buildRoot $specification.relative_path))
        Microsoft.PowerShell.Core\Import-Module -Name $path -Force `
            -ErrorAction Stop
        $command = Get-Stage1EEntryV2ExactCommand `
            -Name ([string]$specification.interface_command) `
            -ExpectedPath $path
        if ([string](& $command) -cne
            [string]$specification.interface_version) {
            throw "Envelope bootstrap interface differs: $($specification.component)"
        }
    }
}

$entryPath = [System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
$repositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../../../../../..'))
$buildRoot = Join-Path $repositoryRoot 'fpga/vivado/build'
$libraryRoot = Join-Path $buildRoot 'lib'
$loadLedger = [System.Collections.Generic.List[object]]::new()
Add-Stage1EEntryV2LoadRecord $loadLedger 'ENTRY_POINT' `
    (ConvertTo-Stage1EEntryV2CanonicalPath $entryPath) `
    $entryInterfaceVersion 'LOADED' `
    "SELECTED_PUBLIC_ENTRY_ROOT:$entryImplementationVersion"

$moduleSpecifications = @(
    [ordered]@{
        component = 'CANONICALIZATION_POWERSHELL'
        relative_path = 'lib/stage1e_runtime_canonical_json_v1.psm1'
        interface_command = 'Get-Stage1ECanonicalJsonInterfaceVersion'
        interface_version = 'stage1e-runtime-canonical-json-interface-v1'
    },
    [ordered]@{
        component = 'ENVELOPE_CONTRACT_POWERSHELL'
        relative_path = 'lib/stage1e_runtime_envelope_contract_v1.psm1'
        interface_command = 'Get-Stage1EEnvelopeContractInterfaceVersion'
        interface_version = 'stage1e-runtime-envelope-contract-interface-v1'
    },
    [ordered]@{
        component = 'ATOMIC_PUBLICATION_POWERSHELL'
        relative_path = 'lib/stage1e_runtime_atomic_publication_v1.psm1'
        interface_command = 'Get-Stage1EAtomicPublicationInterfaceVersion'
        interface_version = 'stage1e-runtime-atomic-publication-interface-v1'
    },
    [ordered]@{
        component = 'CONNECTED_HOST_ASSEMBLY'
        relative_path =
            'runtime/assembly/stage1e_connected_host_assembly_v1.psm1'
        interface_command = 'Get-Stage1EConnectedHostAssemblyInterfaceVersion'
        interface_version = 'stage1e-connected-host-assembly-interface-v1'
    }
)

try {
    foreach ($specification in $moduleSpecifications) {
        $path = [System.IO.Path]::GetFullPath(
            (Join-Path $buildRoot $specification.relative_path))
        $canonicalPath = ConvertTo-Stage1EEntryV2CanonicalPath $path
        Add-Stage1EEntryV2LoadRecord $loadLedger $specification.component `
            $canonicalPath $specification.interface_version 'ATTEMPTED' `
            'FIXED_BOOTSTRAP_MODULE_LOAD_PRE_ACTION'
        if (-not [System.IO.File]::Exists($path)) {
            throw "Required v2 bootstrap module is missing: $path"
        }
        Microsoft.PowerShell.Core\Import-Module -Name $path -Force `
            -ErrorAction Stop
        $command = Get-Stage1EEntryV2ExactCommand `
            -Name ([string]$specification.interface_command) `
            -ExpectedPath $path
        $observed = [string](& $command)
        if ($observed -cne [string]$specification.interface_version) {
            throw "Bootstrap interface differs: $($specification.component)"
        }
        Add-Stage1EEntryV2LoadRecord $loadLedger $specification.component `
            $canonicalPath $observed 'LOADED' `
            'FIXED_BOOTSTRAP_INTERFACE_CONFIRMED'
    }
    $selectedEntry = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot `
            'fpga/vivado/build/runtime/entrypoint/v2/stage1e_production_runtime_entrypoint_v2.ps1'))
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $entryPath, $selectedEntry)) {
        throw 'Invoked path is not the selected production entry root.'
    }
    Import-Stage1EEntryV2EnvelopeProviders $moduleSpecifications
}
catch {
    [Console]::Error.WriteLine(
        "ENTRYPOINT_TERMINATED: controlled v2 assembly failed: $($_.Exception.Message)")
    exit $exitEntrypointTerminated
}

try {
    if (-not (Test-Stage1EEntryV2Sha256 $ExpectedRequestIdentity)) {
        throw 'Expected request identity is not canonical lowercase SHA-256.'
    }
    if (-not [System.IO.Path]::IsPathRooted($RequestPath)) {
        throw 'Request path must be absolute.'
    }
    foreach ($wildcard in @('*', '?', '[', ']')) {
        if ($RequestPath.IndexOf($wildcard) -ge 0) {
            throw 'Request path must be literal.'
        }
    }
    $resolvedRequestPath = [System.IO.Path]::GetFullPath($RequestPath)
    $requestItem = Get-Item -LiteralPath $resolvedRequestPath -Force
    if ($requestItem.PSIsContainer -or
        (($requestItem.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'Request path must select a regular file without redirection.'
    }
    if (Test-Stage1EEntryV2Contained $resolvedRequestPath $repositoryRoot) {
        throw 'Request envelope must be outside the repository source tree.'
    }
    $contract = Import-Stage1EEnvelopeContract -SchemaRoot $libraryRoot
    $requestBytes = [System.IO.File]::ReadAllBytes($resolvedRequestPath)
    $request = ConvertFrom-Stage1ERequestEnvelopeBytes `
        -Bytes $requestBytes -Contract $contract `
        -ExpectedRequestIdentity $ExpectedRequestIdentity
    $canonicalRequestPath = ConvertTo-Stage1EEntryV2CanonicalPath `
        $resolvedRequestPath
    if ([string]$request.evidence_contract.request_path -cne
        $canonicalRequestPath) {
        throw 'Request path differs from its sealed evidence binding.'
    }
    $canonicalRoot = ConvertTo-Stage1EEntryV2CanonicalPath $repositoryRoot
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            [string]$request.launch_contract.source_root, $canonicalRoot)) {
        throw 'Selected source root differs from the sealed request.'
    }
    $reopenedBytes = [System.IO.File]::ReadAllBytes($resolvedRequestPath)
    if (-not (Test-Stage1EEntryV2BytesEqual $requestBytes $reopenedBytes)) {
        throw 'Request bytes changed between controlled observations.'
    }
    $null = ConvertFrom-Stage1ERequestEnvelopeBytes `
        -Bytes $reopenedBytes -Contract $contract `
        -ExpectedRequestIdentity $ExpectedRequestIdentity
    $requestInterfaces = [ordered]@{
        entry_point = 'stage1e-production-runtime-entry-point-contract-v1'
        controller = 'stage1e-controller-v1'
        adapter = 'stage1e-adapter-v1'
        request_envelope = 'stage1e-production-runtime-request-envelope-v1'
        result_envelope = 'stage1e-production-runtime-result-envelope-v1'
        failure_record = 'stage1e-runtime-failure-record-v1'
        runtime_schema = 'stage1e-runtime-schema-v1'
        report = 'stage1e-report-v1'
        message = 'stage1e-message-v1'
        host_requirements = 'stage1e-host-requirements-v1'
        canonicalization = 'stage1e-runtime-canonical-json-interface-v1'
        hash_provider = 'stage1e-runtime-sha256-provider-interface-v1'
        atomic_publication =
            'stage1e-runtime-atomic-publication-interface-v1'
    }
    foreach ($name in $requestInterfaces.Keys) {
        if ([string]$request.interface_contracts[$name].contract_version -cne
            [string]$requestInterfaces[$name]) {
            throw "Request interface version mismatch: $name"
        }
    }
}
catch {
    [Console]::Error.WriteLine(
        "INVOCATION_BLOCKED: v2 request intake failed: $($_.Exception.Message)")
    exit $exitInvocationBlocked
}

$resultNativePath = [System.IO.Path]::GetFullPath(
    ([string]$request.evidence_contract.final_result_path).Replace('/',
        [System.IO.Path]::DirectorySeparatorChar))
$evidenceNativeRoot = [System.IO.Path]::GetFullPath(
    ([string]$request.launch_contract.evidence_root).Replace('/',
        [System.IO.Path]::DirectorySeparatorChar))
if ((Test-Stage1EEntryV2Contained $resultNativePath $repositoryRoot) -or
    -not (Test-Stage1EEntryV2Contained $resultNativePath $evidenceNativeRoot)) {
    [Console]::Error.WriteLine(
        'INVOCATION_BLOCKED: final result path violates the evidence boundary.')
    exit $exitInvocationBlocked
}

try {
    $hostAssembly = Invoke-Stage1EConnectedRuntimeAssembly `
        -ValidatedRequest $request -RepositoryRoot $repositoryRoot `
        -EntryPointPath $entryPath
    $assemblyRequest = $hostAssembly.assembly_request
    $activationContract = $hostAssembly.activation_contract
}
catch {
    [Console]::Error.WriteLine(
        "ENTRYPOINT_TERMINATED: connected Host assembly failed: $($_.Exception.Message)")
    exit $exitEntrypointTerminated
}

$publicStop = $activationContract.public_stop_contract
$stopPublication = Publish-Stage1EConnectedActivationStop `
    -AssemblyRequest $assemblyRequest -HostAssemblyResult $hostAssembly `
    -StopContract $publicStop -EvidenceRoot $evidenceNativeRoot
$null = Import-Stage1EEntryV2EnvelopeProviders $moduleSpecifications
$firstFailure = New-Stage1EEntryV2Failure `
    -Category ([string]$publicStop.failure_category) `
    -Code ([string]$publicStop.failure_code) `
    -Component 'RUNTIME_BACKEND_IDENTITY_V2' `
    -Phase 'ENTRY_ASSEMBLY' `
    -Message 'Activation precheck stopped before process launch because Runtime Backend Identity v2 has not been created.' `
    -CausalReferences @([string]$stopPublication.record_path,
        [string]$hostAssembly.sealed_ledger_path)

Add-Stage1EEntryV2LoadRecord $loadLedger 'CONNECTED_HOST_ASSEMBLY' `
    ([string]$hostAssembly.sealed_ledger_path) `
    'stage1e-connected-host-assembly-interface-v1' 'LOADED' `
    'PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED'
Add-Stage1EEntryV2LoadRecord $loadLedger 'PRT03_DIRECT_ASSEMBLY_LEDGER' `
    ([string]$hostAssembly.publication_receipt_path) `
    'stage1e-prt03-activation-graph-interface-v1' 'LOADED' `
    'INDEPENDENT_GRAPH_EXPECTED_MATCHED_REOPENED_NATURAL_ACTUAL'
Add-Stage1EEntryV2LoadRecord $loadLedger 'ACCEPTED_AE_CLOSURE_REFERENCE' `
    'NONE' 'stage1e-runtime-dependency-closure-interface-v1' 'LOADED' `
    'AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED'
Add-Stage1EEntryV2LoadRecord $loadLedger 'HOST_FULL_TRANSITIVE_CLOSURE' `
    'NONE' 'stage1e-prt03-activation-graph-interface-v1' 'MISSING' `
    'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN'
Add-Stage1EEntryV2LoadRecord $loadLedger 'VIVADO_PRE_DISPATCH_LEDGER' `
    'NONE' 'stage1e-runtime-assembly-ledger-interface-v1' 'MISSING' `
    'VIVADO_PRE_DISPATCH_LEDGER_NOT_AVAILABLE'
Add-Stage1EEntryV2LoadRecord $loadLedger 'POSTPROCESS_PRE_DISPATCH_LEDGER' `
    'NONE' 'stage1e-runtime-assembly-ledger-interface-v1' 'MISSING' `
    'POSTPROCESS_PRE_DISPATCH_LEDGER_NOT_AVAILABLE'
Add-Stage1EEntryV2LoadRecord $loadLedger 'ACTIVATION_PRECHECK' `
    ([string]$stopPublication.record_path) `
    'stage1e-runtime-activation-stop-interface-v1' 'REJECTED' `
    'STRUCTURED_ACTIVATION_STOP_PUBLISHED'

$declaredRoles = [object[]]@($activationContract.direct_roles |
    ForEach-Object { [string]$_.role })
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
        status = 'COMPLETED'
        dependency_closure_state = 'PARTIAL_FOUNDATION'
        declared_component_set = $declaredRoles
        load_ledger = [object[]]$loadLedger.ToArray()
        missing_component = 'RUNTIME_BACKEND_IDENTITY_V2'
        secondary_failures = [object[]]@()
    }
    host_result = New-Stage1EEntryV2MissingReference `
        'stage1e-production-host-result-reference-v1' `
        'HOST_PROCESS_RESULT_NOT_CREATED' 'ACTIVATION_PRECHECK_STOP' $request
    vivado_capability_result = New-Stage1EEntryV2MissingReference `
        'stage1e-production-vivado-capability-reference-v1' `
        'VIVADO_PROCESS_NOT_STARTED' 'ACTIVATION_PRECHECK_STOP' $request
    operation_ledger = [object[]]@()
    report_ledger = [object[]]@()
    parser_result = New-Stage1EEntryV2MissingReference `
        'stage1e-production-parser-result-reference-v1' `
        'POSTPROCESS_NOT_STARTED' 'ACTIVATION_PRECHECK_STOP' $request
    evidence_set = [object[]]@(
        [ordered]@{
            role = 'REQUEST_ENVELOPE'
            status = 'PRESENT'
            path = $canonicalRequestPath
            identity = [string]$request.request_identity
        },
        [ordered]@{
            role = 'PRT03_DIRECT_ASSEMBLY_LEDGER'
            status = 'PRESENT'
            path = [string]$hostAssembly.sealed_ledger_path
            identity = [string]$hostAssembly.direct_ledger_comparison.ledger_sha256
        },
        [ordered]@{
            role = 'PRT03_DIRECT_ASSEMBLY_RECEIPT'
            status = 'PRESENT'
            path = [string]$hostAssembly.publication_receipt_path
            identity = 'NONE'
        },
        [ordered]@{
            role = 'ACTIVATION_STOP_RECORD'
            status = 'PRESENT'
            path = [string]$stopPublication.record_path
            identity = [string]$stopPublication.record_sha256
        },
        [ordered]@{
            role = 'ACTIVATION_STOP_RECEIPT'
            status = 'PRESENT'
            path = [string]$stopPublication.receipt_path
            identity = [string]$stopPublication.receipt_sha256
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
    $resultBytes = ConvertTo-Stage1EResultEnvelopeBytes `
        -Record $result -Contract $contract
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
    $null = ConvertFrom-Stage1EResultEnvelopeBytes `
        -Bytes ([System.IO.File]::ReadAllBytes($resultNativePath)) `
        -Contract $contract `
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
Write-Output 'activation_phase=ACTIVATION_PRECHECK'
Write-Output 'host_assembly_state=PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED'
Write-Output 'accepted_closure_state=AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED'
Write-Output 'host_full_transitive_state=HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN'
Write-Output "activation_stop_path=$($stopPublication.record_path)"
Write-Output 'final_closure_state=FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN'
exit $exitResultPublished
