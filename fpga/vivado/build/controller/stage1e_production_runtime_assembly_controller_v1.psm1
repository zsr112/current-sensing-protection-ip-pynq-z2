Set-StrictMode -Version Latest

$script:Stage1EProductionRuntimeAssemblyControllerInterface =
    'stage1e-production-runtime-assembly-controller-interface-v1'
$script:Stage1EActivationModulePath = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../lib/stage1e_runtime_activation_contract_v1.psm1'))
$script:Stage1EActivationProvider = 'ACTIVATION_CONTRACT_MODULE'
$script:Stage1EActivationProviderInterface =
    'stage1e-runtime-activation-contract-interface-v1'
Microsoft.PowerShell.Core\Import-Module -Name $script:Stage1EActivationModulePath `
    -ErrorAction Stop

$script:Stage1EAssemblyRequestFields = @(
    'schema_version', 'request_identity', 'execution_id', 'attempt_id',
    'source_identity', 'workspace_identity', 'runtime_backend_reference',
    'runtime_backend_reference_state', 'repository_root', 'entry_point_path',
    'evidence_root', 'authorization_effect', 'process_effect',
    'candidate_effect')

function Get-Stage1EProductionRuntimeAssemblyControllerInterfaceVersion {
    return $script:Stage1EProductionRuntimeAssemblyControllerInterface
}

function Copy-Stage1EAssemblyControllerRecord {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record
    )
    $copy = [ordered]@{}
    foreach ($key in $Record.Keys) { $copy[[string]$key] = $Record[$key] }
    return $copy
}

function Assert-Stage1EConnectedAssemblyRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$AssemblyRequest,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ActivationContract
    )
    if (-not (Test-Path -LiteralPath $script:Stage1EActivationModulePath) -or
        [string](Get-Stage1ERuntimeActivationContractInterfaceVersion) -cne
            $script:Stage1EActivationProviderInterface) {
        throw "Assembly controller requires $script:Stage1EActivationProvider."
    }
    $null = Assert-Stage1ERuntimeActivationContract $ActivationContract
    $actual = @($AssemblyRequest.Keys | ForEach-Object { [string]$_ })
    if (($actual -join '|') -cne ($script:Stage1EAssemblyRequestFields -join '|')) {
        throw 'Connected assembly request has an incorrect exact field set/order.'
    }
    if ([string]$AssemblyRequest.schema_version -cne
            'stage1e-connected-runtime-assembly-request-v1' -or
        [string]$AssemblyRequest.runtime_backend_reference_state -cne
            'UNVERIFIED_REQUEST_REFERENCE' -or
        [string]$AssemblyRequest.authorization_effect -cne 'NOT_TOUCHED' -or
        [string]$AssemblyRequest.process_effect -cne 'NOT_STARTED' -or
        [string]$AssemblyRequest.candidate_effect -cne 'NOT_CREATED') {
        throw 'Connected assembly request state or authority differs.'
    }
    foreach ($field in @('request_identity', 'execution_id', 'attempt_id',
            'source_identity', 'workspace_identity',
            'runtime_backend_reference', 'repository_root', 'entry_point_path',
            'evidence_root')) {
        if ([string]::IsNullOrWhiteSpace([string]$AssemblyRequest[$field])) {
            throw "Connected assembly request has an empty $field."
        }
    }
    $selected = [System.IO.Path]::GetFullPath((Join-Path `
            ([string]$AssemblyRequest.repository_root) `
            ([string]$ActivationContract.selected_entry_root.source_path)))
    $observed = [System.IO.Path]::GetFullPath(
        ([string]$AssemblyRequest.entry_point_path))
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $selected, $observed)) {
        throw 'Assembly controller rejected an alternate entry root.'
    }
    return $true
}

function Get-Stage1EConnectedAssemblyPrecheckDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$AssemblyRequest,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ActivationContract
    )
    $null = Assert-Stage1EConnectedAssemblyRequest `
        $AssemblyRequest $ActivationContract
    return [ordered]@{
        schema_version = 'stage1e-connected-assembly-precheck-decision-v1'
        decision = 'PROCEED_HOST_ASSEMBLY_ONLY'
        decision_owner = 'CONNECTED_ASSEMBLY_CONTROLLER'
        request_identity = [string]$AssemblyRequest.request_identity
        authorization_effect = 'NOT_TOUCHED'
        process_effect = 'NOT_STARTED'
        implementation_dispatch_authority = 'NONE'
    }
}

function Get-Stage1EActivationReadinessDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$AssemblyRequest,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ActivationContract,
        [Parameter(Mandatory = $true)]$HostAssemblyResult,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$FixtureResult,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ProtectedAeEvidence
    )
    $null = Assert-Stage1EConnectedAssemblyRequest `
        $AssemblyRequest $ActivationContract
    foreach ($field in @('request_identity', 'execution_id', 'attempt_id',
            'source_identity', 'workspace_identity')) {
        if ([string]$FixtureResult[$field] -cne
                [string]$AssemblyRequest[$field] -or
            [string]$HostAssemblyResult[$field] -cne
                [string]$AssemblyRequest[$field]) {
            throw "Activation-readiness evidence binding differs: $field"
        }
    }
    $readiness = Copy-Stage1EAssemblyControllerRecord `
        $ActivationContract.activation_readiness_contract
    $conditions = [System.Collections.Generic.List[object]]::new()
    $conditionValues = [ordered]@{
        PRT03_ACTIVATION_GRAPH_EXACT =
            ([string]$HostAssemblyResult.activation_graph_state -ceq 'MATCH')
        PRT03_STATIC_DISCOVERY_EXACT =
            ([string]$HostAssemblyResult.static_discovery_state -ceq 'MATCH')
        PRT03_DIRECT_ACTUAL_LEDGER_EXACT =
            ([string]$HostAssemblyResult.direct_ledger_state -ceq 'MATCH')
        ACCEPTED_AE_CLOSURE_REFERENCE_VALID =
            ([string]$HostAssemblyResult.accepted_closure_reference_state -ceq
                'MATCH')
        EXACT_EIGHT_ROLE_REGISTRY =
            ([int]$HostAssemblyResult.direct_role_count -eq 8)
        EXACT_SUBORDINATE_PROVIDER_REGISTRY =
            ([int]$HostAssemblyResult.subordinate_contract_count -eq 10 -and
                [int]$HostAssemblyResult.child_provider_count -eq 10)
        PROTECTED_AE_BYTES_MATCH =
            ([string]$ProtectedAeEvidence.validation_state -ceq
                'PROTECTED_AE_BYTES_MATCH' -and
                [string]$ProtectedAeEvidence.baseline_commit -ceq
                    '809d175ecfded17ad9d1107c3a92d41726ee21f3' -and
                [int]$ProtectedAeEvidence.protected_file_count -eq 91 -and
                [int]$ProtectedAeEvidence.mismatch_count -eq 0)
        BOUND_FIXTURE_POLICY_REVIEW_STOP =
            ([string]$FixtureResult.binding_state -ceq
                'HOST_C_D_E_BINDINGS_MATCH' -and
                [string]$FixtureResult.terminal_status -ceq 'BLOCKED' -and
                [string]$FixtureResult.failure_category -ceq 'POLICY_REVIEW' -and
                [string]$FixtureResult.failure_code -ceq
                    'PRODUCTION_POLICY_REVIEW_NOT_IMPLEMENTED')
        NO_PRODUCTION_OR_DOWNSTREAM_EFFECT =
            ([string]$HostAssemblyResult.authorization_effect -ceq
                    'NOT_TOUCHED' -and
                [string]$HostAssemblyResult.process_effect -ceq 'NOT_STARTED' -and
                [string]$HostAssemblyResult.candidate_effect -ceq 'NOT_CREATED' -and
                [string]$FixtureResult.production_authorization_effect -ceq
                    'NOT_TOUCHED' -and
                [string]$FixtureResult.production_process_effect -ceq
                    'NOT_STARTED' -and
                [string]$FixtureResult.identity_freeze_effect -ceq
                    'NOT_PERFORMED' -and
                [string]$FixtureResult.candidate_effect -ceq 'NOT_CREATED' -and
                [string]$FixtureResult.downstream_effect -ceq 'NONE')
        LIVE_TOOL_LEDGERS_TRUTHFULLY_UNAVAILABLE =
            ([string]$HostAssemblyResult.vivado_ledger_state -ceq
                    'VIVADO_PRE_DISPATCH_LEDGER_NOT_AVAILABLE' -and
                [string]$HostAssemblyResult.postprocess_ledger_state -ceq
                    'POSTPROCESS_PRE_DISPATCH_LEDGER_NOT_AVAILABLE' -and
                [string]$HostAssemblyResult.full_transitive_state -ceq
                    'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN')
    }
    foreach ($name in $conditionValues.Keys) {
        $conditions.Add([ordered]@{
                condition = $name
                state = if ([bool]$conditionValues[$name]) { 'MET' } else { 'NOT_MET' }
            })
    }
    $allMet = @($conditionValues.Values | Where-Object { -not [bool]$_ }).Count -eq 0
    $candidate = if ($allMet) {
        [string]$readiness.target_capability_state
    }
    else { 'NOT_ESTABLISHED' }
    return [ordered]@{
        schema_version = [string]$readiness.schema_version
        capability_candidate = $candidate
        derivation_state = if ($allMet) {
            'ALL_REQUIRED_CONDITIONS_MET'
        }
        else { 'BLOCKING_CONDITION_PRESENT' }
        condition_count = $conditions.Count
        conditions = [object[]]$conditions.ToArray()
        direct_connected_state = [string]$readiness.direct_connected_state
        accepted_closure_state = [string]$readiness.accepted_closure_state
        full_transitive_state = [string]$readiness.full_transitive_state
        vivado_ledger_state =
            [string]$ActivationContract.vivado_projection_contract.live_ledger_state
        postprocess_ledger_state =
            [string]$ActivationContract.postprocess_projection_contract.live_ledger_state
        final_closure_state = [string]$readiness.final_closure_state
        review_state = [string]$readiness.review_state
        qualification_state = [string]$readiness.qualification_state
        runtime_backend_identity_state =
            [string]$readiness.runtime_backend_identity_state
        policy_configuration_identity_state =
            [string]$readiness.policy_configuration_identity_state
        public_dispatch_state = [string]$readiness.public_dispatch_state
        run2_state = [string]$readiness.run2_state
        missing_activation_objects =
            [object[]]@($ActivationContract.missing_activation_objects)
        authorization_effect = 'NOT_TOUCHED'
        process_effect = 'NOT_STARTED'
        candidate_effect = 'NOT_CREATED'
        engineering_acceptance = 'NONE'
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EProductionRuntimeAssemblyControllerInterfaceVersion'
    'Assert-Stage1EConnectedAssemblyRequest'
    'Get-Stage1EConnectedAssemblyPrecheckDecision'
    'Get-Stage1EActivationReadinessDecision'
)
