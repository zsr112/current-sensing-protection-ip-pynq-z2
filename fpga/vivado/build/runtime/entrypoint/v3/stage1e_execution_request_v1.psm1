Set-StrictMode -Version Latest

$script:Stage1EExecutionRequestInterface =
    'stage1e-execution-request-interface-v1'
$script:Stage1EVivadoMaximumGeneratedPathLength = 248
$script:Stage1EVivadoPathSafetyMargin = 16
$script:Stage1EVivadoGeneratedPathTemplates = @(
    [ordered]@{
        evidence_id = 'S1E-ENGINEERING-ARTIFACTS-20260724T174230Z:protection_ip_axi_lite'
        owning_run = 'protection_system_protection_ip_axi_lite_0_0_synth_1'
        relative_path = 'project/{project_identity}.runs/' +
            'protection_system_protection_ip_axi_lite_0_0_synth_1/.Xil/' +
            'Vivado-52096-illusion/' +
            'protection_system_protection_ip_axi_lite_0_0_in_context.xdc'
    }
    [ordered]@{
        evidence_id = 'S1E-ENGINEERING-ARTIFACTS-20260724T174230Z:system_ila_stage2b'
        owning_run = 'protection_system_system_ila_stage2b_0_0_synth_1'
        relative_path = 'project/{project_identity}.runs/' +
            'protection_system_system_ila_stage2b_0_0_synth_1/.Xil/' +
            'Vivado-24976-illusion/' +
            'protection_system_system_ila_stage2b_0_0.hwdef'
    }
    [ordered]@{
        evidence_id = 'S1E-ENGINEERING-ARTIFACTS-20260724T174230Z:processing_system7'
        owning_run = 'protection_system_processing_system7_0_0_synth_1'
        relative_path = 'project/{project_identity}.runs/' +
            'protection_system_processing_system7_0_0_synth_1/.Xil/' +
            'Vivado-41612-illusion/' +
            'protection_system_processing_system7_0_0.hwdef'
    }
    [ordered]@{
        evidence_id = 'STAGE1E-20260718-033953-36f6ec4:smartconnect_xil'
        owning_run = 'protection_system_smartconnect_0_0'
        relative_path = '.Xil/Vivado-0000000000-stage1e-controlled/coregen/' +
            'protection_system_smartconnect_0_0/' +
            'sc_xtlm_protection_system_smartconnect_0_0.mem'
    }
)

function Get-Stage1EExecutionRequestInterfaceVersion {
    return $script:Stage1EExecutionRequestInterface
}

function ConvertTo-Stage1EExecutionNativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path.Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar))
}

function ConvertTo-Stage1EExecutionCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (ConvertTo-Stage1EExecutionNativePath $Path).Replace(
        [System.IO.Path]::DirectorySeparatorChar, '/')
}

function Get-Stage1ECompactVivadoProjectName {
    param([Parameter(Mandatory = $true)][string]$RequestIdentity)

    if ($RequestIdentity -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Request identity must be a lowercase SHA-256 identity.'
    }
    return 's1e_' + $RequestIdentity.Substring(0, 12)
}

function Get-Stage1EVivadoPathBudgetProjection {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RequestIdentity
    )

    $workspacePath = ConvertTo-Stage1EExecutionNativePath $WorkspaceRoot
    $projectName = Get-Stage1ECompactVivadoProjectName $RequestIdentity
    $projections = [System.Collections.Generic.List[object]]::new()
    $longestPath = ''
    $longestLength = 0
    foreach ($template in $script:Stage1EVivadoGeneratedPathTemplates) {
        $relativePath = ([string]$template.relative_path).Replace(
            '{project_identity}', $projectName)
        $projectedPath = ConvertTo-Stage1EExecutionNativePath (
            Join-Path $workspacePath $relativePath)
        if (-not (Test-Stage1EExecutionPathEqualOrDescendant `
                -Candidate $projectedPath -Root $workspacePath) -or
            $projectedPath.Equals($workspacePath,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Reviewed Vivado generated path escaped workspace_root.'
        }
        $projectedLength = $projectedPath.Length
        $canonicalProjectedPath = ConvertTo-Stage1EExecutionCanonicalPath `
            $projectedPath
        $projections.Add([ordered]@{
                evidence_id = [string]$template.evidence_id
                owning_run = [string]$template.owning_run
                relative_path = $relativePath.Replace('\', '/')
                projected_path = $canonicalProjectedPath
                projected_length = $projectedLength
            })
        if ($projectedLength -gt $longestLength) {
            $longestPath = $canonicalProjectedPath
            $longestLength = $projectedLength
        }
    }
    return [ordered]@{
        workspace_root = ConvertTo-Stage1EExecutionCanonicalPath $workspacePath
        compact_project_name = $projectName
        longest_projected_path = $longestPath
        projected_length = $longestLength
        safety_margin = $script:Stage1EVivadoPathSafetyMargin
        maximum_length = $script:Stage1EVivadoMaximumGeneratedPathLength
        projections = @($projections)
    }
}

function Assert-Stage1EVivadoPathBudget {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RequestIdentity
    )

    $projection = Get-Stage1EVivadoPathBudgetProjection `
        -WorkspaceRoot $WorkspaceRoot -RequestIdentity $RequestIdentity
    if ([int]$projection.projected_length + [int]$projection.safety_margin -gt
        [int]$projection.maximum_length) {
        throw (('VIVADO_PATH_BUDGET_EXCEEDED workspace_root="{0}" ' +
            'compact_project_name="{1}" longest_projected_path="{2}" ' +
            'projected_length={3} safety_margin={4} maximum_length={5}') -f
            $projection.workspace_root, $projection.compact_project_name,
            $projection.longest_projected_path, $projection.projected_length,
            $projection.safety_margin, $projection.maximum_length)
    }
    return $projection
}

function Test-Stage1EExecutionPathEqualOrDescendant {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $candidatePath = (ConvertTo-Stage1EExecutionCanonicalPath $Candidate).
        TrimEnd('/')
    $rootPath = (ConvertTo-Stage1EExecutionCanonicalPath $Root).TrimEnd('/')
    if ($candidatePath.Equals($rootPath,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $candidatePath.StartsWith($rootPath + '/',
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-Stage1EExecutionPathsDisjoint {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ((Test-Stage1EExecutionPathEqualOrDescendant $Left $Right) -or
        (Test-Stage1EExecutionPathEqualOrDescendant $Right $Left)) {
        throw "$Label paths overlap."
    }
}

function Invoke-Stage1EExecutionGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
        throw "Git validation failed: $($output -join ' ')"
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Import-Stage1EExecutionRequestContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BuildRoot,
        [ValidateSet('stage1e-execution-request-v1', 'stage1e-execution-request-v2')]
        [string]$SchemaVersion = 'stage1e-execution-request-v1'
    )

    $canonicalJson = Join-Path $BuildRoot 'lib/stage1e_runtime_canonical_json_v1.psm1'
    if ($null -eq (Get-Command Get-Stage1ECanonicalJsonInterfaceVersion `
            -ErrorAction SilentlyContinue)) {
        Import-Module -Name $canonicalJson -ErrorAction Stop
    }
    if ((Get-Stage1ECanonicalJsonInterfaceVersion) -cne
        'stage1e-runtime-canonical-json-interface-v1') {
        throw 'The canonical JSON provider interface differs.'
    }

    $version = if ($SchemaVersion -ceq 'stage1e-execution-request-v2') { 'v2' } else { 'v1' }
    $schemaPath = Join-Path $BuildRoot "config/stage1e_execution_request_schema_$version.json"
    $schema = ConvertFrom-Stage1ECanonicalJsonBytes -Bytes (
        [System.IO.File]::ReadAllBytes($schemaPath))
    return [ordered]@{
        schema = $schema
        registry = [ordered]@{
            $SchemaVersion = $schema
        }
    }
}

function Read-Stage1EExecutionRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [Parameter(Mandatory = $true)][string]$ExpectedRequestIdentity,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Contract
    )

    if (-not [System.IO.Path]::IsPathRooted($RequestPath)) {
        throw 'RequestPath must be absolute.'
    }
    if ($ExpectedRequestIdentity -cnotmatch '^[0-9a-f]{64}$') {
        throw 'ExpectedRequestIdentity must be a lowercase SHA-256 identity.'
    }
    $item = Get-Item -LiteralPath $RequestPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'The execution request must be a regular, non-reparse-point file.'
    }

    $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
    $request = ConvertFrom-Stage1ECanonicalJsonEnvelope -Bytes $bytes `
        -Schema $Contract.schema -SchemaRegistry $Contract.registry
    $identityRecord = [ordered]@{}
    foreach ($key in $request.Keys) {
        if ([string]$key -cne 'request_identity') {
            $identityRecord[[string]$key] = $request[$key]
        }
    }
    $identityBytes = ConvertTo-Stage1ECanonicalJsonBytes -Value $identityRecord `
        -Schema $Contract.schema -SchemaRegistry $Contract.registry `
        -OmitProperty 'request_identity'
    $calculatedIdentity = Get-Stage1ECanonicalDigest -Bytes $identityBytes
    if ([string]$request.request_identity -cne $calculatedIdentity -or
        $calculatedIdentity -cne $ExpectedRequestIdentity) {
        throw 'The whole-record request identity is missing, invalid, or substituted.'
    }
    return $request
}

function Assert-Stage1EExecutionIdentityText {
    param([Parameter(Mandatory = $true)][string]$Value, [string]$Label = 'Identity')

    if ($Value -cnotmatch '^[0-9a-f]{40}$') {
        throw "$Label must be a lowercase 40-character Git identity."
    }
}

function Assert-Stage1EExecutionCleanSource {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $status = Invoke-Stage1EExecutionGit -RepositoryRoot $RepositoryRoot `
        -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    if (-not [string]::IsNullOrEmpty($status)) {
        throw 'WORKTREE_NOT_CLEAN'
    }
}

function Assert-Stage1EExportSource {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Source
    )

    $manifestPath = Join-Path $RepositoryRoot 'SOURCE_MANIFEST.json'
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        [string]$Source.export_manifest_sha256) {
        throw 'EXPORT_MANIFEST_IDENTITY_MISMATCH'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
    if ($manifest.schema -cne 'csip-source-export-v1' -or
        $manifest.origin.commit -cne $Source.expected_commit -or
        $manifest.origin.tree -cne $Source.expected_tree) {
        throw 'EXPORT_ORIGIN_MISMATCH'
    }
    $files = @($manifest.files.Keys | Sort-Object)
    $actual = @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Force | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $_.FullName).Replace('\', '/')
        if ($relative -cne 'SOURCE_MANIFEST.json') { $relative }
    } | Sort-Object)
    if (@(Compare-Object $files $actual).Count -ne 0) { throw 'EXPORT_FILE_SET_MISMATCH' }
    foreach ($relative in $files) {
        if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains('\') -or
            @($relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -ne 0) {
            throw 'EXPORT_PATH_INVALID'
        }
        $path = Join-Path $RepositoryRoot $relative
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $item.Length -ne $manifest.files[$relative].size_bytes -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne
                $manifest.files[$relative].sha256) {
            throw "EXPORT_FILE_CHANGED: $relative"
        }
    }
}

function Assert-Stage1EExecutionRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Request,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$BuildRoot
    )

    $sourceRoot = ConvertTo-Stage1EExecutionNativePath $Request.source.repository_root
    $selectedRepositoryRoot = ConvertTo-Stage1EExecutionNativePath $RepositoryRoot
    if (-not $sourceRoot.Equals($selectedRepositoryRoot,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The sealed request repository_root does not bind this entrypoint repository.'
    }
    if (-not [System.IO.Directory]::Exists($sourceRoot)) {
        throw 'The sealed request repository root does not exist.'
    }
    Assert-Stage1EExecutionIdentityText ([string]$Request.source.expected_commit) 'Expected commit'
    Assert-Stage1EExecutionIdentityText ([string]$Request.source.expected_tree) 'Expected tree'
    $sourceState = 'CLEAN'
    if ($Request.source.Contains('export_manifest_sha256')) {
        Assert-Stage1EExportSource -RepositoryRoot $sourceRoot -Source $Request.source
        $sourceState = 'HASH_VERIFIED_EXPORT'
    } else {
    $actualCommit = Invoke-Stage1EExecutionGit -RepositoryRoot $sourceRoot `
        -Arguments @('rev-parse', 'HEAD')
    $actualTree = Invoke-Stage1EExecutionGit -RepositoryRoot $sourceRoot `
        -Arguments @('rev-parse', 'HEAD^{tree}')
    if ($actualCommit -cne [string]$Request.source.expected_commit) {
        throw 'SOURCE_COMMIT_MISMATCH'
    }
    if ($actualTree -cne [string]$Request.source.expected_tree) {
        throw 'SOURCE_TREE_MISMATCH'
    }
    Assert-Stage1EExecutionCleanSource -RepositoryRoot $sourceRoot
    }

    if ([string]$Request.execution_id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$') {
        throw 'execution_id is not a portable execution identifier.'
    }
    $workspaceRoot = ConvertTo-Stage1EExecutionNativePath $Request.paths.workspace_root
    $outputRoot = ConvertTo-Stage1EExecutionNativePath $Request.paths.output_root
    $null = Assert-Stage1EVivadoPathBudget -WorkspaceRoot $workspaceRoot `
        -RequestIdentity ([string]$Request.request_identity)
    Assert-Stage1EExecutionPathsDisjoint $sourceRoot $workspaceRoot 'Source/workspace'
    Assert-Stage1EExecutionPathsDisjoint $sourceRoot $outputRoot 'Source/output'
    Assert-Stage1EExecutionPathsDisjoint $workspaceRoot $outputRoot 'Workspace/output'
    foreach ($path in @($workspaceRoot, $outputRoot)) {
        if ([System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path)) {
            throw "Execution-ID collision or non-fresh root: $path"
        }
        $parent = [System.IO.Path]::GetDirectoryName($path)
        if ([string]::IsNullOrEmpty($parent) -or
            -not [System.IO.Directory]::Exists($parent)) {
            throw "Fresh root parent does not exist: $path"
        }
    }

    $executionContractPath = Join-Path $BuildRoot 'config/stage1e_execution_contract_v1.json'
    if (-not [System.IO.File]::Exists($executionContractPath) -or
        (Get-Stage1ESha256Hex -Bytes ([System.IO.File]::ReadAllBytes(
                    $executionContractPath))) -cne
            [string]$Request.execution_contract_identity) {
        throw 'The execution contract identity does not match the machine runtime owner.'
    }

    if ([string]$Request.run_kind -ceq 'FORMAL') {
        throw 'FORMAL_CURRENT_RUN_FINDING_COMPARATOR_NOT_IMPLEMENTED'
    }
    if ([string]$Request.finding_decision_identity -cne 'NONE') {
        throw 'ENGINEERING execution requires finding_decision_identity NONE.'
    }
    if ([string]$Request.implementation_profile -cnotin @(
            'SAFE_INERT', 'READY_AWARE_SYNTHETIC_DIGITAL_STIMULUS')) {
        throw 'Unsupported sealed implementation profile.'
    }

    $vivadoExecutable = ConvertTo-Stage1EExecutionNativePath $Request.vivado.executable
    if (-not [System.IO.File]::Exists($vivadoExecutable)) {
        throw 'The sealed Vivado executable does not exist.'
    }
    if ([System.IO.Path]::GetExtension($vivadoExecutable).ToLowerInvariant() -cnotin
        @('.exe', '.bat')) {
        throw 'The sealed Vivado executable must have the exact .exe or .bat extension.'
    }
    return [ordered]@{
        source_root = $sourceRoot
        workspace_root = $workspaceRoot
        output_root = $outputRoot
        vivado_executable = $vivadoExecutable
        source_state = $sourceState
        execution_contract_path = $executionContractPath
    }
}

function Resolve-Stage1EExecutionTerminalDisposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Request,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$ProcessResult,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$VivadoResult
    )

    if ([string]$Request.run_kind -ceq 'FORMAL') {
        throw 'FORMAL_CURRENT_RUN_FINDING_COMPARATOR_NOT_IMPLEMENTED'
    }
    if ([string]$Request.run_kind -cne 'ENGINEERING') {
        throw 'Unsupported run kind at terminal reconciliation.'
    }
    if ([string]$ProcessResult.state -cne 'COMPLETED' -or
        [string]$ProcessResult.exit_code -cne '0') {
        throw 'The supervised process result is not complete and successful.'
    }
    if ([string]$VivadoResult.result_state -cne 'COMPLETED' -or
        -not [bool]$VivadoResult.route_completed -or
        [int]$VivadoResult.forbidden_operation_count -ne 0 -or
        [string]$VivadoResult.collector_state -cne 'COLLECTED') {
        throw 'The Vivado result is incomplete, conflicted, or observed a forbidden operation.'
    }
    if ([string]$Request.build_target -ceq 'ARTIFACTS') {
        $roles = @($VivadoResult.artifact_inventory | ForEach-Object {
                [string]$_.role
            })
        $expectedRoles = @('BITSTREAM', 'XSA', 'HWH', 'LTX', 'ARTIFACT_MANIFEST')
        if (($roles -join ',') -cne ($expectedRoles -join ',') -or
            @($roles | Select-Object -Unique).Count -ne $roles.Count) {
            throw 'The ARTIFACTS result does not contain the exact unique artifact roles.'
        }
    }
    return [ordered]@{
        terminal_status = 'ENGINEERING_EVIDENCE_ONLY'
        acceptance_state = 'NOT_FORMALLY_ACCEPTED'
        reason = 'Engineering evidence was collected without formal acceptance.'
    }
}

function New-Stage1EVivadoExecutionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Request,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Validation
    )

    $projectName = Get-Stage1ECompactVivadoProjectName `
        ([string]$Request.request_identity)
    $projectDirectory = Join-Path $Validation.workspace_root 'project'
    $projectPath = Join-Path $projectDirectory ($projectName + '.xpr')
    return [ordered]@{
        context_schema_version = 'stage1e-vivado-execution-context-v1'
        execution_id = [string]$Request.execution_id
        request_identity = [string]$Request.request_identity
        run_kind = [string]$Request.run_kind
        vivado_version = [string]$Request.vivado.expected_version
        vivado_build = [string]$Request.vivado.expected_build
        repository_root = ConvertTo-Stage1EExecutionCanonicalPath $Validation.source_root
        workspace_path = ConvertTo-Stage1EExecutionCanonicalPath $Validation.workspace_root
        project_path = ConvertTo-Stage1EExecutionCanonicalPath $projectPath
        output_path = ConvertTo-Stage1EExecutionCanonicalPath $Validation.output_root
        report_root = ConvertTo-Stage1EExecutionCanonicalPath (Join-Path $Validation.output_root 'reports')
        artifact_root = ConvertTo-Stage1EExecutionCanonicalPath (Join-Path $Validation.output_root 'artifacts')
        result_path = ConvertTo-Stage1EExecutionCanonicalPath (Join-Path $Validation.output_root 'vivado_result.json')
        part = [string]$Request.hardware.part
        board_part = [string]$Request.hardware.board_part
        build_target = [string]$Request.build_target
        implementation_profile = [string]$Request.implementation_profile
        source_commit = [string]$Request.source.expected_commit
        source_tree = [string]$Request.source.expected_tree
        execution_contract_identity = [string]$Request.execution_contract_identity
        finding_decision_identity = [string]$Request.finding_decision_identity
        project_retention = if ([bool]$Request.retain_project) { 'RETAIN' } else { 'REMOVE' }
        process_identity = [string]$Request.execution_id
        project_identity = $projectName
        design_identity = 'protection_system'
        phase_journal_path = ConvertTo-Stage1EExecutionCanonicalPath (
            Join-Path $Validation.output_root 'journal/runner-phase.tsv')
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EExecutionRequestInterfaceVersion'
    'ConvertTo-Stage1EExecutionNativePath'
    'ConvertTo-Stage1EExecutionCanonicalPath'
    'Test-Stage1EExecutionPathEqualOrDescendant'
    'Assert-Stage1EExecutionPathsDisjoint'
    'Import-Stage1EExecutionRequestContract'
    'Read-Stage1EExecutionRequest'
    'Assert-Stage1EExecutionRequest'
    'Assert-Stage1EExportSource'
    'Resolve-Stage1EExecutionTerminalDisposition'
    'New-Stage1EVivadoExecutionContext'
)
