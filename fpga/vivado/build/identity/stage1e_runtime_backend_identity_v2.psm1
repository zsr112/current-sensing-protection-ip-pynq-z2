Set-StrictMode -Version Latest

$script:Stage1ERuntimeBackendIdentityV2Schema =
    'stage1e-runtime-backend-identity-v2'
$script:Stage1ERuntimeBackendIdentityV2Interface =
    'stage1e-runtime-backend-identity-schema-interface-v2'
$script:Stage1ECanonicalJsonModule = [System.IO.Path]::GetFullPath(
    ([System.IO.Path]::Combine($PSScriptRoot,
        '..\lib\stage1e_runtime_canonical_json_v1.psm1')))
$script:Stage1ERuntimeBackendIdentityV2SchemaPath = [System.IO.Path]::GetFullPath(
    ([System.IO.Path]::Combine($PSScriptRoot,
        '..\lib\stage1e_runtime_backend_identity_v2.schema.json')))
$script:Stage1ERuntimeBackendIdentityV2GitExecutablePath = ''

Microsoft.PowerShell.Core\Import-Module `
    -Name $script:Stage1ECanonicalJsonModule -Force -ErrorAction Stop

$script:Stage1EQualificationRecordDefinitions = [ordered]@{
    'stage1e-human-qualification-authority-record-v1' =
        'human_qualification_authority_record'
    'stage1e-source-freeze-review-record-v1' =
        'source_freeze_review_record'
    'stage1e-q0-q5-live-closure-evidence-v1' =
        'q0_q5_live_closure_evidence'
    'stage1e-runtime-review-record-v1' =
        'runtime_review_record'
    'stage1e-qualification-identity-v1' =
        'qualification_identity'
    'stage1e-qualification-terminal-record-v1' =
        'qualification_terminal_record'
    'stage1e-atomic-q5-result-envelope-v1' =
        'atomic_q5_result_envelope'
}

$script:Stage1ERequiredQ5EvidenceRoles = [object[]]@(
    'Q2_VIVADO_CAPABILITY'
    'Q3_WORKSPACE'
    'HOST_LIVE_CLOSURE'
    'VIVADO_LIVE_CLOSURE'
    'POSTPROCESS_LIVE_CLOSURE'
    'Q4_FRESH_SYNTHESIS'
    'SOURCE_MANIFEST'
    'CONSTRAINT_MANIFEST'
    'REPORT'
    'PARSER'
    'NATIVE_INVOCATION_LEDGER'
    'WARNING_POLICY_RESULT'
    'OPERATION_GRAPH'
    'NO_REPOSITORY_MUTATION'
)

$script:Stage1ERequiredLiveClosure = [ordered]@{
    host_full_transitive_live_closure_state =
        'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_PROVEN'
    vivado_pre_dispatch_ledger_state =
        'VIVADO_PRE_DISPATCH_LEDGER_COMPLETE'
    postprocess_pre_dispatch_ledger_state =
        'POSTPROCESS_PRE_DISPATCH_LEDGER_COMPLETE'
    final_tool_bound_pre_dispatch_closure_state =
        'FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_PROVEN'
}

function New-Stage1ESourceSpecification {
    param(
        [Parameter(Mandatory = $true)][string[]]$ChildBindings,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Language,
        [Parameter(Mandatory = $true)][string]$InterfaceVersion
    )

    return [ordered]@{
        child_bindings = [object[]]@($ChildBindings)
        repository_relative_path = $Path
        language = $Language
        interface_version = $InterfaceVersion
    }
}

$script:Stage1EDirectRuntimeSpecifications = [object[]]@(
    [ordered]@{
        ordinal = 1
        role = 'ENTRY_POINT'
        repository_relative_path = 'fpga/vivado/build/runtime/entrypoint/v2/stage1e_production_runtime_entrypoint_v2.ps1'
        language = 'POWERSHELL'
        interface_version = 'stage1e-production-runtime-entry-point-contract-v1'
    }
    [ordered]@{
        ordinal = 2
        role = 'LAUNCHER'
        repository_relative_path = 'fpga/vivado/build/runtime/launcher/stage1e_production_runtime_launcher_v1.psm1'
        language = 'POWERSHELL'
        interface_version = 'stage1e-production-runtime-launcher-interface-v1'
    }
    [ordered]@{
        ordinal = 3
        role = 'RUNNER'
        repository_relative_path = 'fpga/vivado/build/runtime/runner/stage1e_production_vivado_runner_v1.tcl'
        language = 'TCL'
        interface_version = 'stage1e-production-vivado-runner-interface-v1'
    }
    [ordered]@{
        ordinal = 4
        role = 'COLLECTOR'
        repository_relative_path = 'fpga/vivado/build/runtime/collector/stage1e_production_vivado_collector_v1.tcl'
        language = 'TCL'
        interface_version = 'stage1e-production-vivado-collector-interface-v1'
    }
    [ordered]@{
        ordinal = 5
        role = 'PARSER'
        repository_relative_path = 'fpga/vivado/build/runtime/parser/stage1e_production_evidence_parser_v1.tcl'
        language = 'TCL'
        interface_version = 'stage1e-production-evidence-parser-interface-v1'
    }
    [ordered]@{
        ordinal = 6
        role = 'IDENTITY_SERIALIZER'
        repository_relative_path = 'fpga/vivado/build/runtime/identity/stage1e_production_evidence_serializer_v1.tcl'
        language = 'TCL'
        interface_version = 'stage1e-production-evidence-serializer-interface-v1'
    }
    [ordered]@{
        ordinal = 7
        role = 'HOST_OBSERVER'
        repository_relative_path = 'fpga/vivado/build/runtime/observer/host/stage1e_production_host_observer_v1.psm1'
        language = 'POWERSHELL'
        interface_version = 'stage1e-production-host-observer-interface-v1'
    }
    [ordered]@{
        ordinal = 8
        role = 'VIVADO_CAPABILITY_OBSERVER'
        repository_relative_path = 'fpga/vivado/build/runtime/observer/vivado/stage1e_production_vivado_observer_v1.tcl'
        language = 'TCL'
        interface_version = 'stage1e-production-vivado-observer-interface-v1'
    }
)

$runtimeSchemaSources = [object[]]@(
    (New-Stage1ESourceSpecification @('IDENTITY_V2_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_backend_identity_v2.schema.json' `
        'JSON' 'stage1e-runtime-backend-identity-v2')
    (New-Stage1ESourceSpecification @('IDENTITY_V2_VALIDATOR','IDENTITY_V2_CANONICAL_SERIALIZER','IDENTITY_V2_CANDIDATE_BUILDER') `
        'fpga/vivado/build/identity/stage1e_runtime_backend_identity_v2.psm1' `
        'POWERSHELL' 'stage1e-runtime-backend-identity-schema-interface-v2')
    (New-Stage1ESourceSpecification @('ENVELOPE_CONTRACT_POWERSHELL') `
        'fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.psm1' `
        'POWERSHELL' 'stage1e-runtime-envelope-contract-interface-v1')
    (New-Stage1ESourceSpecification @('ENVELOPE_CONTRACT_TCL') `
        'fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.tcl' `
        'TCL' 'stage1e-runtime-envelope-contract-interface-v1')
    (New-Stage1ESourceSpecification @('VIVADO_RUNTIME_CONTRACT') `
        'fpga/vivado/build/lib/stage1e_vivado_runtime_contract_v1.tcl' `
        'TCL' 'stage1e-vivado-runtime-common-interface-v1')
    (New-Stage1ESourceSpecification @('EVIDENCE_PIPELINE_CONTRACT') `
        'fpga/vivado/build/lib/stage1e_evidence_pipeline_contract_v1.tcl' `
        'TCL' 'stage1e-evidence-pipeline-common-interface-v1')
    (New-Stage1ESourceSpecification @('VIVADO_RECORD_CONTRACT') `
        'fpga/vivado/build/config/stage1e_vivado_runtime_record_contract_v1.dict' `
        'TCL_DICT' 'stage1e-vivado-runtime-record-contract-v1')
    (New-Stage1ESourceSpecification @('EVIDENCE_RECORD_CONTRACT') `
        'fpga/vivado/build/config/stage1e_evidence_record_contract_v1.dict' `
        'TCL_DICT' 'stage1e-evidence-record-contract-v1')
    (New-Stage1ESourceSpecification @('PRT03_ACTIVATION_CONTRACT_CONFIG') `
        'fpga/vivado/build/config/stage1e_runtime_activation_contract_v1.dict' `
        'TCL_DICT' 'stage1e-runtime-activation-contract-v1')
    (New-Stage1ESourceSpecification @('PRT03_ACTIVATION_CONTRACT_PROVIDER') `
        'fpga/vivado/build/lib/stage1e_runtime_activation_contract_v1.psm1' `
        'POWERSHELL' 'stage1e-runtime-activation-contract-interface-v1')
)

$hashProviderSources = [object[]]@(
    (New-Stage1ESourceSpecification @('CANONICALIZATION_POWERSHELL','CODEC_POWERSHELL','HASH_PROVIDER_POWERSHELL') `
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1' `
        'POWERSHELL' 'stage1e-runtime-canonical-json-interface-v1')
    (New-Stage1ESourceSpecification @('CANONICALIZATION_TCL','CODEC_TCL','HASH_PROVIDER_TCL') `
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl' `
        'TCL' 'stage1e-runtime-canonical-json-interface-v1')
    (New-Stage1ESourceSpecification @('PROVIDER_REGISTRY') `
        'fpga/vivado/build/config/stage1e_runtime_provider_contract_v1.dict' `
        'TCL_DICT' 'stage1e-runtime-provider-contract-v1')
    (New-Stage1ESourceSpecification @('HASH_PROVIDER_BOOTSTRAP_TCL') `
        'fpga/vivado/build/dependency/stage1e_hash_bootstrap_v1.tcl' `
        'TCL' 'stage1e-runtime-sha256-provider-interface-v1')
)

$controllerSources = [object[]]@(
    (New-Stage1ESourceSpecification @('VIVADO_CONTROLLER') `
        'fpga/vivado/build/controller/stage1e_production_vivado_controller_v1.tcl' `
        'TCL' 'stage1e-production-vivado-controller-interface-v1')
    (New-Stage1ESourceSpecification @('EVIDENCE_CONTROLLER') `
        'fpga/vivado/build/controller/stage1e_production_evidence_controller_v1.tcl' `
        'TCL' 'stage1e-production-evidence-controller-interface-v1')
    (New-Stage1ESourceSpecification @('AUTHORIZATION_CONSUMPTION_RECEIPT') `
        'fpga/vivado/build/lib/stage1e_runtime_vivado_authorization_consumption_receipt_v1.schema.json' `
        'JSON' 'stage1e-vivado-authorization-consumption-receipt-v1')
    (New-Stage1ESourceSpecification @('PRT03_ASSEMBLY_CONTROLLER') `
        'fpga/vivado/build/controller/stage1e_production_runtime_assembly_controller_v1.psm1' `
        'POWERSHELL' 'stage1e-production-runtime-assembly-controller-interface-v1')
)

$adapterSources = [object[]]@(
    (New-Stage1ESourceSpecification @('VIVADO_ADAPTER') `
        'fpga/vivado/build/adapters/stage1e_production_vivado_adapter_v1.tcl' `
        'TCL' 'stage1e-production-vivado-adapter-interface-v1')
    (New-Stage1ESourceSpecification @('EVIDENCE_ADAPTER') `
        'fpga/vivado/build/adapters/stage1e_production_evidence_adapter_v1.tcl' `
        'TCL' 'stage1e-production-evidence-adapter-interface-v1')
    (New-Stage1ESourceSpecification @('PRT03_ASSEMBLY_ADAPTER') `
        'fpga/vivado/build/adapters/stage1e_production_runtime_assembly_adapter_v1.psm1' `
        'POWERSHELL' 'stage1e-production-runtime-assembly-adapter-interface-v1')
)

$frameworkSources = [object[]]@(
    (New-Stage1ESourceSpecification @('VIVADO_SESSION_ASSEMBLY') `
        'fpga/vivado/build/runtime/runner/stage1e_production_vivado_session_v1.tcl' `
        'TCL' 'stage1e-production-vivado-session-interface-v1')
    (New-Stage1ESourceSpecification @('VIVADO_COMMAND_CONTRACT') `
        'fpga/vivado/build/config/stage1e_vivado_runtime_command_contract_v1.dict' `
        'TCL_DICT' 'stage1e-vivado-runtime-command-contract-v1')
    (New-Stage1ESourceSpecification @('FRAMEWORK_V3_CONTRACT') `
        'fpga/vivado/build/config/stage1e_phase3_implementation_framework_v3.dict' `
        'TCL_DICT' 'stage1e-phase3-implementation-framework-v3')
    (New-Stage1ESourceSpecification @('PRT02_E_DEPENDENCY_CONTRACT') `
        'fpga/vivado/build/config/stage1e_runtime_dependency_contract_v1.dict' `
        'TCL_DICT' 'stage1e-runtime-dependency-contract-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_DECLARED_GRAPH') `
        'fpga/vivado/build/config/stage1e_runtime_declared_graph_v1.dict' `
        'TCL_DICT' 'stage1e-runtime-declared-graph-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_CLOSURE_POWERSHELL') `
        'fpga/vivado/build/dependency/stage1e_runtime_dependency_closure_v1.psm1' `
        'POWERSHELL' 'stage1e-runtime-dependency-closure-interface-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_STATIC_DISCOVERY_TCL') `
        'fpga/vivado/build/dependency/stage1e_tcl_dependency_discovery_v1.tcl' `
        'TCL' 'stage1e-tcl-dependency-discovery-interface-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_SAFE_LOAD_TRACE_TCL') `
        'fpga/vivado/build/dependency/stage1e_tcl_safe_load_trace_v1.tcl' `
        'TCL' 'stage1e-tcl-safe-load-trace-interface-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_ASSEMBLY_LEDGER_POWERSHELL') `
        'fpga/vivado/build/runtime/assembly/stage1e_runtime_assembly_ledger_v1.psm1' `
        'POWERSHELL' 'stage1e-runtime-assembly-ledger-interface-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_ASSEMBLY_LEDGER_TCL') `
        'fpga/vivado/build/runtime/assembly/stage1e_runtime_assembly_ledger_v1.tcl' `
        'TCL' 'stage1e-runtime-assembly-ledger-interface-v1')
    (New-Stage1ESourceSpecification @('PRT03_ACTIVATION_GRAPH_CONFIG') `
        'fpga/vivado/build/config/stage1e_runtime_activation_graph_v1.dict' `
        'TCL_DICT' 'stage1e-prt03-activation-graph-v1')
    (New-Stage1ESourceSpecification @('PRT03_ACTIVATION_GRAPH_PROVIDER') `
        'fpga/vivado/build/lib/stage1e_runtime_activation_graph_v1.psm1' `
        'POWERSHELL' 'stage1e-prt03-activation-graph-interface-v1')
    (New-Stage1ESourceSpecification @('PRT03_CONNECTED_HOST_ASSEMBLY') `
        'fpga/vivado/build/runtime/assembly/stage1e_connected_host_assembly_v1.psm1' `
        'POWERSHELL' 'stage1e-connected-host-assembly-interface-v1')
    (New-Stage1ESourceSpecification @('PRT03_CONNECTED_TCL_PROJECTION') `
        'fpga/vivado/build/runtime/assembly/stage1e_connected_tcl_assembly_projection_v1.tcl' `
        'TCL' 'stage1e-connected-tcl-assembly-projection-interface-v1')
)

$requestSources = [object[]]@(
    (New-Stage1ESourceSpecification @('REQUEST_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_request_envelope_v1.schema.json' `
        'JSON' 'stage1e-production-runtime-request-envelope-v1')
)

$resultSources = [object[]]@(
    (New-Stage1ESourceSpecification @('ATOMIC_PUBLICATION_POWERSHELL') `
        'fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.psm1' `
        'POWERSHELL' 'stage1e-runtime-atomic-publication-interface-v1')
    (New-Stage1ESourceSpecification @('ATOMIC_PUBLICATION_TCL') `
        'fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.tcl' `
        'TCL' 'stage1e-runtime-atomic-publication-interface-v1')
    (New-Stage1ESourceSpecification @('FAILURE_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_failure_record_v1.schema.json' `
        'JSON' 'stage1e-runtime-failure-record-v1')
    (New-Stage1ESourceSpecification @('RESULT_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_result_envelope_v1.schema.json' `
        'JSON' 'stage1e-production-runtime-result-envelope-v1')
    (New-Stage1ESourceSpecification @('PRT03_ACTIVATION_STOP') `
        'fpga/vivado/build/lib/stage1e_runtime_activation_stop_v1.psm1' `
        'POWERSHELL' 'stage1e-runtime-activation-stop-interface-v1')
)

$reportSources = [object[]]@(
    (New-Stage1ESourceSpecification @('REPORT_CONTRACT') `
        'fpga/vivado/build/config/stage1e_report_contract_v1.dict' `
        'TCL_DICT' 'stage1e-production-report-contract-v1')
)

$messageSources = [object[]]@(
    (New-Stage1ESourceSpecification @('MESSAGE_CONTRACT') `
        'fpga/vivado/build/config/stage1e_message_contract_v1.dict' `
        'TCL_DICT' 'stage1e-production-message-contract-v1')
    (New-Stage1ESourceSpecification @('PARSER_FORMAT_PROFILES') `
        'fpga/vivado/build/config/stage1e_parser_format_profiles_v1.dict' `
        'TCL_DICT' 'stage1e-parser-format-profiles-contract-v1')
)

$hostSources = [object[]]@(
    (New-Stage1ESourceSpecification @('HOST_BOUNDARY_CONTRACT') `
        'fpga/vivado/build/lib/stage1e_host_boundary_contract_v1.psm1' `
        'POWERSHELL' 'stage1e-host-boundary-contract-interface-v1')
    (New-Stage1ESourceSpecification @('WINDOWS_PROCESS_CONTROL') `
        'fpga/vivado/build/lib/stage1e_windows_process_control_v1.psm1' `
        'POWERSHELL' 'stage1e-windows-process-control-interface-v1')
    (New-Stage1ESourceSpecification @('WINDOWS_PROCESS_CONTROL_NATIVE_SOURCE') `
        'fpga/vivado/build/lib/stage1e_windows_process_control_v1.cs' `
        'CSHARP' 'stage1e-windows-process-control-interface-v1')
    (New-Stage1ESourceSpecification @('HOST_COMMON_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_common_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-common-v1')
    (New-Stage1ESourceSpecification @('HOST_REQUIREMENTS_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_requirements_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-requirements-v1')
    (New-Stage1ESourceSpecification @('HOST_LAUNCHER_REQUEST_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_launcher_request_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-launcher-request-v1')
    (New-Stage1ESourceSpecification @('HOST_PREFLIGHT_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_preflight_observation_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-preflight-observation-v1')
    (New-Stage1ESourceSpecification @('HOST_PROCESS_INSTANCE_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_process_instance_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-process-instance-v1')
    (New-Stage1ESourceSpecification @('HOST_PROCESS_LEDGER_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_process_ledger_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-process-ledger-v1')
    (New-Stage1ESourceSpecification @('HOST_HEARTBEAT_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_heartbeat_event_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-heartbeat-event-v1')
    (New-Stage1ESourceSpecification @('HOST_TIMEOUT_LEDGER_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_timeout_termination_ledger_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-timeout-termination-ledger-v1')
    (New-Stage1ESourceSpecification @('HOST_RESULT_SCHEMA') `
        'fpga/vivado/build/lib/stage1e_runtime_host_component_result_v1.schema.json' `
        'JSON' 'stage1e-runtime-host-component-result-v1')
    (New-Stage1ESourceSpecification @('VIVADO_PROPERTY_MAP') `
        'fpga/vivado/build/config/stage1e_vivado_runtime_property_map_v1.dict' `
        'TCL_DICT' 'stage1e-vivado-runtime-property-map-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_EXTERNAL_CAPABILITY_CONTRACT') `
        'fpga/vivado/build/config/stage1e_runtime_external_capability_contract_v1.dict' `
        'TCL_DICT' 'stage1e-runtime-external-capability-contract-v1')
    (New-Stage1ESourceSpecification @('PRT02_E_SAFE_LOAD_TRACE_HOST') `
        'fpga/vivado/build/dependency/stage1e_host_safe_load_trace_v1.ps1' `
        'POWERSHELL' 'stage1e-host-safe-load-trace-interface-v1')
)

$script:Stage1ESubordinateContractSpecifications = [object[]]@(
    [ordered]@{ ordinal = 1; contract_role = 'RUNTIME_SCHEMA'; owner = 'RUNTIME_SCHEMA'; interface_version = 'stage1e-runtime-backend-identity-schema-interface-v2'; sources = $runtimeSchemaSources }
    [ordered]@{ ordinal = 2; contract_role = 'HASH_PROVIDER'; owner = 'HASH_PROVIDER'; interface_version = 'stage1e-runtime-sha256-provider-interface-v1'; sources = $hashProviderSources }
    [ordered]@{ ordinal = 3; contract_role = 'CONTROLLER'; owner = 'CONTROLLER'; interface_version = 'stage1e-production-runtime-assembly-controller-interface-v1'; sources = $controllerSources }
    [ordered]@{ ordinal = 4; contract_role = 'ADAPTER'; owner = 'ADAPTER'; interface_version = 'stage1e-production-runtime-assembly-adapter-interface-v1'; sources = $adapterSources }
    [ordered]@{ ordinal = 5; contract_role = 'FRAMEWORK'; owner = 'FRAMEWORK'; interface_version = 'stage1e-phase3-implementation-framework-v3'; sources = $frameworkSources }
    [ordered]@{ ordinal = 6; contract_role = 'REQUEST'; owner = 'REQUEST'; interface_version = 'stage1e-production-runtime-request-envelope-v1'; sources = $requestSources }
    [ordered]@{ ordinal = 7; contract_role = 'RESULT'; owner = 'RESULT'; interface_version = 'stage1e-production-runtime-result-envelope-v1'; sources = $resultSources }
    [ordered]@{ ordinal = 8; contract_role = 'REPORT'; owner = 'REPORT'; interface_version = 'stage1e-production-report-contract-v1'; sources = $reportSources }
    [ordered]@{ ordinal = 9; contract_role = 'MESSAGE'; owner = 'MESSAGE'; interface_version = 'stage1e-production-message-contract-v1'; sources = $messageSources }
    [ordered]@{ ordinal = 10; contract_role = 'HOST'; owner = 'HOST'; interface_version = 'stage1e-host-boundary-contract-interface-v1'; sources = $hostSources }
)

$script:Stage1EAllowedOperations = [object[]]@(
    'opt_design',
    'place_design',
    'route_design',
    'implementation_reports'
)
$script:Stage1EForbiddenOperations = [object[]]@(
    'phys_opt_design',
    'power_opt_design',
    'write_bitstream',
    'write_hw_platform',
    'write_xsa',
    'export_hardware',
    'artifact_collection',
    'artifact_publication',
    'open_hw_manager',
    'connect_hw_server',
    'program_hw_devices',
    'board_access'
)

function Get-Stage1ERuntimeBackendIdentityV2SchemaInterfaceVersion {
    return $script:Stage1ERuntimeBackendIdentityV2Interface
}

function Get-Stage1ERuntimeBackendIdentityV2Schema {
    $bytes = [System.IO.File]::ReadAllBytes(
        $script:Stage1ERuntimeBackendIdentityV2SchemaPath)
    $schema = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes $bytes
    if ([string]$schema['$id'] -cne $script:Stage1ERuntimeBackendIdentityV2Schema) {
        throw [System.IO.InvalidDataException]::new(
            'Runtime Backend Identity v2 schema identifier differs.')
    }
    return $schema
}

function Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry {
    $schema = Get-Stage1ERuntimeBackendIdentityV2Schema
    $registry = [ordered]@{}
    $registry.Add($script:Stage1ERuntimeBackendIdentityV2Schema, $schema)
    return $registry
}

function Initialize-Stage1ERuntimeBackendIdentityV2GitProvider {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$GitExecutablePath)

    if ([string]::IsNullOrWhiteSpace($GitExecutablePath) -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
            $GitExecutablePath) -or
        -not [System.IO.Path]::IsPathRooted($GitExecutablePath)) {
        throw [System.IO.InvalidDataException]::new(
            'RUNTIME_BACKEND_GIT_EXECUTABLE_PATH_INVALID')
    }
    $resolved = [System.IO.Path]::GetFullPath($GitExecutablePath)
    if (-not $resolved.Equals($GitExecutablePath,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [System.IO.File]::Exists($resolved)) {
        throw [System.IO.InvalidDataException]::new(
            'RUNTIME_BACKEND_GIT_EXECUTABLE_PATH_INVALID')
    }
    $file = [System.IO.FileInfo]::new($resolved)
    if (($file.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
        ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        -not $file.Extension.Equals('.exe',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.IO.InvalidDataException]::new(
            'RUNTIME_BACKEND_GIT_EXECUTABLE_PATH_INVALID')
    }
    $script:Stage1ERuntimeBackendIdentityV2GitExecutablePath = $resolved
    return $resolved
}

function Invoke-Stage1ERuntimeBackendGitText {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $gitPath = [string]$script:Stage1ERuntimeBackendIdentityV2GitExecutablePath
    if ([string]::IsNullOrEmpty($gitPath) -or
        -not [System.IO.File]::Exists($gitPath)) {
        throw [System.IO.InvalidDataException]::new(
            'RUNTIME_BACKEND_GIT_PROVIDER_NOT_BOUND')
    }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = [object[]]@(& $gitPath -C $RepositoryRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw [System.IO.InvalidDataException]::new(
            "RUNTIME_BACKEND_GIT_OPERATION_FAILED: $($Arguments -join ' ')")
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $output) { $lines.Add([string]$item) }
    return [ordered]@{
        exit_code = [int64]$exitCode
        text = (($lines.ToArray()) -join "`n").Trim()
    }
}

function Assert-Stage1ECanonicalRepositoryRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf('\') -ge 0 -or
        $Path.StartsWith('/') -or $Path.IndexOf(':') -ge 0 -or
        $Path.IndexOf('*') -ge 0 -or $Path.IndexOf('?') -ge 0) {
        throw [System.IO.InvalidDataException]::new(
            "Repository path is not canonical and relative: $Path")
    }
    $segments = [object[]]@($Path.Split('/'))
    if ($segments.Count -lt 2) {
        throw [System.IO.InvalidDataException]::new(
            "Repository path has insufficient containment: $Path")
    }
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -ceq '.' -or
            $segment -ceq '..') {
            throw [System.IO.InvalidDataException]::new(
                "Repository path contains a prohibited segment: $Path")
        }
    }
    $blockedSegments = [object[]]@('test','tests','fixture','fixtures','historical',
        'history','generated','tmp','outputs')
    foreach ($segment in $segments) {
        if ($blockedSegments -ccontains $segment.ToLowerInvariant()) {
            throw [System.IO.InvalidDataException]::new(
                "Runtime manifest path is test, fixture, historical, or generated source: $Path")
        }
    }
}

function Resolve-Stage1EContainedSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RepositoryRelativePath
    )

    Assert-Stage1ECanonicalRepositoryRelativePath $RepositoryRelativePath
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not [System.IO.Directory]::Exists($root)) {
        throw [System.IO.DirectoryNotFoundException]::new(
            "Repository root does not exist: $root")
    }
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $root (
                $RepositoryRelativePath.Replace('/',
                    [System.IO.Path]::DirectorySeparatorChar))))
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.IO.InvalidDataException]::new(
            "Runtime manifest path escapes the repository: $RepositoryRelativePath")
    }
    if (-not [System.IO.File]::Exists($candidate)) {
        throw [System.IO.FileNotFoundException]::new(
            "Runtime manifest source does not exist: $RepositoryRelativePath")
    }

    $fileInfo = [System.IO.FileInfo]::new($candidate)
    if (($fileInfo.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw [System.IO.InvalidDataException]::new(
            "Runtime manifest source is a reparse point: $RepositoryRelativePath")
    }
    $current = $fileInfo.Directory
    while ($null -ne $current -and
        -not $current.FullName.Equals($root,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw [System.IO.InvalidDataException]::new(
                "Runtime manifest source traverses a reparse point: $RepositoryRelativePath")
        }
        $current = $current.Parent
    }
    return $candidate
}

function Assert-Stage1ECommittedHeadBytes {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RepositoryRelativePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $tracked = Invoke-Stage1ERuntimeBackendGitText $RepositoryRoot @(
        'ls-files','--error-unmatch','--',$RepositoryRelativePath) -AllowFailure
    if ($tracked.exit_code -ne 0) {
        throw [System.IO.InvalidDataException]::new(
            "Runtime source is not Git-tracked: $RepositoryRelativePath")
    }
    $worktreeBlob = Invoke-Stage1ERuntimeBackendGitText $RepositoryRoot @(
        'hash-object','--',$FullPath)
    $headBlob = Invoke-Stage1ERuntimeBackendGitText $RepositoryRoot @(
        'rev-parse',"HEAD:$RepositoryRelativePath") -AllowFailure
    if ($headBlob.exit_code -ne 0 -or
        $worktreeBlob.text -cne $headBlob.text) {
        throw [System.IO.InvalidDataException]::new(
            "Runtime source bytes differ from HEAD: $RepositoryRelativePath")
    }
}

function Get-Stage1EFileEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RepositoryRelativePath,
        [switch]$RequireCommittedBytes
    )

    $fullPath = Resolve-Stage1EContainedSourcePath $RepositoryRoot `
        $RepositoryRelativePath
    if ($RequireCommittedBytes) {
        Assert-Stage1ECommittedHeadBytes $RepositoryRoot `
            $RepositoryRelativePath $fullPath
    }
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    return [ordered]@{
        size_bytes = [int64]$bytes.Length
        file_sha256 = Get-Stage1ESha256Hex -Bytes $bytes
    }
}

function Get-Stage1EDirectRuntimeManifestV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [switch]$RequireCommittedBytes
    )

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($specification in $script:Stage1EDirectRuntimeSpecifications) {
        $evidence = Get-Stage1EFileEvidence $RepositoryRoot `
            ([string]$specification.repository_relative_path) `
            -RequireCommittedBytes:$RequireCommittedBytes
        $items.Add([ordered]@{
                ordinal = [int64]$specification.ordinal
                role = [string]$specification.role
                repository_relative_path =
                    [string]$specification.repository_relative_path
                language = [string]$specification.language
                interface_version = [string]$specification.interface_version
                size_bytes = [int64]$evidence.size_bytes
                file_sha256 = [string]$evidence.file_sha256
            })
    }
    return ,([object[]]$items.ToArray())
}

function Get-Stage1ESubordinateContractIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ContractRole,
        [Parameter(Mandatory = $true)][string]$InterfaceVersion,
        [Parameter(Mandatory = $true)][string]$SourceIdentity,
        [Parameter(Mandatory = $true)][object[]]$SourceManifest
    )

    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append("schema_version=stage1e-runtime-subordinate-contract-manifest-v2`n")
    $null = $builder.Append("contract_role=$ContractRole`n")
    $null = $builder.Append("interface_version=$InterfaceVersion`n")
    $null = $builder.Append("source_identity=$SourceIdentity`n")
    foreach ($entry in $SourceManifest) {
        $childBindings = [string]::Join(',', [string[]]@($entry.child_bindings))
        $null = $builder.Append(('source={0}|{1}|{2}|{3}|{4}|{5}|{6}' -f
                [int64]$entry.ordinal, $childBindings,
                [string]$entry.repository_relative_path,
                [string]$entry.language, [string]$entry.interface_version,
                [int64]$entry.size_bytes, [string]$entry.file_sha256))
        $null = $builder.Append("`n")
    }
    $encoding = [System.Text.UTF8Encoding]::new($false)
    return Get-Stage1ESha256Hex -Bytes $encoding.GetBytes($builder.ToString())
}

function Get-Stage1ESubordinateContractsV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$SourceIdentity,
        [switch]$RequireCommittedBytes
    )

    $contracts = [System.Collections.Generic.List[object]]::new()
    foreach ($contractSpecification in
        $script:Stage1ESubordinateContractSpecifications) {
        $manifest = [System.Collections.Generic.List[object]]::new()
        $ordinal = 0
        foreach ($sourceSpecification in $contractSpecification.sources) {
            $ordinal++
            $evidence = Get-Stage1EFileEvidence $RepositoryRoot `
                ([string]$sourceSpecification.repository_relative_path) `
                -RequireCommittedBytes:$RequireCommittedBytes
            $manifest.Add([ordered]@{
                    ordinal = [int64]$ordinal
                    child_bindings =
                        [object[]]@($sourceSpecification.child_bindings)
                    repository_relative_path =
                        [string]$sourceSpecification.repository_relative_path
                    language = [string]$sourceSpecification.language
                    interface_version =
                        [string]$sourceSpecification.interface_version
                    size_bytes = [int64]$evidence.size_bytes
                    file_sha256 = [string]$evidence.file_sha256
                })
        }
        $manifestArray = [object[]]$manifest.ToArray()
        $contractIdentity = Get-Stage1ESubordinateContractIdentity `
            -ContractRole ([string]$contractSpecification.contract_role) `
            -InterfaceVersion ([string]$contractSpecification.interface_version) `
            -SourceIdentity $SourceIdentity -SourceManifest $manifestArray
        $contracts.Add([ordered]@{
                ordinal = [int64]$contractSpecification.ordinal
                contract_role = [string]$contractSpecification.contract_role
                contract_identity = $contractIdentity
                interface_version =
                    [string]$contractSpecification.interface_version
                source_identity = $SourceIdentity
                owner = [string]$contractSpecification.owner
                source_manifest = $manifestArray
                compatibility_state = 'COMPATIBLE'
            })
    }
    return ,([object[]]$contracts.ToArray())
}

function Test-Stage1EExactArray {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][object[]]$Expected
    )

    if ($Actual.Count -ne $Expected.Count) { return $false }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string]$Actual[$index] -cne [string]$Expected[$index]) {
            return $false
        }
    }
    return $true
}

function Get-Stage1EQualificationRecordSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SchemaVersion)

    if (-not $script:Stage1EQualificationRecordDefinitions.Contains(
            $SchemaVersion)) {
        throw [System.IO.InvalidDataException]::new(
            "QUALIFICATION_RECORD_SCHEMA_UNKNOWN: $SchemaVersion")
    }
    $schema = Get-Stage1ERuntimeBackendIdentityV2Schema
    $definitionName = [string](
        $script:Stage1EQualificationRecordDefinitions[$SchemaVersion])
    if (-not $schema.Contains('definitions') -or
        -not $schema.definitions.Contains($definitionName)) {
        throw [System.IO.InvalidDataException]::new(
            "QUALIFICATION_RECORD_SCHEMA_DEFINITION_MISSING: $definitionName")
    }
    return $schema.definitions[$definitionName]
}

function Get-Stage1EQualificationRecordPayloadBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    if ($Record -isnot [System.Collections.IDictionary] -or
        -not $Record.Contains('schema_version')) {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_RECORD_SCHEMA_VERSION_MISSING')
    }
    $schema = Get-Stage1EQualificationRecordSchema `
        -SchemaVersion ([string]$Record.schema_version)
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    $payload = [ordered]@{}
    foreach ($name in $Record.Keys) {
        if ([string]$name -cne 'identity_sha256') {
            $payload.Add([string]$name, $Record[$name])
        }
    }
    return ConvertTo-Stage1ECanonicalJsonBytes -Value $payload -Schema $schema `
        -SchemaRegistry $registry -OmitProperty 'identity_sha256'
}

function Get-Stage1EQualificationRecordDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    return Get-Stage1ESha256Hex -Bytes (
        Get-Stage1EQualificationRecordPayloadBytes -Record $Record)
}

function Assert-Stage1ECommitAndTreeBinding {
    param([Parameter(Mandatory = $true)]$Record)

    if ([string]$Record.approved_commit -notmatch '^[0-9a-f]{40}$') {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_APPROVED_COMMIT_INVALID')
    }
    if ([string]$Record.approved_tree -notmatch '^[0-9a-f]{40}$') {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_APPROVED_TREE_INVALID')
    }
}

function Assert-Stage1EQ5LiveClosureEvidence {
    param([Parameter(Mandatory = $true)]$Record)

    if ([string]$Record.q2_capability_state -cne 'PASS') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_MISSING_Q2_CAPABILITY')
    }
    if ([string]$Record.q3_workspace_state -cne 'PASS') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_MISSING_Q3_WORKSPACE_LIVE_EVIDENCE')
    }
    if ([string]$Record.q4_fresh_synthesis_state -cne 'PASS') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_MISSING_Q4_FRESH_SYNTHESIS')
    }

    $bindings = [ordered]@{}
    foreach ($binding in $Record.evidence_bindings) {
        $role = [string]$binding.role
        if ($bindings.Contains($role)) {
            throw [System.IO.InvalidDataException]::new(
                "Q5_DUPLICATE_EVIDENCE_ROLE: $role")
        }
        $bindings.Add($role, $binding)
    }
    foreach ($role in $script:Stage1ERequiredQ5EvidenceRoles) {
        if (-not $bindings.Contains([string]$role)) {
            $token = switch ([string]$role) {
                'Q2_VIVADO_CAPABILITY' { 'Q5_MISSING_Q2_CAPABILITY' }
                'Q3_WORKSPACE' { 'Q5_MISSING_Q3_WORKSPACE_LIVE_EVIDENCE' }
                'Q4_FRESH_SYNTHESIS' { 'Q5_MISSING_Q4_FRESH_SYNTHESIS' }
                default { "Q5_MISSING_EVIDENCE_ROLE: $role" }
            }
            throw [System.IO.InvalidDataException]::new($token)
        }
    }
    if ($bindings.Count -ne $script:Stage1ERequiredQ5EvidenceRoles.Count) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_EVIDENCE_ROLE_INVENTORY_MISMATCH')
    }
    foreach ($role in $script:Stage1ERequiredQ5EvidenceRoles) {
        $binding = $bindings[[string]$role]
        if ([string]$binding.execution_id -cne
            [string]$Record.qualification_execution_id) {
            throw [System.IO.InvalidDataException]::new(
                'Q5_MIXED_EXECUTION_IDS')
        }
        if ([string]$binding.source_identity -cne
            [string]$Record.source_identity) {
            throw [System.IO.InvalidDataException]::new(
                'Q5_MIXED_SOURCE_IDENTITIES')
        }
        if ([string]$binding.workspace_identity -cne
            [string]$Record.workspace_identity) {
            throw [System.IO.InvalidDataException]::new(
                'Q5_MIXED_WORKSPACE_IDENTITIES')
        }
        if ([string]$binding.freshness_state -cne 'CURRENT_EXECUTION') {
            if ([string]$role -in @('REPORT','PARSER')) {
                throw [System.IO.InvalidDataException]::new(
                    'Q5_STALE_REPORT_OR_PARSER_EVIDENCE')
            }
            throw [System.IO.InvalidDataException]::new(
                "Q5_STALE_EVIDENCE: $role")
        }
    }
    foreach ($field in $script:Stage1ERequiredLiveClosure.Keys) {
        if ([string]$Record[$field] -cne
            [string]$script:Stage1ERequiredLiveClosure[$field]) {
            $token = switch ([string]$field) {
                'host_full_transitive_live_closure_state' {
                    'Q5_HOST_LIVE_CLOSURE_UNAVAILABLE'
                }
                'vivado_pre_dispatch_ledger_state' {
                    'Q5_VIVADO_LIVE_CLOSURE_UNAVAILABLE'
                }
                'postprocess_pre_dispatch_ledger_state' {
                    'Q5_POSTPROCESS_LIVE_CLOSURE_UNAVAILABLE'
                }
                default { 'Q5_FINAL_TOOL_BOUND_CLOSURE_UNAVAILABLE' }
            }
            throw [System.IO.InvalidDataException]::new($token)
        }
    }
    if ([string]$Record.historical_substitution_state -cne 'NONE') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_HISTORICAL_DCP_OR_REPORT_SUBSTITUTION')
    }
    if ([string]$Record.hidden_provider_state -cne 'NONE') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_HIDDEN_PROVIDER_DETECTED')
    }
    if ([int64]$Record.unclassified_warning_count -ne 0) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_UNCLASSIFIED_WARNING')
    }
    if ([string]$Record.phys_opt_policy_state -cne 'DISABLED' -or
        [string]$Record.phys_opt_configuration_state -cne 'DISABLED' -or
        [string]$Record.phys_opt_authorization_state -cne 'UNAUTHORIZED' -or
        [string]$Record.phys_opt_prohibited_state -cne 'TRUE' -or
        [string]$Record.phys_opt_runtime_readback -cne 'DISABLED') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_PHYS_OPT_CONTROL_STATE_INVALID')
    }
    if ([string]$Record.phys_opt_planned_graph_presence -cne 'ABSENT') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_PHYS_OPT_PRESENT_IN_PLANNED_GRAPH')
    }
    if ([int64]$Record.phys_opt_native_invocation_count -ne 0) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_PHYS_OPT_INVOCATION_NONZERO')
    }
    if ([int64]$Record.implementation_command_invocation_count -ne 0) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_IMPLEMENTATION_INVOCATION_DETECTED')
    }
    if ([string]$Record.no_repository_mutation_state -cne 'PROVEN') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_REPOSITORY_MUTATION_DETECTED')
    }
    if ([string]$Record.run2_authorization_input -cne 'NONE') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_RUN2_AUTHORIZATION_INPUT_PROHIBITED')
    }
}

function Assert-Stage1EQualificationRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    if ($Record -isnot [System.Collections.IDictionary] -or
        -not $Record.Contains('schema_version')) {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_RECORD_SCHEMA_VERSION_MISSING')
    }
    $schemaVersion = [string]$Record.schema_version
    $schema = Get-Stage1EQualificationRecordSchema `
        -SchemaVersion $schemaVersion
    $root = Get-Stage1ERuntimeBackendIdentityV2Schema
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    $null = Assert-Stage1EJsonSchemaValue -Value $Record -Schema $schema `
        -RootSchema $root -SchemaRegistry $registry -Path '$'
    Assert-Stage1ECommitAndTreeBinding $Record

    switch ($schemaVersion) {
        'stage1e-human-qualification-authority-record-v1' {
            if ([string]$Record.run2_authority -cne 'RUN2_NOT_AUTHORIZED' -or
                [string]$Record.board_authority -cne 'BOARD_NOT_AUTHORIZED') {
                throw [System.IO.InvalidDataException]::new(
                    'HUMAN_AUTHORITY_BOUNDARY_INVALID')
            }
            if ([string]$Record.authority_use_state -cne
                    'SINGLE_TRANSITION_SINGLE_EXECUTION' -or
                [string]$Record.reuse_state -cne 'UNUSED') {
                throw [System.IO.InvalidDataException]::new(
                    'HUMAN_AUTHORITY_REUSED')
            }
            if ([string]$Record.authorized_transition -ceq
                'ISSUE_SOURCE_FREEZE_REVIEW') {
                if ([string]$Record.source_freeze_review_authority -cne
                        'SOURCE_FREEZE_REVIEW_AUTHORIZED' -or
                    [string]$Record.q0_q5_qualification_authority -cne
                        'Q0_Q5_QUALIFICATION_NOT_AUTHORIZED') {
                    throw [System.IO.InvalidDataException]::new(
                        'Q1_HUMAN_AUTHORITY_UNAUTHORIZED')
                }
            }
            elseif ([string]$Record.source_freeze_review_authority -cne
                    'SOURCE_FREEZE_REVIEW_NOT_AUTHORIZED' -or
                [string]$Record.q0_q5_qualification_authority -cne
                    'Q0_Q5_QUALIFICATION_AUTHORIZED') {
                throw [System.IO.InvalidDataException]::new(
                    'Q5_HUMAN_AUTHORITY_UNAUTHORIZED')
            }
        }
        'stage1e-source-freeze-review-record-v1' {
            if ([int64]$Record.source_inventory_count -ne 19 -or
                [int64]$Record.protected_source_checked_count -ne 106 -or
                [int64]$Record.protected_source_mismatch_count -ne 0) {
                throw [System.IO.InvalidDataException]::new(
                    'Q1_SOURCE_OR_PROTECTED_INVENTORY_INVALID')
            }
            if ([string]$Record.q1_state -cne 'PASS' -or
                [string]$Record.source_freeze_review -cne
                    'SOURCE_FREEZE_REVIEWED' -or
                [string]$Record.runtime_review -cne 'REVIEW_REQUIRED' -or
                [string]$Record.current_reviewed_effect -cne 'NOT_ISSUED' -or
                [string]$Record.qualification -cne 'NOT_AVAILABLE' -or
                [string]$Record.authorization -cne 'NONE' -or
                [string]$Record.run2 -cne 'NOT_STARTED') {
                throw [System.IO.InvalidDataException]::new(
                    'Q1_STATE_OWNERSHIP_INVALID')
            }
        }
        'stage1e-q0-q5-live-closure-evidence-v1' {
            Assert-Stage1EQ5LiveClosureEvidence $Record
        }
        'stage1e-runtime-review-record-v1' {
            foreach ($field in $script:Stage1ERequiredLiveClosure.Keys) {
                if ([string]$Record[$field] -cne
                    [string]$script:Stage1ERequiredLiveClosure[$field]) {
                    throw [System.IO.InvalidDataException]::new(
                        'RUNTIME_REVIEW_LIVE_CLOSURE_INVALID')
                }
            }
        }
        'stage1e-qualification-identity-v1' {
            if ([string]$Record.current_qualification_state -cne
                    'QUALIFIED_AVAILABLE' -or
                [string]$Record.authorization -cne 'NONE' -or
                [string]$Record.run2 -cne 'NOT_STARTED') {
                throw [System.IO.InvalidDataException]::new(
                    'QUALIFICATION_IDENTITY_BOUNDARY_INVALID')
            }
        }
        'stage1e-qualification-terminal-record-v1' {
            if ([string]$Record.terminal_state -cne
                    'QUALIFIED_NOT_AUTHORIZED' -or
                [string]$Record.authorization -cne 'NONE' -or
                [string]$Record.run2 -cne 'NOT_STARTED' -or
                [string]$Record.implementation -cne 'NOT_EXECUTED' -or
                [string]$Record.artifact -cne 'NONE' -or
                [string]$Record.publication -cne 'NONE' -or
                [string]$Record.board -cne 'NONE') {
                throw [System.IO.InvalidDataException]::new(
                    'QUALIFICATION_TERMINAL_BOUNDARY_INVALID')
            }
        }
        'stage1e-atomic-q5-result-envelope-v1' {
            $expectedLeaves = [object[]]@(
                'runtime_review_record.json'
                'runtime_backend_current_reviewed.json'
                'qualification_identity.json'
                'qualification_terminal_record.json'
            )
            if ($Record.files.Count -ne $expectedLeaves.Count) {
                throw [System.IO.InvalidDataException]::new(
                    'Q5_ATOMIC_FILE_INVENTORY_INVALID')
            }
            for ($index = 0; $index -lt $expectedLeaves.Count; $index++) {
                if ([int64]$Record.files[$index].ordinal -ne ($index + 1) -or
                    [string]$Record.files[$index].leaf_name -cne
                        [string]$expectedLeaves[$index]) {
                    throw [System.IO.InvalidDataException]::new(
                        'Q5_ATOMIC_FILE_INVENTORY_INVALID')
                }
            }
        }
    }
    $expectedDigest = Get-Stage1EQualificationRecordDigest -Record $Record
    if ([string]$Record.identity_sha256 -cne $expectedDigest) {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_RECORD_IDENTITY_MISMATCH')
    }
    return $true
}

function ConvertTo-Stage1EQualificationRecordBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    $null = Assert-Stage1EQualificationRecord -Record $Record
    $schema = Get-Stage1EQualificationRecordSchema `
        -SchemaVersion ([string]$Record.schema_version)
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    return ConvertTo-Stage1ECanonicalJsonBytes -Value $Record -Schema $schema `
        -SchemaRegistry $registry
}

function ConvertFrom-Stage1EQualificationRecordBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $unvalidated = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes $Bytes
    if (-not $unvalidated.Contains('schema_version')) {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_RECORD_SCHEMA_VERSION_MISSING')
    }
    $schema = Get-Stage1EQualificationRecordSchema `
        -SchemaVersion ([string]$unvalidated.schema_version)
    $root = Get-Stage1ERuntimeBackendIdentityV2Schema
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    $record = ConvertFrom-Stage1ECanonicalJsonEnvelope -Bytes $Bytes `
        -Schema $schema -SchemaRegistry $registry
    $null = Assert-Stage1EQualificationRecord -Record $record
    return $record
}

function Complete-Stage1EQualificationRecordIdentity {
    param([Parameter(Mandatory = $true)]$Record)

    $Record.identity_sha256 = Get-Stage1EQualificationRecordDigest -Record $Record
    $null = Assert-Stage1EQualificationRecord -Record $Record
    return $Record
}

function Assert-Stage1EExpectedManifestStructure {
    param([Parameter(Mandatory = $true)]$Record)

    if ($Record.direct_runtime_manifest.Count -ne
        $script:Stage1EDirectRuntimeSpecifications.Count) {
        throw [System.IO.InvalidDataException]::new(
            'Direct Runtime manifest does not contain exactly eight roles.')
    }
    $allPaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    for ($index = 0; $index -lt
        $script:Stage1EDirectRuntimeSpecifications.Count; $index++) {
        $actual = $Record.direct_runtime_manifest[$index]
        $expected = $script:Stage1EDirectRuntimeSpecifications[$index]
        foreach ($field in @('ordinal','role','repository_relative_path',
                'language','interface_version')) {
            if ([string]$actual[$field] -cne [string]$expected[$field]) {
                throw [System.IO.InvalidDataException]::new(
                    "Direct Runtime manifest differs at index $index field $field.")
            }
        }
        Assert-Stage1ECanonicalRepositoryRelativePath `
            ([string]$actual.repository_relative_path)
        if (-not $allPaths.Add([string]$actual.repository_relative_path)) {
            throw [System.IO.InvalidDataException]::new(
                'Direct Runtime manifest contains a duplicate path.')
        }
    }
    if ([string]$Record.direct_runtime_manifest[0].repository_relative_path -match
        'entrypoint_v1') {
        throw [System.IO.InvalidDataException]::new(
            'Entry Point v1 cannot be selected by Runtime Backend Identity v2.')
    }

    if ($Record.subordinate_contracts.Count -ne
        $script:Stage1ESubordinateContractSpecifications.Count) {
        throw [System.IO.InvalidDataException]::new(
            'Subordinate manifest does not contain exactly ten contracts.')
    }
    for ($contractIndex = 0; $contractIndex -lt
        $script:Stage1ESubordinateContractSpecifications.Count; $contractIndex++) {
        $actualContract = $Record.subordinate_contracts[$contractIndex]
        $expectedContract =
            $script:Stage1ESubordinateContractSpecifications[$contractIndex]
        foreach ($field in @('ordinal','contract_role','interface_version','owner')) {
            if ([string]$actualContract[$field] -cne
                [string]$expectedContract[$field]) {
                throw [System.IO.InvalidDataException]::new(
                    "Subordinate contract differs at index $contractIndex field $field.")
            }
        }
        if ($actualContract.source_manifest.Count -ne
            $expectedContract.sources.Count) {
            throw [System.IO.InvalidDataException]::new(
                "Subordinate source closure is incomplete for $($actualContract.contract_role).")
        }
        for ($sourceIndex = 0; $sourceIndex -lt
            $expectedContract.sources.Count; $sourceIndex++) {
            $actualSource = $actualContract.source_manifest[$sourceIndex]
            $expectedSource = $expectedContract.sources[$sourceIndex]
            if ([int64]$actualSource.ordinal -ne ($sourceIndex + 1)) {
                throw [System.IO.InvalidDataException]::new(
                    'Subordinate source manifest ordinals are not contiguous.')
            }
            foreach ($field in @('repository_relative_path','language',
                    'interface_version')) {
                if ([string]$actualSource[$field] -cne
                    [string]$expectedSource[$field]) {
                    throw [System.IO.InvalidDataException]::new(
                        "Subordinate source differs for $($actualContract.contract_role) at index $sourceIndex field $field.")
                }
            }
            if (-not (Test-Stage1EExactArray `
                    ([object[]]@($actualSource.child_bindings)) `
                    ([object[]]@($expectedSource.child_bindings)))) {
                throw [System.IO.InvalidDataException]::new(
                    "Child-provider ownership differs for $($actualSource.repository_relative_path).")
            }
            Assert-Stage1ECanonicalRepositoryRelativePath `
                ([string]$actualSource.repository_relative_path)
            if (-not $allPaths.Add(
                    [string]$actualSource.repository_relative_path)) {
                throw [System.IO.InvalidDataException]::new(
                    "A Runtime source path has multiple primary owners: $($actualSource.repository_relative_path)")
            }
        }
    }
    if ($allPaths.Contains('fpga/vivado/build/lib/source_check.tcl')) {
        throw [System.IO.InvalidDataException]::new(
            'Historical source_check.tcl is reachable from the production manifest.')
    }
    if ([int64]$Record.dependency_closure.declared_source_count -ne
        $allPaths.Count) {
        throw [System.IO.InvalidDataException]::new(
            'Declared dependency source count differs from the exact manifests.')
    }
}

function Assert-Stage1EManifestRepositoryEvidence {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [switch]$RequireCommittedBytes
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Record.direct_runtime_manifest) { $entries.Add($entry) }
    foreach ($contract in $Record.subordinate_contracts) {
        foreach ($entry in $contract.source_manifest) { $entries.Add($entry) }
    }
    foreach ($entry in $entries) {
        $evidence = Get-Stage1EFileEvidence $RepositoryRoot `
            ([string]$entry.repository_relative_path) `
            -RequireCommittedBytes:$RequireCommittedBytes
        if ([int64]$entry.size_bytes -ne [int64]$evidence.size_bytes -or
            [string]$entry.file_sha256 -cne [string]$evidence.file_sha256) {
            throw [System.IO.InvalidDataException]::new(
                "Runtime source evidence differs: $($entry.repository_relative_path)")
        }
    }
}

function Get-Stage1ERuntimeBackendIdentityV2PayloadBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    $payloadRecord = [ordered]@{}
    foreach ($name in $Record.Keys) {
        if ([string]$name -cne 'identity_sha256') {
            $payloadRecord.Add([string]$name, $Record[$name])
        }
    }
    $schema = Get-Stage1ERuntimeBackendIdentityV2Schema
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    return ConvertTo-Stage1ECanonicalJsonBytes -Value $payloadRecord -Schema $schema `
        -SchemaRegistry $registry -OmitProperty 'identity_sha256'
}

function Get-Stage1ERuntimeBackendIdentityV2Digest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    $payload = Get-Stage1ERuntimeBackendIdentityV2PayloadBytes -Record $Record
    return Get-Stage1ESha256Hex -Bytes $payload
}

function Assert-Stage1ERuntimeBackendIdentityV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Record,
        [string]$RepositoryRoot = '',
        [switch]$RequireCommittedBytes
    )

    $schema = Get-Stage1ERuntimeBackendIdentityV2Schema
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    $null = Assert-Stage1EJsonSchemaValue -Value $Record -Schema $schema `
        -RootSchema $schema -SchemaRegistry $registry -Path '$'

    if ([string]$Record.capability_state -ceq 'MOCK_ONLY' -and
        [string]$Record.review_state -ceq 'CURRENT_REVIEWED') {
        throw [System.IO.InvalidDataException]::new(
            'MOCK_ONLY / CURRENT_REVIEWED is an invalid state combination.')
    }
    if ([string]$Record.review_state -ceq 'REVIEW_REQUIRED') {
        if ([string]$Record.review_binding.decision_state -cne
            'REVIEW_REQUIRED') {
            throw [System.IO.InvalidDataException]::new(
                'REVIEW_REQUIRED lacks a matching review binding.')
        }
    }
    else {
        $closure = $Record.dependency_closure
        foreach ($field in $script:Stage1ERequiredLiveClosure.Keys) {
            if ([string]$closure[$field] -cne
                [string]$script:Stage1ERequiredLiveClosure[$field]) {
                throw [System.IO.InvalidDataException]::new(
                    "CURRENT_REVIEWED is prohibited while $field remains unavailable.")
            }
        }
        if ([string]$Record.capability_state -cne 'PRODUCTION_IMPLEMENTED') {
            throw [System.IO.InvalidDataException]::new(
                'CURRENT_REVIEWED requires PRODUCTION_IMPLEMENTED capability.')
        }
        if ([string]$Record.review_binding.decision_state -cne 'APPROVED') {
            throw [System.IO.InvalidDataException]::new(
                'CURRENT_REVIEWED lacks an approved immutable review record.')
        }
        if ([string]$Record.qualification_requirement.
                current_qualification_state -cne 'QUALIFIED_AVAILABLE') {
            throw [System.IO.InvalidDataException]::new(
                'CURRENT_REVIEWED lacks a validated qualification binding.')
        }
    }

    Assert-Stage1EExpectedManifestStructure $Record
    foreach ($contract in $Record.subordinate_contracts) {
        if ([string]$contract.source_identity -cne
            [string]$Record.source_identity) {
            throw [System.IO.InvalidDataException]::new(
                "Cross-source subordinate binding for $($contract.contract_role).")
        }
        $expectedIdentity = Get-Stage1ESubordinateContractIdentity `
            -ContractRole ([string]$contract.contract_role) `
            -InterfaceVersion ([string]$contract.interface_version) `
            -SourceIdentity ([string]$contract.source_identity) `
            -SourceManifest ([object[]]@($contract.source_manifest))
        if ([string]$contract.contract_identity -cne $expectedIdentity) {
            throw [System.IO.InvalidDataException]::new(
                "Subordinate contract identity differs for $($contract.contract_role).")
        }
    }
    if ([string]$Record.canonicalization_contract_identity -cne
        [string]$Record.subordinate_contracts[1].contract_identity) {
        throw [System.IO.InvalidDataException]::new(
            'Canonicalization does not have the single HASH_PROVIDER owner.')
    }
    if ([string]$Record.dependency_closure.prt02_e_binding.source_identity -cne
        [string]$Record.source_identity -or
        [string]$Record.dependency_closure.prt03_binding.source_identity -cne
        [string]$Record.source_identity) {
        throw [System.IO.InvalidDataException]::new(
            'PRT02-E or PRT03 is bound to a different source identity.')
    }
    if (-not (Test-Stage1EExactArray `
            ([object[]]@($Record.dependency_closure.root_roles)) `
            ([object[]]@($script:Stage1EDirectRuntimeSpecifications.role)))) {
        throw [System.IO.InvalidDataException]::new(
            'Dependency closure roots differ from the exact eight-role manifest.')
    }
    if (-not (Test-Stage1EExactArray `
            ([object[]]@($Record.allowed_operations)) `
            $script:Stage1EAllowedOperations) -or
        -not (Test-Stage1EExactArray `
            ([object[]]@($Record.forbidden_operations)) `
            $script:Stage1EForbiddenOperations)) {
        throw [System.IO.InvalidDataException]::new(
            'Allowed or forbidden operation order differs.')
    }
    $expectedDigest = Get-Stage1ERuntimeBackendIdentityV2Digest -Record $Record
    if ([string]$Record.identity_sha256 -cne $expectedDigest) {
        throw [System.IO.InvalidDataException]::new(
            'Runtime Backend Identity v2 self-excluding identity differs.')
    }
    if (-not [string]::IsNullOrEmpty($RepositoryRoot)) {
        Assert-Stage1EManifestRepositoryEvidence -Record $Record `
            -RepositoryRoot $RepositoryRoot `
            -RequireCommittedBytes:$RequireCommittedBytes
    }
    return $true
}

function ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Record,
        [string]$RepositoryRoot = '',
        [switch]$RequireCommittedBytes
    )

    $null = Assert-Stage1ERuntimeBackendIdentityV2 -Record $Record `
        -RepositoryRoot $RepositoryRoot `
        -RequireCommittedBytes:$RequireCommittedBytes
    $schema = Get-Stage1ERuntimeBackendIdentityV2Schema
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    return ConvertTo-Stage1ECanonicalJsonBytes -Value $Record -Schema $schema `
        -SchemaRegistry $registry
}

function ConvertFrom-Stage1ERuntimeBackendIdentityV2Bytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [string]$RepositoryRoot = '',
        [switch]$RequireCommittedBytes
    )

    $schema = Get-Stage1ERuntimeBackendIdentityV2Schema
    $registry = Get-Stage1ERuntimeBackendIdentityV2SchemaRegistry
    $record = ConvertFrom-Stage1ECanonicalJsonEnvelope -Bytes $Bytes `
        -Schema $schema -SchemaRegistry $registry
    $null = Assert-Stage1ERuntimeBackendIdentityV2 -Record $record `
        -RepositoryRoot $RepositoryRoot `
        -RequireCommittedBytes:$RequireCommittedBytes
    return $record
}

function New-Stage1ERuntimeBackendIdentityV2Candidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$SourceIdentity,
        [Parameter(Mandatory = $true)][string]$ValidationEvidenceIdentity,
        [ValidateSet('MOCK_ONLY','PRODUCTION_IMPLEMENTED')]
        [string]$CapabilityState = 'PRODUCTION_IMPLEMENTED',
        [switch]$RequireCommittedBytes
    )

    $directManifest = Get-Stage1EDirectRuntimeManifestV2 `
        -RepositoryRoot $RepositoryRoot `
        -RequireCommittedBytes:$RequireCommittedBytes
    $subordinateContracts = Get-Stage1ESubordinateContractsV2 `
        -RepositoryRoot $RepositoryRoot -SourceIdentity $SourceIdentity `
        -RequireCommittedBytes:$RequireCommittedBytes
    $sourceCount = $directManifest.Count
    foreach ($contract in $subordinateContracts) {
        $sourceCount += $contract.source_manifest.Count
    }

    $record = [ordered]@{
        schema_version = $script:Stage1ERuntimeBackendIdentityV2Schema
        identity_sha256 = ('1' * 64)
        backend_id = 'stage1e-production-runtime-backend'
        backend_version = '2.0.0-candidate'
        capability_state = $CapabilityState
        review_state = 'REVIEW_REQUIRED'
        source_identity = $SourceIdentity
        canonicalization_contract_identity =
            [string]$subordinateContracts[1].contract_identity
        direct_runtime_manifest = [object[]]$directManifest
        subordinate_contracts = [object[]]$subordinateContracts
        dependency_closure = [ordered]@{
            schema_version = 'stage1e-runtime-backend-dependency-closure-v2'
            root_roles = [object[]]@(
                $script:Stage1EDirectRuntimeSpecifications.role)
            declared_source_count = [int64]$sourceCount
            repository_dependency_closure_state =
                'SOURCE_CANDIDATE_CLOSURE_COMPLETE'
            prt02_e_binding = [ordered]@{
                schema_version =
                    'stage1e-runtime-dependency-closure-interface-v1'
                closure_state =
                    'DISCONNECTED_CANDIDATE_CLOSURE_VALIDATED'
                declared_graph_path =
                    'fpga/vivado/build/config/stage1e_runtime_declared_graph_v1.dict'
                provider_contract_path =
                    'fpga/vivado/build/config/stage1e_runtime_provider_contract_v1.dict'
                source_identity = $SourceIdentity
            }
            prt03_binding = [ordered]@{
                schema_version = 'stage1e-prt03-activation-graph-v1'
                readiness_state =
                    'CONNECTED_RUNTIME_ASSEMBLY_READINESS_FOUNDATION'
                direct_connected_state =
                    'PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED'
                activation_graph_path =
                    'fpga/vivado/build/config/stage1e_runtime_activation_graph_v1.dict'
                selected_entry_point_path =
                    'fpga/vivado/build/runtime/entrypoint/v2/stage1e_production_runtime_entrypoint_v2.ps1'
                source_identity = $SourceIdentity
            }
            host_full_transitive_live_closure_state =
                'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN'
            vivado_pre_dispatch_ledger_state =
                'VIVADO_PRE_DISPATCH_LEDGER_NOT_AVAILABLE'
            postprocess_pre_dispatch_ledger_state =
                'POSTPROCESS_PRE_DISPATCH_LEDGER_NOT_AVAILABLE'
            final_tool_bound_pre_dispatch_closure_state =
                'FINAL_TOOL_BOUND_PRE_DISPATCH_CLOSURE_NOT_PROVEN'
            hidden_primary_source_state = 'NONE'
            historical_source_check_state =
                'HISTORICAL_NON_PRODUCTION_NOT_REACHABLE'
            unknown_dependency_action = 'BLOCK'
        }
        interface_compatibility = [ordered]@{
            schema_version = 'stage1e-runtime-interface-compatibility-v2'
            entry_point_interface_version =
                'stage1e-production-runtime-entry-point-contract-v1'
            entry_point_implementation_version =
                'stage1e-production-runtime-entrypoint-implementation-v2'
            launcher_interface_version =
                'stage1e-production-runtime-launcher-interface-v1'
            runner_interface_version =
                'stage1e-production-vivado-runner-interface-v1'
            collector_interface_version =
                'stage1e-production-vivado-collector-interface-v1'
            parser_interface_version =
                'stage1e-production-evidence-parser-interface-v1'
            identity_serializer_interface_version =
                'stage1e-production-evidence-serializer-interface-v1'
            host_observer_interface_version =
                'stage1e-production-host-observer-interface-v1'
            vivado_capability_observer_interface_version =
                'stage1e-production-vivado-observer-interface-v1'
            runtime_schema_interface_version =
                'stage1e-runtime-backend-identity-schema-interface-v2'
            controller_interface_version =
                'stage1e-production-runtime-assembly-controller-interface-v1'
            adapter_interface_version =
                'stage1e-production-runtime-assembly-adapter-interface-v1'
            request_schema_version =
                'stage1e-production-runtime-request-envelope-v1'
            result_schema_version =
                'stage1e-production-runtime-result-envelope-v1'
            report_contract_version = 'stage1e-production-report-contract-v1'
            message_contract_version = 'stage1e-production-message-contract-v1'
            host_contract_version =
                'stage1e-host-boundary-contract-interface-v1'
            dependency_closure_interface_version =
                'stage1e-runtime-dependency-closure-interface-v1'
            activation_graph_interface_version =
                'stage1e-prt03-activation-graph-interface-v1'
            compatibility_state = 'EXACT_MATCH'
        }
        allowed_operations = [object[]]@($script:Stage1EAllowedOperations)
        forbidden_operations = [object[]]@($script:Stage1EForbiddenOperations)
        review_binding = [ordered]@{
            scope = 'PRODUCTION_RUNTIME'
            decision_state = 'REVIEW_REQUIRED'
            validation_evidence_identity = $ValidationEvidenceIdentity
            dependency_closure_decision = 'REVIEW_REQUIRED'
            direct_manifest_decision = 'REVIEW_REQUIRED'
            subordinate_contract_decision = 'REVIEW_REQUIRED'
            review_authority_state = 'NOT_SUPPLIED'
            review_record_state = 'NOT_CREATED'
        }
        qualification_requirement = [ordered]@{
            availability_owner = 'QUALIFICATION_IDENTITY'
            required_availability_value = 'QUALIFIED_AVAILABLE'
            current_qualification_state = 'NOT_AVAILABLE'
            backend_identity_binding_required = $true
            environment_observation_required = $true
            workspace_observation_required = $true
            implementation_authorization_separately_required = $true
        }
        authority_boundary = [ordered]@{
            qualification_decision = 'NONE'
            authorization_issue = 'NONE'
            authorization_consumption_owner = 'CONTROLLER'
            runtime_dispatch_authority = 'NONE'
            engineering_acceptance_decision = 'NONE'
            artifact_authority = 'NONE'
            publication_authority = 'NONE'
            board_authority = 'NONE'
        }
    }
    $record.identity_sha256 =
        Get-Stage1ERuntimeBackendIdentityV2Digest -Record $record
    $null = Assert-Stage1ERuntimeBackendIdentityV2 -Record $record `
        -RepositoryRoot $RepositoryRoot `
        -RequireCommittedBytes:$RequireCommittedBytes
    return $record
}

function New-Stage1EHumanQualificationAuthorityRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AuthorityId,
        [Parameter(Mandatory = $true)]
        [ValidateSet('ISSUE_SOURCE_FREEZE_REVIEW',
            'ISSUE_RUNTIME_REVIEW_AND_QUALIFICATION')]
        [string]$AuthorizedTransition,
        [Parameter(Mandatory = $true)][string]$ApprovedCommit,
        [Parameter(Mandatory = $true)][string]$ApprovedTree,
        [Parameter(Mandatory = $true)][string]$SourceIdentity,
        [Parameter(Mandatory = $true)][string]$ValidationEvidenceIdentity,
        [Parameter(Mandatory = $true)][string]$QualificationExecutionId,
        [Parameter(Mandatory = $true)][string]$WorkspaceIdentity,
        [Parameter(Mandatory = $true)][string]$NamedAuthority,
        [Parameter(Mandatory = $true)][string]$AuthorityRole
    )

    $sourceAuthority = if ($AuthorizedTransition -ceq
        'ISSUE_SOURCE_FREEZE_REVIEW') {
        'SOURCE_FREEZE_REVIEW_AUTHORIZED'
    }
    else {
        'SOURCE_FREEZE_REVIEW_NOT_AUTHORIZED'
    }
    $qualificationAuthority = if ($AuthorizedTransition -ceq
        'ISSUE_RUNTIME_REVIEW_AND_QUALIFICATION') {
        'Q0_Q5_QUALIFICATION_AUTHORIZED'
    }
    else {
        'Q0_Q5_QUALIFICATION_NOT_AUTHORIZED'
    }
    $record = [ordered]@{
        schema_version = 'stage1e-human-qualification-authority-record-v1'
        identity_sha256 = ('1' * 64)
        authority_id = $AuthorityId
        authorized_transition = $AuthorizedTransition
        approved_commit = $ApprovedCommit
        approved_tree = $ApprovedTree
        source_identity = $SourceIdentity
        validation_evidence_identity = $ValidationEvidenceIdentity
        qualification_execution_id = $QualificationExecutionId
        workspace_identity = $WorkspaceIdentity
        source_freeze_review_authority = $sourceAuthority
        q0_q5_qualification_authority = $qualificationAuthority
        run2_authority = 'RUN2_NOT_AUTHORIZED'
        board_authority = 'BOARD_NOT_AUTHORIZED'
        authority_use_state = 'SINGLE_TRANSITION_SINGLE_EXECUTION'
        reuse_state = 'UNUSED'
        named_authority = $NamedAuthority
        authority_role = $AuthorityRole
    }
    return Complete-Stage1EQualificationRecordIdentity $record
}

function New-Stage1ESourceFreezeReviewRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ApprovedCommit,
        [Parameter(Mandatory = $true)][string]$ApprovedTree,
        [Parameter(Mandatory = $true)][string]$QualificationExecutionId,
        [Parameter(Mandatory = $true)][string]$WorkspaceIdentity,
        [Parameter(Mandatory = $true)][string]$SourceCandidateIdentity,
        [Parameter(Mandatory = $true)][string]$ValidationEvidenceIdentity,
        [Parameter(Mandatory = $true)][string]$RuntimeBackendCandidateIdentity,
        [Parameter(Mandatory = $true)][string]$WarningPolicyCandidateIdentity,
        [Parameter(Mandatory = $true)][string]$ImplementationPolicyCandidateIdentity,
        [Parameter(Mandatory = $true)][string]$ImplementationConfigurationCandidateIdentity,
        [Parameter(Mandatory = $true)][string]$HumanDecisionRecordSha256,
        [Parameter(Mandatory = $true)]$HumanAuthorityRecord,
        [Parameter(Mandatory = $true)][string]$PreviewReviewIdentity,
        [Parameter(Mandatory = $true)][string]$Prt04BaseReportSha256,
        [Parameter(Mandatory = $true)][string]$FinalizerCorrectionReportSha256,
        [Parameter(Mandatory = $true)][string]$Prt05AuthorityClosureReportSha256,
        [Parameter(Mandatory = $true)][int64]$SourceInventoryCount,
        [Parameter(Mandatory = $true)][int64]$ProtectedSourceCheckedCount,
        [Parameter(Mandatory = $true)][int64]$ProtectedSourceMismatchCount
    )

    $null = Assert-Stage1EQualificationRecord -Record $HumanAuthorityRecord
    if ([string]$HumanAuthorityRecord.authorized_transition -cne
            'ISSUE_SOURCE_FREEZE_REVIEW' -or
        [string]$HumanAuthorityRecord.approved_commit -cne $ApprovedCommit -or
        [string]$HumanAuthorityRecord.approved_tree -cne $ApprovedTree -or
        [string]$HumanAuthorityRecord.source_identity -cne
            $SourceCandidateIdentity -or
        [string]$HumanAuthorityRecord.validation_evidence_identity -cne
            $ValidationEvidenceIdentity -or
        [string]$HumanAuthorityRecord.qualification_execution_id -cne
            $QualificationExecutionId -or
        [string]$HumanAuthorityRecord.workspace_identity -cne
            $WorkspaceIdentity) {
        throw [System.IO.InvalidDataException]::new(
            'Q1_HUMAN_AUTHORITY_BINDING_MISMATCH')
    }
    $record = [ordered]@{
        schema_version = 'stage1e-source-freeze-review-record-v1'
        identity_sha256 = ('1' * 64)
        q1_state = 'PASS'
        source_freeze_review = 'SOURCE_FREEZE_REVIEWED'
        approved_commit = $ApprovedCommit
        approved_tree = $ApprovedTree
        qualification_execution_id = $QualificationExecutionId
        workspace_identity = $WorkspaceIdentity
        source_candidate_identity = $SourceCandidateIdentity
        validation_evidence_identity = $ValidationEvidenceIdentity
        runtime_backend_candidate_identity = $RuntimeBackendCandidateIdentity
        warning_policy_candidate_identity = $WarningPolicyCandidateIdentity
        implementation_policy_candidate_identity =
            $ImplementationPolicyCandidateIdentity
        implementation_configuration_candidate_identity =
            $ImplementationConfigurationCandidateIdentity
        human_decision_record_sha256 = $HumanDecisionRecordSha256
        human_authority_identity =
            [string]$HumanAuthorityRecord.identity_sha256
        preview_review_identity = $PreviewReviewIdentity
        prt04_base_report_sha256 = $Prt04BaseReportSha256
        finalizer_correction_report_sha256 = $FinalizerCorrectionReportSha256
        prt05_authority_closure_report_sha256 =
            $Prt05AuthorityClosureReportSha256
        source_inventory_count = $SourceInventoryCount
        protected_source_checked_count = $ProtectedSourceCheckedCount
        protected_source_mismatch_count = $ProtectedSourceMismatchCount
        review_decision = 'APPROVED'
        runtime_review = 'REVIEW_REQUIRED'
        current_reviewed_effect = 'NOT_ISSUED'
        qualification = 'NOT_AVAILABLE'
        authorization = 'NONE'
        run2 = 'NOT_STARTED'
        source_freeze_authority = 'CONSUMED_FOR_Q1_ONLY'
        q0_q5_qualification_authority = 'NOT_CONSUMED'
        run2_authority = 'NONE'
        board_authority = 'NONE'
    }
    return Complete-Stage1EQualificationRecordIdentity $record
}

function Assert-Stage1EQ5PromotionInputs {
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)]$SourceFreezeReviewRecord,
        [Parameter(Mandatory = $true)]$LiveClosureEvidence,
        [Parameter(Mandatory = $true)]$QualificationAuthorityRecord
    )

    $null = Assert-Stage1ERuntimeBackendIdentityV2 -Record $Candidate
    $null = Assert-Stage1EQualificationRecord -Record $SourceFreezeReviewRecord
    $null = Assert-Stage1EQualificationRecord -Record $LiveClosureEvidence
    $null = Assert-Stage1EQualificationRecord -Record $QualificationAuthorityRecord
    if ([string]$Candidate.capability_state -cne 'PRODUCTION_IMPLEMENTED' -or
        [string]$Candidate.review_state -cne 'REVIEW_REQUIRED') {
        throw [System.IO.InvalidDataException]::new(
            'Q5_RUNTIME_CANDIDATE_NOT_REVIEW_REQUIRED')
    }
    if ([string]$SourceFreezeReviewRecord.runtime_backend_candidate_identity -cne
            [string]$Candidate.identity_sha256 -or
        [string]$SourceFreezeReviewRecord.source_candidate_identity -cne
            [string]$Candidate.source_identity -or
        [string]$SourceFreezeReviewRecord.validation_evidence_identity -cne
            [string]$Candidate.review_binding.validation_evidence_identity) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_MIXED_SOURCE_IDENTITIES')
    }
    if ([string]$LiveClosureEvidence.source_freeze_review_identity -cne
            [string]$SourceFreezeReviewRecord.identity_sha256) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_SOURCE_FREEZE_REVIEW_BINDING_MISMATCH')
    }
    foreach ($field in @('approved_commit','approved_tree',
            'qualification_execution_id','workspace_identity')) {
        if ([string]$LiveClosureEvidence[$field] -cne
                [string]$SourceFreezeReviewRecord[$field]) {
            $token = if ($field -ceq 'qualification_execution_id') {
                'Q5_MIXED_EXECUTION_IDS'
            }
            elseif ($field -ceq 'workspace_identity') {
                'Q5_MIXED_WORKSPACE_IDENTITIES'
            }
            else {
                'Q5_APPROVED_COMMIT_TREE_MISMATCH'
            }
            throw [System.IO.InvalidDataException]::new($token)
        }
    }
    if ([string]$LiveClosureEvidence.source_identity -cne
            [string]$Candidate.source_identity -or
        [string]$LiveClosureEvidence.validation_evidence_identity -cne
            [string]$Candidate.review_binding.validation_evidence_identity) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_MIXED_SOURCE_IDENTITIES')
    }
    if ([string]$LiveClosureEvidence.prt05_authority_closure_report_sha256 -cne
            [string]$SourceFreezeReviewRecord.
                prt05_authority_closure_report_sha256) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_PRT05_REPORT_BINDING_MISMATCH')
    }
    if ([string]$QualificationAuthorityRecord.authorized_transition -cne
            'ISSUE_RUNTIME_REVIEW_AND_QUALIFICATION' -or
        [string]$QualificationAuthorityRecord.identity_sha256 -cne
            [string]$LiveClosureEvidence.qualification_authority_identity) {
        throw [System.IO.InvalidDataException]::new(
            'Q5_HUMAN_AUTHORITY_BINDING_MISMATCH')
    }
    foreach ($field in @('approved_commit','approved_tree','source_identity',
            'validation_evidence_identity','qualification_execution_id',
            'workspace_identity')) {
        if ([string]$QualificationAuthorityRecord[$field] -cne
            [string]$LiveClosureEvidence[$field]) {
            throw [System.IO.InvalidDataException]::new(
                'Q5_HUMAN_AUTHORITY_BINDING_MISMATCH')
        }
    }
    return $true
}

function New-Stage1ERuntimeReviewRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)]$SourceFreezeReviewRecord,
        [Parameter(Mandatory = $true)]$LiveClosureEvidence,
        [Parameter(Mandatory = $true)]$QualificationAuthorityRecord
    )

    $null = Assert-Stage1EQ5PromotionInputs @PSBoundParameters
    $record = [ordered]@{
        schema_version = 'stage1e-runtime-review-record-v1'
        identity_sha256 = ('1' * 64)
        q5_state = 'PASS'
        runtime_review = 'CURRENT_REVIEWED'
        approved_commit = [string]$LiveClosureEvidence.approved_commit
        approved_tree = [string]$LiveClosureEvidence.approved_tree
        qualification_execution_id =
            [string]$LiveClosureEvidence.qualification_execution_id
        workspace_identity = [string]$LiveClosureEvidence.workspace_identity
        source_identity = [string]$LiveClosureEvidence.source_identity
        validation_evidence_identity =
            [string]$LiveClosureEvidence.validation_evidence_identity
        source_freeze_review_identity =
            [string]$SourceFreezeReviewRecord.identity_sha256
        runtime_backend_candidate_identity = [string]$Candidate.identity_sha256
        live_closure_evidence_identity =
            [string]$LiveClosureEvidence.identity_sha256
        qualification_authority_identity =
            [string]$QualificationAuthorityRecord.identity_sha256
        named_review_authority =
            [string]$QualificationAuthorityRecord.named_authority
        review_decision = 'APPROVED'
        host_full_transitive_live_closure_state =
            [string]$LiveClosureEvidence.
                host_full_transitive_live_closure_state
        vivado_pre_dispatch_ledger_state =
            [string]$LiveClosureEvidence.vivado_pre_dispatch_ledger_state
        postprocess_pre_dispatch_ledger_state =
            [string]$LiveClosureEvidence.postprocess_pre_dispatch_ledger_state
        final_tool_bound_pre_dispatch_closure_state =
            [string]$LiveClosureEvidence.
                final_tool_bound_pre_dispatch_closure_state
        phys_opt_policy_state = [string]$LiveClosureEvidence.phys_opt_policy_state
        phys_opt_configuration_state =
            [string]$LiveClosureEvidence.phys_opt_configuration_state
        phys_opt_authorization_state =
            [string]$LiveClosureEvidence.phys_opt_authorization_state
        phys_opt_prohibited_state =
            [string]$LiveClosureEvidence.phys_opt_prohibited_state
        phys_opt_runtime_readback =
            [string]$LiveClosureEvidence.phys_opt_runtime_readback
        phys_opt_planned_graph_presence =
            [string]$LiveClosureEvidence.phys_opt_planned_graph_presence
        phys_opt_native_invocation_count =
            [int64]$LiveClosureEvidence.phys_opt_native_invocation_count
        no_repository_mutation_state =
            [string]$LiveClosureEvidence.no_repository_mutation_state
        prt05_authority_closure_report_sha256 =
            [string]$LiveClosureEvidence.
                prt05_authority_closure_report_sha256
        authorization = 'NONE'
        run2 = 'NOT_STARTED'
        implementation = 'NOT_EXECUTED'
    }
    return Complete-Stage1EQualificationRecordIdentity $record
}

function New-Stage1ERuntimeBackendIdentityV2CurrentReviewed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)]$RuntimeReviewRecord,
        [Parameter(Mandatory = $true)]$LiveClosureEvidence,
        [Parameter(Mandatory = $true)]$QualificationAuthorityRecord
    )

    $null = Assert-Stage1ERuntimeBackendIdentityV2 -Record $Candidate
    $null = Assert-Stage1EQualificationRecord -Record $RuntimeReviewRecord
    $null = Assert-Stage1EQualificationRecord -Record $LiveClosureEvidence
    $null = Assert-Stage1EQualificationRecord -Record $QualificationAuthorityRecord
    if ([string]$Candidate.capability_state -cne 'PRODUCTION_IMPLEMENTED' -or
        [string]$Candidate.review_state -cne 'REVIEW_REQUIRED') {
        throw [System.IO.InvalidDataException]::new(
            'CURRENT_REVIEWED_REQUIRES_PRODUCTION_REVIEW_REQUIRED_CANDIDATE')
    }
    if ([string]$RuntimeReviewRecord.runtime_backend_candidate_identity -cne
            [string]$Candidate.identity_sha256 -or
        [string]$RuntimeReviewRecord.live_closure_evidence_identity -cne
            [string]$LiveClosureEvidence.identity_sha256 -or
        [string]$RuntimeReviewRecord.qualification_authority_identity -cne
            [string]$QualificationAuthorityRecord.identity_sha256) {
        throw [System.IO.InvalidDataException]::new(
            'CURRENT_REVIEWED_INPUT_BINDING_MISMATCH')
    }
    foreach ($field in $script:Stage1ERequiredLiveClosure.Keys) {
        if ([string]$RuntimeReviewRecord[$field] -cne
                [string]$LiveClosureEvidence[$field] -or
            [string]$LiveClosureEvidence[$field] -cne
                [string]$script:Stage1ERequiredLiveClosure[$field]) {
            throw [System.IO.InvalidDataException]::new(
                "CURRENT_REVIEWED is prohibited while $field remains unavailable.")
        }
    }
    if ([string]$QualificationAuthorityRecord.q0_q5_qualification_authority -cne
        'Q0_Q5_QUALIFICATION_AUTHORIZED') {
        throw [System.IO.InvalidDataException]::new(
            'CURRENT_REVIEWED_QUALIFICATION_BINDING_UNAUTHORIZED')
    }

    $candidateBytes = ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes `
        -Record $Candidate
    $record = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes $candidateBytes
    $record.backend_version = '2.0.0-current-reviewed'
    $record.review_state = 'CURRENT_REVIEWED'
    foreach ($field in $script:Stage1ERequiredLiveClosure.Keys) {
        $record.dependency_closure[$field] =
            [string]$LiveClosureEvidence[$field]
    }
    $record.review_binding = [ordered]@{
        scope = 'PRODUCTION_RUNTIME'
        decision_state = 'APPROVED'
        validation_evidence_identity =
            [string]$Candidate.review_binding.validation_evidence_identity
        dependency_closure_decision = 'PASS'
        direct_manifest_decision = 'PASS'
        subordinate_contract_decision = 'PASS'
        named_review_authority =
            [string]$QualificationAuthorityRecord.named_authority
        review_record_identity = [string]$RuntimeReviewRecord.identity_sha256
        source_freeze_review_identity =
            [string]$RuntimeReviewRecord.source_freeze_review_identity
        live_closure_evidence_identity =
            [string]$LiveClosureEvidence.identity_sha256
        qualification_authority_identity =
            [string]$QualificationAuthorityRecord.identity_sha256
    }
    $record.qualification_requirement.current_qualification_state =
        'QUALIFIED_AVAILABLE'
    $record.identity_sha256 =
        Get-Stage1ERuntimeBackendIdentityV2Digest -Record $record
    $null = Assert-Stage1ERuntimeBackendIdentityV2 -Record $record
    return $record
}

function New-Stage1EQualificationIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CurrentReviewedBackend,
        [Parameter(Mandatory = $true)]$RuntimeReviewRecord,
        [Parameter(Mandatory = $true)]$SourceFreezeReviewRecord,
        [Parameter(Mandatory = $true)]$LiveClosureEvidence,
        [Parameter(Mandatory = $true)]$QualificationAuthorityRecord
    )

    $null = Assert-Stage1ERuntimeBackendIdentityV2 `
        -Record $CurrentReviewedBackend
    foreach ($recordValue in @($RuntimeReviewRecord,$SourceFreezeReviewRecord,
            $LiveClosureEvidence,$QualificationAuthorityRecord)) {
        $null = Assert-Stage1EQualificationRecord -Record $recordValue
    }
    if ([string]$CurrentReviewedBackend.review_state -cne 'CURRENT_REVIEWED' -or
        [string]$CurrentReviewedBackend.review_binding.review_record_identity -cne
            [string]$RuntimeReviewRecord.identity_sha256 -or
        [string]$RuntimeReviewRecord.source_freeze_review_identity -cne
            [string]$SourceFreezeReviewRecord.identity_sha256 -or
        [string]$RuntimeReviewRecord.live_closure_evidence_identity -cne
            [string]$LiveClosureEvidence.identity_sha256 -or
        [string]$RuntimeReviewRecord.qualification_authority_identity -cne
            [string]$QualificationAuthorityRecord.identity_sha256) {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_IDENTITY_INPUT_BINDING_MISMATCH')
    }
    $record = [ordered]@{
        schema_version = 'stage1e-qualification-identity-v1'
        identity_sha256 = ('1' * 64)
        current_qualification_state = 'QUALIFIED_AVAILABLE'
        approved_commit = [string]$RuntimeReviewRecord.approved_commit
        approved_tree = [string]$RuntimeReviewRecord.approved_tree
        qualification_execution_id =
            [string]$RuntimeReviewRecord.qualification_execution_id
        workspace_identity = [string]$RuntimeReviewRecord.workspace_identity
        source_identity = [string]$RuntimeReviewRecord.source_identity
        source_freeze_review_identity =
            [string]$SourceFreezeReviewRecord.identity_sha256
        runtime_review_identity = [string]$RuntimeReviewRecord.identity_sha256
        runtime_backend_identity =
            [string]$CurrentReviewedBackend.identity_sha256
        live_closure_evidence_identity =
            [string]$LiveClosureEvidence.identity_sha256
        qualification_authority_identity =
            [string]$QualificationAuthorityRecord.identity_sha256
        prt05_authority_closure_report_sha256 =
            [string]$RuntimeReviewRecord.
                prt05_authority_closure_report_sha256
        qualification_decision = 'PASS'
        authorization = 'NONE'
        run2 = 'NOT_STARTED'
    }
    return Complete-Stage1EQualificationRecordIdentity $record
}

function New-Stage1EQualificationTerminalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$QualificationIdentity,
        [Parameter(Mandatory = $true)]$CurrentReviewedBackend,
        [Parameter(Mandatory = $true)]$RuntimeReviewRecord
    )

    $null = Assert-Stage1EQualificationRecord -Record $QualificationIdentity
    $null = Assert-Stage1EQualificationRecord -Record $RuntimeReviewRecord
    $null = Assert-Stage1ERuntimeBackendIdentityV2 `
        -Record $CurrentReviewedBackend
    if ([string]$QualificationIdentity.runtime_backend_identity -cne
            [string]$CurrentReviewedBackend.identity_sha256 -or
        [string]$QualificationIdentity.runtime_review_identity -cne
            [string]$RuntimeReviewRecord.identity_sha256) {
        throw [System.IO.InvalidDataException]::new(
            'QUALIFICATION_TERMINAL_INPUT_BINDING_MISMATCH')
    }
    $record = [ordered]@{
        schema_version = 'stage1e-qualification-terminal-record-v1'
        identity_sha256 = ('1' * 64)
        terminal_state = 'QUALIFIED_NOT_AUTHORIZED'
        approved_commit = [string]$QualificationIdentity.approved_commit
        approved_tree = [string]$QualificationIdentity.approved_tree
        qualification_execution_id =
            [string]$QualificationIdentity.qualification_execution_id
        workspace_identity = [string]$QualificationIdentity.workspace_identity
        source_identity = [string]$QualificationIdentity.source_identity
        runtime_review_identity = [string]$RuntimeReviewRecord.identity_sha256
        runtime_backend_identity =
            [string]$CurrentReviewedBackend.identity_sha256
        qualification_identity = [string]$QualificationIdentity.identity_sha256
        authorization = 'NONE'
        run2 = 'NOT_STARTED'
        implementation = 'NOT_EXECUTED'
        artifact = 'NONE'
        publication = 'NONE'
        board = 'NONE'
    }
    return Complete-Stage1EQualificationRecordIdentity $record
}

function New-Stage1EAtomicQ5ResultEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$RuntimeReviewRecord,
        [Parameter(Mandatory = $true)]$CurrentReviewedBackend,
        [Parameter(Mandatory = $true)]$QualificationIdentity,
        [Parameter(Mandatory = $true)]$QualificationTerminalRecord,
        [Parameter(Mandatory = $true)][object[]]$Files
    )

    $null = Assert-Stage1EQualificationRecord -Record $RuntimeReviewRecord
    $null = Assert-Stage1ERuntimeBackendIdentityV2 `
        -Record $CurrentReviewedBackend
    $null = Assert-Stage1EQualificationRecord -Record $QualificationIdentity
    $null = Assert-Stage1EQualificationRecord `
        -Record $QualificationTerminalRecord
    $record = [ordered]@{
        schema_version = 'stage1e-atomic-q5-result-envelope-v1'
        identity_sha256 = ('1' * 64)
        q5_state = 'PASS'
        terminal_state = 'QUALIFIED_NOT_AUTHORIZED'
        approved_commit = [string]$RuntimeReviewRecord.approved_commit
        approved_tree = [string]$RuntimeReviewRecord.approved_tree
        qualification_execution_id =
            [string]$RuntimeReviewRecord.qualification_execution_id
        workspace_identity = [string]$RuntimeReviewRecord.workspace_identity
        source_identity = [string]$RuntimeReviewRecord.source_identity
        runtime_review_identity = [string]$RuntimeReviewRecord.identity_sha256
        runtime_backend_identity =
            [string]$CurrentReviewedBackend.identity_sha256
        qualification_identity = [string]$QualificationIdentity.identity_sha256
        qualification_terminal_identity =
            [string]$QualificationTerminalRecord.identity_sha256
        publication_state = 'ATOMIC_SET_SEALED'
        authorization = 'NONE'
        run2 = 'NOT_STARTED'
        implementation = 'NOT_EXECUTED'
        artifact = 'NONE'
        publication = 'NONE'
        board = 'NONE'
        files = [object[]]$Files
    }
    return Complete-Stage1EQualificationRecordIdentity $record
}

Export-ModuleMember -Function @(
    'Get-Stage1ERuntimeBackendIdentityV2SchemaInterfaceVersion'
    'Get-Stage1ERuntimeBackendIdentityV2Schema'
    'Get-Stage1EDirectRuntimeManifestV2'
    'Get-Stage1ESubordinateContractsV2'
    'Get-Stage1ESubordinateContractIdentity'
    'Get-Stage1ERuntimeBackendIdentityV2PayloadBytes'
    'Get-Stage1ERuntimeBackendIdentityV2Digest'
    'Assert-Stage1ERuntimeBackendIdentityV2'
    'ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes'
    'ConvertFrom-Stage1ERuntimeBackendIdentityV2Bytes'
    'New-Stage1ERuntimeBackendIdentityV2Candidate'
    'Initialize-Stage1ERuntimeBackendIdentityV2GitProvider'
    'Get-Stage1EQualificationRecordSchema'
    'Get-Stage1EQualificationRecordPayloadBytes'
    'Get-Stage1EQualificationRecordDigest'
    'Assert-Stage1EQualificationRecord'
    'ConvertTo-Stage1EQualificationRecordBytes'
    'ConvertFrom-Stage1EQualificationRecordBytes'
    'New-Stage1EHumanQualificationAuthorityRecord'
    'New-Stage1ESourceFreezeReviewRecord'
    'New-Stage1ERuntimeReviewRecord'
    'New-Stage1ERuntimeBackendIdentityV2CurrentReviewed'
    'New-Stage1EQualificationIdentity'
    'New-Stage1EQualificationTerminalRecord'
    'New-Stage1EAtomicQ5ResultEnvelope'
)
