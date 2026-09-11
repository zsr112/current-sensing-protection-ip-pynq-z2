Set-StrictMode -Version Latest

$libraryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../../../lib'))
$contractModule = Join-Path $libraryRoot 'stage1e_host_boundary_contract_v1.psm1'
Import-Module -Name $contractModule -Force -ErrorAction Stop

$script:Stage1EProductionHostObserverInterface =
    'stage1e-production-host-observer-interface-v1'

function Get-Stage1EProductionHostObserverInterfaceVersion {
    return $script:Stage1EProductionHostObserverInterface
}

function ConvertTo-Stage1EHostObserverCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).Replace(
        [System.IO.Path]::DirectorySeparatorChar, '/')
}

function Get-Stage1EHostObserverPathState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedType
    )

    try {
        $native = [System.IO.Path]::GetFullPath($Path.Replace(
                '/', [System.IO.Path]::DirectorySeparatorChar))
        if ($ExpectedType -ceq 'FILE') {
            if ([System.IO.File]::Exists($native)) { return 'PRESENT' }
            if ([System.IO.Directory]::Exists($native)) { return 'WRONG_TYPE' }
        }
        else {
            if ([System.IO.Directory]::Exists($native)) { return 'PRESENT' }
            if ([System.IO.File]::Exists($native)) { return 'WRONG_TYPE' }
        }
        return 'MISSING'
    }
    catch { return 'UNAVAILABLE' }
}

function Test-Stage1EHostObserverReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $current = [System.IO.Path]::GetFullPath($Path.Replace(
                '/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not [System.IO.File]::Exists($current) -and
            -not [System.IO.Directory]::Exists($current)) {
            $current = [System.IO.Path]::GetDirectoryName($current)
        }
        while (-not [string]::IsNullOrEmpty($current)) {
            if ([System.IO.File]::Exists($current) -or
                [System.IO.Directory]::Exists($current)) {
                $attributes = [System.IO.File]::GetAttributes($current)
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) `
                    -ne 0) {
                    return 'DETECTED'
                }
            }
            $parent = [System.IO.Path]::GetDirectoryName($current)
            if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $current) {
                break
            }
            $current = $parent
        }
        return 'CLEAR'
    }
    catch { return 'UNKNOWN' }
}

function Get-Stage1EProductionHostPreflightObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ProcessProviderObservation,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    $null = Assert-Stage1EHostRecord -Role launcher_request `
        -Record $LauncherRequest -Contract $HostContract
    $conflicts = [System.Collections.Generic.List[string]]::new()
    $executableState = Get-Stage1EHostObserverPathState `
        $LauncherRequest.executable_path 'FILE'
    $cwdState = Get-Stage1EHostObserverPathState $LauncherRequest.cwd 'DIRECTORY'
    $evidenceState = Get-Stage1EHostObserverPathState `
        $LauncherRequest.evidence_root 'DIRECTORY'
    if ($executableState -cne 'PRESENT') {
        $conflicts.Add("Exact executable state is $executableState.")
    }
    if ($cwdState -cne 'PRESENT') {
        $conflicts.Add("Exact cwd state is $cwdState.")
    }
    if ($evidenceState -cne 'PRESENT') {
        $conflicts.Add("Evidence root state is $evidenceState.")
    }
    foreach ($directoryName in @(
            'workspace_root', 'log_root', 'journal_root',
            'temporary_root', 'cache_root')) {
        $state = Get-Stage1EHostObserverPathState `
            $LauncherRequest[$directoryName] 'DIRECTORY'
        if ($state -cne 'PRESENT') {
            $conflicts.Add(
                "Required directory '$directoryName' state is $state.")
        }
    }
    foreach ($outputName in @(
            'preflight_result_path', 'process_ledger_path',
            'process_event_journal_path', 'timeout_termination_ledger_path',
            'timeout_event_journal_path', 'heartbeat_path', 'stdout_path',
            'stderr_path', 'host_result_path',
            'expected_vivado_result_path')) {
        $nativeOutput = $LauncherRequest[$outputName].Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputParent = [System.IO.Path]::GetDirectoryName(
            [System.IO.Path]::GetFullPath($nativeOutput))
        if (-not [System.IO.Directory]::Exists($outputParent)) {
            $conflicts.Add(
                "Output parent for '$outputName' does not exist.")
        }
        if ([System.IO.File]::Exists($nativeOutput) -or
            [System.IO.Directory]::Exists($nativeOutput)) {
            $conflicts.Add(
                "Final output '$outputName' already exists.")
        }
    }
    $rootSeparation = if (
        (Test-Stage1EHostPathsDisjoint $LauncherRequest.source_root `
            $LauncherRequest.workspace_root) -and
        (Test-Stage1EHostPathsDisjoint $LauncherRequest.source_root `
            $LauncherRequest.evidence_root) -and
        (Test-Stage1EHostPathsDisjoint $LauncherRequest.workspace_root `
            $LauncherRequest.evidence_root)) {
        'DISJOINT'
    }
    else {
        $conflicts.Add('Source, workspace, and evidence roots overlap.')
        'OVERLAP'
    }
    $reparseStates = @(
        (Test-Stage1EHostObserverReparsePoint $LauncherRequest.executable_path),
        (Test-Stage1EHostObserverReparsePoint $LauncherRequest.cwd),
        (Test-Stage1EHostObserverReparsePoint $LauncherRequest.evidence_root),
        (Test-Stage1EHostObserverReparsePoint $LauncherRequest.log_root),
        (Test-Stage1EHostObserverReparsePoint $LauncherRequest.journal_root),
        (Test-Stage1EHostObserverReparsePoint $LauncherRequest.temporary_root),
        (Test-Stage1EHostObserverReparsePoint $LauncherRequest.cache_root))
    if ($reparseStates -contains 'DETECTED') {
        $reparseState = 'DETECTED'
        $conflicts.Add('A required foundation path traverses a reparse point.')
    }
    elseif ($reparseStates -contains 'UNKNOWN') {
        $reparseState = 'UNKNOWN'
        $conflicts.Add('A required foundation reparse-point observation is unknown.')
    }
    else { $reparseState = 'CLEAR' }
    $providerAvailable = (
        [string]$ProcessProviderObservation.interface_version -ceq
            'stage1e-windows-process-control-interface-v1')
    if (-not $providerAvailable) {
        $conflicts.Add('The exact process-control provider is unavailable.')
    }
    $environmentState = 'EXPLICIT'
    $systemRootEntries = @($LauncherRequest.environment |
        Where-Object { [string]$_.name -ceq 'SystemRoot' })
    $observedSystemRoot = [System.Environment]::GetEnvironmentVariable(
        'SystemRoot', [System.EnvironmentVariableTarget]::Process)
    if ($systemRootEntries.Count -ne 1 -or
        -not [string]::Equals(
            [string]$systemRootEntries[0].value,
            [string]$observedSystemRoot,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        $environmentState = 'INVALID'
        $conflicts.Add(
            'The exact parent SystemRoot observation differs from the child projection.')
    }
    $repositoryOutput = 'CLEAR'
    foreach ($pathName in @(
            'preflight_result_path', 'process_ledger_path',
            'process_event_journal_path', 'timeout_termination_ledger_path',
            'timeout_event_journal_path', 'heartbeat_path', 'stdout_path',
            'stderr_path', 'host_result_path')) {
        if (Test-Stage1EHostPathWithinBoundary `
                $LauncherRequest[$pathName] $LauncherRequest.source_root) {
            $repositoryOutput = 'DETECTED'
            $conflicts.Add("Runtime output '$pathName' is inside source.")
        }
    }
    $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()) {
        'X64' { 'X64' }
        'X86' { 'X86' }
        'Arm64' { 'ARM64' }
        default { 'UNKNOWN' }
    }
    $record = [ordered]@{
        schema_version = 'stage1e-runtime-host-preflight-observation-v1'
        observation_scope = 'FOUNDATION_NON_QUALIFYING'
        observation_state = if ($conflicts.Count -eq 0) { 'READY' } `
            else { 'BLOCKED' }
        request_identity = [string]$LauncherRequest.request_identity
        execution_id = [string]$LauncherRequest.execution_id
        attempt_id = [string]$LauncherRequest.attempt_id
        platform = 'WINDOWS'
        os_version = [System.Environment]::OSVersion.Version.ToString()
        process_architecture = $architecture
        powershell_version = $PSVersionTable.PSVersion.ToString()
        clr_version = [System.Environment]::Version.ToString()
        process_provider_interface =
            'stage1e-windows-process-control-interface-v1'
        containment_capability = if ($providerAvailable) {
            'AVAILABLE'
        }
        else { 'UNAVAILABLE' }
        monotonic_clock_capability = 'AVAILABLE'
        executable_requested_path =
            [string]$LauncherRequest.executable_path
        executable_final_path = if ($executableState -ceq 'PRESENT') {
            ConvertTo-Stage1EHostObserverCanonicalPath `
                $LauncherRequest.executable_path
        }
        else { 'NONE' }
        executable_file_state = $executableState
        cwd_requested_path = [string]$LauncherRequest.cwd
        cwd_final_path = if ($cwdState -ceq 'PRESENT') {
            ConvertTo-Stage1EHostObserverCanonicalPath $LauncherRequest.cwd
        }
        else { 'NONE' }
        cwd_directory_state = $cwdState
        evidence_requested_path = [string]$LauncherRequest.evidence_root
        evidence_final_path = if ($evidenceState -ceq 'PRESENT') {
            ConvertTo-Stage1EHostObserverCanonicalPath `
                $LauncherRequest.evidence_root
        }
        else { 'NONE' }
        evidence_directory_state = $evidenceState
        path_reparse_state = $reparseState
        advanced_path_hardening_state =
            'DEFERRED_FUTURE_HOST_CONTRACT'
        root_separation_state = $rootSeparation
        environment_projection_state = $environmentState
        repository_runtime_output_state = $repositoryOutput
        conflicts = [object[]]$conflicts.ToArray()
        authority_boundary = Get-Stage1EHostAuthorityBoundary
    }
    $null = Assert-Stage1EHostRecord -Role preflight -Record $record `
        -Contract $HostContract
    return $record
}

function Get-Stage1EExpectedProcessRole {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)][uint32]$RootProcessId,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest
    )

    if ([uint32]$Observation.ProcessId -eq
        $RootProcessId) {
        return 'ROOT_PROCESS'
    }
    if (-not [bool]$Observation.ImagePathAvailable) {
        return 'UNEXPECTED_DESCENDANT'
    }
    foreach ($topology in $LauncherRequest.expected_topology) {
        if ([string]$topology.role -ceq 'DECLARED_SUPPORT_PROCESS' -and
            (Test-Stage1EHostPathEqual $Observation.ImagePath `
                $topology.image_path)) {
            return 'DECLARED_SUPPORT_PROCESS'
        }
    }
    return 'UNEXPECTED_DESCENDANT'
}

function ConvertTo-Stage1EHostJobEventRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Observation,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    $isProcessEvent = [string]$Observation.EventType -in @(
        'NEW_PROCESS', 'EXIT_PROCESS', 'ABNORMAL_EXIT_PROCESS')
    $record = [ordered]@{
        schema_version = 'stage1e-runtime-host-job-event-v1'
        sequence = [int64]$Observation.Sequence
        event_type = [string]$Observation.EventType
        native_message_type = [int64]$Observation.NativeMessageType
        pid = if ([bool]$Observation.ProcessIdAvailable) {
            [int64]$Observation.ProcessId
        }
        else { 'UNAVAILABLE' }
        parent_pid = if ([bool]$Observation.ParentProcessIdAvailable) {
            [int64]$Observation.ParentProcessId
        }
        else { 'UNAVAILABLE' }
        creation_time_utc = if ([bool]$Observation.CreationTimeAvailable) {
            $Observation.CreationTimeUtc.ToString(
                'o', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        else { 'UNAVAILABLE' }
        image_path = if ([bool]$Observation.ImagePathAvailable) {
            ConvertTo-Stage1EHostObserverCanonicalPath $Observation.ImagePath
        }
        else { 'NONE' }
        observation_handle_state = if (-not $isProcessEvent) {
            'NOT_APPLICABLE'
        }
        elseif (-not [bool]$Observation.ObservationHandleAvailable) {
            'UNAVAILABLE'
        }
        elseif ([bool]$Observation.RetainedHandle) { 'RETAINED' }
        else { 'OPENED_FOR_OBSERVATION' }
        job_membership = if (-not $isProcessEvent) {
            'NOT_APPLICABLE'
        }
        elseif (-not [bool]$Observation.JobMembershipAvailable) { 'UNKNOWN' }
        elseif ([bool]$Observation.IsInJob) { 'IN_JOB' }
        else { 'NOT_IN_JOB' }
        exit_state = if (-not $isProcessEvent) { 'NOT_APPLICABLE' }
        elseif (-not [bool]$Observation.ExitStateAvailable) { 'UNAVAILABLE' }
        elseif ([bool]$Observation.HasExited) { 'EXITED' }
        else { 'RUNNING' }
        exit_code = if (-not $isProcessEvent) { 'UNAVAILABLE' }
        elseif ([bool]$Observation.ExitCodeAvailable) {
            [int64]$Observation.ExitCode
        }
        elseif ([bool]$Observation.ExitStateAvailable -and
            -not [bool]$Observation.HasExited) { 'STILL_ACTIVE' }
        else { 'UNAVAILABLE' }
        receipt_monotonic_ticks = [int64]$Observation.ReceiptMonotonicTicks
        receipt_elapsed_ms = [int64]$Observation.ReceiptElapsedMilliseconds
        availability_state = [string]$Observation.AvailabilityState
        conflicts = [object[]]@($Observation.Conflicts |
            ForEach-Object { [string]$_ })
    }
    $null = Assert-Stage1EHostRecord -Role job_event -Record $record `
        -Contract $HostContract
    return $record
}

function Get-Stage1EProductionHostProcessObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Process,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest,
        [Parameter(Mandatory = $true)][int]$ObservationOrdinal,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$FirstSeenOrdinals,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract,
        [bool]$TerminalObservation = $false
    )

    $raw = [object[]]@()
    $rawJobEvents = [object[]]@()
    for ($captureAttempt = 0; $captureAttempt -lt 3; $captureAttempt++) {
        $beforeEvents = [object[]]@($Process.GetJobEvents())
        $raw = [object[]]@($Process.Observe())
        $afterEvents = [object[]]@($Process.GetJobEvents())
        $rawJobEvents = $afterEvents
        if ($beforeEvents.Count -eq $afterEvents.Count) { break }
    }
    $snapshotProcessIds = [uint32[]]@($Process.GetCurrentJobProcessIds())
    $instances = [System.Collections.Generic.List[object]]::new()
    $conflicts = [System.Collections.Generic.List[string]]::new()
    $observedRoles = [System.Collections.Generic.List[string]]::new()
    $jobEvents = [System.Collections.Generic.List[object]]::new()
    $jobEventSequencesByPid = [ordered]@{}
    $newProcessCounts = [ordered]@{}
    $exitProcessCounts = [ordered]@{}
    $activeZeroCount = 0
    foreach ($rawJobEvent in $rawJobEvents) {
        $jobEvent = ConvertTo-Stage1EHostJobEventRecord $rawJobEvent `
            $HostContract
        if ([int64]$jobEvent.sequence -ne ($jobEvents.Count + 1)) {
            $conflicts.Add('The Job event sequence is not append-only monotonic.')
        }
        if ([string]$jobEvent.event_type -in @(
                'ACTIVE_PROCESS_LIMIT', 'COMPLETION_PORT_FAILURE',
                'UNKNOWN_JOB_MESSAGE')) {
            $conflicts.Add(
                "Blocking Job event '$($jobEvent.event_type)' was observed.")
        }
        if ([string]$jobEvent.availability_state -in @(
                'UNAVAILABLE', 'CONFLICT')) {
            $conflicts.Add(
                "Job event sequence $($jobEvent.sequence) has incomplete evidence.")
        }
        if ([string]$jobEvent.event_type -ceq 'ACTIVE_PROCESS_ZERO') {
            $activeZeroCount++
        }
        if ($jobEvent.pid -is [long] -or $jobEvent.pid -is [int]) {
            $pidKey = [string]$jobEvent.pid
            if (-not $jobEventSequencesByPid.Contains($pidKey)) {
                $jobEventSequencesByPid[$pidKey] =
                    [System.Collections.Generic.List[long]]::new()
            }
            $jobEventSequencesByPid[$pidKey].Add([int64]$jobEvent.sequence)
            if ([string]$jobEvent.event_type -ceq 'NEW_PROCESS') {
                if (-not $newProcessCounts.Contains($pidKey)) {
                    $newProcessCounts[$pidKey] = 0
                }
                $newProcessCounts[$pidKey]++
                if ($newProcessCounts[$pidKey] -ne 1) {
                    $conflicts.Add(
                        "PID $pidKey has duplicate NEW_PROCESS events.")
                }
            }
            elseif ([string]$jobEvent.event_type -in @(
                    'EXIT_PROCESS', 'ABNORMAL_EXIT_PROCESS')) {
                if (-not $exitProcessCounts.Contains($pidKey)) {
                    $exitProcessCounts[$pidKey] = 0
                }
                $exitProcessCounts[$pidKey]++
                if ($exitProcessCounts[$pidKey] -gt 1) {
                    $conflicts.Add(
                        "PID $pidKey has duplicate terminal Job events.")
                }
                if (-not $newProcessCounts.Contains($pidKey)) {
                    $conflicts.Add(
                        "PID $pidKey exited without a reconciled NEW_PROCESS event.")
                }
            }
        }
        $jobEvents.Add($jobEvent)
    }
    if ($TerminalObservation -and $activeZeroCount -ne 1) {
        $conflicts.Add(
            'Terminal observation requires exactly one ACTIVE_PROCESS_ZERO event.')
    }
    $instanceKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($observation in $raw) {
        if ([uint32]$observation.ProcessId -eq 0) {
            $conflicts.Add('A required process PID was unavailable.')
            continue
        }
        $key = if ([bool]$observation.CreationTimeAvailable) {
            "$($observation.ProcessId):$(
                $observation.CreationTimeUtc.ToFileTimeUtc())"
        }
        else { "$($observation.ProcessId):UNAVAILABLE" }
        if (-not $instanceKeys.Add($key)) {
            $conflicts.Add(
                "A duplicate or ambiguous process instance '$key' was observed.")
            continue
        }
        if (-not [bool]$observation.CreationTimeAvailable) {
            $conflicts.Add(
                "Process creation time unavailable for PID $(
                    $observation.ProcessId).")
        }
        if (-not $FirstSeenOrdinals.Contains($key)) {
            $FirstSeenOrdinals.Add($key, $ObservationOrdinal)
        }
        $role = Get-Stage1EExpectedProcessRole $observation `
            ([uint32]$Process.ProcessId) $LauncherRequest
        $observedRoles.Add($role)
        if ($role -ceq 'ROOT_PROCESS') {
            $expectedImage = [string]$LauncherRequest.expected_image_path
            $parentState = if (
                [bool]$observation.ParentProcessIdAvailable -and
                [uint32]$observation.ParentProcessId -eq [uint32]$PID) {
                'ROOT_PARENT'
            }
            elseif ([bool]$observation.ParentProcessIdAvailable) {
                $conflicts.Add(
                    'The root process parent differs from the active launcher.')
                'MISMATCHED'
            }
            else {
                $conflicts.Add('The root process parent PID is unavailable.')
                'UNAVAILABLE'
            }
        }
        elseif ($role -ceq 'DECLARED_SUPPORT_PROCESS') {
            $matching = @($LauncherRequest.expected_topology |
                Where-Object {
                    [string]$_.role -ceq 'DECLARED_SUPPORT_PROCESS' -and
                    [bool]$observation.ImagePathAvailable -and
                    (Test-Stage1EHostPathEqual $_.image_path `
                        $observation.ImagePath)
                })
            $expectedImage = if ($matching.Count -gt 0) {
                [string]$matching[0].image_path
            }
            else { '' }
            $parentState = if (
                [bool]$observation.ParentProcessIdAvailable -and
                [uint32]$observation.ParentProcessId -eq
                    [uint32]$Process.ProcessId) { 'MATCHED' }
            elseif ([bool]$observation.ParentProcessIdAvailable) {
                'MISMATCHED'
            }
            else { 'UNAVAILABLE' }
            if ($parentState -ceq 'MISMATCHED') {
                $conflicts.Add(
                    "Declared support-process parent mismatch for PID $(
                        $observation.ProcessId).")
            }
            elseif ($parentState -ceq 'UNAVAILABLE') {
                $conflicts.Add(
                    "Declared support-process parent unavailable for PID $(
                        $observation.ProcessId).")
            }
        }
        else {
            $expectedImage = ''
            $parentState = 'UNAVAILABLE'
            $conflicts.Add(
                "Unexpected contained descendant PID $($observation.ProcessId).")
        }
        if ([bool]$observation.ImagePathAvailable) {
            $imagePath = ConvertTo-Stage1EHostObserverCanonicalPath `
                $observation.ImagePath
            $imageState = 'PRESENT'
            if ([string]::IsNullOrEmpty($expectedImage)) {
                $expectedImageState = 'NOT_DECLARED'
            }
            elseif (Test-Stage1EHostPathEqual $imagePath $expectedImage) {
                $expectedImageState = 'MATCHED'
            }
            else {
                $expectedImageState = 'MISMATCHED'
                $conflicts.Add(
                    "Process image mismatch for PID $($observation.ProcessId).")
            }
        }
        else {
            $imagePath = 'NONE'
            $imageState = 'UNAVAILABLE'
            $expectedImageState = 'UNAVAILABLE'
            $conflicts.Add(
                "Process image unavailable for PID $($observation.ProcessId).")
        }
        if ([bool]$observation.JobMembershipAvailable) {
            $jobState = if ([bool]$observation.IsInJob) {
                'IN_JOB'
            }
            else {
                $conflicts.Add(
                    "Process PID $($observation.ProcessId) is outside the job.")
                'NOT_IN_JOB'
            }
        }
        else {
            $jobState = 'UNKNOWN'
            $conflicts.Add(
                "Job membership unavailable for PID $($observation.ProcessId).")
        }
        if ([bool]$observation.ExitStateAvailable) {
            if ([bool]$observation.HasExited) {
                $exitState = 'EXITED'
                $exitCode = if ([bool]$observation.ExitCodeAvailable) {
                    [int64]$observation.ExitCode
                }
                else { 'UNAVAILABLE' }
            }
            else {
                $exitState = 'RUNNING'
                $exitCode = 'STILL_ACTIVE'
            }
        }
        else {
            $exitState = 'UNAVAILABLE'
            $exitCode = 'UNAVAILABLE'
        }
        if ($TerminalObservation -and
            $role -in @('ROOT_PROCESS', 'DECLARED_SUPPORT_PROCESS') -and
            $exitState -cne 'EXITED') {
            $conflicts.Add(
                "Terminal exit state unavailable for PID $(
                    $observation.ProcessId).")
        }
        $observationHandleAvailable =
            [bool]$observation.ObservationHandleAvailable
        if (-not $observationHandleAvailable) {
            $conflicts.Add(
                "Direct observation-handle evidence unavailable for PID $(
                    $observation.ProcessId).")
        }
        $pidKey = [string]$observation.ProcessId
        $eventSequences = if ($jobEventSequencesByPid.Contains($pidKey)) {
            [object[]]$jobEventSequencesByPid[$pidKey].ToArray()
        }
        else {
            $conflicts.Add(
                "Process PID $pidKey has no reconciled Job completion event.")
            [object[]]@()
        }
        if (-not $newProcessCounts.Contains($pidKey) -or
            [int]$newProcessCounts[$pidKey] -ne 1) {
            $conflicts.Add(
                "Process PID $pidKey has no singular NEW_PROCESS event.")
        }
        $instance = [ordered]@{
            schema_version = 'stage1e-runtime-host-process-instance-v1'
            role = $role
            pid = [int64]$observation.ProcessId
            parent_pid = [int64]$observation.ParentProcessId
            creation_time_utc = if (
                [bool]$observation.CreationTimeAvailable) {
                $observation.CreationTimeUtc.ToString(
                    'o', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            else { 'UNAVAILABLE' }
            observation_time_utc = [System.DateTime]::UtcNow.ToString(
                'o', [System.Globalization.CultureInfo]::InvariantCulture)
            image_path = $imagePath
            image_state = $imageState
            expected_image_state = $expectedImageState
            parent_state = $parentState
            handle_state = if (-not $observationHandleAvailable) {
                'UNAVAILABLE'
            }
            elseif ([bool]$observation.RetainedHandle) {
                'RETAINED'
            }
            else { 'OPENED_FOR_OBSERVATION' }
            observation_handle_available = $observationHandleAvailable
            job_membership = $jobState
            job_event_sequences = [object[]]@($eventSequences)
            argument_observation_state = 'REQUEST_BOUND_ONLY'
            cwd_observation_state = 'REQUEST_BOUND_ONLY'
            first_seen_ordinal = [int64]$FirstSeenOrdinals[$key]
            last_seen_ordinal = [int64]$ObservationOrdinal
            exit_state = $exitState
            exit_code = $exitCode
            authority_boundary = Get-Stage1EHostAuthorityBoundary
        }
        $null = Assert-Stage1EHostRecord -Role process_instance `
            -Record $instance -Contract $HostContract
        $instances.Add($instance)
    }
    foreach ($newPidKey in $newProcessCounts.Keys) {
        if (@($instances | Where-Object {
                    [string]$_.pid -ceq [string]$newPidKey
                }).Count -ne 1) {
            $conflicts.Add(
                "NEW_PROCESS PID $newPidKey does not map to one process instance.")
        }
    }
    foreach ($snapshotPid in $snapshotProcessIds) {
        $snapshotKey = [string]$snapshotPid
        if (-not $newProcessCounts.Contains($snapshotKey)) {
            $conflicts.Add(
                "Current Job snapshot PID $snapshotPid lacks NEW_PROCESS evidence.")
        }
        if (@($instances | Where-Object {
                    [int64]$_.pid -eq [int64]$snapshotPid
                }).Count -ne 1) {
            $conflicts.Add(
                "Current Job snapshot PID $snapshotPid lacks one process record.")
        }
    }
    if ($TerminalObservation -and $snapshotProcessIds.Count -ne 0) {
        $conflicts.Add('The terminal Job membership snapshot is not empty.')
    }
    if (@($instances | Where-Object { $_.role -ceq 'ROOT_PROCESS' }).Count `
        -ne 1) {
        $conflicts.Add('The exact root process instance is not singular.')
    }
    foreach ($topology in $LauncherRequest.expected_topology) {
        $count = @($instances | Where-Object {
                [string]$_.role -ceq [string]$topology.role -and
                [string]$_.image_state -ceq 'PRESENT' -and
                (Test-Stage1EHostPathEqual $_.image_path $topology.image_path)
            }).Count
        if ($count -gt [int64]$topology.maximum_count) {
            $conflicts.Add(
                "Topology role '$($topology.role)' exceeds its maximum.")
        }
    }
    return [ordered]@{
        instances = [object[]]$instances.ToArray()
        job_events = [object[]]$jobEvents.ToArray()
        snapshot_process_ids = [object[]]@($snapshotProcessIds |
            ForEach-Object { [int64]$_ })
        conflicts = [object[]]$conflicts.ToArray()
        topology_state = if ($conflicts.Count -eq 0) { 'MATCHED' } `
            else { 'CONFLICT' }
    }
}

function New-Stage1EHostHeartbeatCursor {
    return [ordered]@{
        complete_offset = [int64]0
        prior_bytes = [byte[]]@()
        last_sequence = [int64]0
        trailing_partial = $false
    }
}

function Read-Stage1EHostObserverSharedBytes {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $stream = [System.IO.FileStream]::new(
        $LiteralPath, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -gt [int]::MaxValue) {
            throw [System.IO.InvalidDataException]::new(
                'Heartbeat journal exceeds the bounded observer size.')
        }
        $bytes = [byte[]]::new([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -eq 0) {
                throw [System.IO.EndOfStreamException]::new(
                    'Heartbeat journal changed during a bounded read.')
            }
            $offset += $read
        }
        Write-Output -NoEnumerate $bytes
    }
    finally { $stream.Dispose() }
}

function Read-Stage1EProductionHostHeartbeatJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest,
        [Parameter(Mandatory = $true)][uint32]$RootProcessId,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Cursor,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    $nativePath = $LauncherRequest.heartbeat_path.Replace(
        '/', [System.IO.Path]::DirectorySeparatorChar)
    $events = [System.Collections.Generic.List[object]]::new()
    $conflicts = [System.Collections.Generic.List[string]]::new()
    if (-not [System.IO.File]::Exists($nativePath)) {
        return [ordered]@{
            state = 'MISSING'
            events = [object[]]@()
            conflicts = [object[]]@()
            trailing_partial = $false
        }
    }
    $bytes = Read-Stage1EHostObserverSharedBytes $nativePath
    $prior = [byte[]]$Cursor.prior_bytes
    if ($bytes.Length -lt $prior.Length) {
        $conflicts.Add('Heartbeat journal shrank after observation.')
    }
    else {
        for ($index = 0; $index -lt $prior.Length; $index++) {
            if ($bytes[$index] -ne $prior[$index]) {
                $conflicts.Add('Heartbeat journal changed previously observed bytes.')
                break
            }
        }
    }
    if ($conflicts.Count -eq 0) {
        $start = [int64]$Cursor.complete_offset
        $recordStart = $start
        for ($index = $start; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -ne 0x0a) { continue }
            $length = [int]($index - $recordStart + 1)
            $recordBytes = [byte[]]::new($length)
            [System.Array]::Copy($bytes, [int]$recordStart,
                $recordBytes, 0, $length)
            try {
                $event = ConvertFrom-Stage1EHostRecordBytes -Role heartbeat `
                    -Bytes $recordBytes -Contract $HostContract
                if ([string]$event.execution_id -cne
                        [string]$LauncherRequest.execution_id -or
                    [string]$event.attempt_id -cne
                        [string]$LauncherRequest.attempt_id -or
                    [uint32]$event.emitter_pid -ne $RootProcessId) {
                    throw [System.IO.InvalidDataException]::new(
                        'Heartbeat event binding differs from the active attempt.')
                }
                if ([int64]$event.sequence -ne
                    ([int64]$Cursor.last_sequence + 1)) {
                    throw [System.IO.InvalidDataException]::new(
                        'Heartbeat sequence is duplicate, regressing, or discontinuous.')
                }
                $Cursor.last_sequence = [int64]$event.sequence
                $events.Add($event)
            }
            catch {
                $conflicts.Add("Malformed heartbeat record: $($_.Exception.Message)")
            }
            $recordStart = $index + 1
            $Cursor.complete_offset = [int64]$recordStart
        }
        $Cursor.trailing_partial = ($recordStart -lt $bytes.Length)
    }
    $Cursor.prior_bytes = [byte[]]$bytes.Clone()
    return [ordered]@{
        state = if ($conflicts.Count -gt 0) { 'CONFLICT' } `
            elseif ($events.Count -gt 0) { 'RECEIVED' } else { 'UNCHANGED' }
        events = [object[]]$events.ToArray()
        conflicts = [object[]]$conflicts.ToArray()
        trailing_partial = [bool]$Cursor.trailing_partial
    }
}

function Get-Stage1EHostEvidenceFileObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('PRESENT', 'MISSING', 'PARTIAL', 'UNAVAILABLE')]
        [string]$OverrideStatus
    )

    $native = $Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $status = if (-not [string]::IsNullOrEmpty($OverrideStatus)) {
        $OverrideStatus
    }
    elseif ([System.IO.File]::Exists($native)) { 'PRESENT' }
    else { 'MISSING' }
    return [ordered]@{
        status = $status
        path = if ($status -ceq 'UNAVAILABLE') { 'NONE' } else { $Path }
        byte_count = if ([System.IO.File]::Exists($native)) {
            [int64](Get-Item -LiteralPath $native).Length
        }
        else { 'UNAVAILABLE' }
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EProductionHostObserverInterfaceVersion'
    'Get-Stage1EProductionHostPreflightObservation'
    'Get-Stage1EProductionHostProcessObservation'
    'New-Stage1EHostHeartbeatCursor'
    'Read-Stage1EProductionHostHeartbeatJournal'
    'Get-Stage1EHostEvidenceFileObservation'
)
