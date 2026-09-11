[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Microsoft.PowerShell.Core\Import-Module -Name Microsoft.PowerShell.Management `
    -ErrorAction Stop
Microsoft.PowerShell.Core\Import-Module -Name Microsoft.PowerShell.Utility `
    -ErrorAction Stop
$PSModuleAutoloadingPreference = 'None'

$root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar)
$output = [System.IO.Path]::GetFullPath($OutputPath)
$rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
if ($output.StartsWith($rootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Safe-load trace output must be external to the repository.'
}
if ([System.IO.File]::Exists($output)) {
    throw "Safe-load trace output already exists: $output"
}
$outputDirectory = [System.IO.Path]::GetDirectoryName($output)
if (-not [System.IO.Directory]::Exists($outputDirectory)) {
    $null = [System.IO.Directory]::CreateDirectory($outputDirectory)
}

$controlledEnvironment = [ordered]@{
    SystemRoot = [System.Environment]::GetEnvironmentVariable('SystemRoot')
    TEMP = $outputDirectory
    TMP = $outputDirectory
    PSModulePath = (Join-Path $outputDirectory 'disabled-module-path')
    PSExecutionPolicyPreference =
        [System.Environment]::GetEnvironmentVariable(
            'PSExecutionPolicyPreference')
}
foreach ($name in @([System.Environment]::GetEnvironmentVariables(
            [System.EnvironmentVariableTarget]::Process).Keys)) {
    if (-not $controlledEnvironment.Contains([string]$name)) {
        [System.Environment]::SetEnvironmentVariable(
            [string]$name, $null,
            [System.EnvironmentVariableTarget]::Process)
    }
}
foreach ($name in $controlledEnvironment.Keys) {
    [System.Environment]::SetEnvironmentVariable(
        $name, [string]$controlledEnvironment[$name],
        [System.EnvironmentVariableTarget]::Process)
}
[System.IO.Directory]::SetCurrentDirectory($outputDirectory)

function Get-Stage1EControlledFileSnapshot {
    param([Parameter(Mandatory = $true)][string]$PathRoot)
    $snapshot = [ordered]@{}
    foreach ($item in @(Get-ChildItem -LiteralPath $PathRoot -Recurse -Force -File |
            Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 })) {
        $relative = $item.FullName.Substring($PathRoot.Length).TrimStart('\','/')
        $digest = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $snapshot[$relative.Replace('\','/')] = "$($item.Length)|$($item.LastWriteTimeUtc.Ticks)|$digest"
    }
    return $snapshot
}

$script:Stage1EInitialRepositorySnapshot =
    Get-Stage1EControlledFileSnapshot $root
$script:Stage1EInitialEvidenceSnapshot =
    Get-Stage1EControlledFileSnapshot $outputDirectory
$script:Stage1EInitialEnvironment = [ordered]@{}
foreach ($name in @([System.Environment]::GetEnvironmentVariables(
            [System.EnvironmentVariableTarget]::Process).Keys | Sort-Object)) {
    $script:Stage1EInitialEnvironment[[string]$name] =
        [System.Environment]::GetEnvironmentVariable([string]$name)
}
$script:Stage1EInitialCwd = [System.IO.Directory]::GetCurrentDirectory()
$script:Stage1EInitialProfile = $PROFILE
$script:Stage1EInitialProfileExists = [System.IO.File]::Exists($PROFILE)
$script:Stage1EInitialProfileBytes = if ($script:Stage1EInitialProfileExists) {
    [System.IO.File]::ReadAllBytes($PROFILE)
} else { [byte[]]@() }

function Test-Stage1ETraceBytesEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

$script:Stage1ETraceRecords = [System.Collections.Generic.List[object]]::new()
$script:Stage1ERehearsalRecords = [System.Collections.Generic.List[object]]::new()
$script:Stage1ETraceOrdinal = 0
$script:Stage1ERehearsalOrdinal = 0
$script:Stage1ELoadOrdinal = 0
$script:Stage1EAttemptOrdinal = 0
$script:Stage1ECurrentRequester = 'TRACE_ASSEMBLY'
$script:Stage1ECurrentPredicate = 'CONTROLLED_INTERNAL_HARNESS'

function Get-Stage1ETraceNodeForPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $map = @{
        'fpga/vivado/build/runtime/entrypoint/stage1e_production_runtime_entrypoint_v1.ps1' = 'ENTRY_POINT'
        'fpga/vivado/build/runtime/launcher/stage1e_production_runtime_launcher_v1.psm1' = 'LAUNCHER'
        'fpga/vivado/build/runtime/observer/host/stage1e_production_host_observer_v1.psm1' = 'HOST_OBSERVER'
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1' = 'PS_CANONICAL_JSON'
        'fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.psm1' = 'PS_ENVELOPE_CONTRACT'
        'fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.psm1' = 'PS_ATOMIC_PUBLICATION'
        'fpga/vivado/build/lib/stage1e_host_boundary_contract_v1.psm1' = 'HOST_BOUNDARY_CONTRACT'
        'fpga/vivado/build/lib/stage1e_windows_process_control_v1.psm1' = 'WINDOWS_PROCESS_CONTROL_MODULE'
    }
    if (-not $map.ContainsKey($RelativePath)) {
        throw "Trace target is not a declared Host node: $RelativePath"
    }
    return $map[$RelativePath]
}

function Add-Stage1ETraceRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$Provider = 'NONE',
        [string]$InterfaceVersion = 'NONE',
        [string]$DeclaredEdge = 'NONE',
        [string]$Target = 'NONE',
        [string]$EdgeType = 'NONE',
        [string]$AttemptId = 'NONE',
        [int]$LoadOrdinal = 0,
        [string]$Predicate = 'NONE',
        [string]$EvidenceClass = 'OBSERVED_SAFE_LOAD_TRACE',
        [string]$Requester = $script:Stage1ECurrentRequester,
        [string]$InterfaceCommand = 'NONE'
    )
    $isRehearsal = $EvidenceClass -ceq 'DECLARED_ASSEMBLY_REHEARSAL'
    if ($isRehearsal) { $script:Stage1ERehearsalOrdinal++ }
    else { $script:Stage1ETraceOrdinal++ }
    $record = [ordered]@{
            kind = $Kind
            ordinal = $(if($isRehearsal){$script:Stage1ERehearsalOrdinal}else{$script:Stage1ETraceOrdinal})
            scenario = 'HOST_DISCONNECTED_SAFE_LOAD'
            domain = 'HOST_POWERSHELL'
            requester = $Requester
            target = $Target
            edge_type = $EdgeType
            source_path = $SourcePath.Replace('\', '/')
            provider = $Provider
            interface_version = $InterfaceVersion
            interface_command = $InterfaceCommand
            attempt_state = $State
            declared_edge = $DeclaredEdge
            attempt_id = $AttemptId
            load_ordinal = $LoadOrdinal
            predicate = $Predicate
            evidence_class = $EvidenceClass
            reason = $Reason
        }
    if ($isRehearsal) { $script:Stage1ERehearsalRecords.Add($record) }
    else { $script:Stage1ETraceRecords.Add($record) }
}

function Start-Stage1ETraceAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$Requester,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$EdgeType,
        [string]$DeclaredEdge = 'NONE',
        [string]$Provider = 'NONE',
        [string]$InterfaceVersion = 'NONE',
        [string]$Predicate = 'CONTROLLED_INTERNAL_HARNESS',
        [string]$EvidenceClass = 'OBSERVED_SAFE_LOAD_TRACE',
        [string]$Reason = 'CONTROLLED_TRACE_EVENT',
        [string]$InterfaceCommand = 'NONE'
    )
    $script:Stage1EAttemptOrdinal++
    $script:Stage1ELoadOrdinal++
    $attemptId = ('HOST-{0:D4}' -f $script:Stage1EAttemptOrdinal)
    $context = [pscustomobject][ordered]@{
        Kind = $Kind
        SourcePath = $SourcePath
        Requester = $Requester
        Target = $Target
        EdgeType = $EdgeType
        DeclaredEdge = $DeclaredEdge
        Provider = $Provider
        InterfaceVersion = $InterfaceVersion
        InterfaceCommand = $InterfaceCommand
        Predicate = $Predicate
        EvidenceClass = $EvidenceClass
        Reason = $Reason
        AttemptId = $attemptId
        LoadOrdinal = $script:Stage1ELoadOrdinal
    }
    Add-Stage1ETraceRecord -Kind $Kind -State ATTEMPTED `
        -SourcePath $SourcePath -Reason ($Reason + '_ATTEMPT') `
        -Provider $Provider -InterfaceVersion $InterfaceVersion `
        -DeclaredEdge $DeclaredEdge -Target $Target -EdgeType $EdgeType `
        -AttemptId $attemptId -LoadOrdinal $script:Stage1ELoadOrdinal `
        -Predicate $Predicate -EvidenceClass $EvidenceClass `
        -Requester $Requester -InterfaceCommand $InterfaceCommand
    return $context
}

function Complete-Stage1ETraceAttempt {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]
        [ValidateSet('LOADED','FAILED','OPTIONAL_NOT_LOADED','BLOCKED')]
        [string]$TerminalState
    )
    Add-Stage1ETraceRecord -Kind $Context.Kind -State $TerminalState `
        -SourcePath $Context.SourcePath `
        -Reason ($Context.Reason + '_TERMINAL') `
        -Provider $Context.Provider `
        -InterfaceVersion $Context.InterfaceVersion `
        -DeclaredEdge $Context.DeclaredEdge -Target $Context.Target `
        -EdgeType $Context.EdgeType -AttemptId $Context.AttemptId `
        -LoadOrdinal $Context.LoadOrdinal -Predicate $Context.Predicate `
        -EvidenceClass $Context.EvidenceClass -Requester $Context.Requester `
        -InterfaceCommand $Context.InterfaceCommand
}

function Add-Stage1ETraceAttempt {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$Requester,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$EdgeType,
        [string]$DeclaredEdge = 'NONE',
        [string]$Provider = 'NONE',
        [string]$InterfaceVersion = 'NONE',
        [ValidateSet('LOADED','FAILED','OPTIONAL_NOT_LOADED','BLOCKED')]
        [string]$TerminalState = 'LOADED',
        [string]$Predicate = 'CONTROLLED_INTERNAL_HARNESS',
        [string]$EvidenceClass = 'OBSERVED_SAFE_LOAD_TRACE',
        [string]$Reason = 'CONTROLLED_TRACE_EVENT',
        [string]$InterfaceCommand = 'NONE'
    )
    $context = Start-Stage1ETraceAttempt -Kind $Kind -SourcePath $SourcePath `
        -Requester $Requester -Target $Target -EdgeType $EdgeType `
        -DeclaredEdge $DeclaredEdge -Provider $Provider `
        -InterfaceVersion $InterfaceVersion -Predicate $Predicate `
        -EvidenceClass $EvidenceClass -Reason $Reason `
        -InterfaceCommand $InterfaceCommand
    Complete-Stage1ETraceAttempt $context $TerminalState
}

function Add-Stage1ERehearsalRecord {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Requester,
        [Parameter(Mandatory = $true)][string]$EdgeType,
        [Parameter(Mandatory = $true)][string]$DeclaredEdge,
        [string]$Provider = 'NONE',
        [string]$InterfaceVersion = 'NONE',
        [string]$Predicate = 'DECLARED_SCHEMA_REHEARSAL'
    )
    $script:Stage1ERehearsalRecords.Add([ordered]@{
            kind = 'FILE_READ'
            scenario = 'HOST_DISCONNECTED_SAFE_LOAD'
            domain = 'HOST_POWERSHELL'
            ordinal = $script:Stage1ERehearsalRecords.Count + 1
            attempt_id = 'REHEARSAL'
            load_ordinal = 0
            requester = $Requester
            target = $Target
            edge_type = $EdgeType
            source_path = $SourcePath.Replace('\', '/')
            provider = $Provider
            interface_version = $InterfaceVersion
            interface_command = 'NONE'
            attempt_state = 'DECLARED'
            declared_edge = $DeclaredEdge
            predicate = $Predicate
            evidence_class = 'DECLARED_ASSEMBLY_REHEARSAL'
            reason = 'DIRECT_DOTNET_READ_NOT_INTERCEPTABLE' })
}

function ConvertTo-Stage1ERelativeTracePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($rootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Safe-load attempted a source outside the repository: $full"
    }
    return $full.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-Stage1ETraceRequesterNode {
    param([string]$Fallback = $script:Stage1ECurrentRequester)
    foreach ($frame in @(Get-PSCallStack)) {
        $candidate = [string]$frame.ScriptName
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $relative = ConvertTo-Stage1ERelativeTracePath $candidate
            $node = Get-Stage1ETraceNodeForPath $relative
            if ($node -notin @('REVIEW_HOST_SAFE_LOAD_HARNESS')) {
                return $node
            }
        }
        catch { }
    }
    return $Fallback
}

function global:Import-Module {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Force
    )
    $relative = ConvertTo-Stage1ERelativeTracePath $Name
    $target = Get-Stage1ETraceNodeForPath $relative
    $requester = Get-Stage1ETraceRequesterNode
    $attempt = Start-Stage1ETraceAttempt 'POWERSHELL_MODULE' $relative `
        $requester $target 'POWERSHELL_MODULE' 'POWERSHELL_MODULE' `
        -Reason 'CONTROLLED_MODULE_IMPORT'
    try {
        Microsoft.PowerShell.Core\Import-Module -Name $Name -Force:$Force `
            -ErrorAction Stop | Out-Null
        Complete-Stage1ETraceAttempt $attempt LOADED
    }
    catch {
        Complete-Stage1ETraceAttempt $attempt FAILED
        throw
    }
}

function global:Add-Type {
    Add-Stage1ETraceRecord 'MUTATION' 'BLOCKED' 'NONE' `
        'SOURCE_TIME_ADD_TYPE_PROHIBITED'
    throw 'Add-Type is prohibited during disconnected safe-load tracing.'
}

function global:Start-Process {
    Add-Stage1ETraceRecord 'MUTATION' 'BLOCKED' 'NONE' `
        'SOURCE_TIME_PROCESS_LAUNCH_PROHIBITED'
    throw 'Process launch is prohibited during disconnected safe-load tracing.'
}

foreach ($mutationCommand in @(
        'Set-Content', 'Add-Content', 'Out-File', 'New-Item',
        'Remove-Item', 'Move-Item', 'Copy-Item', 'Rename-Item',
        'Set-Item', 'Clear-Content',
        'Set-Location', 'Push-Location', 'Pop-Location')) {
    $definition = @"
function global:$mutationCommand {
    Add-Stage1ETraceRecord 'MUTATION' 'BLOCKED' 'NONE' 'SOURCE_TIME_${mutationCommand}_PROHIBITED' -EdgeType 'MUTATION' -Predicate 'SOURCE_TIME_MUTATION'
    throw '$mutationCommand is prohibited during disconnected safe-load tracing.'
}
"@
    Invoke-Expression $definition
}
function global:Invoke-Expression {
    Add-Stage1ETraceRecord 'MUTATION' 'BLOCKED' 'NONE' `
        'SOURCE_TIME_INVOKE-EXPRESSION_PROHIBITED' -EdgeType 'MUTATION' `
        -Predicate 'SOURCE_TIME_MUTATION'
    throw 'Invoke-Expression is prohibited during disconnected safe-load tracing.'
}

$entryPath = Join-Path $root `
    'fpga/vivado/build/runtime/entrypoint/stage1e_production_runtime_entrypoint_v1.ps1'
$entryAttempt = Start-Stage1ETraceAttempt 'POWERSHELL_SCRIPT' `
    (ConvertTo-Stage1ERelativeTracePath $entryPath) `
    'REVIEW_HOST_SAFE_LOAD_HARNESS' 'ENTRY_POINT' 'REVIEW_ASSEMBLY_ROOT' `
    'REVIEW_ASSEMBLY_ROOT' -Provider 'ENTRY_POINT_INTERFACE' `
    -InterfaceVersion 'stage1e-production-runtime-entry-point-contract-v1' `
    -Predicate 'ENTRYPOINT_REHEARSAL' `
    -EvidenceClass 'DECLARED_ASSEMBLY_REHEARSAL' `
    -Reason 'DISCONNECTED_ENTRY_POINT_PARSE' `
    -InterfaceCommand 'stage1e_production_runtime_entrypoint_v1.ps1'
try {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $entryPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) {
        throw 'Disconnected entry-point parse failed.'
    }
    Complete-Stage1ETraceAttempt $entryAttempt LOADED
}
catch {
    Complete-Stage1ETraceAttempt $entryAttempt FAILED
    throw
}

$imports = @(
    @('ENTRY_POINT','fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1'),
    @('ENTRY_POINT','fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.psm1'),
    @('ENTRY_POINT','fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.psm1'),
    @('REVIEW_HOST_SAFE_LOAD_HARNESS','fpga/vivado/build/runtime/launcher/stage1e_production_runtime_launcher_v1.psm1')
)
foreach ($specification in $imports) {
    $script:Stage1ECurrentRequester = $specification[0]
    $relative = $specification[1]
    Import-Module -Name (Join-Path $root $relative) -Force
}
Add-Stage1ETraceAttempt 'DOTNET_SOURCE_PROVIDER' `
    'fpga/vivado/build/lib/stage1e_windows_process_control_v1.cs' `
    'WINDOWS_PROCESS_CONTROL_MODULE' 'WINDOWS_PROCESS_CONTROL_SOURCE' `
    'DOTNET_SOURCE_PROVIDER' 'DOTNET_SOURCE_PROVIDER' `
    -Provider 'WINDOWS_PROCESS_CONTROL' `
    -InterfaceVersion 'stage1e-windows-process-control-interface-v1' `
    -TerminalState OPTIONAL_NOT_LOADED -Predicate 'PROCESS_PROVIDER_DEFERRED' `
    -Reason 'PROCESS_PROVIDER_LOAD_DEFERRED_NO_PROCESS_LAUNCH'

$interfaces = @(
    @('CANONICALIZATION_POWERSHELL',
        'Get-Stage1ECanonicalJsonInterfaceVersion',
        'stage1e-runtime-canonical-json-interface-v1',
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1'),
    @('HASH_PROVIDER_POWERSHELL',
        'Get-Stage1ESha256ProviderInterfaceVersion',
        'stage1e-runtime-sha256-provider-interface-v1',
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1'),
    @('ENVELOPE_CONTRACT_POWERSHELL',
        'Get-Stage1EEnvelopeContractInterfaceVersion',
        'stage1e-runtime-envelope-contract-interface-v1',
        'fpga/vivado/build/lib/stage1e_runtime_envelope_contract_v1.psm1'),
    @('ATOMIC_PUBLICATION_POWERSHELL',
        'Get-Stage1EAtomicPublicationInterfaceVersion',
        'stage1e-runtime-atomic-publication-interface-v1',
        'fpga/vivado/build/lib/stage1e_runtime_atomic_publication_v1.psm1'),
    @('HOST_BOUNDARY_CONTRACT',
        'Get-Stage1EHostBoundaryContractInterfaceVersion',
        'stage1e-host-boundary-contract-interface-v1',
        'fpga/vivado/build/lib/stage1e_host_boundary_contract_v1.psm1'),
    @('WINDOWS_PROCESS_CONTROL',
        'Get-Stage1EWindowsProcessControlInterfaceVersion',
        'stage1e-windows-process-control-interface-v1',
        'fpga/vivado/build/lib/stage1e_windows_process_control_v1.psm1'),
    @('HOST_OBSERVER_INTERFACE',
        'Get-Stage1EProductionHostObserverInterfaceVersion',
        'stage1e-production-host-observer-interface-v1',
        'fpga/vivado/build/runtime/observer/host/stage1e_production_host_observer_v1.psm1'),
    @('LAUNCHER_INTERFACE',
        'Get-Stage1EProductionRuntimeLauncherInterfaceVersion',
        'stage1e-production-runtime-launcher-interface-v1',
        'fpga/vivado/build/runtime/launcher/stage1e_production_runtime_launcher_v1.psm1')
)
foreach ($specification in $interfaces) {
    $providerTarget = Get-Stage1ETraceNodeForPath $specification[3]
    $providerAttempt = Start-Stage1ETraceAttempt 'PROVIDER' `
        $specification[3] $providerTarget `
        $providerTarget 'PROVIDER_OBSERVATION' 'PROVIDER_OBSERVATION' `
        -Provider $specification[0] -InterfaceVersion $specification[2] `
        -Predicate 'INTERFACE_VERSION_CONFIRMED' `
        -Reason 'PROVIDER_INTERFACE' -InterfaceCommand $specification[1]
    try {
        $commands = @(Get-Command -Name $specification[1] `
            -CommandType Function -ErrorAction Stop)
        if ($commands.Count -ne 1) {
            throw "Safe-load provider command is ambiguous: $($specification[0])"
        }
        $command = $commands[0]
        $commandSource = [string]$command.ScriptBlock.File
        if ([string]::IsNullOrWhiteSpace($commandSource) -and
            $null -ne $command.Module) {
            $commandSource = [string]$command.Module.Path
        }
        if ([string]::IsNullOrWhiteSpace($commandSource) -or
            (ConvertTo-Stage1ERelativeTracePath $commandSource) -cne
                [string]$specification[3]) {
            throw "Safe-load provider source was substituted: $($specification[0])"
        }
        $observed = [string](& $command)
        if ($observed -cne $specification[2]) {
            throw "Safe-load provider interface mismatch: $($specification[0])"
        }
        Complete-Stage1ETraceAttempt $providerAttempt LOADED
    }
    catch {
        Complete-Stage1ETraceAttempt $providerAttempt FAILED
        throw
    }
}

$script:Stage1ECurrentRequester = 'HOST_SCHEMA_LOAD'
$null = Import-Stage1EEnvelopeContract -SchemaRoot (Join-Path $root `
    'fpga/vivado/build/lib')
$null = Import-Stage1EHostBoundaryContract
$schemas = @(
    'stage1e_runtime_failure_record_v1.schema.json',
    'stage1e_runtime_request_envelope_v1.schema.json',
    'stage1e_runtime_result_envelope_v1.schema.json',
    'stage1e_runtime_host_common_v1.schema.json',
    'stage1e_runtime_host_requirements_v1.schema.json',
    'stage1e_runtime_host_launcher_request_v1.schema.json',
    'stage1e_runtime_host_preflight_observation_v1.schema.json',
    'stage1e_runtime_host_process_instance_v1.schema.json',
    'stage1e_runtime_host_process_ledger_v1.schema.json',
    'stage1e_runtime_host_heartbeat_event_v1.schema.json',
    'stage1e_runtime_host_timeout_termination_ledger_v1.schema.json',
    'stage1e_runtime_host_component_result_v1.schema.json'
)
foreach ($leaf in $schemas) {
    $relative = "fpga/vivado/build/lib/$leaf"
    $path = Join-Path $root $relative
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -eq 0) { throw "Schema is empty during trace: $relative" }
    $schemaNode = switch ($leaf) {
        'stage1e_runtime_failure_record_v1.schema.json' { 'A_FAILURE_SCHEMA' }
        'stage1e_runtime_request_envelope_v1.schema.json' { 'A_REQUEST_SCHEMA' }
        'stage1e_runtime_result_envelope_v1.schema.json' { 'A_RESULT_SCHEMA' }
        'stage1e_runtime_host_common_v1.schema.json' { 'HOST_COMMON_SCHEMA' }
        'stage1e_runtime_host_requirements_v1.schema.json' { 'HOST_REQUIREMENTS_SCHEMA' }
        'stage1e_runtime_host_launcher_request_v1.schema.json' { 'HOST_LAUNCHER_REQUEST_SCHEMA' }
        'stage1e_runtime_host_preflight_observation_v1.schema.json' { 'HOST_PREFLIGHT_SCHEMA' }
        'stage1e_runtime_host_process_instance_v1.schema.json' { 'HOST_PROCESS_INSTANCE_SCHEMA' }
        'stage1e_runtime_host_process_ledger_v1.schema.json' { 'HOST_PROCESS_LEDGER_SCHEMA' }
        'stage1e_runtime_host_heartbeat_event_v1.schema.json' { 'HOST_HEARTBEAT_SCHEMA' }
        'stage1e_runtime_host_timeout_termination_ledger_v1.schema.json' { 'HOST_TIMEOUT_LEDGER_SCHEMA' }
        'stage1e_runtime_host_component_result_v1.schema.json' { 'HOST_RESULT_SCHEMA' }
    }
    Add-Stage1ERehearsalRecord $relative $schemaNode 'HOST_BOUNDARY_CONTRACT' `
        'SCHEMA_PROVIDER' 'SCHEMA_PROVIDER' `
        -Predicate 'HOST_SCHEMA_DIRECT_DOTNET_READ'
}

if ([System.IO.Directory]::GetCurrentDirectory() -cne $outputDirectory) {
    throw 'Candidate changed cwd during safe-load.'
}
if ([System.Environment]::GetEnvironmentVariable('PSModulePath') -cne
        $controlledEnvironment.PSModulePath) {
    throw 'Candidate changed PSModulePath during safe-load.'
}

$finalRepositorySnapshot = Get-Stage1EControlledFileSnapshot $root
$finalEvidenceSnapshot = Get-Stage1EControlledFileSnapshot $outputDirectory
$snapshotMismatch = @(
    $script:Stage1EInitialRepositorySnapshot.Keys +
    $finalRepositorySnapshot.Keys | Sort-Object -Unique |
        Where-Object {
            $script:Stage1EInitialRepositorySnapshot[$_] -cne
                $finalRepositorySnapshot[$_]
        })
$evidenceMismatch = @(
    $script:Stage1EInitialEvidenceSnapshot.Keys +
    $finalEvidenceSnapshot.Keys | Sort-Object -Unique |
        Where-Object {
            # The two trace publications are intentionally new evidence files;
            # every other pre-existing evidence byte must remain identical.
            $_ -notin @([System.IO.Path]::GetFileName($output),
                [System.IO.Path]::GetFileName($output) + '.rehearsal') -and
            $script:Stage1EInitialEvidenceSnapshot[$_] -cne
                $finalEvidenceSnapshot[$_]
        })
$finalEnvironment = [ordered]@{}
foreach ($name in @([System.Environment]::GetEnvironmentVariables(
            [System.EnvironmentVariableTarget]::Process).Keys | Sort-Object)) {
    $finalEnvironment[[string]$name] =
        [System.Environment]::GetEnvironmentVariable([string]$name)
}
if ($snapshotMismatch.Count -gt 0 -or $evidenceMismatch.Count -gt 0 -or
    ($script:Stage1EInitialCwd -cne [System.IO.Directory]::GetCurrentDirectory()) -or
    ($script:Stage1EInitialEnvironment | Out-String) -cne
        ($finalEnvironment | Out-String)) {
    Add-Stage1ETraceRecord 'MUTATION' 'BLOCKED' 'NONE' `
        'CONTROLLED_REPOSITORY_OR_PROCESS_STATE_CHANGED' `
        -EdgeType 'MUTATION' -Predicate 'SOURCE_TIME_MUTATION'
    throw 'Controlled repository, evidence, environment, or cwd state changed during safe-load.'
}
if ([System.IO.File]::Exists($PROFILE) -ne $script:Stage1EInitialProfileExists -or
    ($script:Stage1EInitialProfileExists -and
        -not (Test-Stage1ETraceBytesEqual `
            ([System.IO.File]::ReadAllBytes($PROFILE)) `
            $script:Stage1EInitialProfileBytes))) {
    Add-Stage1ETraceRecord 'MUTATION' 'BLOCKED' $PROFILE `
        'PROFILE_EXISTENCE_OR_BYTES_CHANGED' -EdgeType 'MUTATION' `
        -Predicate 'SOURCE_TIME_MUTATION'
    throw 'PowerShell profile changed during safe-load.'
}

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($record in $script:Stage1ETraceRecords) {
    $fields = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $record.Keys | Sort-Object) {
        $value = ([string]$record[$key]).Replace('|', '\p').
            Replace("`t", '\t').Replace("`r", '\r').Replace("`n", '\n')
        $fields.Add("$key=$value")
    }
    $lines.Add(($fields -join '|'))
}
[System.IO.File]::WriteAllLines($output, $lines,
    [System.Text.UTF8Encoding]::new($false))
$rehearsalOutput = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($output),
    ([System.IO.Path]::GetFileName($output) + '.rehearsal'))
$rehearsalLines = [System.Collections.Generic.List[string]]::new()
foreach ($record in $script:Stage1ERehearsalRecords) {
    $fields = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $record.Keys | Sort-Object) {
        $value = ([string]$record[$key]).Replace('|', '\p').
            Replace("`t", '\t').Replace("`r", '\r').Replace("`n", '\n')
        $fields.Add("$key=$value")
    }
    $rehearsalLines.Add(($fields -join '|'))
}
[System.IO.File]::WriteAllLines($rehearsalOutput, $rehearsalLines,
    [System.Text.UTF8Encoding]::new($false))
Write-Output "HOST_TRACE_RECORDS=$($lines.Count) HOST_REHEARSAL_RECORDS=$($rehearsalLines.Count)"
