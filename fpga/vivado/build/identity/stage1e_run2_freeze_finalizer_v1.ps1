[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('PREVIEW_ONLY','ISSUE_SOURCE_FREEZE_REVIEW',
        'ISSUE_RUNTIME_REVIEW_AND_QUALIFICATION')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ExpectedApprovedCommit,

    [Parameter(Mandatory = $true)]
    [string]$RepositoryRoot,

    [Parameter(Mandatory = $true)]
    [string]$GitExecutablePath,

    [Parameter(Mandatory = $true)]
    [string]$HumanDecisionRecordPath,

    [Parameter(Mandatory = $true)]
    [string]$FreezeEvidenceRoot,

    [string]$HumanAuthorityRecordPath = '',

    [string]$AcceptedPreviewRoot = '',

    [string]$SourceFreezeReviewRecordPath = '',

    [string]$Q5LiveClosureEvidencePath = '',

    [string]$QualificationExecutionId = '',

    [string]$WorkspaceIdentity = ''
)

$ErrorActionPreference = 'Stop'
Microsoft.PowerShell.Core\Set-StrictMode -Version Latest

$builtInProviderManifests = [object[]]@(
    [System.IO.Path]::Combine([string]$PSHOME,
        'Modules\Microsoft.PowerShell.Management\Microsoft.PowerShell.Management.psd1')
    [System.IO.Path]::Combine([string]$PSHOME,
        'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
)
foreach ($manifest in $builtInProviderManifests) {
    if (-not [System.IO.File]::Exists($manifest)) {
        throw "FINALIZER_BUILTIN_PROVIDER_UNAVAILABLE: $manifest"
    }
    Microsoft.PowerShell.Core\Import-Module -Name $manifest -ErrorAction Stop
}

$script:Stage1EFinalizerAliasConflictNames = [string[]]@(
    'Assert-Stage1EAcceptedPreview'
    'Assert-Stage1ECanonicalRelativePath'
    'Assert-Stage1ECorrectionEvidenceOutput'
    'Assert-Stage1EFindingSelectionContracts'
    'Assert-Stage1EFreezeReviewBinding'
    'Assert-Stage1EHumanDecisionCoverage'
    'ConvertFrom-Stage1ECanonicalJsonBytes'
    'ConvertFrom-Stage1ECanonicalJsonEnvelope'
    'ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes'
    'ConvertTo-Stage1EUtf8Bytes'
    'Get-Stage1EFinalizerProviderCommand'
    'Get-Stage1EPreviewReviewIdentity'
    'Get-Stage1EProtectedSourceSummary'
    'Get-Stage1ESha256Hex'
    'Import-Module'
    'Import-Stage1EFinalizerProviders'
    'Invoke-Stage1EFinalizerIdentityProvider'
    'Invoke-Stage1EGitText'
    'Join-Path'
    'New-Stage1ERuntimeBackendIdentityV2Candidate'
    'Publish-Stage1EAtomicAuthoritySet'
    'Read-Stage1EQualificationRecord'
    'Read-Stage1EHumanDecisionRecord'
    'Resolve-Stage1EExternalNewRoot'
    'Resolve-Stage1EGitExecutablePath'
    'Set-StrictMode'
    'Write-Stage1ENewBytes'
    'git'
)
$ambientAliasConflicts = [System.Collections.Generic.List[string]]::new()
foreach ($name in $script:Stage1EFinalizerAliasConflictNames) {
    $aliasItem = Microsoft.PowerShell.Management\Get-Item `
        -LiteralPath ('Alias:' + $name) -ErrorAction SilentlyContinue
    if ($null -ne $aliasItem) {
        $ambientAliasConflicts.Add($name)
    }
}
if ($ambientAliasConflicts.Count -ne 0) {
    throw ('FINALIZER_AMBIENT_ALIAS_CONFLICT: ' +
        ($ambientAliasConflicts -join ', '))
}

$importTimeFunctionConflicts = [System.Collections.Generic.List[string]]::new()
foreach ($name in [string[]]@('Set-StrictMode','Import-Module')) {
    $functionItem = Microsoft.PowerShell.Management\Get-Item `
        -LiteralPath ('Function:' + $name) `
        -ErrorAction SilentlyContinue
    if ($null -ne $functionItem) {
        $importTimeFunctionConflicts.Add($name)
    }
}
if ($importTimeFunctionConflicts.Count -ne 0) {
    throw ('FINALIZER_IMPORT_TIME_FUNCTION_CONFLICT: ' +
        ($importTimeFunctionConflicts -join ', '))
}
$script:Stage1EFinalizerCommandResolutionGuardsEstablished = $true

$script:ProductionFinalizationState = 'NOT_AUTHORIZED'
$script:ApprovedPrt04Inventory = [object[]]@(
    'docs/design/stage1e_implementation_policy_v3.md'
    'docs/handoff/stage1e_prt04_run1_finding_human_review_packet_v1.md'
    'docs/handoff/stage1e_prt04_run2_freeze_candidate_execution_report_v1.md'
    'docs/handoff/stage1e_prt04_run2_freeze_review_packet_v1.md'
    'fpga/vivado/build/config/stage1e_implementation_configuration_v3.dict'
    'fpga/vivado/build/config/stage1e_implementation_warning_policy_v3.dict'
    'fpga/vivado/build/config/stage1e_phase3_implementation_framework_v3.dict'
    'fpga/vivado/build/config/stage1e_run1_finding_inventory_v1.json'
    'fpga/vivado/build/config/stage1e_run2_freeze_review_candidate_v1.json'
    'fpga/vivado/build/identity/stage1e_run2_freeze_finalizer_v1.ps1'
    'fpga/vivado/build/identity/stage1e_runtime_backend_identity_v2.psm1'
    'fpga/vivado/build/lib/stage1e_run1_human_decision_record_v1.schema.json'
    'fpga/vivado/build/lib/stage1e_runtime_backend_identity_v2.schema.json'
    'fpga/vivado/build/runtime/README.md'
    'fpga/vivado/build/tests/stage1e_prt02_evidence_static_tests.tcl'
    'fpga/vivado/build/tests/stage1e_prt02_host_static_tests.ps1'
    'fpga/vivado/build/tests/stage1e_prt04_freeze_candidate_tests.ps1'
    'fpga/vivado/build/tests/stage1e_prt04_runtime_backend_identity_v2_tests.tcl'
    'fpga/vivado/build/tests/stage1e_runtime_regression_tests.ps1'
)

function Resolve-Stage1EGitExecutablePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
            $Path) -or
        -not [System.IO.Path]::IsPathRooted($Path)) {
        throw 'FINALIZER_GIT_EXECUTABLE_PATH_INVALID: require a literal absolute path.'
    }
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolved.Equals($Path,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'FINALIZER_GIT_EXECUTABLE_PATH_NOT_NORMALIZED'
    }
    if (-not [System.IO.File]::Exists($resolved)) {
        throw "FINALIZER_GIT_EXECUTABLE_NOT_FOUND: $resolved"
    }
    $file = [System.IO.FileInfo]::new($resolved)
    if (($file.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
        ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
        -not $file.Extension.Equals('.exe',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "FINALIZER_GIT_EXECUTABLE_NOT_REGULAR: $resolved"
    }
    return $resolved
}

function Invoke-Stage1EGitText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = [object[]]@(
            & $script:Stage1EFinalizerGitExecutablePath `
                -C $Root @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Git command failed ($exitCode): $script:Stage1EFinalizerGitExecutablePath $($Arguments -join ' '); $($output -join ' ')"
    }
    $textLines = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $output) {
        $textLines.Add([string]$item)
    }
    return [ordered]@{
        exit_code = $exitCode
        lines = $output
        text = (($textLines.ToArray()) -join "`n").Trim()
    }
}

function Get-Stage1EProtectedSourceSummary {
    param([Parameter(Mandatory = $true)][string]$Root)

    $acceptedCommits = [object[]]@(
        '6e270d6', 'fcf86a4', '961fb01', 'de49682', '809d175', 'a8c133f')
    $excludedIntegration = [object[]]@(
        'fpga/vivado/build/runtime/README.md'
        'fpga/vivado/build/tests/stage1e_runtime_regression_tests.ps1'
        'fpga/vivado/build/tests/stage1e_prt02_host_static_tests.ps1'
        'fpga/vivado/build/tests/stage1e_prt02_evidence_static_tests.tcl'
    )
    $paths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($commit in $acceptedCommits) {
        $changed = Invoke-Stage1EGitText $Root @(
            'diff-tree','--no-commit-id','--name-only','-r',$commit)
        foreach ($pathValue in $changed.lines) {
            $path = ([string]$pathValue).Trim().Replace('\','/')
            if (-not [string]::IsNullOrEmpty($path) -and
                $excludedIntegration -cnotcontains $path) {
                $null = $paths.Add($path)
            }
        }
    }
    if ($paths.Count -ne 106) {
        throw "Protected PRT02/PRT03 inventory differs: $($paths.Count)"
    }

    $mismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
        $fullPath = [System.IO.Path]::Combine($Root, $path.Replace('/', '\'))
        if (-not [System.IO.File]::Exists($fullPath)) {
            $mismatches.Add($path)
            continue
        }
        $headBlob = Invoke-Stage1EGitText $Root @('rev-parse',"HEAD:$path") `
            -AllowFailure
        $worktreeBlob = Invoke-Stage1EGitText $Root @(
            'hash-object','--',$fullPath) -AllowFailure
        if ($headBlob.exit_code -ne 0 -or $worktreeBlob.exit_code -ne 0 -or
            $headBlob.text -cne $worktreeBlob.text) {
            $mismatches.Add($path)
        }
    }
    if ($mismatches.Count -ne 0) {
        throw "Protected PRT02/PRT03 bytes differ: $($mismatches -join ', ')"
    }
    return [ordered]@{
        checked_count = [int64]$paths.Count
        mismatch_count = [int64]$mismatches.Count
    }
}

function Assert-Stage1ECanonicalRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf('\') -ge 0 -or
        $Path.StartsWith('/') -or $Path.IndexOf(':') -ge 0) {
        throw "Inventory path is not canonical and relative: $Path"
    }
    foreach ($segment in $Path.Split('/')) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -ceq '.' -or
            $segment -ceq '..') {
            throw "Inventory path has a prohibited segment: $Path"
        }
    }
}

function Resolve-Stage1EExternalNewRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    if (-not [System.IO.Path]::IsPathRooted($Root) -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
            $Root)) {
        throw 'AUTHORITY_OUTPUT_ROOT_INVALID'
    }
    $resolved = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $repositoryResolved = [System.IO.Path]::GetFullPath($Repository).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $repositoryPrefix = $repositoryResolved +
        [System.IO.Path]::DirectorySeparatorChar
    if ($resolved.Equals($repositoryResolved,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith($repositoryPrefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'AUTHORITY_OUTPUT_ROOT_INSIDE_REPOSITORY'
    }
    if ([System.IO.Directory]::Exists($resolved) -or
        [System.IO.File]::Exists($resolved)) {
        throw 'AUTHORITY_OUTPUT_ROOT_ALREADY_EXISTS'
    }
    return $resolved
}

function Write-Stage1ENewBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $stream = [System.IO.FileStream]::new($Path,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}

function ConvertTo-Stage1EUtf8Bytes {
    param([Parameter(Mandatory = $true)][string]$Text)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    return $encoding.GetBytes($Text)
}

function Read-Stage1EHumanDecisionRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedCommit,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
            $Path) -or
        -not [System.IO.Path]::IsPathRooted($Path)) {
        throw 'HUMAN_DECISION_RECORD_PATH_INVALID'
    }
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($resolvedPath)) {
        throw 'HUMAN_DECISION_RECORD_MISSING'
    }
    $decisionBytes = [System.IO.File]::ReadAllBytes($resolvedPath)
    $schemaBytes = [System.IO.File]::ReadAllBytes($SchemaPath)
    $schema = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes $schemaBytes
    $registry = [ordered]@{}
    $registry.Add('stage1e-run1-human-decision-record-v1', $schema)
    $record = ConvertFrom-Stage1ECanonicalJsonEnvelope -Bytes $decisionBytes `
        -Schema $schema -SchemaRegistry $registry
    if ([string]$record.approved_commit -cne $ExpectedCommit) {
        throw 'Human decision record is bound to a different approved commit.'
    }
    if ([string]$record.approved_commit -notmatch '^[0-9a-f]{40}$') {
        throw 'Human decision record commit is not canonical.'
    }
    return [ordered]@{
        record = $record
        bytes = $decisionBytes
        sha256 = Get-Stage1ESha256Hex -Bytes $decisionBytes
    }
}

function Assert-Stage1EFindingSelectionContracts {
    param([Parameter(Mandatory = $true)]$FindingInventory)

    foreach ($finding in $FindingInventory.findings) {
        $identifier = [string]$finding.stable_identifier
        $hasAllowed = if ($finding -is [System.Collections.IDictionary]) {
            $finding.Contains('allowed_human_selections')
        }
        else {
            $null -ne $finding.PSObject.Properties['allowed_human_selections']
        }
        if (-not $hasAllowed) {
            throw "Finding lacks allowed_human_selections: $identifier"
        }

        $route = [string]$finding.proposed_engineering_route
        if (-not [bool]$finding.human_decision_required) {
            $expected = [object[]]@()
        }
        elseif ($route -ceq 'ACCEPT_CANDIDATE') {
            $expected = [object[]]@(
                'ACCEPT_WITH_EXACT_CONTRACT', 'REJECT_AND_FIX', 'DEFER_BLOCKING')
        }
        elseif ($route -ceq 'FIX_REQUIRED' -or
            $route -ceq 'EVIDENCE_INSUFFICIENT') {
            $expected = [object[]]@('REJECT_AND_FIX', 'DEFER_BLOCKING')
        }
        else {
            throw "Finding route has no accepted selection contract: $identifier"
        }
        $actual = [object[]]@($finding.allowed_human_selections)
        if ($actual.Count -ne $expected.Count) {
            throw "Finding has an incorrect allowed-selection count: $identifier"
        }
        for ($index = 0; $index -lt $expected.Count; $index++) {
            if ([string]$actual[$index] -cne [string]$expected[$index]) {
                throw "Finding has an incorrect ordered allowed-selection contract: $identifier"
            }
        }
    }
    return [int64]$FindingInventory.finding_count
}

function Assert-Stage1EHumanDecisionCoverage {
    param(
        [Parameter(Mandatory = $true)]$FindingInventory,
        [Parameter(Mandatory = $true)]$DecisionRecord
    )

    $null = Assert-Stage1EFindingSelectionContracts $FindingInventory
    $required = [ordered]@{}
    foreach ($finding in $FindingInventory.findings) {
        if ([bool]$finding.human_decision_required) {
            $identifier = [string]$finding.stable_identifier
            if ($required.Contains($identifier)) {
                throw "Duplicate required finding identifier: $identifier"
            }
            $required.Add($identifier, $finding)
        }
    }
    if ($required.Count -ne [int64]$FindingInventory.human_decision_required_count) {
        throw 'Human-decision count differs from the canonical finding inventory.'
    }

    $observed = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($decision in $DecisionRecord.decisions) {
        $identifier = [string]$decision.stable_identifier
        if (-not $required.Contains($identifier)) {
            throw "Human decision references an unknown or informational item: $identifier"
        }
        if (-not $observed.Add($identifier)) {
            throw "Human decision record contains a duplicate item: $identifier"
        }
        $selection = [string]$decision.selection
        $allowed = [object[]]@(
            $required[$identifier].allowed_human_selections)
        if ($allowed -cnotcontains $selection) {
            throw "Finding $identifier does not allow selection $selection."
        }
    }
    if ($observed.Count -ne $required.Count) {
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($identifier in $required.Keys) {
            if (-not $observed.Contains([string]$identifier)) {
                $missing.Add([string]$identifier)
            }
        }
        throw "Human decision record is incomplete: $($missing -join ', ')"
    }
    return $required.Count
}

function Assert-Stage1EFreezeReviewBinding {
    param(
        [Parameter(Mandatory = $true)]$HumanRecord,
        [Parameter(Mandatory = $true)][string]$ExpectedCommit,
        [Parameter(Mandatory = $true)][string]$BaseExecutionReportSha256,
        [Parameter(Mandatory = $true)][int64]$ApprovedInventoryCount,
        [Parameter(Mandatory = $true)]$ValidationSummary,
        [Parameter(Mandatory = $true)]$ProtectedSourceSummary
    )

    if ([string]$HumanRecord.approved_commit -cne $ExpectedCommit) {
        throw 'Human decision record is bound to a different approved commit.'
    }
    if ([string]$HumanRecord.freeze_review_selection -cne
        'APPROVE_SOURCE_CANDIDATE_FOR_COMMIT') {
        throw 'Human decision record does not approve the source candidate.'
    }
    $humanExecutionHash = [string]$HumanRecord.execution_report_sha256
    if ($humanExecutionHash -notmatch '^[0-9a-f]{64}$' -or
        $humanExecutionHash -match '^([0-9a-f])\1{63}$') {
        throw 'Human decision record execution-report SHA-256 is not canonical.'
    }
    if ($BaseExecutionReportSha256 -notmatch '^[0-9a-f]{64}$' -or
        $humanExecutionHash -cne $BaseExecutionReportSha256) {
        throw 'Human decision record execution-report SHA-256 differs from committed bytes.'
    }
    if ($ApprovedInventoryCount -ne 19 -or
        [int64]$HumanRecord.approved_inventory_count -ne 19) {
        throw 'Approved PRT04 inventory count must be exactly 19.'
    }
    if ([int64]$ValidationSummary.suite_count -ne 33 -or
        [int64]$ValidationSummary.case_count -ne 634 -or
        [int64]$ValidationSummary.failure_count -ne 0 -or
        [int64]$HumanRecord.validation_summary.suite_count -ne 33 -or
        [int64]$HumanRecord.validation_summary.case_count -ne 634 -or
        [int64]$HumanRecord.validation_summary.failure_count -ne 0) {
        throw 'Validation summary must be exactly 33 suites, 634 cases, 0 failures.'
    }
    if ([int64]$ProtectedSourceSummary.checked_count -ne 106 -or
        [int64]$ProtectedSourceSummary.mismatch_count -ne 0 -or
        [int64]$HumanRecord.protected_source_summary.checked_count -ne 106 -or
        [int64]$HumanRecord.protected_source_summary.mismatch_count -ne 0) {
        throw 'Protected-source summary must be exactly 106 checked, 0 mismatches.'
    }
    return $true
}

function Assert-Stage1ECorrectionEvidenceOutput {
    param(
        [Parameter(Mandatory = $true)][string]$ValidationText,
        [Parameter(Mandatory = $true)][string]$SummaryText,
        [Parameter(Mandatory = $true)][string]$CorrectionReportSha256
    )

    if ($CorrectionReportSha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Finalizer correction-report SHA-256 is not canonical.'
    }
    $binding = "finalizer_correction_report_sha256=$CorrectionReportSha256`n"
    if (-not $ValidationText.Contains($binding)) {
        throw 'FINALIZER_CORRECTION_REPORT_OMITTED_FROM_VALIDATION'
    }
    if (-not $SummaryText.Contains($binding)) {
        throw 'FINALIZER_CORRECTION_REPORT_OMITTED_FROM_SUMMARY'
    }
    return $true
}

function Get-Stage1EFinalizerProviderCommand {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSModuleInfo]$Module,
        [Parameter(Mandatory = $true)][string]$ExpectedModulePath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $resolvedExpectedPath = [System.IO.Path]::GetFullPath($ExpectedModulePath)
    $resolvedModulePath = [System.IO.Path]::GetFullPath(
        [string]$Module.Path)
    if (-not $resolvedModulePath.Equals($resolvedExpectedPath,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "FINALIZER_PROVIDER_MODULE_SUBSTITUTED: $Name"
    }
    $command = $Module.ExportedCommands[$Name]
    if ($null -eq $command) {
        throw "FINALIZER_PROVIDER_COMMAND_UNAVAILABLE: $Name"
    }
    if ($command.CommandType -ne
            [System.Management.Automation.CommandTypes]::Function -or
        [string]$command.Name -cne $Name -or
        [string]$command.ModuleName -cne [string]$Module.Name -or
        [string]$command.Source -cne [string]$Module.Name -or
        $null -eq $command.Module -or
        -not [object]::ReferenceEquals($command.Module, $Module) -or
        -not ([System.IO.Path]::GetFullPath(
                [string]$command.Module.Path).Equals($resolvedExpectedPath,
                [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "FINALIZER_PROVIDER_COMMAND_SUBSTITUTED: $Name"
    }
    return $command
}

function Assert-Stage1ERuntimeInvocationGuards {
    $aliasConflicts = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $script:Stage1EFinalizerAliasConflictNames) {
        $aliasItem = Microsoft.PowerShell.Management\Get-Item `
            -LiteralPath ('Alias:' + $name) -ErrorAction SilentlyContinue
        if ($null -ne $aliasItem) {
            $aliasConflicts.Add($name)
        }
    }
    if ($aliasConflicts.Count -ne 0) {
        throw ('FINALIZER_AMBIENT_ALIAS_CONFLICT: ' +
            ($aliasConflicts -join ', '))
    }

    if ([string]$script:Stage1EFinalizerGitExecutablePath -cne
            [string]$script:Stage1EFinalizerExpectedGitExecutablePath -or
        -not [System.IO.File]::Exists(
            $script:Stage1EFinalizerGitExecutablePath)) {
        throw 'FINALIZER_GIT_EXECUTABLE_BINDING_CHANGED'
    }
    $shaCommand = $script:Stage1EFinalizerExpectedCanonicalProviderCommands[
        'Get-Stage1ESha256Hex']
    $observedGitSha256 = [string](& $shaCommand -Bytes (
            [System.IO.File]::ReadAllBytes(
                $script:Stage1EFinalizerGitExecutablePath)))
    if ($observedGitSha256 -cne
            [string]$script:Stage1EFinalizerExpectedGitExecutableSha256) {
        throw 'FINALIZER_GIT_EXECUTABLE_BINDING_CHANGED'
    }

    if (-not [object]::ReferenceEquals(
            $script:Stage1EFinalizerCanonicalProviderModule,
            $script:Stage1EFinalizerExpectedCanonicalProviderModule) -or
        -not [object]::ReferenceEquals(
            $script:Stage1EFinalizerIdentityProviderModule,
            $script:Stage1EFinalizerExpectedIdentityProviderModule)) {
        throw 'FINALIZER_PROVIDER_MODULE_BINDING_CHANGED'
    }
    foreach ($name in
        $script:Stage1EFinalizerExpectedCanonicalProviderCommands.Keys) {
        $active = $script:Stage1EFinalizerCanonicalProviderCommands[$name]
        $expected =
            $script:Stage1EFinalizerExpectedCanonicalProviderCommands[$name]
        if (-not [object]::ReferenceEquals($active, $expected) -or
            -not [object]::ReferenceEquals(
                $active.Module,
                $script:Stage1EFinalizerExpectedCanonicalProviderModule)) {
            throw "FINALIZER_PROVIDER_COMMAND_BINDING_CHANGED: $name"
        }
    }
    foreach ($name in
        $script:Stage1EFinalizerExpectedIdentityProviderCommands.Keys) {
        $active = $script:Stage1EFinalizerIdentityProviderCommands[$name]
        $expected =
            $script:Stage1EFinalizerExpectedIdentityProviderCommands[$name]
        if (-not [object]::ReferenceEquals($active, $expected) -or
            -not [object]::ReferenceEquals(
                $active.Module,
                $script:Stage1EFinalizerExpectedIdentityProviderModule)) {
            throw "FINALIZER_PROVIDER_COMMAND_BINDING_CHANGED: $name"
        }
    }
}

function Import-Stage1EFinalizerProviders {
    param(
        [Parameter(Mandatory = $true)][string]$CanonicalModulePath,
        [Parameter(Mandatory = $true)][string]$IdentityModulePath,
        [Parameter(Mandatory = $true)][string]$GitExecutablePath
    )

    $canonicalProviders = [object[]]@(
        Microsoft.PowerShell.Core\Import-Module -Name $CanonicalModulePath `
            -Force -PassThru -ErrorAction Stop)
    if ($canonicalProviders.Count -ne 1) {
        throw 'FINALIZER_CANONICAL_PROVIDER_IMPORT_AMBIGUOUS'
    }
    $canonicalProvider = $canonicalProviders[0]
    $canonicalCommands = [ordered]@{}
    foreach ($name in @(
            'Get-Stage1ECanonicalJsonInterfaceVersion',
            'Get-Stage1ESha256ProviderInterfaceVersion',
            'Get-Stage1ESha256Hex',
            'Compare-Stage1EBytes',
            'ConvertFrom-Stage1ECanonicalJsonBytes',
            'ConvertFrom-Stage1ECanonicalJsonEnvelope')) {
        $canonicalCommands.Add($name,
            (Get-Stage1EFinalizerProviderCommand `
                -Module $canonicalProvider `
                -ExpectedModulePath $CanonicalModulePath -Name $name))
    }

    # The identity module force-imports the canonical module in its private
    # module scope. Capture exact canonical FunctionInfo objects first so that
    # this nested reload cannot remove the Finalizer's Provider access.
    $globalJoinPath = Microsoft.PowerShell.Management\Get-Item `
        -LiteralPath 'Function:Join-Path' -ErrorAction SilentlyContinue
    $hadGlobalJoinPath = $null -ne $globalJoinPath
    $globalJoinPathScriptBlock = if ($hadGlobalJoinPath) {
        $globalJoinPath.ScriptBlock
    }
    else {
        $null
    }
    $globalJoinPathOptions = if ($hadGlobalJoinPath) {
        $globalJoinPath.Options
    }
    else {
        [System.Management.Automation.ScopedItemOptions]::None
    }
    Microsoft.PowerShell.Management\Set-Item `
        -Path 'Function:global:Join-Path' -Value {
            Microsoft.PowerShell.Management\Join-Path @args
        } -Force
    try {
        $identityProviders = [object[]]@(
            Microsoft.PowerShell.Core\Import-Module -Name $IdentityModulePath `
                -Force -PassThru -ErrorAction Stop)
        if ($identityProviders.Count -ne 1) {
            throw 'FINALIZER_IDENTITY_PROVIDER_IMPORT_AMBIGUOUS'
        }
        $identityProvider = $identityProviders[0]
        & $identityProvider {
            param([string]$ExactGitExecutablePath)
            $script:Stage1EFinalizerExactGitExecutablePath =
                $ExactGitExecutablePath
            Microsoft.PowerShell.Management\Set-Item `
                -Path 'Function:script:Join-Path' -Value {
                    Microsoft.PowerShell.Management\Join-Path @args
                } -Force
            Microsoft.PowerShell.Management\Set-Item `
                -Path 'Function:script:git' -Value {
                    & $script:Stage1EFinalizerExactGitExecutablePath @args
                } -Force
        } $GitExecutablePath
    }
    finally {
        if ($hadGlobalJoinPath) {
            Microsoft.PowerShell.Management\Set-Item `
                -Path 'Function:global:Join-Path' `
                -Value $globalJoinPathScriptBlock `
                -Options $globalJoinPathOptions -Force
        }
        else {
            Microsoft.PowerShell.Management\Remove-Item `
                -Path 'Function:global:Join-Path' -Force `
                -ErrorAction SilentlyContinue
        }
    }
    $identityCommands = [ordered]@{}
    foreach ($name in @(
            'Get-Stage1ERuntimeBackendIdentityV2SchemaInterfaceVersion',
            'Initialize-Stage1ERuntimeBackendIdentityV2GitProvider',
            'New-Stage1ERuntimeBackendIdentityV2Candidate',
            'ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes',
            'ConvertFrom-Stage1ERuntimeBackendIdentityV2Bytes',
            'Assert-Stage1EQualificationRecord',
            'ConvertTo-Stage1EQualificationRecordBytes',
            'ConvertFrom-Stage1EQualificationRecordBytes',
            'New-Stage1ESourceFreezeReviewRecord',
            'New-Stage1ERuntimeReviewRecord',
            'New-Stage1ERuntimeBackendIdentityV2CurrentReviewed',
            'New-Stage1EQualificationIdentity',
            'New-Stage1EQualificationTerminalRecord',
            'New-Stage1EAtomicQ5ResultEnvelope')) {
        $identityCommands.Add($name,
            (Get-Stage1EFinalizerProviderCommand `
                -Module $identityProvider `
                -ExpectedModulePath $IdentityModulePath -Name $name))
    }

    $canonicalInterface = [string](& $canonicalCommands[
            'Get-Stage1ECanonicalJsonInterfaceVersion'])
    $shaInterface = [string](& $canonicalCommands[
            'Get-Stage1ESha256ProviderInterfaceVersion'])
    $identityInterface = [string](& $identityCommands[
            'Get-Stage1ERuntimeBackendIdentityV2SchemaInterfaceVersion'])
    $boundGitPath = [string](& $identityCommands[
            'Initialize-Stage1ERuntimeBackendIdentityV2GitProvider'] `
        -GitExecutablePath $GitExecutablePath)
    $probeBytes = [System.Text.UTF8Encoding]::new($false).GetBytes('abc')
    $probeDigest = [string](& $canonicalCommands[
            'Get-Stage1ESha256Hex'] -Bytes $probeBytes)
    if ($canonicalInterface -cne
            'stage1e-runtime-canonical-json-interface-v1' -or
        $shaInterface -cne 'stage1e-runtime-sha256-provider-interface-v1' -or
        $identityInterface -cne
            'stage1e-runtime-backend-identity-schema-interface-v2' -or
        -not $boundGitPath.Equals($GitExecutablePath,
            [System.StringComparison]::OrdinalIgnoreCase) -or
        $probeDigest -cne
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') {
        throw 'FINALIZER_PROVIDER_SELF_TEST_FAILED'
    }

    return [ordered]@{
        canonical_commands = $canonicalCommands
        identity_commands = $identityCommands
        canonical_module = $canonicalProvider
        identity_module = $identityProvider
    }
}

$repository = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar)
if (-not [System.IO.Directory]::Exists(
        ([System.IO.Path]::Combine($repository, '.git')))) {
    throw 'RepositoryRoot is not the expected Git working repository.'
}
$script:Stage1EFinalizerGitExecutablePath =
    Resolve-Stage1EGitExecutablePath $GitExecutablePath
$evidenceRoot = Resolve-Stage1EExternalNewRoot $FreezeEvidenceRoot $repository

if ($Mode -ceq 'PREVIEW_ONLY') {
    foreach ($value in @($HumanAuthorityRecordPath,$AcceptedPreviewRoot,
            $SourceFreezeReviewRecordPath,$Q5LiveClosureEvidencePath,
            $QualificationExecutionId,$WorkspaceIdentity)) {
        if (-not [string]::IsNullOrEmpty([string]$value)) {
            throw 'PREVIEW_AUTHORITY_INPUT_PROHIBITED'
        }
    }
}
elseif ($Mode -ceq 'ISSUE_SOURCE_FREEZE_REVIEW') {
    if ([string]::IsNullOrWhiteSpace($HumanAuthorityRecordPath)) {
        throw 'Q1_HUMAN_AUTHORITY_RECORD_MISSING'
    }
    if ([string]::IsNullOrWhiteSpace($AcceptedPreviewRoot)) {
        throw 'Q1_ACCEPTED_PREVIEW_ROOT_MISSING'
    }
    if (-not [string]::IsNullOrEmpty($SourceFreezeReviewRecordPath) -or
        -not [string]::IsNullOrEmpty($Q5LiveClosureEvidencePath)) {
        throw 'Q1_CURRENT_REVIEWED_INPUT_PROHIBITED'
    }
}
else {
    if ([string]::IsNullOrWhiteSpace($HumanAuthorityRecordPath)) {
        throw 'Q5_HUMAN_AUTHORITY_RECORD_MISSING'
    }
    if ([string]::IsNullOrWhiteSpace($SourceFreezeReviewRecordPath)) {
        throw 'Q5_SOURCE_FREEZE_REVIEW_RECORD_MISSING'
    }
    if ([string]::IsNullOrWhiteSpace($Q5LiveClosureEvidencePath)) {
        throw 'Q5_LIVE_CLOSURE_EVIDENCE_MISSING'
    }
    if (-not [string]::IsNullOrEmpty($AcceptedPreviewRoot)) {
        throw 'Q5_ACCEPTED_PREVIEW_INPUT_PROHIBITED'
    }
}
if ($Mode -cne 'PREVIEW_ONLY') {
    if ([string]::IsNullOrWhiteSpace($QualificationExecutionId) -or
        $QualificationExecutionId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$') {
        throw 'QUALIFICATION_EXECUTION_ID_INVALID'
    }
    if ($WorkspaceIdentity -notmatch '^[0-9a-f]{64}$' -or
        $WorkspaceIdentity -match '^([0-9a-f])\1{63}$') {
        throw 'QUALIFICATION_WORKSPACE_IDENTITY_INVALID'
    }
}

$identityModule = [System.IO.Path]::Combine($repository, `
    'fpga\vivado\build\identity\stage1e_runtime_backend_identity_v2.psm1'
)
$canonicalModule = [System.IO.Path]::Combine($repository, `
    'fpga\vivado\build\lib\stage1e_runtime_canonical_json_v1.psm1'
)
$providers = Import-Stage1EFinalizerProviders `
    -CanonicalModulePath $canonicalModule -IdentityModulePath $identityModule `
    -GitExecutablePath $script:Stage1EFinalizerGitExecutablePath
$script:Stage1EFinalizerCanonicalProviderCommands =
    $providers.canonical_commands
$script:Stage1EFinalizerIdentityProviderCommands = $providers.identity_commands
$script:Stage1EFinalizerCanonicalProviderModule = $providers.canonical_module
$script:Stage1EFinalizerIdentityProviderModule = $providers.identity_module
$script:Stage1EFinalizerExpectedCanonicalProviderModule =
    $providers.canonical_module
$script:Stage1EFinalizerExpectedIdentityProviderModule =
    $providers.identity_module
$script:Stage1EFinalizerExpectedCanonicalProviderCommands = [ordered]@{}
foreach ($name in $providers.canonical_commands.Keys) {
    $script:Stage1EFinalizerExpectedCanonicalProviderCommands.Add(
        $name, $providers.canonical_commands[$name])
}
$script:Stage1EFinalizerExpectedIdentityProviderCommands = [ordered]@{}
foreach ($name in $providers.identity_commands.Keys) {
    $script:Stage1EFinalizerExpectedIdentityProviderCommands.Add(
        $name, $providers.identity_commands[$name])
}
$script:Stage1EFinalizerExpectedGitExecutablePath =
    $script:Stage1EFinalizerGitExecutablePath

function Get-Stage1ESha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return & $script:Stage1EFinalizerCanonicalProviderCommands[
        'Get-Stage1ESha256Hex'] -Bytes $Bytes
}

function ConvertFrom-Stage1ECanonicalJsonBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return & $script:Stage1EFinalizerCanonicalProviderCommands[
        'ConvertFrom-Stage1ECanonicalJsonBytes'] -Bytes $Bytes
}

function ConvertFrom-Stage1ECanonicalJsonEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Schema,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$SchemaRegistry
    )
    return & $script:Stage1EFinalizerCanonicalProviderCommands[
        'ConvertFrom-Stage1ECanonicalJsonEnvelope'] -Bytes $Bytes `
        -Schema $Schema -SchemaRegistry $SchemaRegistry
}

function New-Stage1ERuntimeBackendIdentityV2Candidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$SourceIdentity,
        [Parameter(Mandatory = $true)][string]$ValidationEvidenceIdentity,
        [Parameter(Mandatory = $true)]
        [ValidateSet('PRODUCTION_IMPLEMENTED')][string]$CapabilityState,
        [switch]$RequireCommittedBytes
    )
    return & $script:Stage1EFinalizerIdentityProviderCommands[
        'New-Stage1ERuntimeBackendIdentityV2Candidate'] @PSBoundParameters
}

function ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [switch]$RequireCommittedBytes
    )
    return & $script:Stage1EFinalizerIdentityProviderCommands[
        'ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes'] @PSBoundParameters
}

function Invoke-Stage1EFinalizerIdentityProvider {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parameters
    )

    & ${function:Assert-Stage1ERuntimeInvocationGuards}
    if (-not $script:Stage1EFinalizerIdentityProviderCommands.Contains($Name)) {
        throw "FINALIZER_PROVIDER_COMMAND_UNAVAILABLE: $Name"
    }
    $command = $script:Stage1EFinalizerIdentityProviderCommands[$Name]
    return & $command @Parameters
}

function Read-Stage1EQualificationRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSchemaVersion
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
            $Path) -or
        -not [System.IO.Path]::IsPathRooted($Path)) {
        throw "QUALIFICATION_RECORD_PATH_INVALID: $ExpectedSchemaVersion"
    }
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($resolved)) {
        throw "QUALIFICATION_RECORD_MISSING: $ExpectedSchemaVersion"
    }
    $bytes = [System.IO.File]::ReadAllBytes($resolved)
    try {
        $record = Invoke-Stage1EFinalizerIdentityProvider `
            -Name 'ConvertFrom-Stage1EQualificationRecordBytes' `
            -Parameters ([ordered]@{ Bytes = $bytes })
    }
    catch {
        throw "QUALIFICATION_RECORD_INVALID: $ExpectedSchemaVersion"
    }
    if ([string]$record.schema_version -cne $ExpectedSchemaVersion) {
        throw "QUALIFICATION_RECORD_SCHEMA_MISMATCH: $ExpectedSchemaVersion"
    }
    return [ordered]@{
        path = $resolved
        bytes = $bytes
        record = $record
        sha256 = Get-Stage1ESha256Hex -Bytes $bytes
    }
}

function Get-Stage1EPreviewReviewIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$PreviewFiles
    )

    $expected = [object[]]@(
        'source_candidate_preview.txt'
        'validation_evidence_candidate_preview.txt'
        'runtime_backend_candidate_preview.json'
        'warning_policy_candidate_preview.txt'
        'implementation_policy_candidate_preview.txt'
        'implementation_configuration_candidate_preview.txt'
        'preview_summary.txt'
    )
    if ($PreviewFiles.Count -ne $expected.Count) {
        throw 'PREVIEW_FILE_INVENTORY_MISMATCH'
    }
    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append(
        "schema_version=stage1e-accepted-preview-review-identity-v1`n")
    foreach ($leaf in $expected) {
        if (-not $PreviewFiles.Contains([string]$leaf)) {
            throw "PREVIEW_FILE_MISSING: $leaf"
        }
        $bytes = [byte[]]$PreviewFiles[[string]$leaf]
        $null = $builder.Append(('file={0}|{1}|{2}' -f $leaf,
                $bytes.Length, (Get-Stage1ESha256Hex -Bytes $bytes)))
        $null = $builder.Append("`n")
    }
    return Get-Stage1ESha256Hex -Bytes (
        ConvertTo-Stage1EUtf8Bytes $builder.ToString())
}

function Assert-Stage1EAcceptedPreview {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ExpectedFiles
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
            $Root) -or
        -not [System.IO.Path]::IsPathRooted($Root)) {
        throw 'Q1_ACCEPTED_PREVIEW_ROOT_INVALID'
    }
    $resolved = [System.IO.Path]::GetFullPath($Root)
    if (-not [System.IO.Directory]::Exists($resolved)) {
        throw 'Q1_ACCEPTED_PREVIEW_ROOT_MISSING'
    }
    $files = [object[]]@([System.IO.DirectoryInfo]::new($resolved).GetFiles())
    if ($files.Count -ne $ExpectedFiles.Count) {
        throw 'Q1_STALE_PREVIEW_IDENTITY'
    }
    $compareCommand = $script:Stage1EFinalizerCanonicalProviderCommands[
        'Compare-Stage1EBytes']
    foreach ($leaf in $ExpectedFiles.Keys) {
        $path = [System.IO.Path]::Combine($resolved, [string]$leaf)
        if (-not [System.IO.File]::Exists($path)) {
            throw 'Q1_STALE_PREVIEW_IDENTITY'
        }
        $observed = [System.IO.File]::ReadAllBytes($path)
        if (-not [bool](& $compareCommand `
                -Left ([byte[]]$ExpectedFiles[$leaf]) -Right $observed)) {
            throw 'Q1_STALE_PREVIEW_IDENTITY'
        }
    }
    return Get-Stage1EPreviewReviewIdentity -PreviewFiles $ExpectedFiles
}

function Publish-Stage1EAtomicAuthoritySet {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$FileBytes,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$VerifierKinds
    )

    $final = [System.IO.Path]::GetFullPath($Root)
    if ([System.IO.Directory]::Exists($final) -or
        [System.IO.File]::Exists($final)) {
        throw 'AUTHORITY_OUTPUT_ROOT_ALREADY_EXISTS'
    }
    $parent = [System.IO.Path]::GetDirectoryName($final)
    if ([string]::IsNullOrEmpty($parent) -or
        -not [System.IO.Directory]::Exists($parent)) {
        throw 'AUTHORITY_OUTPUT_PARENT_MISSING'
    }
    $temporary = [System.IO.Path]::Combine($parent,
        ('.' + [System.IO.Path]::GetFileName($final) + '.stage1e-tmp-' +
            [guid]::NewGuid().ToString('N')))
    $createdTemporary = $false
    $publishedFinal = $false
    $compareCommand = $script:Stage1EFinalizerCanonicalProviderCommands[
        'Compare-Stage1EBytes']
    try {
        $null = [System.IO.Directory]::CreateDirectory($temporary)
        $createdTemporary = $true
        foreach ($leafValue in $FileBytes.Keys) {
            $leaf = [string]$leafValue
            if ([System.IO.Path]::GetFileName($leaf) -cne $leaf) {
                throw "AUTHORITY_OUTPUT_LEAF_INVALID: $leaf"
            }
            $path = [System.IO.Path]::Combine($temporary, $leaf)
            Write-Stage1ENewBytes -Path $path -Bytes ([byte[]]$FileBytes[$leaf])
            $reopened = [System.IO.File]::ReadAllBytes($path)
            if (-not [bool](& $compareCommand `
                    -Left ([byte[]]$FileBytes[$leaf]) -Right $reopened)) {
                throw "AUTHORITY_OUTPUT_READBACK_MISMATCH: $leaf"
            }
            if ($VerifierKinds.Contains($leaf)) {
                $kind = [string]$VerifierKinds[$leaf]
                if ($kind -ceq 'RUNTIME_BACKEND') {
                    $null = Invoke-Stage1EFinalizerIdentityProvider `
                        -Name 'ConvertFrom-Stage1ERuntimeBackendIdentityV2Bytes' `
                        -Parameters ([ordered]@{ Bytes = $reopened })
                }
                elseif ($kind -ceq 'QUALIFICATION_RECORD') {
                    $null = Invoke-Stage1EFinalizerIdentityProvider `
                        -Name 'ConvertFrom-Stage1EQualificationRecordBytes' `
                        -Parameters ([ordered]@{ Bytes = $reopened })
                }
                else {
                    throw "AUTHORITY_OUTPUT_VERIFIER_UNKNOWN: $kind"
                }
            }
        }
        [System.IO.Directory]::Move($temporary, $final)
        $createdTemporary = $false
        $publishedFinal = $true
        foreach ($leafValue in $FileBytes.Keys) {
            $leaf = [string]$leafValue
            $reopened = [System.IO.File]::ReadAllBytes(
                [System.IO.Path]::Combine($final, $leaf))
            if (-not [bool](& $compareCommand `
                    -Left ([byte[]]$FileBytes[$leaf]) -Right $reopened)) {
                throw "AUTHORITY_OUTPUT_FINAL_READBACK_MISMATCH: $leaf"
            }
        }
    }
    catch {
        if ($createdTemporary -and
            [System.IO.Directory]::Exists($temporary)) {
            [System.IO.Directory]::Delete($temporary, $true)
        }
        if ($publishedFinal -and [System.IO.Directory]::Exists($final)) {
            [System.IO.Directory]::Delete($final, $true)
        }
        throw
    }
    return [ordered]@{
        publication_state = 'ATOMIC_SET_PUBLISHED'
        root = $final
        file_count = [int64]$FileBytes.Count
    }
}

$gitExecutableSha256 = Get-Stage1ESha256Hex -Bytes (
    [System.IO.File]::ReadAllBytes($script:Stage1EFinalizerGitExecutablePath))
$script:Stage1EFinalizerExpectedGitExecutableSha256 = $gitExecutableSha256
$head = Invoke-Stage1EGitText $repository @('rev-parse','HEAD')
if ($head.text -cne $ExpectedApprovedCommit) {
    throw "WRONG_APPROVED_COMMIT: expected $ExpectedApprovedCommit; observed $($head.text)"
}
$tree = Invoke-Stage1EGitText $repository @('rev-parse','HEAD^{tree}')
$correctionReportPath =
    'docs/handoff/stage1e_prt04_finalizer_provider_correction_execution_report_v1.md'
Assert-Stage1ECanonicalRelativePath $correctionReportPath
$correctionTracked = Invoke-Stage1EGitText $repository @(
    'ls-files','--error-unmatch','--',$correctionReportPath) -AllowFailure
if ($correctionTracked.exit_code -ne 0) {
    throw "FINALIZER_CORRECTION_REPORT_NOT_TRACKED: $correctionReportPath"
}
$correctionReportFullPath = [System.IO.Path]::Combine(
    $repository, $correctionReportPath.Replace('/', '\'))
if (-not [System.IO.File]::Exists($correctionReportFullPath)) {
    throw "FINALIZER_CORRECTION_REPORT_MISSING: $correctionReportPath"
}
$correctionWorktreeBlob = Invoke-Stage1EGitText $repository @(
    'hash-object','--',$correctionReportFullPath)
$correctionHeadBlob = Invoke-Stage1EGitText $repository @(
    'rev-parse',"HEAD:$correctionReportPath")
if ($correctionWorktreeBlob.text -cne $correctionHeadBlob.text) {
    throw "FINALIZER_CORRECTION_REPORT_BYTES_DIFFER: $correctionReportPath"
}
$finalizerCorrectionReportSha256 = Get-Stage1ESha256Hex -Bytes (
    [System.IO.File]::ReadAllBytes($correctionReportFullPath))
$prt05ReportPath =
    'docs/handoff/stage1e_prt05_qualification_authority_closure_execution_report_v1.md'
Assert-Stage1ECanonicalRelativePath $prt05ReportPath
$prt05Tracked = Invoke-Stage1EGitText $repository @(
    'ls-files','--error-unmatch','--',$prt05ReportPath) -AllowFailure
if ($prt05Tracked.exit_code -ne 0) {
    throw "PRT05_AUTHORITY_REPORT_NOT_TRACKED: $prt05ReportPath"
}
$prt05ReportFullPath = [System.IO.Path]::Combine(
    $repository, $prt05ReportPath.Replace('/', '\'))
if (-not [System.IO.File]::Exists($prt05ReportFullPath)) {
    throw "PRT05_AUTHORITY_REPORT_MISSING: $prt05ReportPath"
}
$prt05WorktreeBlob = Invoke-Stage1EGitText $repository @(
    'hash-object','--',$prt05ReportFullPath)
$prt05HeadBlob = Invoke-Stage1EGitText $repository @(
    'rev-parse',"HEAD:$prt05ReportPath")
if ($prt05WorktreeBlob.text -cne $prt05HeadBlob.text) {
    throw "PRT05_AUTHORITY_REPORT_BYTES_DIFFER: $prt05ReportPath"
}
$prt05AuthorityClosureReportSha256 = Get-Stage1ESha256Hex -Bytes (
    [System.IO.File]::ReadAllBytes($prt05ReportFullPath))
$porcelainBefore = Invoke-Stage1EGitText $repository @(
    'status','--porcelain=v1','--untracked-files=all')
if (-not [string]::IsNullOrEmpty($porcelainBefore.text)) {
    throw 'DIRTY_WORKTREE: finalization requires exact empty Git porcelain.'
}

$remoteRef = Invoke-Stage1EGitText $repository @(
    'rev-parse','--verify','refs/remotes/origin/main') -AllowFailure
if ($remoteRef.exit_code -eq 0) {
    $alignment = Invoke-Stage1EGitText $repository @(
        'rev-list','--left-right','--count',
        "$ExpectedApprovedCommit...refs/remotes/origin/main")
    if ($alignment.text -notmatch '^0\s+0$') {
        throw "LOCAL_REMOTE_MISMATCH: $($alignment.text)"
    }
    $alignmentState = 'LOCAL_REMOTE_ALIGNED_TO_RECORDED_ORIGIN_MAIN'
    $offlineLimit = 'NONE'
}
else {
    $alignmentState = 'OFFLINE_REMOTE_REFERENCE_UNAVAILABLE'
    $offlineLimit =
        'No local refs/remotes/origin/main was available; network freshness was not asserted.'
}

$baseExecutionReportPath =
    'docs/handoff/stage1e_prt04_run2_freeze_candidate_execution_report_v1.md'
$freezeCandidatePath =
    'fpga/vivado/build/config/stage1e_run2_freeze_review_candidate_v1.json'
$baseExecutionReportRow = $null
$freezeCandidateRow = $null
$inventoryRows = [System.Collections.Generic.List[object]]::new()
foreach ($relativePath in $script:ApprovedPrt04Inventory) {
    Assert-Stage1ECanonicalRelativePath $relativePath
    $tracked = Invoke-Stage1EGitText $repository @(
        'ls-files','--error-unmatch','--',$relativePath) -AllowFailure
    if ($tracked.exit_code -ne 0) {
        throw "Approved PRT04 inventory path is not Git-tracked: $relativePath"
    }
    $fullPath = [System.IO.Path]::Combine(
        $repository, $relativePath.Replace('/', '\'))
    if (-not [System.IO.File]::Exists($fullPath)) {
        throw "Approved PRT04 inventory path is missing: $relativePath"
    }
    $worktreeBlob = Invoke-Stage1EGitText $repository @(
        'hash-object','--',$fullPath)
    $headBlob = Invoke-Stage1EGitText $repository @(
        'rev-parse',"HEAD:$relativePath")
    if ($worktreeBlob.text -cne $headBlob.text) {
        throw "Approved PRT04 inventory bytes differ from HEAD: $relativePath"
    }
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    $row = [ordered]@{
        repository_relative_path = $relativePath
        size_bytes = [int64]$bytes.Length
        file_sha256 = Get-Stage1ESha256Hex -Bytes $bytes
    }
    $inventoryRows.Add($row)
    if ($relativePath -ceq $baseExecutionReportPath) {
        if ($null -ne $baseExecutionReportRow) {
            throw 'Approved PRT04 inventory has duplicate base execution reports.'
        }
        $baseExecutionReportRow = $row
    }
    if ($relativePath -ceq $freezeCandidatePath) {
        if ($null -ne $freezeCandidateRow) {
            throw 'Approved PRT04 inventory has duplicate freeze-review candidates.'
        }
        $freezeCandidateRow = $row
    }
}

if ($inventoryRows.Count -ne 19) {
    throw "Approved PRT04 inventory count differs: $($inventoryRows.Count)"
}
if ($null -eq $baseExecutionReportRow -or $null -eq $freezeCandidateRow) {
    throw 'Approved PRT04 inventory lacks a unique review-evidence binding.'
}
$baseExecutionReportSha256 = [string]$baseExecutionReportRow.file_sha256
$freezeCandidateSha256 = [string]$freezeCandidateRow.file_sha256
$protectedSourceSummary = Get-Stage1EProtectedSourceSummary $repository
$baseValidationSummary = [ordered]@{
    suite_count = [int64]33
    case_count = [int64]634
    failure_count = [int64]0
}

$findingPath = [System.IO.Path]::Combine($repository, `
    'fpga\vivado\build\config\stage1e_run1_finding_inventory_v1.json'
)
$findingBytes = [System.IO.File]::ReadAllBytes($findingPath)
$findingInventory = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes $findingBytes
if ([string]$findingInventory.schema_version -cne
    'stage1e-run1-finding-inventory-v1' -or
    [int64]$findingInventory.finding_count -ne 19 -or
    [int64]$findingInventory.warning_key_count -ne 12 -or
    [int64]$findingInventory.warning_observation_count -ne 121 -or
    [int64]$findingInventory.accepted_disposition_count -ne 0) {
    throw 'Canonical Run1 finding inventory control totals differ.'
}

$humanSchemaPath = [System.IO.Path]::Combine($repository, `
    'fpga\vivado\build\lib\stage1e_run1_human_decision_record_v1.schema.json'
)
$human = Read-Stage1EHumanDecisionRecord `
    -Path $HumanDecisionRecordPath -ExpectedCommit $ExpectedApprovedCommit `
    -SchemaPath $humanSchemaPath
$humanDecisionCount = Assert-Stage1EHumanDecisionCoverage `
    -FindingInventory $findingInventory -DecisionRecord $human.record
$null = Assert-Stage1EFreezeReviewBinding `
    -HumanRecord $human.record -ExpectedCommit $ExpectedApprovedCommit `
    -BaseExecutionReportSha256 $baseExecutionReportSha256 `
    -ApprovedInventoryCount $inventoryRows.Count `
    -ValidationSummary $baseValidationSummary `
    -ProtectedSourceSummary $protectedSourceSummary

$sourceBuilder = [System.Text.StringBuilder]::new()
$null = $sourceBuilder.Append("schema_version=stage1e-source-freeze-candidate-v1`n")
$null = $sourceBuilder.Append("mode=PREVIEW_ONLY`n")
$null = $sourceBuilder.Append("approved_commit=$ExpectedApprovedCommit`n")
$null = $sourceBuilder.Append("approved_tree=$($tree.text)`n")
$null = $sourceBuilder.Append("porcelain=EMPTY`n")
$null = $sourceBuilder.Append("alignment=$alignmentState`n")
foreach ($row in $inventoryRows) {
    $null = $sourceBuilder.Append(('source={0}|{1}|{2}' -f
            $row.repository_relative_path, $row.size_bytes, $row.file_sha256))
    $null = $sourceBuilder.Append("`n")
}
$sourcePayloadBytes = ConvertTo-Stage1EUtf8Bytes $sourceBuilder.ToString()
$sourceCandidateIdentity = Get-Stage1ESha256Hex -Bytes $sourcePayloadBytes

$validationPayloadText = @(
    'schema_version=stage1e-prt04-validation-evidence-candidate-v1'
    "base_execution_report_sha256=$baseExecutionReportSha256"
    "finalizer_correction_report_sha256=$finalizerCorrectionReportSha256"
    "prt05_authority_closure_report_sha256=$prt05AuthorityClosureReportSha256"
    "freeze_review_candidate_sha256=$freezeCandidateSha256"
    "approved_commit=$ExpectedApprovedCommit"
    "approved_tree=$($tree.text)"
    "base_validation_suite_count=$($baseValidationSummary.suite_count)"
    "base_validation_case_count=$($baseValidationSummary.case_count)"
    "base_validation_failure_count=$($baseValidationSummary.failure_count)"
    "protected_source_checked_count=$($protectedSourceSummary.checked_count)"
    "protected_source_mismatch_count=$($protectedSourceSummary.mismatch_count)"
    "human_decision_record_sha256=$($human.sha256)"
    'authority=NONE'
) -join "`n"
$validationPayloadText += "`n"
$validationBytes = ConvertTo-Stage1EUtf8Bytes $validationPayloadText
$validationCandidateIdentity = Get-Stage1ESha256Hex -Bytes $validationBytes

& ${function:Assert-Stage1ERuntimeInvocationGuards}
$runtimeCandidate = & ${function:New-Stage1ERuntimeBackendIdentityV2Candidate} `
    -RepositoryRoot $repository -SourceIdentity $sourceCandidateIdentity `
    -ValidationEvidenceIdentity $validationCandidateIdentity `
    -CapabilityState PRODUCTION_IMPLEMENTED -RequireCommittedBytes
& ${function:Assert-Stage1ERuntimeInvocationGuards}
$runtimeCandidateBytes = & `
    ${function:ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes} `
    -Record $runtimeCandidate -RepositoryRoot $repository -RequireCommittedBytes

$policyPath = [System.IO.Path]::Combine($repository, `
    'docs\design\stage1e_implementation_policy_v3.md'
)
$warningPath = [System.IO.Path]::Combine($repository, `
    'fpga\vivado\build\config\stage1e_implementation_warning_policy_v3.dict'
)
$configurationPath = [System.IO.Path]::Combine($repository, `
    'fpga\vivado\build\config\stage1e_implementation_configuration_v3.dict'
)
$policyHash = Get-Stage1ESha256Hex -Bytes (
    [System.IO.File]::ReadAllBytes($policyPath))
$warningHash = Get-Stage1ESha256Hex -Bytes (
    [System.IO.File]::ReadAllBytes($warningPath))
$configurationHash = Get-Stage1ESha256Hex -Bytes (
    [System.IO.File]::ReadAllBytes($configurationPath))

$warningPayloadText = @(
    'schema_version=stage1e-warning-policy-candidate-preview-v3'
    "source_identity=$sourceCandidateIdentity"
    "warning_policy_file_sha256=$warningHash"
    "human_decision_record_sha256=$($human.sha256)"
    'decision_state=HUMAN_DECISIONS_SUPPLIED_PREVIEW_ONLY'
    'authority=NONE'
) -join "`n"
$warningPayloadText += "`n"
$warningPayloadBytes = ConvertTo-Stage1EUtf8Bytes $warningPayloadText
$warningCandidateIdentity = Get-Stage1ESha256Hex -Bytes $warningPayloadBytes

$policyPayloadText = @(
    'schema_version=stage1e-implementation-policy-candidate-preview-v3'
    "source_identity=$sourceCandidateIdentity"
    "runtime_backend_identity=$($runtimeCandidate.identity_sha256)"
    "warning_policy_identity=$warningCandidateIdentity"
    "policy_file_sha256=$policyHash"
    'review_state=REVIEW_REQUIRED'
    'authority=NONE'
) -join "`n"
$policyPayloadText += "`n"
$policyPayloadBytes = ConvertTo-Stage1EUtf8Bytes $policyPayloadText
$policyCandidateIdentity = Get-Stage1ESha256Hex -Bytes $policyPayloadBytes

$configurationPayloadText = @(
    'schema_version=stage1e-implementation-configuration-candidate-preview-v3'
    "source_identity=$sourceCandidateIdentity"
    "runtime_backend_identity=$($runtimeCandidate.identity_sha256)"
    "implementation_policy_identity=$policyCandidateIdentity"
    "warning_policy_identity=$warningCandidateIdentity"
    "configuration_file_sha256=$configurationHash"
    'freeze_state=PREVIEW_ONLY_NOT_FROZEN'
    'authority=NONE'
) -join "`n"
$configurationPayloadText += "`n"
$configurationPayloadBytes = ConvertTo-Stage1EUtf8Bytes $configurationPayloadText
$configurationCandidateIdentity =
    Get-Stage1ESha256Hex -Bytes $configurationPayloadBytes

$summaryText = @(
    'schema_version=stage1e-run2-freeze-finalizer-preview-result-v1'
    'mode=PREVIEW_ONLY'
    "production_finalization_state=$script:ProductionFinalizationState"
    "approved_commit=$ExpectedApprovedCommit"
    "approved_tree=$($tree.text)"
    "alignment_state=$alignmentState"
    "offline_verification_limit=$offlineLimit"
    "approved_inventory_count=$($inventoryRows.Count)"
    "human_decision_count=$humanDecisionCount"
    "base_execution_report_sha256=$baseExecutionReportSha256"
    "finalizer_correction_report_sha256=$finalizerCorrectionReportSha256"
    "prt05_authority_closure_report_sha256=$prt05AuthorityClosureReportSha256"
    "freeze_review_candidate_sha256=$freezeCandidateSha256"
    "base_validation_suite_count=$($baseValidationSummary.suite_count)"
    "base_validation_case_count=$($baseValidationSummary.case_count)"
    "base_validation_failure_count=$($baseValidationSummary.failure_count)"
    "protected_source_checked_count=$($protectedSourceSummary.checked_count)"
    "protected_source_mismatch_count=$($protectedSourceSummary.mismatch_count)"
    "git_executable_path=$script:Stage1EFinalizerGitExecutablePath"
    "git_executable_sha256=$gitExecutableSha256"
    "source_candidate_identity=$sourceCandidateIdentity"
    "validation_evidence_candidate_identity=$validationCandidateIdentity"
    "runtime_backend_candidate_identity=$($runtimeCandidate.identity_sha256)"
    "warning_policy_candidate_identity=$warningCandidateIdentity"
    "implementation_policy_candidate_identity=$policyCandidateIdentity"
    "implementation_configuration_candidate_identity=$configurationCandidateIdentity"
    'runtime_review=REVIEW_REQUIRED'
    'qualification_effect=NONE'
    'authorization_effect=NONE'
    'current_reviewed_effect=NOT_ISSUED'
    'q1_effect=NOT_ISSUED'
    'artifact_effect=NONE'
    'publication_effect=NONE'
    'board_effect=NONE'
    'repository_mutation=NONE'
) -join "`n"
$summaryText += "`n"
$null = Assert-Stage1ECorrectionEvidenceOutput `
    -ValidationText $validationPayloadText -SummaryText $summaryText `
    -CorrectionReportSha256 $finalizerCorrectionReportSha256
$summaryBytes = ConvertTo-Stage1EUtf8Bytes $summaryText

$porcelainAfterConstruction = Invoke-Stage1EGitText $repository @(
    'status','--porcelain=v1','--untracked-files=all')
if (-not [string]::IsNullOrEmpty($porcelainAfterConstruction.text)) {
    throw 'Repository changed while constructing freeze preview payloads.'
}

$previewFiles = [ordered]@{
    'source_candidate_preview.txt' = $sourcePayloadBytes
    'validation_evidence_candidate_preview.txt' = $validationBytes
    'runtime_backend_candidate_preview.json' = $runtimeCandidateBytes
    'warning_policy_candidate_preview.txt' = $warningPayloadBytes
    'implementation_policy_candidate_preview.txt' = $policyPayloadBytes
    'implementation_configuration_candidate_preview.txt' =
        $configurationPayloadBytes
    'preview_summary.txt' = $summaryBytes
}
$previewReviewIdentity = Get-Stage1EPreviewReviewIdentity `
    -PreviewFiles $previewFiles

if ($Mode -ceq 'PREVIEW_ONLY') {
    $previewVerifiers = [ordered]@{
        'runtime_backend_candidate_preview.json' = 'RUNTIME_BACKEND'
    }
    $null = Publish-Stage1EAtomicAuthoritySet -Root $evidenceRoot `
        -FileBytes $previewFiles -VerifierKinds $previewVerifiers
    $porcelainAfterPublication = Invoke-Stage1EGitText $repository @(
        'status','--porcelain=v1','--untracked-files=all')
    if (-not [string]::IsNullOrEmpty($porcelainAfterPublication.text)) {
        if ([System.IO.Directory]::Exists($evidenceRoot)) {
            [System.IO.Directory]::Delete($evidenceRoot, $true)
        }
        throw 'Repository changed during external preview publication.'
    }
    return [pscustomobject]@{
        Status = 'PREVIEW_ONLY_COMPLETE_NO_AUTHORITY'
        ProductionFinalization = $script:ProductionFinalizationState
        EvidenceRoot = $evidenceRoot
        ApprovedCommit = $ExpectedApprovedCommit
        SourceCandidateIdentity = $sourceCandidateIdentity
        ValidationEvidenceCandidateIdentity = $validationCandidateIdentity
        PreviewReviewIdentity = $previewReviewIdentity
        BaseExecutionReportSha256 = $baseExecutionReportSha256
        FinalizerCorrectionReportSha256 = $finalizerCorrectionReportSha256
        Prt05AuthorityClosureReportSha256 =
            $prt05AuthorityClosureReportSha256
        FreezeReviewCandidateSha256 = $freezeCandidateSha256
        GitExecutablePath = $script:Stage1EFinalizerGitExecutablePath
        GitExecutableSha256 = $gitExecutableSha256
        RuntimeBackendCandidateIdentity = $runtimeCandidate.identity_sha256
        WarningPolicyCandidateIdentity = $warningCandidateIdentity
        ImplementationPolicyCandidateIdentity = $policyCandidateIdentity
        ImplementationConfigurationCandidateIdentity =
            $configurationCandidateIdentity
        RuntimeReview = 'REVIEW_REQUIRED'
        QualificationEffect = 'NONE'
        AuthorizationEffect = 'NONE'
        CurrentReviewedEffect = 'NOT_ISSUED'
        Q1Effect = 'NOT_ISSUED'
        ArtifactEffect = 'NONE'
        BoardEffect = 'NONE'
    }
}

if ($Mode -ceq 'ISSUE_SOURCE_FREEZE_REVIEW') {
    $acceptedPreviewIdentity = Assert-Stage1EAcceptedPreview `
        -Root $AcceptedPreviewRoot -ExpectedFiles $previewFiles
    $authority = Read-Stage1EQualificationRecord `
        -Path $HumanAuthorityRecordPath `
        -ExpectedSchemaVersion `
            'stage1e-human-qualification-authority-record-v1'
    if ([string]$authority.record.authorized_transition -cne
        'ISSUE_SOURCE_FREEZE_REVIEW') {
        throw 'Q1_HUMAN_AUTHORITY_UNAUTHORIZED'
    }
    $q1Record = Invoke-Stage1EFinalizerIdentityProvider `
        -Name 'New-Stage1ESourceFreezeReviewRecord' `
        -Parameters ([ordered]@{
            ApprovedCommit = $ExpectedApprovedCommit
            ApprovedTree = [string]$tree.text
            QualificationExecutionId = $QualificationExecutionId
            WorkspaceIdentity = $WorkspaceIdentity
            SourceCandidateIdentity = $sourceCandidateIdentity
            ValidationEvidenceIdentity = $validationCandidateIdentity
            RuntimeBackendCandidateIdentity =
                [string]$runtimeCandidate.identity_sha256
            WarningPolicyCandidateIdentity = $warningCandidateIdentity
            ImplementationPolicyCandidateIdentity = $policyCandidateIdentity
            ImplementationConfigurationCandidateIdentity =
                $configurationCandidateIdentity
            HumanDecisionRecordSha256 = [string]$human.sha256
            HumanAuthorityRecord = $authority.record
            PreviewReviewIdentity = $acceptedPreviewIdentity
            Prt04BaseReportSha256 = $baseExecutionReportSha256
            FinalizerCorrectionReportSha256 =
                $finalizerCorrectionReportSha256
            Prt05AuthorityClosureReportSha256 =
                $prt05AuthorityClosureReportSha256
            SourceInventoryCount = [int64]$inventoryRows.Count
            ProtectedSourceCheckedCount =
                [int64]$protectedSourceSummary.checked_count
            ProtectedSourceMismatchCount =
                [int64]$protectedSourceSummary.mismatch_count
        })
    $q1Bytes = Invoke-Stage1EFinalizerIdentityProvider `
        -Name 'ConvertTo-Stage1EQualificationRecordBytes' `
        -Parameters ([ordered]@{ Record = $q1Record })
    $q1Leaf = 'source_freeze_review_record.json'
    $inventoryText = @(
        'schema_version=stage1e-authority-sha256-inventory-v1'
        ('file={0}|{1}|{2}' -f $q1Leaf, $q1Bytes.Length,
            (Get-Stage1ESha256Hex -Bytes $q1Bytes))
    ) -join "`n"
    $inventoryText += "`n"
    $q1Files = [ordered]@{
        $q1Leaf = $q1Bytes
        'sha256_inventory.txt' = ConvertTo-Stage1EUtf8Bytes $inventoryText
    }
    $q1Verifiers = [ordered]@{
        $q1Leaf = 'QUALIFICATION_RECORD'
    }
    $null = Publish-Stage1EAtomicAuthoritySet -Root $evidenceRoot `
        -FileBytes $q1Files -VerifierKinds $q1Verifiers
    $porcelainAfterPublication = Invoke-Stage1EGitText $repository @(
        'status','--porcelain=v1','--untracked-files=all')
    if (-not [string]::IsNullOrEmpty($porcelainAfterPublication.text)) {
        if ([System.IO.Directory]::Exists($evidenceRoot)) {
            [System.IO.Directory]::Delete($evidenceRoot, $true)
        }
        throw 'Q1_REPOSITORY_MUTATION_DETECTED'
    }
    return [pscustomobject]@{
        Status = 'SOURCE_FREEZE_REVIEWED_Q1_PASS'
        EvidenceRoot = $evidenceRoot
        SourceFreezeReviewIdentity = $q1Record.identity_sha256
        Q1 = 'PASS'
        RuntimeReview = 'REVIEW_REQUIRED'
        CurrentReviewed = 'NOT_ISSUED'
        Qualification = 'NOT_AVAILABLE'
        Authorization = 'NONE'
        Run2 = 'NOT_STARTED'
    }
}

$sourceFreeze = Read-Stage1EQualificationRecord `
    -Path $SourceFreezeReviewRecordPath `
    -ExpectedSchemaVersion 'stage1e-source-freeze-review-record-v1'
$liveClosure = Read-Stage1EQualificationRecord `
    -Path $Q5LiveClosureEvidencePath `
    -ExpectedSchemaVersion 'stage1e-q0-q5-live-closure-evidence-v1'
$qualificationAuthority = Read-Stage1EQualificationRecord `
    -Path $HumanAuthorityRecordPath `
    -ExpectedSchemaVersion 'stage1e-human-qualification-authority-record-v1'
if ([string]$sourceFreeze.record.approved_commit -cne
        $ExpectedApprovedCommit -or
    [string]$sourceFreeze.record.approved_tree -cne [string]$tree.text) {
    throw 'Q5_APPROVED_COMMIT_TREE_MISMATCH'
}
if ([string]$sourceFreeze.record.qualification_execution_id -cne
        $QualificationExecutionId -or
    [string]$liveClosure.record.qualification_execution_id -cne
        $QualificationExecutionId -or
    [string]$qualificationAuthority.record.qualification_execution_id -cne
        $QualificationExecutionId) {
    throw 'Q5_MIXED_EXECUTION_IDS'
}
if ([string]$sourceFreeze.record.workspace_identity -cne $WorkspaceIdentity -or
    [string]$liveClosure.record.workspace_identity -cne $WorkspaceIdentity -or
    [string]$qualificationAuthority.record.workspace_identity -cne
        $WorkspaceIdentity) {
    throw 'Q5_MIXED_WORKSPACE_IDENTITIES'
}
if ([string]$sourceFreeze.record.source_candidate_identity -cne
        $sourceCandidateIdentity -or
    [string]$sourceFreeze.record.validation_evidence_identity -cne
        $validationCandidateIdentity -or
    [string]$sourceFreeze.record.runtime_backend_candidate_identity -cne
        [string]$runtimeCandidate.identity_sha256) {
    throw 'Q5_MIXED_SOURCE_IDENTITIES'
}
if ([string]$sourceFreeze.record.prt05_authority_closure_report_sha256 -cne
        $prt05AuthorityClosureReportSha256 -or
    [string]$liveClosure.record.prt05_authority_closure_report_sha256 -cne
        $prt05AuthorityClosureReportSha256) {
    throw 'Q5_PRT05_REPORT_BINDING_MISMATCH'
}

$runtimeReview = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'New-Stage1ERuntimeReviewRecord' `
    -Parameters ([ordered]@{
        Candidate = $runtimeCandidate
        SourceFreezeReviewRecord = $sourceFreeze.record
        LiveClosureEvidence = $liveClosure.record
        QualificationAuthorityRecord = $qualificationAuthority.record
    })
$currentBackend = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'New-Stage1ERuntimeBackendIdentityV2CurrentReviewed' `
    -Parameters ([ordered]@{
        Candidate = $runtimeCandidate
        RuntimeReviewRecord = $runtimeReview
        LiveClosureEvidence = $liveClosure.record
        QualificationAuthorityRecord = $qualificationAuthority.record
    })
$qualification = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'New-Stage1EQualificationIdentity' `
    -Parameters ([ordered]@{
        CurrentReviewedBackend = $currentBackend
        RuntimeReviewRecord = $runtimeReview
        SourceFreezeReviewRecord = $sourceFreeze.record
        LiveClosureEvidence = $liveClosure.record
        QualificationAuthorityRecord = $qualificationAuthority.record
    })
$terminal = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'New-Stage1EQualificationTerminalRecord' `
    -Parameters ([ordered]@{
        QualificationIdentity = $qualification
        CurrentReviewedBackend = $currentBackend
        RuntimeReviewRecord = $runtimeReview
    })
$runtimeReviewBytes = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'ConvertTo-Stage1EQualificationRecordBytes' `
    -Parameters ([ordered]@{ Record = $runtimeReview })
$currentBackendBytes = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'ConvertTo-Stage1ERuntimeBackendIdentityV2Bytes' `
    -Parameters ([ordered]@{
        Record = $currentBackend
        RepositoryRoot = $repository
        RequireCommittedBytes = $true
    })
$qualificationBytes = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'ConvertTo-Stage1EQualificationRecordBytes' `
    -Parameters ([ordered]@{ Record = $qualification })
$terminalBytes = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'ConvertTo-Stage1EQualificationRecordBytes' `
    -Parameters ([ordered]@{ Record = $terminal })
$q5PrimaryFiles = [ordered]@{
    'runtime_review_record.json' = $runtimeReviewBytes
    'runtime_backend_current_reviewed.json' = $currentBackendBytes
    'qualification_identity.json' = $qualificationBytes
    'qualification_terminal_record.json' = $terminalBytes
}
$q5Rows = [System.Collections.Generic.List[object]]::new()
$ordinal = 0
foreach ($leafValue in $q5PrimaryFiles.Keys) {
    $ordinal++
    $leaf = [string]$leafValue
    $bytes = [byte[]]$q5PrimaryFiles[$leaf]
    $q5Rows.Add([ordered]@{
            ordinal = [int64]$ordinal
            leaf_name = $leaf
            byte_count = [int64]$bytes.Length
            file_sha256 = Get-Stage1ESha256Hex -Bytes $bytes
        })
}
$q5Envelope = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'New-Stage1EAtomicQ5ResultEnvelope' `
    -Parameters ([ordered]@{
        RuntimeReviewRecord = $runtimeReview
        CurrentReviewedBackend = $currentBackend
        QualificationIdentity = $qualification
        QualificationTerminalRecord = $terminal
        Files = [object[]]$q5Rows.ToArray()
    })
$q5EnvelopeBytes = Invoke-Stage1EFinalizerIdentityProvider `
    -Name 'ConvertTo-Stage1EQualificationRecordBytes' `
    -Parameters ([ordered]@{ Record = $q5Envelope })
$q5Files = [ordered]@{}
foreach ($leafValue in $q5PrimaryFiles.Keys) {
    $q5Files.Add([string]$leafValue, [byte[]]$q5PrimaryFiles[$leafValue])
}
$q5Files.Add('q5_result_envelope.json', $q5EnvelopeBytes)
$q5InventoryBuilder = [System.Text.StringBuilder]::new()
$null = $q5InventoryBuilder.Append(
    "schema_version=stage1e-authority-sha256-inventory-v1`n")
foreach ($leafValue in $q5Files.Keys) {
    $leaf = [string]$leafValue
    $bytes = [byte[]]$q5Files[$leaf]
    $null = $q5InventoryBuilder.Append(('file={0}|{1}|{2}' -f $leaf,
            $bytes.Length, (Get-Stage1ESha256Hex -Bytes $bytes)))
    $null = $q5InventoryBuilder.Append("`n")
}
$q5Files.Add('sha256_inventory.txt',
    (ConvertTo-Stage1EUtf8Bytes $q5InventoryBuilder.ToString()))
$q5Verifiers = [ordered]@{
    'runtime_review_record.json' = 'QUALIFICATION_RECORD'
    'runtime_backend_current_reviewed.json' = 'RUNTIME_BACKEND'
    'qualification_identity.json' = 'QUALIFICATION_RECORD'
    'qualification_terminal_record.json' = 'QUALIFICATION_RECORD'
    'q5_result_envelope.json' = 'QUALIFICATION_RECORD'
}
$null = Publish-Stage1EAtomicAuthoritySet -Root $evidenceRoot `
    -FileBytes $q5Files -VerifierKinds $q5Verifiers
$porcelainAfterPublication = Invoke-Stage1EGitText $repository @(
    'status','--porcelain=v1','--untracked-files=all')
if (-not [string]::IsNullOrEmpty($porcelainAfterPublication.text)) {
    if ([System.IO.Directory]::Exists($evidenceRoot)) {
        [System.IO.Directory]::Delete($evidenceRoot, $true)
    }
    throw 'Q5_REPOSITORY_MUTATION_DETECTED'
}
return [pscustomobject]@{
    Status = 'QUALIFIED_NOT_AUTHORIZED_Q5_PASS'
    EvidenceRoot = $evidenceRoot
    RuntimeReviewIdentity = $runtimeReview.identity_sha256
    RuntimeBackendIdentity = $currentBackend.identity_sha256
    QualificationIdentity = $qualification.identity_sha256
    QualificationTerminalIdentity = $terminal.identity_sha256
    Q5 = 'PASS'
    RuntimeReview = 'CURRENT_REVIEWED'
    Qualification = 'QUALIFIED_AVAILABLE'
    TerminalState = 'QUALIFIED_NOT_AUTHORIZED'
    Authorization = 'NONE'
    Run2 = 'NOT_STARTED'
    Implementation = 'NOT_EXECUTED'
    Artifact = 'NONE'
    Publication = 'NONE'
    Board = 'NONE'
}
