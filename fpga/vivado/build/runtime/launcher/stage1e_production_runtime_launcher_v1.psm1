Set-StrictMode -Version Latest

$libraryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../../lib'))
$observerRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../observer/host'))
$contractModule = Join-Path $libraryRoot 'stage1e_host_boundary_contract_v1.psm1'
$processModule = Join-Path $libraryRoot 'stage1e_windows_process_control_v1.psm1'
$observerModule = Join-Path $observerRoot `
    'stage1e_production_host_observer_v1.psm1'
Import-Module -Name $contractModule -Force -ErrorAction Stop
Import-Module -Name $processModule -Force -ErrorAction Stop
Import-Module -Name $observerModule -Force -ErrorAction Stop

$script:Stage1EProductionRuntimeLauncherInterface =
    'stage1e-production-runtime-launcher-interface-v1'

function Get-Stage1EProductionRuntimeLauncherInterfaceVersion {
    return $script:Stage1EProductionRuntimeLauncherInterface
}

function New-Stage1EHostFailureState {
    return [ordered]@{
        next_ordinal = 1
        first_failure = 'NONE'
        secondary_failures =
            [System.Collections.Generic.List[object]]::new()
    }
}

function Add-Stage1EHostFailure {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$FailureState,
        [Parameter(Mandatory = $true)]
        [ValidateSet('FAILED', 'BLOCKED')][string]$TerminalStatus,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Component,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$AuthorizationEffect,
        [Parameter(Mandatory = $true)][string]$ProcessEffect,
        [Parameter(Mandatory = $true)][string]$EvidenceState,
        [Parameter(Mandatory = $true)][string]$RetryDisposition,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][object[]]$References
    )

    $ordinal = [int64]$FailureState.next_ordinal
    $FailureState.next_ordinal = $ordinal + 1
    $record = [ordered]@{
        terminal_status = $TerminalStatus
        failure_category = $Category
        failure_code = $Code
        failure_component = $Component
        failure_phase = $Phase
        first_failure_ordinal = $ordinal
        authorization_effect = $AuthorizationEffect
        process_effect = $ProcessEffect
        evidence_state = $EvidenceState
        retry_disposition = $RetryDisposition
        candidate_effect = 'NOT_CREATED'
        message = $Message
        causal_evidence_references = [object[]]$References
    }
    if ($FailureState.first_failure -isnot
        [System.Collections.IDictionary]) {
        $FailureState.first_failure = $record
    }
    else {
        $FailureState.secondary_failures.Add($record)
    }
    return $record
}

function New-Stage1EHostProcessEvent {
    param(
        [Parameter(Mandatory = $true)][int]$Ordinal,
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [object[]]$Instances,
        [Parameter(Mandatory = $true)][string]$Message
    )
    return [ordered]@{
        schema_version = 'stage1e-runtime-host-process-event-v1'
        ordinal = [int64]$Ordinal
        event_type = $EventType
        elapsed_ms = [int64]$Stopwatch.ElapsedMilliseconds
        observation_time_utc = [System.DateTime]::UtcNow.ToString(
            'o', [System.Globalization.CultureInfo]::InvariantCulture)
        instances = [object[]]$Instances
        message = $Message
    }
}

function Add-Stage1EHostProcessEvent {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Events,
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [object[]]$Instances,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$JournalRoot,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    $event = New-Stage1EHostProcessEvent ($Events.Count + 1) $EventType `
        $Stopwatch $Instances $Message
    $null = Assert-Stage1EHostRecord -Role process_event -Record $event `
        -Contract $HostContract
    $null = Add-Stage1EHostJournalRecord -Role process_event -Record $event `
        -LiteralPath $JournalPath -BoundaryPath $JournalRoot `
        -Contract $HostContract
    $Events.Add($event)
    return $event
}

function Add-Stage1EHostTimeoutEvent {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Events,
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)][string]$DeadlineKind,
        [Parameter(Mandatory = $true)][int64]$ConfiguredBudgetMs,
        [Parameter(Mandatory = $true)][int64]$StartElapsedMs,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory = $true)][string]$Outcome,
        [Parameter(Mandatory = $true)][bool]$IsFirstFailure,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$JournalRoot,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    $event = [ordered]@{
        schema_version =
            'stage1e-runtime-host-timeout-termination-event-v1'
        ordinal = [int64]($Events.Count + 1)
        event_type = $EventType
        deadline_kind = $DeadlineKind
        configured_budget_ms = $ConfiguredBudgetMs
        start_elapsed_ms = $StartElapsedMs
        event_elapsed_ms = [int64]$Stopwatch.ElapsedMilliseconds
        outcome = $Outcome
        is_first_failure = $IsFirstFailure
        message = $Message
    }
    $null = Assert-Stage1EHostRecord -Role timeout_event -Record $event `
        -Contract $HostContract
    $null = Add-Stage1EHostJournalRecord -Role timeout_event -Record $event `
        -LiteralPath $JournalPath -BoundaryPath $JournalRoot `
        -Contract $HostContract
    $Events.Add($event)
    return $event
}

function Test-Stage1EHostTopologyMinimumsSatisfied {
    param(
        [Parameter(Mandatory = $true)][object[]]$Instances,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest
    )

    foreach ($topology in $LauncherRequest.expected_topology) {
        $count = @($Instances | Where-Object {
                [string]$_.role -ceq [string]$topology.role -and
                [string]$_.image_state -ceq 'PRESENT' -and
                (Test-Stage1EHostPathEqual $_.image_path $topology.image_path)
            }).Count
        if ($count -lt [int64]$topology.minimum_count) { return $false }
    }
    return $true
}

function Get-Stage1EHostExecutionProcessLimit {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest
    )

    $limit = [int64]0
    foreach ($topology in $LauncherRequest.expected_topology) {
        $limit += [int64]$topology.maximum_count
    }
    if ($limit -lt 1 -or $limit -gt 32) {
        throw [System.InvalidOperationException]::new(
            'The expected-topology maximum sum is outside the HOST bound.')
    }
    return $limit
}

function Test-Stage1EHostDeadlineExpired {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory = $true)][int64]$StartElapsedMs,
        [Parameter(Mandatory = $true)][int64]$BudgetMs
    )
    return (($Stopwatch.ElapsedMilliseconds - $StartElapsedMs) -ge $BudgetMs)
}

function Add-Stage1EHostPreResumeDeadlineFailure {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$FailureState,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[object]]$TimeoutEvents,
        [Parameter(Mandatory = $true)][string]$DeadlineKind,
        [Parameter(Mandatory = $true)][string]$FailureCode,
        [Parameter(Mandatory = $true)][int64]$ConfiguredBudgetMs,
        [Parameter(Mandatory = $true)][int64]$StartElapsedMs,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory = $true)][string]$ProcessEffect,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    $isFirst = $FailureState.first_failure -isnot
        [System.Collections.IDictionary]
    $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
        'DEADLINE_EXPIRED' $DeadlineKind $ConfiguredBudgetMs `
        $StartElapsedMs $Stopwatch 'EXPIRED' $isFirst $Message `
        $LauncherRequest.timeout_event_journal_path `
        $LauncherRequest.journal_root $HostContract
    return Add-Stage1EHostFailure $FailureState 'BLOCKED' 'TIMEOUT' `
        $FailureCode 'PRODUCTION_LAUNCHER' 'PROCESS_LAUNCH' 'NOT_TOUCHED' `
        $ProcessEffect 'PARTIAL_PRESERVED' 'NEW_EXECUTION_REQUIRED' `
        $Message ([object[]]@($LauncherRequest.timeout_event_journal_path))
}

function Get-Stage1EHostFailureProcessControlException {
    param([Parameter(Mandatory = $true)][System.Exception]$Exception)

    $current = $Exception
    while ($null -ne $current) {
        if ($current.GetType().FullName -ceq
            'Stage1E.Runtime.Host.V1.ProcessControlException') {
            return $current
        }
        $current = $current.InnerException
    }
    return $null
}

function Complete-Stage1EHostTerminationPolicy {
    param(
        [Parameter(Mandatory = $true)][object]$Process,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest,
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[object]]$TimeoutEvents,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    $gracefulStart = [int64]$Stopwatch.ElapsedMilliseconds
    if ([string]$LauncherRequest.graceful_termination_mode -ceq
        'WINDOW_CLOSE') {
        $closeResult = Request-Stage1EWindowsGracefulTermination `
            -Process $Process
        if ([bool]$closeResult.RequestIssued) {
            $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
                'GRACEFUL_TERMINATION_REQUESTED' 'GRACEFUL_TERMINATION' `
                $LauncherRequest.graceful_termination_timeout_ms `
                $gracefulStart $Stopwatch 'REQUESTED' $false `
                'A single operating-system window-close request was issued.' `
                $LauncherRequest.timeout_event_journal_path `
                $LauncherRequest.journal_root $HostContract
            $gracefulExit = Wait-Stage1EWindowsJobEmpty -Process $Process `
                -TimeoutMilliseconds `
                    ([int]$LauncherRequest.graceful_termination_timeout_ms) `
                -ObservationIntervalMilliseconds `
                    ([int]$LauncherRequest.observation_interval_ms)
            $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
                'GRACEFUL_WAIT_COMPLETED' 'GRACEFUL_TERMINATION' `
                $LauncherRequest.graceful_termination_timeout_ms `
                $gracefulStart $Stopwatch `
                $(if ($gracefulExit) { 'SUCCEEDED' } else { 'EXPIRED' }) `
                $false 'The bounded graceful-termination wait completed.' `
                $LauncherRequest.timeout_event_journal_path `
                $LauncherRequest.journal_root $HostContract
            if ($gracefulExit) { return 'GRACEFUL_EXIT' }
        }
        else {
            $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
                'GRACEFUL_TERMINATION_UNAVAILABLE' 'GRACEFUL_TERMINATION' `
                $LauncherRequest.graceful_termination_timeout_ms `
                $gracefulStart $Stopwatch 'UNAVAILABLE' $false `
                'No contained top-level window accepted a close request.' `
                $LauncherRequest.timeout_event_journal_path `
                $LauncherRequest.journal_root $HostContract
        }
    }
    else {
        $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
            'GRACEFUL_TERMINATION_UNAVAILABLE' 'GRACEFUL_TERMINATION' 0 `
            $gracefulStart $Stopwatch 'UNAVAILABLE' $false `
            'The sealed request selected no graceful termination mechanism.' `
            $LauncherRequest.timeout_event_journal_path `
            $LauncherRequest.journal_root $HostContract
    }
    if (Test-Stage1EWindowsJobEmpty -Process $Process) {
        return 'GRACEFUL_EXIT'
    }
    $forcedStart = [int64]$Stopwatch.ElapsedMilliseconds
    $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
        'FORCED_TERMINATION_REQUESTED' 'TERMINAL_OBSERVATION' `
        $LauncherRequest.terminal_observation_timeout_ms $forcedStart `
        $Stopwatch 'REQUESTED' $false `
        'A single contained-tree forced termination was requested.' `
        $LauncherRequest.timeout_event_journal_path `
        $LauncherRequest.journal_root $HostContract
    Stop-Stage1EWindowsContainedProcessTree -Process $Process
    $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
        'FORCED_TERMINATION_COMPLETED' 'TERMINAL_OBSERVATION' `
        $LauncherRequest.terminal_observation_timeout_ms $forcedStart `
        $Stopwatch 'SUCCEEDED' $false `
        'TerminateJobObject returned success for the contained tree.' `
        $LauncherRequest.timeout_event_journal_path `
        $LauncherRequest.journal_root $HostContract
    $terminal = Wait-Stage1EWindowsJobEmpty -Process $Process `
        -TimeoutMilliseconds `
            ([int]$LauncherRequest.terminal_observation_timeout_ms) `
        -ObservationIntervalMilliseconds `
            ([int]$LauncherRequest.observation_interval_ms)
    $null = Add-Stage1EHostTimeoutEvent $TimeoutEvents `
        'TERMINAL_WAIT_COMPLETED' 'TERMINAL_OBSERVATION' `
        $LauncherRequest.terminal_observation_timeout_ms $forcedStart `
        $Stopwatch $(if ($terminal) { 'SUCCEEDED' } else { 'EXPIRED' }) `
        $false 'The bounded post-termination observation wait completed.' `
        $LauncherRequest.timeout_event_journal_path `
        $LauncherRequest.journal_root $HostContract
    if ($terminal) { return 'FORCED_EXIT' }
    return 'INCOMPLETE'
}

function Invoke-Stage1EProductionRuntimeLauncher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Collections.IDictionary]$LauncherRequest
    )

    $hostContract = Import-Stage1EHostBoundaryContract
    $null = Assert-Stage1EHostRecord -Role launcher_request `
        -Record $LauncherRequest -Contract $hostContract
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $processEvents = [System.Collections.Generic.List[object]]::new()
    $timeoutEvents = [System.Collections.Generic.List[object]]::new()
    $failureState = New-Stage1EHostFailureState
    $firstSeen = [ordered]@{}
    $heartbeatCursor = New-Stage1EHostHeartbeatCursor
    $heartbeatFinalCursor = [ordered]@{
        complete_offset = [int64]0
        observed_byte_count = [int64]0
        last_sequence = [int64]0
        trailing_partial = $false
        terminal_read_state = 'NOT_PERFORMED'
    }
    $process = $null
    $creationAttemptCount = 0
    $resumeCount = 0
    $rootProcessId = 'UNAVAILABLE'
    $exitCode = 'UNAVAILABLE'
    $launcherState = 'LAUNCH_NOT_ATTEMPTED'
    $terminalStatus = 'BLOCKED'
    $processEffect = 'NOT_STARTED'
    $authorizationEffect = 'NOT_TOUCHED'
    $terminationDisposition = 'NOT_REQUIRED'
    $terminalTreeState = 'TERMINAL'
    $allConflicts = [System.Collections.Generic.List[string]]::new()
    $lastInstances = [object[]]@()
    $maxObservedInstances = 0
    $lastJobEvents = [object[]]@()
    $terminalSnapshotProcessIds = [object[]]@()
    $executionProcessLimit = Get-Stage1EHostExecutionProcessLimit `
        $LauncherRequest
    $publications = [ordered]@{}
    $totalStart = [int64]0
    $startupStart = [int64]0
    $childDiscoveryStart = [int64]0
    $heartbeatStart = [int64]0
    $lastHeartbeatElapsed = [int64]0

    try {
    $providerObservation = Import-Stage1EWindowsProcessControlProvider
    $preflight = Get-Stage1EProductionHostPreflightObservation `
        -LauncherRequest $LauncherRequest `
        -ProcessProviderObservation $providerObservation `
        -HostContract $hostContract
    $publications.preflight = Publish-Stage1EHostRecord -Role preflight `
        -Record $preflight -LiteralPath $LauncherRequest.preflight_result_path `
        -BoundaryPath $LauncherRequest.evidence_root -Contract $hostContract
    $null = Add-Stage1EHostTimeoutEvent $timeoutEvents 'DEADLINE_ARMED' `
        'TOTAL_LIFETIME' $LauncherRequest.total_lifetime_timeout_ms `
        $totalStart $stopwatch 'ARMED' $false `
        'The total monotonic launcher lifetime deadline was armed.' `
        $LauncherRequest.timeout_event_journal_path `
        $LauncherRequest.journal_root $hostContract
    $null = Add-Stage1EHostProcessEvent $processEvents `
        'PREFLIGHT_OBSERVED' $stopwatch ([object[]]@()) `
        'The read-only host foundation preflight was recorded.' `
        $LauncherRequest.process_event_journal_path `
        $LauncherRequest.journal_root $hostContract

    if ([string]$preflight.observation_state -cne 'READY') {
        foreach ($conflict in $preflight.conflicts) {
            $allConflicts.Add([string]$conflict)
        }
        $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
            'HOST_PREFLIGHT' 'HOST_PREFLIGHT_CONFLICT' 'HOST_OBSERVER' `
            'HOST_PREFLIGHT' 'NOT_TOUCHED' 'NOT_STARTED' `
            'PARTIAL_PRESERVED' 'REVIEW_BEFORE_NEW_LAUNCH' `
            'Host foundation preflight contained a blocking conflict.' `
            ([object[]]@($LauncherRequest.preflight_result_path))
    }
    elseif (Test-Stage1EHostDeadlineExpired $stopwatch $totalStart `
            ([int64]$LauncherRequest.total_lifetime_timeout_ms)) {
        $null = Add-Stage1EHostPreResumeDeadlineFailure $failureState `
            $timeoutEvents 'TOTAL_LIFETIME' `
            'TOTAL_LIFETIME_TIMEOUT_PRELAUNCH' `
            $LauncherRequest.total_lifetime_timeout_ms $totalStart `
            $stopwatch 'NOT_STARTED' `
            'The total lifetime expired after provider/preflight completion.' `
            $LauncherRequest $hostContract
        $launcherState = 'PROCESS_TIMED_OUT'
    }
    else {
        $startupStart = [int64]$stopwatch.ElapsedMilliseconds
        $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
            'DEADLINE_ARMED' 'STARTUP' `
            $LauncherRequest.startup_timeout_ms $startupStart $stopwatch `
            'ARMED' $false 'The exact process-startup deadline was armed.' `
            $LauncherRequest.timeout_event_journal_path `
            $LauncherRequest.journal_root $hostContract
        $null = Add-Stage1EHostProcessEvent $processEvents `
            'LAUNCH_REQUESTED' $stopwatch ([object[]]@()) `
            'The single exact process-creation attempt was requested.' `
            $LauncherRequest.process_event_journal_path `
            $LauncherRequest.journal_root $hostContract
        if (Test-Stage1EHostDeadlineExpired $stopwatch $totalStart `
                ([int64]$LauncherRequest.total_lifetime_timeout_ms)) {
            $null = Add-Stage1EHostPreResumeDeadlineFailure $failureState `
                $timeoutEvents 'TOTAL_LIFETIME' `
                'TOTAL_LIFETIME_TIMEOUT_PRELAUNCH' `
                $LauncherRequest.total_lifetime_timeout_ms $totalStart `
                $stopwatch 'NOT_STARTED' `
                'The total lifetime expired immediately before process creation.' `
                $LauncherRequest $hostContract
            $launcherState = 'PROCESS_TIMED_OUT'
        }
        else {
        try {
            $process = New-Stage1EWindowsControlledProcess `
                -LauncherRequest $LauncherRequest -HostContract $hostContract
            $creationAttemptCount = [int]$process.CreationAttemptCount
            $rootProcessId = [int64]$process.ProcessId
            if (-not [bool]$process.CreatedSuspended -or
                -not [bool]$process.JobAssignedBeforeResume -or
                -not [bool]$process.MembershipVerifiedBeforeResume -or
                -not [bool]$process.CompletionPortAssociatedBeforeCreate -or
                -not [bool]$process.RootNewProcessObservedBeforeResume) {
                throw [System.InvalidOperationException]::new(
                    'Race-controlled containment or Job-event facts are incomplete before resume.')
            }
            if ([uint32]$process.ParentProcessId -ne [uint32]$PID) {
                throw [System.InvalidOperationException]::new(
                    'The exact root process parent differs from the active launcher process.')
            }
            $preResumeObservation =
                Get-Stage1EProductionHostProcessObservation `
                    -Process $process -LauncherRequest $LauncherRequest `
                    -ObservationOrdinal ($processEvents.Count + 1) `
                    -FirstSeenOrdinals $firstSeen -HostContract $hostContract
            $lastInstances = [object[]]$preResumeObservation.instances
            $lastJobEvents = [object[]]$preResumeObservation.job_events
            $terminalSnapshotProcessIds =
                [object[]]$preResumeObservation.snapshot_process_ids
            $maxObservedInstances = [Math]::Max(
                $maxObservedInstances, $lastInstances.Count)
            $null = Add-Stage1EHostProcessEvent $processEvents `
                'PROCESS_CREATED_SUSPENDED' $stopwatch $lastInstances `
                'CreateProcessW returned one suspended root process.' `
                $LauncherRequest.process_event_journal_path `
                $LauncherRequest.journal_root $hostContract
            $null = Add-Stage1EHostProcessEvent $processEvents `
                'JOB_ASSIGNED' $stopwatch $lastInstances `
                'Job membership and root NEW_PROCESS evidence were verified before resume.' `
                $LauncherRequest.process_event_journal_path `
                $LauncherRequest.journal_root $hostContract
            if ($preResumeObservation.conflicts.Count -gt 0) {
                foreach ($conflict in $preResumeObservation.conflicts) {
                    $allConflicts.Add([string]$conflict)
                }
                $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                    'PROCESS_OBSERVATION' `
                    'PROCESS_INSTANCE_EVIDENCE_INCOMPLETE' 'HOST_OBSERVER' `
                    'PROCESS_LAUNCH' 'NOT_TOUCHED' 'NOT_STARTED' `
                    'PARTIAL_PRESERVED' `
                    'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                    'Pre-resume process-instance or Job-event evidence was incomplete.' `
                    ([object[]]@($LauncherRequest.process_event_journal_path))
                $launcherState = 'PROCESS_OBSERVATION_LOST'
            }
            elseif (Test-Stage1EHostDeadlineExpired $stopwatch $totalStart `
                    ([int64]$LauncherRequest.total_lifetime_timeout_ms)) {
                $null = Add-Stage1EHostPreResumeDeadlineFailure $failureState `
                    $timeoutEvents 'TOTAL_LIFETIME' `
                    'TOTAL_LIFETIME_TIMEOUT_PRE_RESUME' `
                    $LauncherRequest.total_lifetime_timeout_ms $totalStart `
                    $stopwatch 'NOT_STARTED' `
                    'The total lifetime expired after suspended containment and observation.' `
                    $LauncherRequest $hostContract
                $launcherState = 'PROCESS_TIMED_OUT'
            }
            elseif (Test-Stage1EHostDeadlineExpired $stopwatch $startupStart `
                    ([int64]$LauncherRequest.startup_timeout_ms)) {
                $null = Add-Stage1EHostPreResumeDeadlineFailure $failureState `
                    $timeoutEvents 'STARTUP' `
                    'PROCESS_STARTUP_TIMEOUT_PRE_RESUME' `
                    $LauncherRequest.startup_timeout_ms $startupStart `
                    $stopwatch 'NOT_STARTED' `
                    'The startup deadline expired immediately before resume.' `
                    $LauncherRequest $hostContract
                $launcherState = 'PROCESS_TIMED_OUT'
            }
            elseif (Test-Stage1EHostDeadlineExpired $stopwatch $totalStart `
                    ([int64]$LauncherRequest.total_lifetime_timeout_ms)) {
                $null = Add-Stage1EHostPreResumeDeadlineFailure $failureState `
                    $timeoutEvents 'TOTAL_LIFETIME' `
                    'TOTAL_LIFETIME_TIMEOUT_PRE_RESUME' `
                    $LauncherRequest.total_lifetime_timeout_ms $totalStart `
                    $stopwatch 'NOT_STARTED' `
                    'The total lifetime expired immediately before resume.' `
                    $LauncherRequest $hostContract
                $launcherState = 'PROCESS_TIMED_OUT'
            }
            else {
                $resumePrevious = Resume-Stage1EWindowsControlledProcess `
                    -Process $process
                $resumeCount = [int]$process.ResumeCount
                if ([uint32]$resumePrevious -ne 1 -or $resumeCount -ne 1) {
                    throw [System.InvalidOperationException]::new(
                        'The primary thread did not make exactly one resume transition.')
                }
                $null = Add-Stage1EHostProcessEvent $processEvents `
                    'THREAD_RESUMED' $stopwatch $lastInstances `
                    'The contained primary thread resumed exactly once.' `
                    $LauncherRequest.process_event_journal_path `
                    $LauncherRequest.journal_root $hostContract
                $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                    'DEADLINE_CANCELLED' 'STARTUP' `
                    $LauncherRequest.startup_timeout_ms $startupStart `
                    $stopwatch 'CANCELLED' $false `
                    'The exact root process was contained and resumed.' `
                    $LauncherRequest.timeout_event_journal_path `
                    $LauncherRequest.journal_root $hostContract
                $childDiscoveryStart = [int64]$stopwatch.ElapsedMilliseconds
                $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                    'DEADLINE_ARMED' 'CHILD_DISCOVERY' `
                    $LauncherRequest.child_discovery_timeout_ms `
                    $childDiscoveryStart $stopwatch 'ARMED' $false `
                    'The declared process-topology discovery deadline was armed.' `
                    $LauncherRequest.timeout_event_journal_path `
                    $LauncherRequest.journal_root $hostContract
                if ([bool]$LauncherRequest.heartbeat_required) {
                    $heartbeatStart = [int64]$stopwatch.ElapsedMilliseconds
                    $lastHeartbeatElapsed = $heartbeatStart
                    $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                        'DEADLINE_ARMED' 'HEARTBEAT_SILENCE' `
                        $LauncherRequest.heartbeat_silence_timeout_ms `
                        $heartbeatStart $stopwatch 'ARMED' $false `
                        'The one-way heartbeat-silence deadline was armed.' `
                        $LauncherRequest.timeout_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                }
            }
        }
        catch {
            $controlException = Get-Stage1EHostFailureProcessControlException `
                $_.Exception
            if ($null -ne $controlException) {
                $creationAttemptCount = if (
                    [bool]$controlException.ProcessCreationAttempted) { 1 } `
                    else { 0 }
                if ([bool]$controlException.ProcessCreated) {
                    $rootProcessId = [int64]$controlException.ProcessId
                    $processEffect = 'NOT_STARTED'
                    $authorizationEffect = 'NOT_TOUCHED'
                }
                $code = 'EXACT_PROCESS_CREATION_FAILED'
                $message = "Process control failed at $(
                    $controlException.Operation): $($controlException.Message)"
            }
            else {
                $code = 'PROCESS_CONTROL_INTERNAL_FAILURE'
                $message = "Process control failed: $($_.Exception.Message)"
            }
            $null = Add-Stage1EHostProcessEvent $processEvents `
                'PROCESS_CREATION_FAILED' $stopwatch ([object[]]@()) `
                $message $LauncherRequest.process_event_journal_path `
                $LauncherRequest.journal_root $hostContract
            $null = Add-Stage1EHostFailure $failureState 'FAILED' 'LAUNCH' `
                $code 'PROCESS_CONTROL' 'PROCESS_LAUNCH' `
                $authorizationEffect $processEffect 'PARTIAL_PRESERVED' `
                'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' $message `
                ([object[]]@($LauncherRequest.process_event_journal_path))
            $launcherState = 'LAUNCH_FAILED'
            $terminalStatus = 'FAILED'
        }
        }
    }

    if ($null -ne $process -and
        $failureState.first_failure -isnot
            [System.Collections.IDictionary]) {
        $childDiscoverySatisfied = $false
        $runningRecorded = $false
        while ($failureState.first_failure -isnot
            [System.Collections.IDictionary]) {
            try {
                $observation = Get-Stage1EProductionHostProcessObservation `
                    -Process $process -LauncherRequest $LauncherRequest `
                    -ObservationOrdinal ($processEvents.Count + 1) `
                    -FirstSeenOrdinals $firstSeen -HostContract $hostContract
                $lastInstances = [object[]]$observation.instances
                $lastJobEvents = [object[]]$observation.job_events
                $terminalSnapshotProcessIds =
                    [object[]]$observation.snapshot_process_ids
                $maxObservedInstances = [Math]::Max(
                    $maxObservedInstances, $lastInstances.Count)
                if ($observation.conflicts.Count -gt 0) {
                    foreach ($conflict in $observation.conflicts) {
                        $allConflicts.Add([string]$conflict)
                    }
                    $null = Add-Stage1EHostProcessEvent $processEvents `
                        'TOPOLOGY_CONFLICT' $stopwatch $lastInstances `
                        'The contained process topology conflicted with the request.' `
                        $LauncherRequest.process_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'PROCESS_OBSERVATION' 'PROCESS_TOPOLOGY_CONFLICT' `
                        'HOST_OBSERVER' 'PROCESS_LAUNCH' 'STATE_UNKNOWN' `
                        'STARTED_RUNNING' 'PARTIAL_PRESERVED' `
                        'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                        'The observed process topology was not the declared topology.' `
                        ([object[]]@($LauncherRequest.process_event_journal_path))
                    $launcherState = 'PROCESS_OBSERVATION_LOST'
                    break
                }
                if (-not $childDiscoverySatisfied -and
                    (Test-Stage1EHostTopologyMinimumsSatisfied $lastInstances `
                        $LauncherRequest)) {
                    $childDiscoverySatisfied = $true
                    $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                        'DEADLINE_CANCELLED' 'CHILD_DISCOVERY' `
                        $LauncherRequest.child_discovery_timeout_ms `
                        $childDiscoveryStart $stopwatch 'CANCELLED' $false `
                        'All minimum declared process roles were observed.' `
                        $LauncherRequest.timeout_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                }
                if (-not $runningRecorded) {
                    $runningRecorded = $true
                    $null = Add-Stage1EHostProcessEvent $processEvents `
                        'PROCESS_RUNNING' $stopwatch $lastInstances `
                        'The exact contained process tree entered transient running state.' `
                        $LauncherRequest.process_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                }
                $heartbeat = Read-Stage1EProductionHostHeartbeatJournal `
                    -LauncherRequest $LauncherRequest `
                    -RootProcessId ([uint32]$process.ProcessId) `
                    -Cursor $heartbeatCursor -HostContract $hostContract
                if ($heartbeat.conflicts.Count -gt 0) {
                    foreach ($conflict in $heartbeat.conflicts) {
                        $allConflicts.Add([string]$conflict)
                    }
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'PROCESS_OBSERVATION' 'HEARTBEAT_CONTRACT_CONFLICT' `
                        'HOST_OBSERVER' 'PROCESS_LAUNCH' 'STATE_UNKNOWN' `
                        'STARTED_RUNNING' 'PARTIAL_PRESERVED' `
                        'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                        'Heartbeat framing, binding, or sequence was invalid.' `
                        ([object[]]@($LauncherRequest.heartbeat_path))
                    $launcherState = 'PROCESS_OBSERVATION_LOST'
                    break
                }
                foreach ($heartbeatEvent in $heartbeat.events) {
                    $lastHeartbeatElapsed = [int64]$stopwatch.ElapsedMilliseconds
                    $null = Add-Stage1EHostProcessEvent $processEvents `
                        'HEARTBEAT_RECEIVED' $stopwatch $lastInstances `
                        "Non-authoritative heartbeat sequence $(
                            $heartbeatEvent.sequence) was received." `
                        $LauncherRequest.process_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                }
                if (Test-Stage1EWindowsJobEmpty -Process $process) {
                    if (-not $childDiscoverySatisfied) {
                        $null = Add-Stage1EHostFailure $failureState 'FAILED' `
                            'LAUNCH' 'DECLARED_CHILD_NOT_ESTABLISHED' `
                            'HOST_OBSERVER' 'PROCESS_LAUNCH' 'STATE_UNKNOWN' `
                            'EXITED_OBSERVED' 'PARTIAL_PRESERVED' `
                            'NEW_EXECUTION_REQUIRED' `
                            'The process tree exited before every required declared role was established.' `
                            ([object[]]@(
                                $LauncherRequest.process_event_journal_path))
                        $launcherState = 'LAUNCH_FAILED'
                        $terminalStatus = 'FAILED'
                    }
                    break
                }
                $elapsed = [int64]$stopwatch.ElapsedMilliseconds
                if (-not $childDiscoverySatisfied -and
                    ($elapsed - $childDiscoveryStart) -ge
                        [int64]$LauncherRequest.child_discovery_timeout_ms) {
                    $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                        'DEADLINE_EXPIRED' 'CHILD_DISCOVERY' `
                        $LauncherRequest.child_discovery_timeout_ms `
                        $childDiscoveryStart $stopwatch 'EXPIRED' $true `
                        'A required declared support process was not discovered.' `
                        $LauncherRequest.timeout_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'TIMEOUT' 'CHILD_DISCOVERY_TIMEOUT' `
                        'PRODUCTION_LAUNCHER' 'PROCESS_LAUNCH' `
                        'STATE_UNKNOWN' 'STARTED_RUNNING' `
                        'PARTIAL_PRESERVED' 'NEW_EXECUTION_REQUIRED' `
                        'The fixed process child-discovery budget expired.' `
                        ([object[]]@(
                            $LauncherRequest.timeout_event_journal_path))
                    $launcherState = 'PROCESS_TIMED_OUT'
                    break
                }
                if ([bool]$LauncherRequest.heartbeat_required -and
                    ($elapsed - $lastHeartbeatElapsed) -ge
                        [int64]$LauncherRequest.heartbeat_silence_timeout_ms) {
                    $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                        'DEADLINE_EXPIRED' 'HEARTBEAT_SILENCE' `
                        $LauncherRequest.heartbeat_silence_timeout_ms `
                        $lastHeartbeatElapsed $stopwatch 'EXPIRED' $true `
                        'No valid attempt-bound heartbeat arrived within budget.' `
                        $LauncherRequest.timeout_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'TIMEOUT' 'HEARTBEAT_SILENCE_TIMEOUT' `
                        'PRODUCTION_LAUNCHER' 'PROCESS_LAUNCH' `
                        'STATE_UNKNOWN' 'STARTED_RUNNING' `
                        'PARTIAL_PRESERVED' 'NEW_EXECUTION_REQUIRED' `
                        'The fixed heartbeat-silence budget expired.' `
                        ([object[]]@(
                            $LauncherRequest.timeout_event_journal_path))
                    $launcherState = 'PROCESS_TIMED_OUT'
                    break
                }
                if (($elapsed - $totalStart) -ge
                    [int64]$LauncherRequest.total_lifetime_timeout_ms) {
                    $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                        'DEADLINE_EXPIRED' 'TOTAL_LIFETIME' `
                        $LauncherRequest.total_lifetime_timeout_ms `
                        $totalStart $stopwatch 'EXPIRED' $true `
                        'The total launcher lifetime expired despite process activity.' `
                        $LauncherRequest.timeout_event_journal_path `
                        $LauncherRequest.journal_root $hostContract
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'TIMEOUT' 'TOTAL_LIFETIME_TIMEOUT' `
                        'PRODUCTION_LAUNCHER' 'PROCESS_LAUNCH' `
                        'STATE_UNKNOWN' 'STARTED_RUNNING' `
                        'PARTIAL_PRESERVED' 'NEW_EXECUTION_REQUIRED' `
                        'The fixed total lifetime budget expired.' `
                        ([object[]]@(
                            $LauncherRequest.timeout_event_journal_path))
                    $launcherState = 'PROCESS_TIMED_OUT'
                    break
                }
                [System.Threading.Thread]::Sleep(
                    [int]$LauncherRequest.observation_interval_ms)
            }
            catch {
                $allConflicts.Add($_.Exception.Message)
                $null = Add-Stage1EHostProcessEvent $processEvents `
                    'OBSERVATION_LOST' $stopwatch $lastInstances `
                    'Required process observation continuity was lost.' `
                    $LauncherRequest.process_event_journal_path `
                    $LauncherRequest.journal_root $hostContract
                $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                    'PROCESS_OBSERVATION' 'PROCESS_OBSERVATION_LOST' `
                    'HOST_OBSERVER' 'PROCESS_LAUNCH' 'STATE_UNKNOWN' `
                    'OBSERVATION_LOST' 'INTEGRITY_UNKNOWN' `
                    'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                    'Required process-instance observation raised an error.' `
                    ([object[]]@($LauncherRequest.process_event_journal_path))
                $launcherState = 'PROCESS_OBSERVATION_LOST'
                break
            }
        }
    }

    if ($null -ne $process) {
        if ($failureState.first_failure -is
            [System.Collections.IDictionary]) {
            if (Test-Stage1EWindowsJobEmpty -Process $process) {
                $terminationDisposition = 'NATURAL_EXIT'
                $processEffect = 'EXITED_OBSERVED'
            }
            else {
                try {
                    $terminationDisposition = Complete-Stage1EHostTerminationPolicy `
                        -Process $process -LauncherRequest $LauncherRequest `
                        -Stopwatch $stopwatch -TimeoutEvents $timeoutEvents `
                        -HostContract $hostContract
                    if ($terminationDisposition -ceq 'INCOMPLETE') {
                        $terminalTreeState = 'UNKNOWN'
                        $launcherState = 'PROCESS_TERMINAL_STATE_UNKNOWN'
                        $processEffect = 'STATE_UNKNOWN'
                        $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                            'PROCESS_OBSERVATION' `
                            'PROCESS_TERMINAL_STATE_UNKNOWN' 'PROCESS_CONTROL' `
                            'TERMINATION' 'STATE_UNKNOWN' 'STATE_UNKNOWN' `
                            'INTEGRITY_UNKNOWN' `
                            'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                            'Bounded termination could not prove an empty process tree.' `
                            ([object[]]@(
                                $LauncherRequest.timeout_event_journal_path))
                    }
                    else {
                        $processEffect = 'TERMINATED_BY_POLICY'
                    }
                }
                catch {
                    $terminalTreeState = 'UNKNOWN'
                    $terminationDisposition = 'UNKNOWN'
                    $launcherState = 'PROCESS_TERMINAL_STATE_UNKNOWN'
                    $processEffect = 'STATE_UNKNOWN'
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'PROCESS_OBSERVATION' 'PROCESS_TERMINATION_FAILED' `
                        'PROCESS_CONTROL' 'TERMINATION' 'STATE_UNKNOWN' `
                        'STATE_UNKNOWN' 'INTEGRITY_UNKNOWN' `
                        'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                        "Bounded termination failed: $($_.Exception.Message)" `
                        ([object[]]@(
                            $LauncherRequest.timeout_event_journal_path))
                }
            }
        }
        else {
            $terminationDisposition = 'NATURAL_EXIT'
            $processEffect = 'EXITED_OBSERVED'
            $launcherState = 'PROCESS_EXITED'
            $terminalStatus = 'COMPLETED'
            $authorizationEffect = 'STATE_UNKNOWN'
        }
        try {
            $terminalObservation =
                Get-Stage1EProductionHostProcessObservation `
                    -Process $process -LauncherRequest $LauncherRequest `
                    -ObservationOrdinal ($processEvents.Count + 1) `
                    -FirstSeenOrdinals $firstSeen -HostContract $hostContract `
                    -TerminalObservation $true
            $lastInstances = [object[]]$terminalObservation.instances
            $lastJobEvents = [object[]]$terminalObservation.job_events
            $terminalSnapshotProcessIds =
                [object[]]$terminalObservation.snapshot_process_ids
            $maxObservedInstances = [Math]::Max(
                $maxObservedInstances, $lastInstances.Count)
            $null = Add-Stage1EHostProcessEvent $processEvents `
                'EXIT_OBSERVED' $stopwatch $lastInstances `
                'The retained root process terminal state was observed.' `
                $LauncherRequest.process_event_journal_path `
                $LauncherRequest.journal_root $hostContract
            if ($terminalObservation.conflicts.Count -gt 0) {
                foreach ($conflict in $terminalObservation.conflicts) {
                    $allConflicts.Add([string]$conflict)
                }
                $terminalTreeState = 'OBSERVATION_LOST'
                $launcherState = 'PROCESS_OBSERVATION_LOST'
                if ($failureState.first_failure -isnot
                    [System.Collections.IDictionary]) {
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'PROCESS_OBSERVATION' `
                        'PROCESS_INSTANCE_EVIDENCE_INCOMPLETE' `
                        'HOST_OBSERVER' 'TERMINATION' $authorizationEffect `
                        'OBSERVATION_LOST' 'PARTIAL_PRESERVED' `
                        'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                        'Terminal process-instance or Job-event evidence was incomplete.' `
                        ([object[]]@(
                            $LauncherRequest.process_event_journal_path))
                }
            }
            $exitObservation = Get-Stage1EWindowsRootExitCode -Process $process
            $exitCode = $exitObservation.exit_code
            if (-not [bool]$exitObservation.available) {
                $terminalTreeState = 'UNKNOWN'
                $launcherState = 'PROCESS_TERMINAL_STATE_UNKNOWN'
                $processEffect = 'STATE_UNKNOWN'
                if ($failureState.first_failure -isnot
                    [System.Collections.IDictionary]) {
                    $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                        'PROCESS_OBSERVATION' 'ROOT_EXIT_CODE_UNAVAILABLE' `
                        'HOST_OBSERVER' 'TERMINATION' 'STATE_UNKNOWN' `
                        'STATE_UNKNOWN' 'INTEGRITY_UNKNOWN' `
                        'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                        'The retained root process remained nonterminal.' `
                        ([object[]]@(
                            $LauncherRequest.process_event_journal_path))
                }
            }
            $captureComplete = Complete-Stage1EWindowsOutputCapture `
                -Process $process `
                -TimeoutMilliseconds `
                    ([int]$LauncherRequest.terminal_observation_timeout_ms)
            if (-not $captureComplete) {
                throw [System.IO.IOException]::new(
                    'Native stdout/stderr capture did not reach terminal state.')
            }
        }
        catch {
            $terminalTreeState = 'OBSERVATION_LOST'
            if ($failureState.first_failure -isnot
                [System.Collections.IDictionary]) {
                $launcherState = 'PROCESS_OBSERVATION_LOST'
                $terminalStatus = 'BLOCKED'
                $processEffect = 'OBSERVATION_LOST'
                $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                    'EVIDENCE_INCOMPLETE' 'TERMINAL_CAPTURE_INCOMPLETE' `
                    'PRODUCTION_LAUNCHER' 'TERMINATION' 'STATE_UNKNOWN' `
                    'OBSERVATION_LOST' 'PARTIAL_PRESERVED' `
                    'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                    "Terminal capture was incomplete: $($_.Exception.Message)" `
                    ([object[]]@(
                        $LauncherRequest.stdout_path,
                        $LauncherRequest.stderr_path))
            }
            else {
                $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                    'EVIDENCE_INCOMPLETE' 'TERMINAL_CAPTURE_INCOMPLETE' `
                    'PRODUCTION_LAUNCHER' 'TERMINATION' 'STATE_UNKNOWN' `
                    $processEffect 'PARTIAL_PRESERVED' `
                    'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                    "Terminal capture was incomplete: $($_.Exception.Message)" `
                    ([object[]]@(
                        $LauncherRequest.stdout_path,
                        $LauncherRequest.stderr_path))
            }
        }
    }

    if ($null -ne $process -and
        (Test-Stage1EWindowsJobEmpty -Process $process)) {
        try {
            $terminalHeartbeat = Read-Stage1EProductionHostHeartbeatJournal `
                -LauncherRequest $LauncherRequest `
                -RootProcessId ([uint32]$process.ProcessId) `
                -Cursor $heartbeatCursor -HostContract $hostContract
            foreach ($heartbeatEvent in $terminalHeartbeat.events) {
                $lastHeartbeatElapsed = [int64]$stopwatch.ElapsedMilliseconds
                $null = Add-Stage1EHostProcessEvent $processEvents `
                    'HEARTBEAT_RECEIVED' $stopwatch $lastInstances `
                    "Final non-authoritative heartbeat sequence $(
                        $heartbeatEvent.sequence) was received." `
                    $LauncherRequest.process_event_journal_path `
                    $LauncherRequest.journal_root $hostContract
            }
            $heartbeatFinalCursor.complete_offset =
                [int64]$heartbeatCursor.complete_offset
            $heartbeatFinalCursor.observed_byte_count =
                [int64]([byte[]]$heartbeatCursor.prior_bytes).Length
            $heartbeatFinalCursor.last_sequence =
                [int64]$heartbeatCursor.last_sequence
            $heartbeatFinalCursor.trailing_partial =
                [bool]$terminalHeartbeat.trailing_partial
            $heartbeatFinalCursor.terminal_read_state =
                if ([bool]$terminalHeartbeat.trailing_partial) { 'PARTIAL' }
                else { [string]$terminalHeartbeat.state }
            if ($terminalHeartbeat.conflicts.Count -gt 0) {
                foreach ($conflict in $terminalHeartbeat.conflicts) {
                    $allConflicts.Add([string]$conflict)
                }
                $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                    'PROCESS_OBSERVATION' 'HEARTBEAT_CONTRACT_CONFLICT' `
                    'HOST_OBSERVER' 'TERMINATION' $authorizationEffect `
                    $processEffect 'PARTIAL_PRESERVED' `
                    'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                    'The final heartbeat read found changed, malformed, or conflicting evidence.' `
                    ([object[]]@($LauncherRequest.heartbeat_path))
                $launcherState = 'PROCESS_OBSERVATION_LOST'
            }
            if ([bool]$terminalHeartbeat.trailing_partial) {
                $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                    'EVIDENCE_INCOMPLETE' 'HEARTBEAT_TRAILING_PARTIAL' `
                    'HOST_OBSERVER' 'TERMINATION' $authorizationEffect `
                    $processEffect 'PARTIAL_PRESERVED' `
                    'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                    'A trailing partial heartbeat record remained after process-tree termination.' `
                    ([object[]]@($LauncherRequest.heartbeat_path))
                $launcherState = 'PROCESS_OBSERVATION_LOST'
            }
        }
        catch {
            $heartbeatFinalCursor.complete_offset =
                [int64]$heartbeatCursor.complete_offset
            $heartbeatFinalCursor.observed_byte_count =
                [int64]([byte[]]$heartbeatCursor.prior_bytes).Length
            $heartbeatFinalCursor.last_sequence =
                [int64]$heartbeatCursor.last_sequence
            $heartbeatFinalCursor.trailing_partial =
                [bool]$heartbeatCursor.trailing_partial
            $heartbeatFinalCursor.terminal_read_state = 'CONFLICT'
            $allConflicts.Add($_.Exception.Message)
            $null = Add-Stage1EHostFailure $failureState 'BLOCKED' `
                'EVIDENCE_INCOMPLETE' 'HEARTBEAT_TERMINAL_READ_FAILED' `
                'HOST_OBSERVER' 'TERMINATION' $authorizationEffect `
                $processEffect 'PARTIAL_PRESERVED' `
                'RETRY_PROHIBITED_PENDING_RUNTIME_FIX' `
                "The final bounded heartbeat read failed: $($_.Exception.Message)" `
                ([object[]]@($LauncherRequest.heartbeat_path))
            $launcherState = 'PROCESS_OBSERVATION_LOST'
        }
    }

    if ($failureState.first_failure -is
        [System.Collections.IDictionary]) {
        $terminalStatus = [string]$failureState.first_failure.terminal_status
        if ($resumeCount -gt 0 -and
            $authorizationEffect -ceq 'NOT_TOUCHED') {
            $authorizationEffect = 'STATE_UNKNOWN'
        }
    }
    else {
        $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
            'DEADLINE_CANCELLED' 'TOTAL_LIFETIME' `
            $LauncherRequest.total_lifetime_timeout_ms $totalStart `
            $stopwatch 'CANCELLED' $false `
            'The complete contained process tree exited before total lifetime.' `
            $LauncherRequest.timeout_event_journal_path `
            $LauncherRequest.journal_root $hostContract
        if ([bool]$LauncherRequest.heartbeat_required) {
            $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                'DEADLINE_CANCELLED' 'HEARTBEAT_SILENCE' `
                $LauncherRequest.heartbeat_silence_timeout_ms `
                $lastHeartbeatElapsed $stopwatch 'CANCELLED' $false `
                'Heartbeat supervision ended at complete process-tree exit.' `
                $LauncherRequest.timeout_event_journal_path `
                $LauncherRequest.journal_root $hostContract
        }
    }

    foreach ($deadlineKind in @(
            'TOTAL_LIFETIME', 'STARTUP', 'CHILD_DISCOVERY',
            'HEARTBEAT_SILENCE')) {
        $armed = @($timeoutEvents | Where-Object {
                $_.event_type -ceq 'DEADLINE_ARMED' -and
                $_.deadline_kind -ceq $deadlineKind
            })
        $closed = @($timeoutEvents | Where-Object {
                $_.deadline_kind -ceq $deadlineKind -and
                $_.event_type -in @(
                    'DEADLINE_CANCELLED', 'DEADLINE_EXPIRED')
            })
        if ($armed.Count -gt $closed.Count) {
            $lastArmed = $armed[$armed.Count - 1]
            $null = Add-Stage1EHostTimeoutEvent $timeoutEvents `
                'DEADLINE_CANCELLED' $deadlineKind `
                $lastArmed.configured_budget_ms $lastArmed.start_elapsed_ms `
                $stopwatch 'CANCELLED' $false `
                'The armed deadline closed at the explicit Host Plane terminal state.' `
                $LauncherRequest.timeout_event_journal_path `
                $LauncherRequest.journal_root $hostContract
        }
    }

    $terminalEventType = if ($terminalTreeState -ceq 'TERMINAL') {
        'PROCESS_TREE_TERMINAL'
    }
    elseif ($terminalTreeState -ceq 'OBSERVATION_LOST') {
        'OBSERVATION_LOST'
    }
    else { 'TERMINAL_STATE_UNKNOWN' }
    $null = Add-Stage1EHostProcessEvent $processEvents $terminalEventType `
        $stopwatch $lastInstances `
        'The Host Plane reached its explicit terminal observation state.' `
        $LauncherRequest.process_event_journal_path `
        $LauncherRequest.journal_root $hostContract

    $processLedger = [ordered]@{
        schema_version = 'stage1e-runtime-host-process-ledger-v1'
        ledger_state = 'APPEND_ONLY_TERMINAL'
        request_identity = [string]$LauncherRequest.request_identity
        execution_id = [string]$LauncherRequest.execution_id
        attempt_id = [string]$LauncherRequest.attempt_id
        creation_attempt_count = [int64]$creationAttemptCount
        resume_count = [int64]$resumeCount
        execution_process_limit = [int64]$executionProcessLimit
        root_process_id = $rootProcessId
        events = [object[]]$processEvents.ToArray()
        job_events = [object[]]$lastJobEvents
        observed_instance_count = [int64]$maxObservedInstances
        terminal_snapshot_process_ids =
            [object[]]$terminalSnapshotProcessIds
        terminal_tree_state = $terminalTreeState
        heartbeat_final_cursor = $heartbeatFinalCursor
        authority_boundary = Get-Stage1EHostAuthorityBoundary
    }
    $timeoutLedger = [ordered]@{
        schema_version =
            'stage1e-runtime-host-timeout-termination-ledger-v1'
        ledger_state = 'APPEND_ONLY_TERMINAL'
        request_identity = [string]$LauncherRequest.request_identity
        execution_id = [string]$LauncherRequest.execution_id
        attempt_id = [string]$LauncherRequest.attempt_id
        first_failure_ordinal = if ($failureState.first_failure -is
            [System.Collections.IDictionary]) {
            [int64]$failureState.first_failure.first_failure_ordinal
        }
        else { 'NONE' }
        events = [object[]]$timeoutEvents.ToArray()
        terminal_termination_state = $terminationDisposition
        authority_boundary = Get-Stage1EHostAuthorityBoundary
    }
    $publications.process_ledger = Publish-Stage1EHostRecord `
        -Role process_ledger -Record $processLedger `
        -LiteralPath $LauncherRequest.process_ledger_path `
        -BoundaryPath $LauncherRequest.evidence_root -Contract $hostContract
    $publications.timeout_ledger = Publish-Stage1EHostRecord `
        -Role timeout_ledger -Record $timeoutLedger `
        -LiteralPath $LauncherRequest.timeout_termination_ledger_path `
        -BoundaryPath $LauncherRequest.evidence_root -Contract $hostContract

    $preflightEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.preflight_result_path
    $processLedgerEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.process_ledger_path
    $processJournalEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.process_event_journal_path
    $timeoutLedgerEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.timeout_termination_ledger_path
    $timeoutJournalEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.timeout_event_journal_path
    $heartbeatEvidence = if ([bool]$heartbeatFinalCursor.trailing_partial) {
        Get-Stage1EHostEvidenceFileObservation `
            $LauncherRequest.heartbeat_path -OverrideStatus PARTIAL
    }
    else {
        Get-Stage1EHostEvidenceFileObservation `
            $LauncherRequest.heartbeat_path
    }
    $stdoutEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.stdout_path
    $stderrEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.stderr_path
    $vivadoEvidence = Get-Stage1EHostEvidenceFileObservation `
        $LauncherRequest.expected_vivado_result_path
    $evidenceRecords = @(
        $preflightEvidence, $processLedgerEvidence, $processJournalEvidence,
        $timeoutLedgerEvidence, $timeoutJournalEvidence, $heartbeatEvidence,
        $stdoutEvidence, $stderrEvidence, $vivadoEvidence)
    $evidenceState = if ([bool]$heartbeatFinalCursor.trailing_partial -or
        [string]$heartbeatFinalCursor.terminal_read_state -ceq 'CONFLICT') {
        'PARTIAL_PRESERVED'
    }
    elseif (@($evidenceRecords |
            Where-Object { $_.status -cne 'PRESENT' }).Count -eq 0) {
        'COMPLETE'
    }
    else { 'PARTIAL_PRESERVED' }
    $hostResult = [ordered]@{
        schema_version = 'stage1e-runtime-host-component-result-v1'
        result_state = 'SEALED'
        request_identity = [string]$LauncherRequest.request_identity
        execution_id = [string]$LauncherRequest.execution_id
        attempt_id = [string]$LauncherRequest.attempt_id
        runtime_backend_identity =
            [string]$LauncherRequest.runtime_backend_identity
        workspace_identity = [string]$LauncherRequest.workspace_identity
        launcher_state = $launcherState
        terminal_status = $terminalStatus
        process_effect = $processEffect
        authorization_effect = $authorizationEffect
        creation_attempt_count = [int64]$creationAttemptCount
        resume_count = [int64]$resumeCount
        execution_process_limit = [int64]$executionProcessLimit
        root_process_id = $rootProcessId
        exit_code = $exitCode
        termination_disposition = $terminationDisposition
        evidence_state = $evidenceState
        heartbeat_final_cursor = $heartbeatFinalCursor
        first_failure = $failureState.first_failure
        secondary_failures =
            [object[]]$failureState.secondary_failures.ToArray()
        preflight_observation = $preflightEvidence
        process_ledger = $processLedgerEvidence
        process_event_journal = $processJournalEvidence
        timeout_termination_ledger = $timeoutLedgerEvidence
        timeout_event_journal = $timeoutJournalEvidence
        heartbeat_journal = $heartbeatEvidence
        stdout_capture = $stdoutEvidence
        stderr_capture = $stderrEvidence
        vivado_component_result = $vivadoEvidence
        conflicts = [object[]]@($allConflicts.ToArray() |
            Select-Object -Unique)
        acceptance_decision = 'NOT_OWNED'
        authority_boundary = Get-Stage1EHostAuthorityBoundary
    }
    $null = Assert-Stage1EHostRecord -Role host_result -Record $hostResult `
        -Contract $hostContract
    $publications.host_result = Publish-Stage1EHostRecord `
        -Role host_result -Record $hostResult `
        -LiteralPath $LauncherRequest.host_result_path `
        -BoundaryPath $LauncherRequest.evidence_root -Contract $hostContract
    if ($null -ne $process) {
        Close-Stage1EWindowsControlledProcess -Process $process
        $process = $null
    }
    $stopwatch.Stop()
    return [ordered]@{
        interface_version = $script:Stage1EProductionRuntimeLauncherInterface
        terminal_result = $hostResult
        process_ledger = $processLedger
        timeout_termination_ledger = $timeoutLedger
        publications = $publications
    }
    }
    finally {
        if ($null -ne $process) {
            try { Close-Stage1EWindowsControlledProcess -Process $process }
            finally { $process = $null }
        }
        if ($stopwatch.IsRunning) { $stopwatch.Stop() }
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EProductionRuntimeLauncherInterfaceVersion'
    'Invoke-Stage1EProductionRuntimeLauncher'
)
