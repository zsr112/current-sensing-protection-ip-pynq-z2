Set-StrictMode -Version Latest

$script:Stage1EConnectedHostAssemblyInterface =
    'stage1e-connected-host-assembly-interface-v1'
$script:Stage1EConnectedAssemblyBuildRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../..'))
$script:Stage1EConnectedAssemblyRepositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $script:Stage1EConnectedAssemblyBuildRoot '../../..'))
$script:Stage1EDependencyModulePath = Join-Path `
    $script:Stage1EConnectedAssemblyBuildRoot `
    'dependency/stage1e_runtime_dependency_closure_v1.psm1'
$script:Stage1EAtomicModulePath = Join-Path `
    $script:Stage1EConnectedAssemblyBuildRoot `
    'lib/stage1e_runtime_atomic_publication_v1.psm1'
$script:Stage1EGraphModulePath = Join-Path `
    $script:Stage1EConnectedAssemblyBuildRoot `
    'lib/stage1e_runtime_activation_graph_v1.psm1'
$script:Stage1EActivationModulePath = Join-Path `
    $script:Stage1EConnectedAssemblyBuildRoot `
    'lib/stage1e_runtime_activation_contract_v1.psm1'
$script:Stage1EStopModulePath = Join-Path `
    $script:Stage1EConnectedAssemblyBuildRoot `
    'lib/stage1e_runtime_activation_stop_v1.psm1'
$script:Stage1EAdapterModulePath = Join-Path `
    $script:Stage1EConnectedAssemblyBuildRoot `
    'adapters/stage1e_production_runtime_assembly_adapter_v1.psm1'
$script:Stage1EControllerModulePath = Join-Path `
    $script:Stage1EConnectedAssemblyBuildRoot `
    'controller/stage1e_production_runtime_assembly_controller_v1.psm1'
$script:Stage1EDependencyInterface =
    'stage1e-runtime-dependency-closure-interface-v1'
$script:Stage1EAtomicInterface =
    'stage1e-runtime-atomic-publication-interface-v1'

Microsoft.PowerShell.Core\Import-Module -Name $script:Stage1EDependencyModulePath `
    -ErrorAction Stop
Microsoft.PowerShell.Core\Import-Module -Name $script:Stage1EAtomicModulePath `
    -ErrorAction Stop
if ([string](Get-Stage1EDependencyClosureInterfaceVersion) -cne
        $script:Stage1EDependencyInterface -or
    [string](Get-Stage1EAtomicPublicationInterfaceVersion) -cne
        $script:Stage1EAtomicInterface) {
    throw 'Connected Host assembly accepted closure interface differs.'
}

$script:Stage1EPrt03EventFields = @(
    'event_ordinal', 'operation_attempt_id', 'parent_attempt_id',
    'event_kind', 'evidence_class', 'event_state', 'requester', 'target',
    'source_path', 'provider', 'interface_version', 'domain',
    'load_ordinal', 'edge_type', 'message')
$script:Stage1EPrt03LedgerFields = @(
    'requester', 'target', 'source_path', 'provider', 'interface_version',
    'domain', 'load_ordinal', 'attempt_state', 'edge_type', 'evidence_source')

function Get-Stage1EConnectedHostAssemblyInterfaceVersion {
    return $script:Stage1EConnectedHostAssemblyInterface
}

function ConvertTo-Stage1EPrt03CanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).Replace('\','/')
}

function Test-Stage1EPrt03Contained {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Boundary
    )
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    $boundaryFull = [System.IO.Path]::GetFullPath($Boundary)
    $prefix = $boundaryFull.TrimEnd('\','/') +
        [System.IO.Path]::DirectorySeparatorChar
    return ($candidateFull.Equals($boundaryFull,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        $candidateFull.StartsWith($prefix,
            [System.StringComparison]::OrdinalIgnoreCase))
}

function ConvertTo-Stage1EPrt03RepositoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = $script:Stage1EConnectedAssemblyRepositoryRoot.TrimEnd('\','/')
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Observed PRT03 source is outside the repository: $full"
    }
    return $full.Substring($prefix.Length).Replace('\','/')
}

function Get-Stage1EPrt03CommandSource {
    param([Parameter(Mandatory = $true)]$Command)
    $source = [string]$Command.ScriptBlock.File
    if ([string]::IsNullOrWhiteSpace($source) -and $null -ne $Command.Module) {
        $source = [string]$Command.Module.Path
    }
    if ([string]::IsNullOrWhiteSpace($source)) {
        throw "Observed PRT03 interface has no source: $($Command.Name)"
    }
    return [System.IO.Path]::GetFullPath($source)
}

function Get-Stage1EPrt03ExactCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ExpectedPath
    )
    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($command in @(Get-Command -Name $Name -CommandType Function `
            -All -ErrorAction Stop)) {
        try {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals(
                    (Get-Stage1EPrt03CommandSource $command),
                    [System.IO.Path]::GetFullPath($ExpectedPath))) {
                $matches.Add($command)
            }
        }
        catch { }
    }
    if ($matches.Count -ne 1) {
        throw "Observed PRT03 interface is missing, duplicate, or substituted: $Name"
    }
    return $matches[0]
}

function Add-Stage1EPrt03NaturalEvent {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Events,
        [Parameter(Mandatory = $true)][string]$OperationAttemptId,
        [Parameter(Mandatory = $true)][string]$ParentAttemptId,
        [Parameter(Mandatory = $true)][string]$EventKind,
        [Parameter(Mandatory = $true)][string]$EventState,
        [Parameter(Mandatory = $true)][string]$Requester,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$InterfaceVersion,
        [Parameter(Mandatory = $true)][int]$LoadOrdinal,
        [Parameter(Mandatory = $true)][string]$EdgeType,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $Events.Add([ordered]@{
            event_ordinal = $Events.Count + 1
            operation_attempt_id = $OperationAttemptId
            parent_attempt_id = $ParentAttemptId
            event_kind = $EventKind
            evidence_class = 'PRT03_NATURAL_RUNTIME_OBSERVATION'
            event_state = $EventState
            requester = $Requester
            target = $Target
            source_path = $SourcePath
            provider = $Provider
            interface_version = $InterfaceVersion
            domain = 'HOST_POWERSHELL'
            load_ordinal = $LoadOrdinal
            edge_type = $EdgeType
            message = $Message
        })
}

function Invoke-Stage1EPrt03ObservedModuleLoad {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Events,
        [Parameter(Mandatory = $true)][string]$ParentAttemptId,
        [Parameter(Mandatory = $true)][int]$LoadOrdinal,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$InterfaceCommand,
        [Parameter(Mandatory = $true)][string]$InterfaceVersion,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    $resolved = Resolve-Stage1EContainedSourceWithAncestors `
        -RepositoryRoot $script:Stage1EConnectedAssemblyRepositoryRoot `
        -RepositoryPath $RepositoryPath
    $operationId = 'PRT03-DIRECT-' + $LoadOrdinal.ToString('D4',
        [System.Globalization.CultureInfo]::InvariantCulture)
    Add-Stage1EPrt03NaturalEvent $Events $operationId $ParentAttemptId `
        'POWERSHELL_MODULE_IMPORT' 'ATTEMPTED' 'CONNECTED_HOST_ASSEMBLY' `
        $Target $RepositoryPath $Provider $InterfaceVersion $LoadOrdinal `
        'POWERSHELL_MODULE' 'IMPORT_ATTEMPT_RECORDED_BEFORE_ACTION'
    try {
        $loaded = @(& $Action)
        $exact = @($loaded | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and
                [System.StringComparer]::OrdinalIgnoreCase.Equals(
                    [System.IO.Path]::GetFullPath([string]$_.Path),
                    $resolved.Path) })
        if ($exact.Count -ne 1) {
            throw "Natural PRT03 import did not return one exact module: $RepositoryPath"
        }
        $command = Get-Stage1EPrt03ExactCommand $InterfaceCommand $resolved.Path
        $observedVersion = [string](& $command)
        $observedPath = ConvertTo-Stage1EPrt03RepositoryPath `
            (Get-Stage1EPrt03CommandSource $command)
        if ($observedVersion -cne $InterfaceVersion -or
            $observedPath -cne $RepositoryPath) {
            throw "Natural PRT03 import interface or source differs: $Target"
        }
        Add-Stage1EPrt03NaturalEvent $Events $operationId $ParentAttemptId `
            'POWERSHELL_MODULE_IMPORT' 'LOADED' 'CONNECTED_HOST_ASSEMBLY' `
            $Target $observedPath $Provider $observedVersion $LoadOrdinal `
            'POWERSHELL_MODULE' 'IMPORTED_MODULE_AND_INTERFACE_OBSERVED'
        return [ordered]@{
            requester = 'CONNECTED_HOST_ASSEMBLY'
            target = $Target
            source_path = $observedPath
            provider = $Provider
            interface_version = $observedVersion
            domain = 'HOST_POWERSHELL'
            load_ordinal = $LoadOrdinal
            attempt_state = 'LOADED'
            edge_type = 'POWERSHELL_MODULE'
            evidence_source = 'NATURAL_RUNTIME_OBSERVATION'
        }
    }
    catch {
        Add-Stage1EPrt03NaturalEvent $Events $operationId $ParentAttemptId `
            'POWERSHELL_MODULE_IMPORT' 'FAILED' 'CONNECTED_HOST_ASSEMBLY' `
            $Target $RepositoryPath $Provider $InterfaceVersion $LoadOrdinal `
            'POWERSHELL_MODULE' $_.Exception.Message
        throw
    }
}

function ConvertTo-Stage1EPrt03SealedValue {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    return $Value.Replace('\','\\').Replace('|','\p').
        Replace("`t",'\t').Replace("`r",'\r').Replace("`n",'\n')
}

function ConvertTo-Stage1EPrt03SealedLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record
    )
    return (($Record.Keys | ForEach-Object {
                "$_=$(ConvertTo-Stage1EPrt03SealedValue ([string]$Record[$_]))"
            }) -join '|')
}

function Publish-Stage1EPrt03DirectLedger {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Binding
    )
    $evidenceRoot = [System.IO.Path]::GetFullPath(
        ([string]$Binding.evidence_root).Replace('/', '\'))
    if (-not [System.IO.Directory]::Exists($evidenceRoot) -or
        (Test-Stage1EPrt03Contained $evidenceRoot `
            $script:Stage1EConnectedAssemblyRepositoryRoot)) {
        throw 'PRT03 direct ledger evidence root is missing or inside source.'
    }
    $ledgerPath = Join-Path $evidenceRoot 'stage1e-prt03-direct-assembly.ledger'
    $receiptPath = Join-Path $evidenceRoot 'stage1e-prt03-direct-assembly.receipt'
    $header = [ordered]@{
        schema_version = 'stage1e-prt03-direct-assembly-ledger-v1'
        interface_version = 'stage1e-prt03-activation-graph-interface-v1'
        ledger_type = 'PRT03_DIRECT_ASSEMBLY_LEDGER'
        publication_state = 'SEALED'
        observation_mode = 'NATURAL_FIXED_ASSEMBLY'
        request_identity = [string]$Binding.request_identity
        execution_id = [string]$Binding.execution_id
        attempt_id = [string]$Binding.attempt_id
        source_identity = [string]$Binding.source_identity
        record_count = $Records.Count
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add((ConvertTo-Stage1EPrt03SealedLine $header))
    foreach ($record in @($Records | Sort-Object {
                [int]$_.load_ordinal })) {
        $sealed = [ordered]@{ record_kind = 'RECORD' }
        foreach ($field in $script:Stage1EPrt03LedgerFields) {
            $sealed[$field] = [string]$record[$field]
        }
        $lines.Add((ConvertTo-Stage1EPrt03SealedLine $sealed))
    }
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        (($lines -join "`n") + "`n"))
    $publication = Publish-Stage1EAtomicBytes -LiteralPath $ledgerPath `
        -Bytes $bytes -BoundaryPath $evidenceRoot
    $receipt = [ordered]@{
        schema_version = 'stage1e-prt03-direct-assembly-ledger-receipt-v1'
        interface_version = 'stage1e-prt03-activation-graph-interface-v1'
        ledger_type = 'PRT03_DIRECT_ASSEMBLY_LEDGER'
        ledger_path = ConvertTo-Stage1EPrt03CanonicalPath $ledgerPath
        publication_state = 'PUBLISHED'
        ledger_byte_count = [int64]$publication.byte_count
        ledger_sha256 = [string]$publication.byte_sha256
        request_identity = [string]$Binding.request_identity
        execution_id = [string]$Binding.execution_id
        attempt_id = [string]$Binding.attempt_id
    }
    $receiptBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        (ConvertTo-Stage1EPrt03SealedLine $receipt))
    $null = Publish-Stage1EAtomicBytes -LiteralPath $receiptPath `
        -Bytes $receiptBytes -BoundaryPath $evidenceRoot
    return [ordered]@{
        ledger_path = $ledgerPath
        receipt_path = $receiptPath
        ledger_sha256 = [string]$publication.byte_sha256
        ledger_byte_count = [int64]$publication.byte_count
    }
}

function Invoke-Stage1EConnectedRuntimeAssembly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ValidatedRequest,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$EntryPointPath
    )
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $root, $script:Stage1EConnectedAssemblyRepositoryRoot)) {
        throw 'Connected runtime assembly rejected an alternate repository root.'
    }
    $selectedEntry = [System.IO.Path]::GetFullPath((Join-Path $root `
        'fpga/vivado/build/runtime/entrypoint/v2/stage1e_production_runtime_entrypoint_v2.ps1'))
    $actualEntry = [System.IO.Path]::GetFullPath($EntryPointPath)
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $selectedEntry, $actualEntry)) {
        throw 'Connected runtime assembly rejected an alternate Entry Point root.'
    }
    $binding = [ordered]@{
        request_identity = [string]$ValidatedRequest.request_identity
        execution_id = [string]$ValidatedRequest.execution_id
        attempt_id = [string]$ValidatedRequest.attempt_id
        source_identity = [string]$ValidatedRequest.source_identity
        workspace_identity = [string]$ValidatedRequest.workspace_identity
        evidence_root = [string]$ValidatedRequest.launch_contract.evidence_root
    }
    foreach ($field in $binding.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$binding[$field])) {
            throw "Connected runtime assembly has an empty binding: $field"
        }
    }

    $events = [System.Collections.Generic.List[object]]::new()
    $records = [System.Collections.Generic.List[object]]::new()
    $parentId = 'PRT03-DIRECT-0001'
    $rootPath = ConvertTo-Stage1EPrt03RepositoryPath $PSCommandPath
    Add-Stage1EPrt03NaturalEvent $events $parentId 'NONE' `
        'ASSEMBLY_ROOT_INVOCATION' 'ATTEMPTED' 'ENTRY_POINT_V2' `
        'CONNECTED_HOST_ASSEMBLY' $rootPath 'CONNECTED_HOST_ASSEMBLY' `
        $script:Stage1EConnectedHostAssemblyInterface 1 'ASSEMBLY_ROOT' `
        'NATURAL_ASSEMBLY_ROOT_ENTERED_BEFORE_CHILD_LOADS'

    $records.Add((Invoke-Stage1EPrt03ObservedModuleLoad $events $parentId 2 `
        'ACTIVATION_GRAPH_MODULE' `
        'fpga/vivado/build/lib/stage1e_runtime_activation_graph_v1.psm1' `
        'ACTIVATION_GRAPH_MODULE' `
        'Get-Stage1EPrt03ActivationGraphInterfaceVersion' `
        'stage1e-prt03-activation-graph-interface-v1' {
            Microsoft.PowerShell.Core\Import-Module -Name `
                $script:Stage1EGraphModulePath -Force -PassThru -ErrorAction Stop
        }))
    $records.Add((Invoke-Stage1EPrt03ObservedModuleLoad $events $parentId 3 `
        'ACTIVATION_CONTRACT_MODULE' `
        'fpga/vivado/build/lib/stage1e_runtime_activation_contract_v1.psm1' `
        'ACTIVATION_CONTRACT_MODULE' `
        'Get-Stage1ERuntimeActivationContractInterfaceVersion' `
        'stage1e-runtime-activation-contract-interface-v1' {
            Microsoft.PowerShell.Core\Import-Module -Name `
                $script:Stage1EActivationModulePath -Force -PassThru `
                -ErrorAction Stop
        }))
    $records.Add((Invoke-Stage1EPrt03ObservedModuleLoad $events $parentId 4 `
        'ACTIVATION_STOP_MODULE' `
        'fpga/vivado/build/lib/stage1e_runtime_activation_stop_v1.psm1' `
        'ACTIVATION_STOP_MODULE' 'Get-Stage1EActivationStopInterfaceVersion' `
        'stage1e-runtime-activation-stop-interface-v1' {
            Microsoft.PowerShell.Core\Import-Module -Name `
                $script:Stage1EStopModulePath -Force -PassThru -ErrorAction Stop
        }))
    $records.Add((Invoke-Stage1EPrt03ObservedModuleLoad $events $parentId 5 `
        'ASSEMBLY_ADAPTER' `
        'fpga/vivado/build/adapters/stage1e_production_runtime_assembly_adapter_v1.psm1' `
        'ASSEMBLY_ADAPTER' `
        'Get-Stage1EProductionRuntimeAssemblyAdapterInterfaceVersion' `
        'stage1e-production-runtime-assembly-adapter-interface-v1' {
            Microsoft.PowerShell.Core\Import-Module -Name `
                $script:Stage1EAdapterModulePath -Force -PassThru -ErrorAction Stop
        }))
    $records.Add((Invoke-Stage1EPrt03ObservedModuleLoad $events $parentId 6 `
        'ASSEMBLY_CONTROLLER' `
        'fpga/vivado/build/controller/stage1e_production_runtime_assembly_controller_v1.psm1' `
        'ASSEMBLY_CONTROLLER' `
        'Get-Stage1EProductionRuntimeAssemblyControllerInterfaceVersion' `
        'stage1e-production-runtime-assembly-controller-interface-v1' {
            Microsoft.PowerShell.Core\Import-Module -Name `
                $script:Stage1EControllerModulePath -Force -PassThru `
                -ErrorAction Stop
        }))

    $rootCommand = Get-Stage1EPrt03ExactCommand `
        'Get-Stage1EConnectedHostAssemblyInterfaceVersion' $PSCommandPath
    $rootObservedPath = ConvertTo-Stage1EPrt03RepositoryPath `
        (Get-Stage1EPrt03CommandSource $rootCommand)
    $rootRecord = [ordered]@{
        requester = 'ENTRY_POINT_V2'
        target = 'CONNECTED_HOST_ASSEMBLY'
        source_path = $rootObservedPath
        provider = 'CONNECTED_HOST_ASSEMBLY'
        interface_version = [string](& $rootCommand)
        domain = 'HOST_POWERSHELL'
        load_ordinal = 1
        attempt_state = 'LOADED'
        edge_type = 'ASSEMBLY_ROOT'
        evidence_source = 'NATURAL_RUNTIME_OBSERVATION'
    }
    Add-Stage1EPrt03NaturalEvent $events $parentId 'NONE' `
        'ASSEMBLY_ROOT_INVOCATION' 'LOADED' 'ENTRY_POINT_V2' `
        'CONNECTED_HOST_ASSEMBLY' $rootObservedPath 'CONNECTED_HOST_ASSEMBLY' `
        ([string]$rootRecord.interface_version) 1 'ASSEMBLY_ROOT' `
        'NATURAL_ASSEMBLY_ROOT_TERMINATED_AFTER_CHILD_LOADS'
    $records.Add($rootRecord)

    $null = Assert-Stage1EConnectedLoadEventLedger -Events $events.ToArray() `
        -ExpectedAttemptCount 6 -RequireNested $true
    $publication = Publish-Stage1EPrt03DirectLedger `
        -Records $records.ToArray() -Binding $binding

    # Expected and static declarations are intentionally read only after
    # natural Actual observations have been sealed.
    $graph = Import-Stage1EPrt03ActivationGraph
    $discovery = Get-Stage1EPrt03StaticDiscovery -Graph $graph
    $staticComparison = Compare-Stage1EPrt03DeclaredAndStatic `
        -Graph $graph -Discovery $discovery
    $directComparison = Compare-Stage1EPrt03DirectAssemblyLedger `
        -LedgerPath $publication.ledger_path `
        -ReceiptPath $publication.receipt_path `
        -RequestIdentity ([string]$binding.request_identity) `
        -ExecutionId ([string]$binding.execution_id) `
        -AttemptId ([string]$binding.attempt_id) `
        -SourceIdentity ([string]$binding.source_identity) -Graph $graph
    $closureReference = Assert-Stage1EPrt03AcceptedClosureReference $graph
    $activation = Import-Stage1ERuntimeActivationContract
    $assemblyRequest = New-Stage1EConnectedAssemblyRequest `
        -ValidatedRequest $ValidatedRequest -RepositoryRoot $root `
        -EntryPointPath $actualEntry -ActivationContract $activation
    $precheck = Get-Stage1EConnectedAssemblyPrecheckDecision `
        -AssemblyRequest $assemblyRequest -ActivationContract $activation
    if ([string]$precheck.decision -cne 'PROCEED_HOST_ASSEMBLY_ONLY') {
        throw 'Connected runtime assembly Controller did not preserve its boundary.'
    }

    return [ordered]@{
        schema_version = 'stage1e-prt03-connected-runtime-assembly-result-v1'
        interface_version = $script:Stage1EConnectedHostAssemblyInterface
        assembly_state = 'PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED'
        request_identity = [string]$binding.request_identity
        execution_id = [string]$binding.execution_id
        attempt_id = [string]$binding.attempt_id
        source_identity = [string]$binding.source_identity
        workspace_identity = [string]$binding.workspace_identity
        selected_entry_root = ConvertTo-Stage1EPrt03CanonicalPath $selectedEntry
        assembly_request = $assemblyRequest
        activation_contract = $activation
        activation_graph_state = 'MATCH'
        activation_graph = $graph
        static_discovery_state = [string]$staticComparison.comparison_state
        static_discovery_comparison = $staticComparison
        direct_ledger_state = [string]$directComparison.comparison_state
        direct_ledger_comparison = $directComparison
        accepted_closure_reference_state =
            [string]$closureReference.reference_state
        accepted_closure_reference = $closureReference
        accepted_closure_state =
            'AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED'
        full_transitive_state =
            'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN'
        direct_role_count = $activation.direct_roles.Count
        subordinate_contract_count = $activation.subordinate_contracts.Count
        child_provider_count = $activation.child_providers.Count
        observed_event_count = $events.Count
        observed_terminal_count = $records.Count
        event_ledger = [object[]]$events.ToArray()
        sealed_ledger_path = ConvertTo-Stage1EPrt03CanonicalPath `
            $publication.ledger_path
        publication_receipt_path = ConvertTo-Stage1EPrt03CanonicalPath `
            $publication.receipt_path
        vivado_ledger_state = 'VIVADO_PRE_DISPATCH_LEDGER_NOT_AVAILABLE'
        postprocess_ledger_state =
            'POSTPROCESS_PRE_DISPATCH_LEDGER_NOT_AVAILABLE'
        final_closure_state =
            'FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN'
        authorization_effect = 'NOT_TOUCHED'
        process_effect = 'NOT_STARTED'
        candidate_effect = 'NOT_CREATED'
    }
}

function Publish-Stage1EConnectedActivationStop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$AssemblyRequest,
        [Parameter(Mandatory = $true)]$HostAssemblyResult,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$StopContract,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )
    foreach ($field in @('request_identity', 'execution_id', 'attempt_id')) {
        if ([string]$AssemblyRequest[$field] -cne
            [string]$HostAssemblyResult[$field]) {
            throw "Connected activation-stop binding differs: $field"
        }
    }
    $record = New-Stage1EActivationStopRecord `
        -AssemblyRequest $AssemblyRequest `
        -HostAssemblyResult $HostAssemblyResult -StopContract $StopContract
    $publication = Publish-Stage1EActivationStopRecord `
        -Record $record -EvidenceRoot $EvidenceRoot
    $reopened = Read-Stage1EActivationStopPublication `
        -RecordPath $publication.record_path `
        -ReceiptPath $publication.receipt_path
    if ([string]$reopened.comparison_state -cne 'MATCH') {
        throw 'Connected activation-stop publication did not reopen exactly.'
    }
    return $publication
}

Export-ModuleMember -Function @(
    'Get-Stage1EConnectedHostAssemblyInterfaceVersion'
    'Invoke-Stage1EConnectedRuntimeAssembly'
    'Publish-Stage1EConnectedActivationStop'
)
