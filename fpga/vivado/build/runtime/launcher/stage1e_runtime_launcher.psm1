Set-StrictMode -Version Latest

$script:Stage1EAllowedOperations = @(
    'opt_design'
    'place_design'
    'route_design'
    'implementation_reports'
)

function Assert-Stage1ESha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Value -notmatch '^[0-9a-fA-F]{64}$' -or
        $Value -eq ('0' * 64)) {
        throw "$Label is not a non-placeholder SHA-256 identity."
    }
}

function Assert-Stage1EExactKeys {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Record,
        [Parameter(Mandatory = $true)][string[]]$Keys,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $actual = @($Record.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $expected = @($Keys | Sort-Object)
    if (($actual -join "`n") -ne ($expected -join "`n")) {
        throw "$Label fields differ."
    }
    foreach ($key in $Keys) {
        if ($null -eq $Record[$key] -or [string]::IsNullOrWhiteSpace(
                [string]$Record[$key])) {
            throw "$Label has an empty field: $key"
        }
    }
}

function Test-Stage1ERuntimeLaunchRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Request)

    $required = @(
        'schema_version'
        'mode'
        'requested_operations'
        'cwd'
        'runtime_backend_identity'
        'policy_identity'
        'configuration_identity'
        'authorization_state'
        'artifact_authority'
        'board_authority'
    )
    Assert-Stage1EExactKeys -Record $Request -Keys $required `
        -Label 'Runtime launch request'

    if ($Request.schema_version -ne 'stage1e-runtime-launch-request-v1') {
        throw 'Runtime launch request schema mismatch.'
    }
    if ($Request.mode -ne 'MOCK_ONLY') {
        throw 'Production runtime dispatch is unavailable.'
    }
    if ($Request.authorization_state -ne 'NOT_APPLICABLE_MOCK') {
        throw 'The mock launcher cannot consume or represent authorization.'
    }
    if ($Request.artifact_authority -ne 'NONE' -or
        $Request.board_authority -ne 'NONE') {
        throw 'Artifact and board authority must remain NONE.'
    }
    if ((@($Request.requested_operations) -join "`n") -ne
        ($script:Stage1EAllowedOperations -join "`n")) {
        throw 'Requested operation graph is not the fixed Stage 1E graph.'
    }
    foreach ($field in @(
            'runtime_backend_identity',
            'policy_identity',
            'configuration_identity')) {
        Assert-Stage1ESha256 -Value ([string]$Request[$field]) -Label $field
    }
    if (-not (Test-Path -LiteralPath $Request.cwd -PathType Container)) {
        throw 'Runtime launch cwd does not exist.'
    }

    return $true
}

function Invoke-Stage1ERuntimeLauncherMock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Request,
        [Parameter(Mandatory = $true)][scriptblock]$ProcessInvoker,
        [Parameter(Mandatory = $true)][scriptblock]$EnvironmentObserver
    )

    $null = Test-Stage1ERuntimeLaunchRequest -Request $Request
    $resolvedCwd = (Resolve-Path -LiteralPath $Request.cwd).Path
    $environment = & $EnvironmentObserver $resolvedCwd $Request
    if ($environment -isnot [hashtable]) {
        throw 'Environment observer did not return a hashtable.'
    }
    Assert-Stage1EExactKeys -Record $environment -Keys @(
        'status', 'environment_identity', 'cwd', 'xil_path',
        'launcher_lifetime', 'child_process_observation',
        'dispatch_monitoring'
    ) -Label 'Environment observation'
    if ($environment.status -ne 'CURRENT') {
        throw 'Environment observation is stale or incomplete.'
    }
    Assert-Stage1ESha256 -Value $environment.environment_identity `
        -Label 'environment_identity'

    $process = & $ProcessInvoker $resolvedCwd $Request
    if ($process -isnot [hashtable]) {
        throw 'Mock process invoker did not return a hashtable.'
    }
    Assert-Stage1EExactKeys -Record $process -Keys @(
        'status', 'exit_code', 'child_process_observed',
        'dispatch_monitoring', 'stdout', 'stderr'
    ) -Label 'Mock process observation'

    return [ordered]@{
        schema_version = 'stage1e-runtime-launch-result-v1'
        mode = 'MOCK_ONLY'
        status = [string]$process.status
        resolved_cwd = $resolvedCwd
        environment = $environment
        process = $process
        authorization_consumption = 'NOT_OWNED'
        acceptance_decision = 'NOT_OWNED'
        artifact_authority = 'NONE'
        board_authority = 'NONE'
    }
}

Export-ModuleMember -Function @(
    'Test-Stage1ERuntimeLaunchRequest'
    'Invoke-Stage1ERuntimeLauncherMock'
)
