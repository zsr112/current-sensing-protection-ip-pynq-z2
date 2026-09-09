[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$ExpectedRequestIdentity
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Stage1EEntrypointInterface =
    'stage1e-production-runtime-entrypoint-contract-v3'
$script:Stage1EExitPublished = 0
$script:Stage1EExitBlocked = 20

function Get-Stage1EProductionRuntimeEntrypointV3InterfaceVersion {
    return $script:Stage1EEntrypointInterface
}

function Get-Stage1EEntrypointRepositoryRoot {
    return [System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '../../../../../..'))
}

function ConvertTo-Stage1ETclBase64 {
    param([Parameter(Mandatory = $true)][string]$Value)

    return [Convert]::ToBase64String(
        [System.Text.UTF8Encoding]::new($false).GetBytes($Value))
}

function New-Stage1EVivadoBootstrap {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context,
        [Parameter(Mandatory = $true)][string]$BootstrapPath,
        [Parameter(Mandatory = $true)][string]$RunnerPath
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Generated only from the sealed Stage 1E request.')
    if ($env:CSIP_BOARD_REPO) {
        $boardRepoEncoded = ConvertTo-Stage1ETclBase64 $env:CSIP_BOARD_REPO.Replace('\', '/')
        $lines.Add(('set_param board.repoPaths [list [encoding convertfrom utf-8 [binary decode base64 {{{0}}}]]]' -f $boardRepoEncoded))
    }
    $lines.Add('set stage1e_execution_context [dict create]')
    foreach ($key in $Context.Keys) {
        $encoded = ConvertTo-Stage1ETclBase64 ([string]$Context[$key])
        $lines.Add((
            'dict set stage1e_execution_context {0} [encoding convertfrom utf-8 [binary decode base64 {{{1}}}]]' -f
                $key, $encoded))
    }
    $runnerEncoded = ConvertTo-Stage1ETclBase64 $RunnerPath.Replace('\', '/')
    $lines.Add((
        'set stage1e_runner_path [encoding convertfrom utf-8 [binary decode base64 {{{0}}}]]' -f
            $runnerEncoded))
    $lines.Add('source $stage1e_runner_path')
    $lines.Add('::stage1e::production_vivado_runner_v2::run $stage1e_execution_context')
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        (($lines -join "`n") + "`n"))
    New-Stage1EExecutionFile -LiteralPath $BootstrapPath -Bytes $bytes
}

function Import-Stage1ETerminalResultContract {
    param([Parameter(Mandatory = $true)][string]$BuildRoot)

    $schemaPath = Join-Path $BuildRoot 'config/stage1e_terminal_result_schema_v1.json'
    $schema = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes (
        [System.IO.File]::ReadAllBytes($schemaPath))
    return [ordered]@{
        schema = $schema
        registry = [ordered]@{ 'stage1e-terminal-result-v1' = $schema }
    }
}

function New-Stage1ETerminalResultRecord {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Request,
        [Parameter(Mandatory = $true)][string]$TerminalStatus,
        [Parameter(Mandatory = $true)][string]$FailureCode,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][string]$SourceState,
        [Parameter(Mandatory = $true)][string]$ProcessState,
        [Parameter(Mandatory = $true)][string]$ProcessExitCode,
        [Parameter(Mandatory = $true)][string]$VivadoResultState,
        [Parameter(Mandatory = $true)][string]$GuiProjectPath,
        [Parameter(Mandatory = $true)][bool]$SynthRunAvailable,
        [Parameter(Mandatory = $true)][bool]$ImplRunAvailable,
        [Parameter(Mandatory = $true)][bool]$ProjectSafeToOpen,
        [Parameter(Mandatory = $true)][string]$AcceptanceState
    )

    return [ordered]@{
        schema_version = 'stage1e-terminal-result-v1'
        terminal_result_identity = ('a' * 64)
        execution_id = [string]$Request.execution_id
        request_identity = [string]$Request.request_identity
        execution_contract_identity = [string]$Request.execution_contract_identity
        implementation_profile = [string]$Request.implementation_profile
        run_kind = [string]$Request.run_kind
        terminal_status = $TerminalStatus
        failure_code = $FailureCode
        reason = $Reason
        source_state = $SourceState
        process_state = $ProcessState
        process_exit_code = $ProcessExitCode
        vivado_result_state = $VivadoResultState
        GUI_PROJECT_PATH = $GuiProjectPath
        SYNTH_RUN_AVAILABLE = $SynthRunAvailable
        IMPL_RUN_AVAILABLE = $ImplRunAvailable
        PROJECT_SAFE_TO_OPEN = $ProjectSafeToOpen
        acceptance_state = $AcceptanceState
        finding_decision_identity = [string]$Request.finding_decision_identity
    }
}

function Publish-Stage1ETerminalResult {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $identityRecord = [ordered]@{}
    foreach ($key in $Record.Keys) {
        if ([string]$key -cne 'terminal_result_identity') {
            $identityRecord[[string]$key] = $Record[$key]
        }
    }
    $identityBytes = ConvertTo-Stage1ECanonicalJsonBytes -Value $identityRecord `
        -Schema $Contract.schema -SchemaRegistry $Contract.registry `
        -OmitProperty 'terminal_result_identity'
    $Record.terminal_result_identity = Get-Stage1ECanonicalDigest -Bytes $identityBytes
    $bytes = ConvertTo-Stage1ECanonicalJsonBytes -Value $Record `
        -Schema $Contract.schema -SchemaRegistry $Contract.registry
    New-Stage1EExecutionFile -LiteralPath $Path -Bytes $bytes
    Write-Output "terminal_result_path=$Path"
    Write-Output "terminal_result_identity=$($Record.terminal_result_identity)"
}

function Read-Stage1EVivadoResult {
    param(
        [Parameter(Mandatory = $true)][string]$BuildRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not [System.IO.File]::Exists($Path)) {
        throw 'The single Vivado process did not publish a terminal result.'
    }
    $schemaPath = Join-Path $BuildRoot 'config/stage1e_vivado_result_schema_v1.json'
    $schema = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes (
        [System.IO.File]::ReadAllBytes($schemaPath))
    $registry = [ordered]@{ 'stage1e-vivado-result-v1' = $schema }
    return ConvertFrom-Stage1ECanonicalJsonEnvelope -Bytes (
        [System.IO.File]::ReadAllBytes($Path)) -Schema $schema `
        -SchemaRegistry $registry
}

function Assert-Stage1EArtifactInventory {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$VivadoResult)

    $roles = @($VivadoResult.artifact_inventory | ForEach-Object {
            [string]$_.role
        })
    $expectedRoles = @('BITSTREAM', 'XSA', 'HWH', 'LTX', 'ARTIFACT_MANIFEST')
    if (($roles -join ',') -cne ($expectedRoles -join ',') -or
        @($roles | Select-Object -Unique).Count -ne $roles.Count) {
        throw 'ARTIFACTS requires the exact unique BITSTREAM, XSA, HWH, LTX, and ARTIFACT_MANIFEST roles.'
    }
}

$repositoryRoot = Get-Stage1EEntrypointRepositoryRoot
$buildRoot = Join-Path $repositoryRoot 'fpga/vivado/build'
$requestModule = Join-Path $PSScriptRoot 'stage1e_execution_request_v1.psm1'
$hostModule = Join-Path $PSScriptRoot 'stage1e_execution_host_v1.psm1'
$request = $null
$validation = $null
$terminalContract = $null
$terminalPath = $null

try {
    Import-Module -Name $requestModule -Force -ErrorAction Stop
    Import-Module -Name $hostModule -Force -ErrorAction Stop
    $canonicalModule = Join-Path $buildRoot 'lib/stage1e_runtime_canonical_json_v1.psm1'
    Import-Module -Name $canonicalModule -Force -ErrorAction Stop
    $schemaVersion = (Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json).schema_version
    $requestContract = Import-Stage1EExecutionRequestContract -BuildRoot $buildRoot -SchemaVersion $schemaVersion
    $request = Read-Stage1EExecutionRequest -RequestPath $RequestPath `
        -ExpectedRequestIdentity $ExpectedRequestIdentity -Contract $requestContract
    $validation = Assert-Stage1EExecutionRequest -Request $request `
        -RepositoryRoot $repositoryRoot -BuildRoot $buildRoot
    $terminalContract = Import-Stage1ETerminalResultContract -BuildRoot $buildRoot

    $null = [System.IO.Directory]::CreateDirectory($validation.workspace_root)
    $null = [System.IO.Directory]::CreateDirectory($validation.output_root)
    $projectRoot = Join-Path $validation.workspace_root 'project'
    $null = [System.IO.Directory]::CreateDirectory($projectRoot)
    $reportRoot = Join-Path $validation.output_root 'reports'
    $artifactRoot = Join-Path $validation.output_root 'artifacts'
    $logRoot = Join-Path $validation.output_root 'logs'
    $journalRoot = Join-Path $validation.output_root 'journal'
    foreach ($directory in @($reportRoot, $artifactRoot, $logRoot, $journalRoot)) {
        $null = [System.IO.Directory]::CreateDirectory($directory)
    }

    $terminalPath = Join-Path $validation.output_root 'terminal_result.json'
    $stdoutPath = Join-Path $logRoot 'vivado.stdout.log'
    $stderrPath = Join-Path $logRoot 'vivado.stderr.log'
    $journalPath = Join-Path $journalRoot 'host-process.tsv'
    New-Stage1EExecutionFile -LiteralPath $journalPath -Bytes (
        [System.Text.UTF8Encoding]::new($false).GetBytes(
            "utc_timestamp`tstate`tdetail`n"))
    $context = New-Stage1EVivadoExecutionContext -Request $request `
        -Validation $validation
    $bootstrapPath = Join-Path $validation.workspace_root 'stage1e_execution_bootstrap.tcl'
    $runnerPath = Join-Path $buildRoot 'runtime/runner/stage1e_production_vivado_runner_v2.tcl'
    New-Stage1EVivadoBootstrap -Context $context -BootstrapPath $bootstrapPath `
        -RunnerPath $runnerPath
    $processResult = Invoke-Stage1EExecutionProcess `
        -Executable $validation.vivado_executable `
        -ArgumentList @('-mode', 'batch', '-source', $bootstrapPath) `
        -WorkingDirectory $validation.workspace_root -StdoutPath $stdoutPath `
        -StderrPath $stderrPath -JournalPath $journalPath `
        -TimeoutSeconds ([int]$request.timeout_seconds)

    if ([string]$processResult.state -cne 'COMPLETED') {
        throw "Process supervision ended in $($processResult.state)."
    }
    if ([string]$processResult.exit_code -cne '0') {
        throw "The controlled Vivado process exited with $($processResult.exit_code)."
    }
    if ($request.source.Contains('export_manifest_sha256')) {
        Assert-Stage1EExportSource -RepositoryRoot $repositoryRoot -Source $request.source
    }
    $vivadoResult = Read-Stage1EVivadoResult -BuildRoot $buildRoot `
        -Path (Join-Path $validation.output_root 'vivado_result.json')
    if ([string]$vivadoResult.execution_id -cne [string]$request.execution_id -or
        [string]$vivadoResult.request_identity -cne [string]$request.request_identity -or
        [string]$vivadoResult.implementation_profile -cne
            [string]$request.implementation_profile -or
        [string]$vivadoResult.execution_contract_identity -cne
            [string]$request.execution_contract_identity) {
        throw 'The Vivado terminal result does not bind the sealed request.'
    }
    if ([string]$vivadoResult.result_state -cne 'COMPLETED' -or
        -not [bool]$vivadoResult.route_completed -or
        [int]$vivadoResult.forbidden_operation_count -ne 0 -or
        [string]$vivadoResult.collector_state -cne 'COLLECTED') {
        throw 'The Vivado result is incomplete, conflicted, or observed a forbidden operation.'
    }
    if ([string]$request.build_target -ceq 'ARTIFACTS') {
        Assert-Stage1EArtifactInventory $vivadoResult
    }
    $disposition = Resolve-Stage1EExecutionTerminalDisposition -Request $request `
        -ProcessResult $processResult -VivadoResult $vivadoResult
    $record = New-Stage1ETerminalResultRecord -Request $request `
        -TerminalStatus $disposition.terminal_status -FailureCode 'NONE' `
        -Reason $disposition.reason -SourceState $validation.source_state `
        -ProcessState $processResult.state `
        -ProcessExitCode $processResult.exit_code `
        -VivadoResultState $vivadoResult.result_state `
        -GuiProjectPath ([string]$vivadoResult.GUI_PROJECT_PATH) `
        -SynthRunAvailable ([bool]$vivadoResult.SYNTH_RUN_AVAILABLE) `
        -ImplRunAvailable ([bool]$vivadoResult.IMPL_RUN_AVAILABLE) `
        -ProjectSafeToOpen ([bool]$vivadoResult.PROJECT_SAFE_TO_OPEN) `
        -AcceptanceState $disposition.acceptance_state
    Publish-Stage1ETerminalResult -Record $record -Contract $terminalContract `
        -Path $terminalPath
    exit $script:Stage1EExitPublished
}
catch {
    $reason = $_.Exception.Message
    if ($null -ne $request -and $null -ne $validation -and
        $null -ne $terminalContract -and $null -ne $terminalPath -and
        -not [System.IO.File]::Exists($terminalPath)) {
        $record = New-Stage1ETerminalResultRecord -Request $request `
            -TerminalStatus 'BLOCKED' -FailureCode 'EXECUTION_BLOCKED' `
            -Reason $reason -SourceState $validation.source_state `
            -ProcessState 'BLOCKED_OR_FAILED' -ProcessExitCode 'UNAVAILABLE' `
            -VivadoResultState 'UNAVAILABLE' -GuiProjectPath 'UNAVAILABLE' `
            -SynthRunAvailable $false -ImplRunAvailable $false `
            -ProjectSafeToOpen $false -AcceptanceState 'NOT_ACCEPTED'
        try {
            Publish-Stage1ETerminalResult -Record $record -Contract $terminalContract `
                -Path $terminalPath
        }
        catch {
            Write-Error "Unable to publish terminal result: $($_.Exception.Message)"
        }
    }
    Write-Error "Stage 1E execution blocked: $reason"
    exit $script:Stage1EExitBlocked
}
