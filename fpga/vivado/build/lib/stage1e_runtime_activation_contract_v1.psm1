Set-StrictMode -Version Latest

$script:Stage1ERuntimeActivationContractInterface =
    'stage1e-runtime-activation-contract-interface-v1'
$script:Stage1EActivationBuildRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
$script:Stage1EActivationRepositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $script:Stage1EActivationBuildRoot '../../..'))
$script:Stage1EActivationContractPath = Join-Path `
    $script:Stage1EActivationBuildRoot `
    'config/stage1e_runtime_activation_contract_v1.dict'
$script:Stage1EDependencyModulePath = Join-Path `
    $script:Stage1EActivationBuildRoot `
    'dependency/stage1e_runtime_dependency_closure_v1.psm1'
$script:Stage1EDependencyInterface =
    'stage1e-runtime-dependency-closure-interface-v1'

Microsoft.PowerShell.Core\Import-Module -Name `
    $script:Stage1EDependencyModulePath -ErrorAction Stop
if ([string](Get-Stage1EDependencyClosureInterfaceVersion) -cne
    $script:Stage1EDependencyInterface) {
    throw 'Activation contract dependency-closure interface differs.'
}

$script:Stage1EActivationTopFields = @(
    'schema_version', 'interface_version', 'contract_state',
    'selected_entry_root', 'protected_entry_inputs', 'direct_roles',
    'subordinate_contracts', 'child_providers', 'process_domains',
    'interface_registry', 'host_assembly_contract',
    'vivado_projection_contract', 'postprocess_projection_contract',
    'activation_readiness_contract', 'public_stop_contract',
    'fixture_stop_contract', 'missing_activation_objects',
    'authority_boundary')
$script:Stage1ESelectedEntryFields = @(
    'selection_state', 'source_path', 'interface_version',
    'implementation_version', 'process_domain', 'alternate_root_action')
$script:Stage1EProtectedEntryFields = @(
    'ordinal', 'selection_state', 'source_path', 'interface_version',
    'implementation_version', 'process_domain', 'alternate_root_action')
$script:Stage1EDirectRoleFields = @(
    'ordinal', 'role', 'source_path', 'interface_version',
    'process_domains', 'connection_state')
$script:Stage1ESubordinateFields = @(
    'ordinal', 'contract_role', 'owner', 'source_paths',
    'interface_versions', 'process_domains', 'connection_state')
$script:Stage1EChildProviderFields = @(
    'ordinal', 'provider_key', 'source_path', 'interface_version',
    'process_domains', 'connection_state')
$script:Stage1EProcessDomainFields = @(
    'ordinal', 'domain', 'interpreter', 'direct_roles',
    'subordinate_components', 'live_ledger_state')
$script:Stage1EInterfaceFields = @(
    'ordinal', 'interface_key', 'source_path', 'interface_command',
    'interface_version', 'language', 'process_domains', 'verification_mode')
$script:Stage1EHostAssemblyFields = @(
    'schema_version', 'ledger_type', 'expected_record_count',
    'expected_attempt_count', 'event_evidence_class', 'attempt_state',
    'terminal_states', 'direct_connected_state', 'accepted_closure_state',
    'full_transitive_state', 'final_closure_state')
$script:Stage1EProjectionFields = @(
    'schema_version', 'ledger_type', 'expected_record_count',
    'structural_state', 'live_ledger_state', 'final_closure_state')
$script:Stage1EActivationReadinessFields = @(
    'schema_version', 'target_capability_state', 'review_state',
    'direct_connected_state', 'accepted_closure_state',
    'full_transitive_state', 'final_closure_state', 'qualification_state',
    'runtime_backend_identity_state', 'policy_configuration_identity_state',
    'public_dispatch_state', 'run2_state')
$script:Stage1EStopFields = @(
    'schema_version', 'interface_version', 'terminal_status',
    'failure_category', 'failure_code', 'outer_phase',
    'activation_subphase', 'authorization_effect', 'process_effect',
    'candidate_effect', 'missing_activation_object')
$script:Stage1EFixtureStopFields = @(
    'schema_version', 'terminal_status', 'failure_category', 'failure_code',
    'failure_phase', 'authorization_effect', 'process_effect',
    'candidate_effect')
$script:Stage1EAuthorityFields = @(
    'qualification_decision', 'authorization_issue',
    'authorization_consumption', 'engineering_acceptance',
    'bitstream_xsa_generation', 'artifact_collection', 'publication',
    'hardware_manager', 'board_access')
$script:Stage1EConnectedEventFields = @(
    'event_ordinal', 'operation_attempt_id', 'parent_attempt_id',
    'event_kind', 'evidence_class', 'event_state', 'requester', 'target',
    'source_path', 'provider', 'interface_version', 'domain',
    'load_ordinal', 'edge_type', 'message')

function Get-Stage1ERuntimeActivationContractInterfaceVersion {
    return $script:Stage1ERuntimeActivationContractInterface
}

function Get-Stage1ERuntimeActivationContractPath {
    return [System.IO.Path]::GetFullPath($script:Stage1EActivationContractPath)
}

function Assert-Stage1EActivationExactFields {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $actual = @($Record.Keys | ForEach-Object { [string]$_ })
    if (($actual -join '|') -cne ($Expected -join '|')) {
        throw "$Label has an incorrect exact field set/order."
    }
}

function ConvertFrom-Stage1EActivationRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $record = ConvertFrom-Stage1ETclDictionary -Text $Text
    Assert-Stage1EActivationExactFields $record $Fields $Label
    return $record
}

function ConvertFrom-Stage1EActivationRecordList {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $ordinal = 0
    foreach ($item in @(ConvertFrom-Stage1ETclList -Text $Text)) {
        $ordinal++
        $record = ConvertFrom-Stage1EActivationRecord $item $Fields `
            "$Label $ordinal"
        if ([string]$record.ordinal -cne [string]$ordinal) {
            throw "$Label has a noncanonical ordinal at record $ordinal."
        }
        $records.Add($record)
    }
    return $records.ToArray()
}

function Test-Stage1EActivationExactList {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][object[]]$Expected
    )
    if ($Actual.Count -ne $Expected.Count) { return $false }
    for ($index = 0; $index -lt $Actual.Count; $index++) {
        if ([string]$Actual[$index] -cne [string]$Expected[$index]) {
            return $false
        }
    }
    return $true
}

function Assert-Stage1EActivationUniqueField {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($record in $Records) {
        $value = [string]$record[$Field]
        if ([string]::IsNullOrWhiteSpace($value) -or -not $seen.Add($value)) {
            throw "$Label has an empty or duplicate $Field value '$value'."
        }
    }
}

function Assert-Stage1ERuntimeActivationContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )
    Assert-Stage1EActivationExactFields $Contract `
        $script:Stage1EActivationTopFields 'Activation contract'
    if ([string]$Contract.schema_version -cne
            'stage1e-runtime-activation-contract-v1' -or
        [string]$Contract.interface_version -cne
            $script:Stage1ERuntimeActivationContractInterface -or
        [string]$Contract.contract_state -cne
            'PRT03_ACTIVATION_TARGET_DECLARED') {
        throw 'Activation contract identity or state differs.'
    }

    $selected = $Contract.selected_entry_root
    Assert-Stage1EActivationExactFields $selected `
        $script:Stage1ESelectedEntryFields 'Selected entry root'
    if ([string]$selected.selection_state -cne 'SELECTED_PUBLIC_ENTRY_ROOT' -or
        [string]$selected.source_path -cne
            'fpga/vivado/build/runtime/entrypoint/v2/stage1e_production_runtime_entrypoint_v2.ps1' -or
        [string]$selected.interface_version -cne
            'stage1e-production-runtime-entry-point-contract-v1' -or
        [string]$selected.process_domain -cne 'HOST_POWERSHELL' -or
        [string]$selected.alternate_root_action -cne 'BLOCK') {
        throw 'Selected production entry root differs from the frozen v2 root.'
    }
    if ($Contract.protected_entry_inputs.Count -ne 1 -or
        [string]$Contract.protected_entry_inputs[0].selection_state -cne
            'PROTECTED_ACCEPTED_INPUT' -or
        [string]$Contract.protected_entry_inputs[0].source_path -cne
            'fpga/vivado/build/runtime/entrypoint/stage1e_production_runtime_entrypoint_v1.ps1') {
        throw 'Protected PRT02-A entry input registry differs.'
    }

    $expectedRoles = @('ENTRY_POINT', 'LAUNCHER', 'RUNNER', 'COLLECTOR',
        'PARSER', 'IDENTITY_SERIALIZER', 'HOST_OBSERVER',
        'VIVADO_CAPABILITY_OBSERVER')
    if (-not (Test-Stage1EActivationExactList `
            @($Contract.direct_roles | ForEach-Object { $_.role }) `
            $expectedRoles)) {
        throw 'Activation contract direct role order differs.'
    }
    Assert-Stage1EActivationUniqueField $Contract.direct_roles role `
        'Direct role registry'

    $expectedSubordinates = @('RUNTIME_SCHEMA', 'HASH_PROVIDER',
        'CONTROLLER', 'ADAPTER', 'FRAMEWORK', 'REQUEST', 'RESULT', 'REPORT',
        'MESSAGE', 'HOST')
    if (-not (Test-Stage1EActivationExactList `
            @($Contract.subordinate_contracts | ForEach-Object {
                    $_.contract_role }) $expectedSubordinates)) {
        throw 'Activation subordinate contract order differs.'
    }
    Assert-Stage1EActivationUniqueField $Contract.subordinate_contracts `
        contract_role 'Subordinate contract registry'

    $expectedChildren = @('CANONICALIZATION_POWERSHELL',
        'CANONICALIZATION_TCL', 'CODEC_POWERSHELL', 'CODEC_TCL',
        'ATOMIC_PUBLICATION_POWERSHELL', 'ATOMIC_PUBLICATION_TCL',
        'HASH_PROVIDER_POWERSHELL', 'HASH_PROVIDER_TCL',
        'WINDOWS_PROCESS_CONTROL', 'VIVADO_SESSION_ASSEMBLY')
    if (-not (Test-Stage1EActivationExactList `
            @($Contract.child_providers | ForEach-Object { $_.provider_key }) `
            $expectedChildren)) {
        throw 'Activation child-provider order differs.'
    }
    Assert-Stage1EActivationUniqueField $Contract.child_providers provider_key `
        'Child-provider registry'

    $expectedDomains = @('HOST_POWERSHELL', 'VIVADO_TCL',
        'HOST_POSTPROCESS_TCL')
    if (-not (Test-Stage1EActivationExactList `
            @($Contract.process_domains | ForEach-Object { $_.domain }) `
            $expectedDomains)) {
        throw 'Activation process-domain order differs.'
    }
    Assert-Stage1EActivationUniqueField $Contract.process_domains domain `
        'Process-domain registry'

    if ($Contract.interface_registry.Count -ne 34) {
        throw 'Activation interface registry must contain exactly 34 entries.'
    }
    Assert-Stage1EActivationUniqueField $Contract.interface_registry `
        interface_key 'Interface registry'
    foreach ($entry in $Contract.interface_registry) {
        if ([string]$entry.verification_mode -notin @(
                'POWERSHELL_COMMAND', 'POWERSHELL_AST_ENTRY', 'TCL_COMMAND')) {
            throw "Unknown interface verification mode: $($entry.interface_key)"
        }
        $null = Resolve-Stage1EContainedSourceWithAncestors `
            -RepositoryRoot $script:Stage1EActivationRepositoryRoot `
            -RepositoryPath ([string]$entry.source_path)
    }

    $host = $Contract.host_assembly_contract
    if ([string]$host.ledger_type -cne 'PRT03_DIRECT_ASSEMBLY_LEDGER' -or
        [int]$host.expected_record_count -ne 6 -or
        [int]$host.expected_attempt_count -ne 6 -or
        [string]$host.event_evidence_class -cne
            'PRT03_NATURAL_RUNTIME_OBSERVATION' -or
        [string]$host.direct_connected_state -cne
            'PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED' -or
        [string]$host.accepted_closure_state -cne
            'AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED' -or
        [string]$host.full_transitive_state -cne
            'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN' -or
        [string]$host.final_closure_state -cne
            'FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN') {
        throw 'Connected Host assembly contract differs.'
    }
    foreach ($projection in @($Contract.vivado_projection_contract,
            $Contract.postprocess_projection_contract)) {
        if ([string]$projection.final_closure_state -cne
            'FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN') {
            throw 'Tcl projection overstates final closure.'
        }
    }
    if ([int]$Contract.vivado_projection_contract.expected_record_count -ne 35 -or
        [int]$Contract.postprocess_projection_contract.expected_record_count -ne 29 -or
        [string]$Contract.vivado_projection_contract.live_ledger_state -cne
            'VIVADO_PRE_DISPATCH_LEDGER_NOT_AVAILABLE' -or
        [string]$Contract.postprocess_projection_contract.live_ledger_state -cne
            'POSTPROCESS_PRE_DISPATCH_LEDGER_NOT_AVAILABLE') {
        throw 'Deferred Tcl projection states differ.'
    }

    $readiness = $Contract.activation_readiness_contract
    if ([string]$readiness.target_capability_state -cne
            'PRODUCTION_IMPLEMENTED' -or
        [string]$readiness.review_state -cne 'REVIEW_REQUIRED' -or
        [string]$readiness.direct_connected_state -cne
            'PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED' -or
        [string]$readiness.accepted_closure_state -cne
            'AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED' -or
        [string]$readiness.full_transitive_state -cne
            'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN' -or
        [string]$readiness.runtime_backend_identity_state -cne
            'RUNTIME_BACKEND_IDENTITY_V2_NOT_CREATED' -or
        [string]$readiness.public_dispatch_state -cne
            'PUBLIC_PRODUCTION_DISPATCH_BLOCKED') {
        throw 'Activation-readiness result contract differs.'
    }
    $publicStop = $Contract.public_stop_contract
    if ([string]$publicStop.interface_version -cne
            'stage1e-runtime-activation-stop-interface-v1' -or
        [string]$publicStop.terminal_status -cne 'BLOCKED' -or
        [string]$publicStop.failure_category -cne 'IDENTITY_BINDING' -or
        [string]$publicStop.failure_code -cne
            'RUNTIME_BACKEND_IDENTITY_V2_NOT_CREATED' -or
        [string]$publicStop.outer_phase -cne 'ENTRY_ASSEMBLY' -or
        [string]$publicStop.activation_subphase -cne 'ACTIVATION_PRECHECK' -or
        [string]$publicStop.authorization_effect -cne 'NOT_TOUCHED' -or
        [string]$publicStop.process_effect -cne 'NOT_STARTED' -or
        [string]$publicStop.candidate_effect -cne 'NOT_CREATED' -or
        [string]$publicStop.missing_activation_object -cne
            'RUNTIME_BACKEND_IDENTITY_V2') {
        throw 'Public production stop contract differs.'
    }
    $fixtureStop = $Contract.fixture_stop_contract
    if ([string]$fixtureStop.failure_category -cne 'POLICY_REVIEW' -or
        [string]$fixtureStop.failure_code -cne
            'PRODUCTION_POLICY_REVIEW_NOT_IMPLEMENTED' -or
        [string]$fixtureStop.candidate_effect -cne 'NOT_CREATED') {
        throw 'Non-Vivado fixture stop contract differs.'
    }
    $expectedMissing = @('CURRENT_SOURCE_IDENTITY',
        'RUNTIME_BACKEND_IDENTITY_V2', 'REVIEWED_POLICY_IDENTITY',
        'FROZEN_CONFIGURATION_IDENTITY', 'QUALIFICATION_IDENTITY',
        'ENVIRONMENT_IDENTITY', 'WORKSPACE_IDENTITY',
        'FRESH_SYNTHESIS_PREDECESSOR', 'ONE_USE_AUTHORIZATION')
    if (-not (Test-Stage1EActivationExactList `
            $Contract.missing_activation_objects $expectedMissing)) {
        throw 'Activation missing-object registry differs.'
    }
    foreach ($field in $script:Stage1EAuthorityFields) {
        $expected = if ($field -ceq 'authorization_consumption') {
            'NOT_TOUCHED'
        }
        else { 'NONE' }
        if ([string]$Contract.authority_boundary[$field] -cne $expected) {
            throw "Activation authority boundary broadened: $field"
        }
    }
    return $true
}

function Import-Stage1ERuntimeActivationContract {
    [CmdletBinding()]
    param()
    $raw = Read-Stage1ETclDictionaryFile `
        -Path $script:Stage1EActivationContractPath
    Assert-Stage1EActivationExactFields $raw $script:Stage1EActivationTopFields `
        'Raw activation contract'
    $contract = [ordered]@{
        schema_version = [string]$raw.schema_version
        interface_version = [string]$raw.interface_version
        contract_state = [string]$raw.contract_state
        selected_entry_root = ConvertFrom-Stage1EActivationRecord `
            $raw.selected_entry_root $script:Stage1ESelectedEntryFields `
            'Selected entry root'
        protected_entry_inputs = @(ConvertFrom-Stage1EActivationRecordList `
            $raw.protected_entry_inputs $script:Stage1EProtectedEntryFields `
            'Protected entry input')
        direct_roles = @(ConvertFrom-Stage1EActivationRecordList `
            $raw.direct_roles $script:Stage1EDirectRoleFields 'Direct role')
        subordinate_contracts = @(ConvertFrom-Stage1EActivationRecordList `
            $raw.subordinate_contracts $script:Stage1ESubordinateFields `
            'Subordinate contract')
        child_providers = @(ConvertFrom-Stage1EActivationRecordList `
            $raw.child_providers $script:Stage1EChildProviderFields `
            'Child provider')
        process_domains = @(ConvertFrom-Stage1EActivationRecordList `
            $raw.process_domains $script:Stage1EProcessDomainFields `
            'Process domain')
        interface_registry = @(ConvertFrom-Stage1EActivationRecordList `
            $raw.interface_registry $script:Stage1EInterfaceFields `
            'Interface')
        host_assembly_contract = ConvertFrom-Stage1EActivationRecord `
            $raw.host_assembly_contract $script:Stage1EHostAssemblyFields `
            'Host assembly contract'
        vivado_projection_contract = ConvertFrom-Stage1EActivationRecord `
            $raw.vivado_projection_contract $script:Stage1EProjectionFields `
            'Vivado projection contract'
        postprocess_projection_contract = ConvertFrom-Stage1EActivationRecord `
            $raw.postprocess_projection_contract $script:Stage1EProjectionFields `
            'Post-process projection contract'
        activation_readiness_contract = ConvertFrom-Stage1EActivationRecord `
            $raw.activation_readiness_contract `
            $script:Stage1EActivationReadinessFields `
            'Activation-readiness contract'
        public_stop_contract = ConvertFrom-Stage1EActivationRecord `
            $raw.public_stop_contract $script:Stage1EStopFields `
            'Public stop contract'
        fixture_stop_contract = ConvertFrom-Stage1EActivationRecord `
            $raw.fixture_stop_contract $script:Stage1EFixtureStopFields `
            'Fixture stop contract'
        missing_activation_objects = @(ConvertFrom-Stage1ETclList `
            -Text $raw.missing_activation_objects)
        authority_boundary = ConvertFrom-Stage1EActivationRecord `
            $raw.authority_boundary $script:Stage1EAuthorityFields `
            'Activation authority boundary'
    }
    $null = Assert-Stage1ERuntimeActivationContract $contract
    return $contract
}

function Get-Stage1EActivationInterfaceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract,
        [Parameter(Mandatory = $true)][string]$InterfaceKey
    )
    $records = @($Contract.interface_registry | Where-Object {
            [string]$_.interface_key -ceq $InterfaceKey })
    if ($records.Count -ne 1) {
        throw "Activation interface registry does not contain exactly one $InterfaceKey."
    }
    return $records[0]
}

function Assert-Stage1EConnectedLoadEventLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Events,
        [Parameter(Mandatory = $true)][int]$ExpectedAttemptCount,
        [bool]$RequireNested = $true
    )
    if ($Events.Count -ne ($ExpectedAttemptCount * 2)) {
        throw 'Connected load-event ledger does not contain one attempt and terminal per operation.'
    }
    $attempts = @{}
    $terminals = @{}
    $loadOrdinals = [System.Collections.Generic.HashSet[int]]::new()
    for ($eventIndex = 0; $eventIndex -lt $Events.Count; $eventIndex++) {
        $event = $Events[$eventIndex]
        Assert-Stage1EActivationExactFields $event `
            $script:Stage1EConnectedEventFields `
            "Connected load event $($eventIndex + 1)"
        if ([int]$event.event_ordinal -ne ($eventIndex + 1) -or
            [string]$event.evidence_class -cne
                'PRT03_NATURAL_RUNTIME_OBSERVATION') {
            throw 'Connected load event is reordered or is rehearsal evidence.'
        }
        $id = [string]$event.operation_attempt_id
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw 'Connected load event has an empty operation attempt ID.'
        }
        if ([string]$event.event_state -ceq 'ATTEMPTED') {
            if ($attempts.ContainsKey($id) -or $terminals.ContainsKey($id)) {
                throw "Connected load attempt is duplicated: $id"
            }
            $parent = [string]$event.parent_attempt_id
            if ($parent -cne 'NONE' -and
                (-not $attempts.ContainsKey($parent) -or
                    $terminals.ContainsKey($parent))) {
                throw "Connected child attempt is outside its active parent: $id"
            }
            if (-not $loadOrdinals.Add([int]$event.load_ordinal)) {
                throw "Connected load ordinal is duplicated: $($event.load_ordinal)"
            }
            $attempts[$id] = $event
            continue
        }
        if ([string]$event.event_state -notin @('LOADED', 'FAILED', 'BLOCKED')) {
            throw "Connected load terminal state is invalid: $($event.event_state)"
        }
        if (-not $attempts.ContainsKey($id) -or $terminals.ContainsKey($id)) {
            throw "Connected load terminal lacks exactly one prior attempt: $id"
        }
        $attempt = $attempts[$id]
        foreach ($field in @('operation_attempt_id', 'parent_attempt_id',
                'event_kind', 'requester', 'target', 'source_path', 'provider',
                'interface_version', 'domain', 'load_ordinal', 'edge_type')) {
            if ([string]$attempt[$field] -cne [string]$event[$field]) {
                throw "Connected load attempt/terminal differs for $id at $field."
            }
        }
        $terminals[$id] = $event
    }
    if ($attempts.Count -ne $ExpectedAttemptCount -or
        $terminals.Count -ne $ExpectedAttemptCount) {
        throw 'Connected load chronology has a missing attempt or terminal.'
    }
    for ($ordinal = 1; $ordinal -le $ExpectedAttemptCount; $ordinal++) {
        if (-not $loadOrdinals.Contains($ordinal)) {
            throw "Connected load chronology is missing load ordinal $ordinal."
        }
    }
    $nestedCount = 0
    foreach ($id in $attempts.Keys) {
        $attempt = $attempts[$id]
        $parent = [string]$attempt.parent_attempt_id
        if ($parent -ceq 'NONE') { continue }
        $nestedCount++
        if ([int]$terminals[$id].event_ordinal -ge
            [int]$terminals[$parent].event_ordinal) {
            throw "Connected child terminal does not precede its parent terminal: $id"
        }
    }
    if ($RequireNested -and $nestedCount -eq 0) {
        throw 'Connected load chronology contains no observed nested operation.'
    }
    return $true
}

Export-ModuleMember -Function @(
    'Get-Stage1ERuntimeActivationContractInterfaceVersion'
    'Get-Stage1ERuntimeActivationContractPath'
    'Import-Stage1ERuntimeActivationContract'
    'Assert-Stage1ERuntimeActivationContract'
    'Get-Stage1EActivationInterfaceRecord'
    'Assert-Stage1EConnectedLoadEventLedger'
)
