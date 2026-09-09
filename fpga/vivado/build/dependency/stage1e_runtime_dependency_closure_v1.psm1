Set-StrictMode -Version Latest

$script:Stage1EDependencyClosureInterface =
    'stage1e-runtime-dependency-closure-interface-v1'
$script:Stage1EDependencyHashAdapterInterface =
    'stage1e-prt02e-sha256-empty-byte-adapter-interface-v1'
$script:Stage1EDependencyBuildRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
$script:Stage1EDependencyRepositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../../../..'))

function Get-Stage1EDependencyClosureInterfaceVersion {
    return $script:Stage1EDependencyClosureInterface
}

function Get-Stage1EDependencyHashAdapterInterfaceVersion {
    return $script:Stage1EDependencyHashAdapterInterface
}

function Get-Stage1EDependencySha256Hex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $provider = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $provider.ComputeHash($Bytes) }
    finally { $provider.Dispose() }
    $builder = [System.Text.StringBuilder]::new(64)
    foreach ($octet in $digest) {
        $null = $builder.Append($octet.ToString('x2',
                [System.Globalization.CultureInfo]::InvariantCulture))
    }
    return $builder.ToString()
}

function ConvertFrom-Stage1ETclList {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $items = [System.Collections.Generic.List[string]]::new()
    $index = 0
    while ($index -lt $Text.Length) {
        while ($index -lt $Text.Length -and
            [char]::IsWhiteSpace($Text[$index])) { $index++ }
        if ($index -ge $Text.Length) { break }

        $builder = [System.Text.StringBuilder]::new()
        if ($Text[$index] -eq '{') {
            $depth = 1
            $index++
            while ($index -lt $Text.Length -and $depth -gt 0) {
                $character = $Text[$index]
                if ($character -eq '\') {
                    if ($index + 1 -ge $Text.Length) {
                        throw 'Tcl list contains a trailing backslash.'
                    }
                    $null = $builder.Append($character)
                    $index++
                    $null = $builder.Append($Text[$index])
                    $index++
                    continue
                }
                if ($character -eq '{') {
                    $depth++
                    $null = $builder.Append($character)
                    $index++
                    continue
                }
                if ($character -eq '}') {
                    $depth--
                    $index++
                    if ($depth -gt 0) { $null = $builder.Append($character) }
                    continue
                }
                $null = $builder.Append($character)
                $index++
            }
            if ($depth -ne 0) { throw 'Tcl list contains an unmatched brace.' }
            if ($index -lt $Text.Length -and
                -not [char]::IsWhiteSpace($Text[$index])) {
                throw 'Tcl braced list element has trailing characters.'
            }
        }
        elseif ($Text[$index] -eq '"') {
            $index++
            $closed = $false
            while ($index -lt $Text.Length) {
                $character = $Text[$index]
                if ($character -eq '"') {
                    $closed = $true
                    $index++
                    break
                }
                if ($character -eq '\') {
                    if ($index + 1 -ge $Text.Length) {
                        throw 'Tcl quoted list element has a trailing backslash.'
                    }
                    $index++
                    $character = $Text[$index]
                    switch ($character) {
                        'n' { $null = $builder.Append("`n") }
                        'r' { $null = $builder.Append("`r") }
                        't' { $null = $builder.Append("`t") }
                        default { $null = $builder.Append($character) }
                    }
                    $index++
                    continue
                }
                $null = $builder.Append($character)
                $index++
            }
            if (-not $closed) { throw 'Tcl list contains an unmatched quote.' }
            if ($index -lt $Text.Length -and
                -not [char]::IsWhiteSpace($Text[$index])) {
                throw 'Tcl quoted list element has trailing characters.'
            }
        }
        else {
            while ($index -lt $Text.Length -and
                -not [char]::IsWhiteSpace($Text[$index])) {
                $character = $Text[$index]
                if ($character -eq '\') {
                    if ($index + 1 -ge $Text.Length) {
                        throw 'Tcl bare list element has a trailing backslash.'
                    }
                    $index++
                    $character = $Text[$index]
                }
                $null = $builder.Append($character)
                $index++
            }
        }
        $items.Add($builder.ToString())
    }
    return $items.ToArray()
}

function ConvertFrom-Stage1ETclDictionary {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $items = @(ConvertFrom-Stage1ETclList -Text $Text)
    if (($items.Count % 2) -ne 0) {
        throw 'Tcl dictionary does not contain an even number of elements.'
    }
    $result = [ordered]@{}
    for ($index = 0; $index -lt $items.Count; $index += 2) {
        $key = $items[$index]
        if ($result.Contains($key)) {
            throw "Tcl dictionary contains duplicate key '$key'."
        }
        $result[$key] = $items[$index + 1]
    }
    return $result
}

function Read-Stage1ETclDictionaryFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes(
        [System.IO.Path]::GetFullPath($Path))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and
        $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        throw "Tcl dictionary contains a UTF-8 BOM: $Path"
    }
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $encoding.GetString($bytes)
    return ConvertFrom-Stage1ETclDictionary -Text $text
}

function ConvertFrom-Stage1ERecordList {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(ConvertFrom-Stage1ETclList -Text $Text)) {
        $records.Add((ConvertFrom-Stage1ETclDictionary -Text $item))
    }
    return $records.ToArray()
}

function Import-Stage1EDependencyContracts {
    [CmdletBinding()]
    param([string]$BuildRoot = $script:Stage1EDependencyBuildRoot)

    $configRoot = Join-Path ([System.IO.Path]::GetFullPath($BuildRoot)) 'config'
    $dependency = Read-Stage1ETclDictionaryFile -Path (Join-Path $configRoot `
        'stage1e_runtime_dependency_contract_v1.dict')
    $provider = Read-Stage1ETclDictionaryFile -Path (Join-Path $configRoot `
        'stage1e_runtime_provider_contract_v1.dict')
    $external = Read-Stage1ETclDictionaryFile -Path (Join-Path $configRoot `
        'stage1e_runtime_external_capability_contract_v1.dict')
    $graph = Read-Stage1ETclDictionaryFile -Path (Join-Path $configRoot `
        'stage1e_runtime_declared_graph_v1.dict')

    return [pscustomobject]@{
        Dependency = $dependency
        Provider = $provider
        External = $external
        Graph = $graph
        Nodes = @(ConvertFrom-Stage1ERecordList -Text $graph.nodes)
        Edges = @(ConvertFrom-Stage1ERecordList -Text $graph.edges)
        Providers = @(ConvertFrom-Stage1ERecordList -Text $provider.providers)
        Capabilities = @(ConvertFrom-Stage1ERecordList -Text `
            $external.capabilities)
        IdentityInputs = @(ConvertFrom-Stage1ERecordList -Text `
            $graph.identity_inputs)
        TraceProjections = @(ConvertFrom-Stage1ERecordList -Text `
            $graph.trace_projection_nodes)
        ReviewToolNodes = @(ConvertFrom-Stage1ETclList -Text `
            $graph.review_tool_nodes)
        TraceProjectionEdges = @(ConvertFrom-Stage1ERecordList -Text `
            $graph.trace_projection_edges)
        LedgerProjectionRules = @(ConvertFrom-Stage1ERecordList -Text `
            $graph.ledger_projection_rules)
        ReviewTraceEdges = @(ConvertFrom-Stage1ERecordList -Text `
            $graph.review_trace_edges)
        TraceExpectedOccurrences = @(ConvertFrom-Stage1ERecordList -Text `
            $graph.trace_expected_occurrences)
        TraceProviderOrder = @(ConvertFrom-Stage1ERecordList -Text `
            $graph.trace_provider_order)
    }
}

function Test-Stage1EExactList {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Actual.Count -ne $Expected.Count) {
        throw "$Label count differs: expected $($Expected.Count), observed $($Actual.Count)."
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string]$Actual[$index] -cne [string]$Expected[$index]) {
            throw "$Label differs at ordinal $($index + 1)."
        }
    }
    return $true
}

function Assert-Stage1EDependencyContracts {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Contracts)

    if ($Contracts.Dependency.schema_version -cne
        'stage1e-runtime-dependency-contract-v1' -or
        $Contracts.Provider.schema_version -cne
        'stage1e-runtime-provider-contract-v1' -or
        $Contracts.External.schema_version -cne
        'stage1e-runtime-external-capability-contract-v1' -or
        $Contracts.Graph.schema_version -cne
        'stage1e-runtime-declared-graph-v1') {
        throw 'Dependency contract version mismatch.'
    }

    $expectedDirect = @(
        'ENTRY_POINT', 'LAUNCHER', 'RUNNER', 'COLLECTOR', 'PARSER',
        'IDENTITY_SERIALIZER', 'HOST_OBSERVER',
        'VIVADO_CAPABILITY_OBSERVER')
    $actualDirect = @(ConvertFrom-Stage1ETclList -Text `
        $Contracts.Dependency.direct_role_order)
    $null = Test-Stage1EExactList $actualDirect $expectedDirect `
        'Direct runtime role order'

    $expectedSubordinate = @(
        'RUNTIME_SCHEMA', 'HASH_PROVIDER', 'CONTROLLER', 'ADAPTER',
        'FRAMEWORK', 'REQUEST', 'RESULT', 'REPORT', 'MESSAGE', 'HOST')
    $actualSubordinate = @(ConvertFrom-Stage1ETclList -Text `
        $Contracts.Dependency.subordinate_contract_order)
    $null = Test-Stage1EExactList $actualSubordinate $expectedSubordinate `
        'Subordinate contract order'

    $directNodes = @($Contracts.Nodes | Where-Object {
            $_.node_class -ceq 'DIRECT_RUNTIME_SOURCE' })
    $null = Test-Stage1EExactList @($directNodes.role) $expectedDirect `
        'Declared direct runtime nodes'
    if ($Contracts.IdentityInputs.Count -ne 9) {
        throw 'Declared identity input count differs from the nine sealed inputs.'
    }

    $nodeIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $paths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $expectedOrdinal = 0
    foreach ($node in $Contracts.Nodes) {
        $expectedOrdinal++
        if ([int]$node.ordinal -ne $expectedOrdinal) {
            throw "Declared node ordinal differs at $($node.node_id)."
        }
        if (-not $nodeIds.Add([string]$node.node_id)) {
            throw "Duplicate declared node id: $($node.node_id)"
        }
        if ([string]::IsNullOrEmpty([string]$node.termination)) {
            throw "Declared node has no termination: $($node.node_id)"
        }
        if ($node.repository_path -ne 'NONE' -and
            -not $paths.Add([string]$node.repository_path)) {
            throw "Duplicate declared repository path: $($node.repository_path)"
        }
    }
    $reviewIds = @($Contracts.ReviewToolNodes)
    foreach ($reviewId in $reviewIds) {
        $reviewNode = $Contracts.Nodes | Where-Object {
            $_.node_id -ceq $reviewId } | Select-Object -First 1
        if ($null -eq $reviewNode -or
            $reviewNode.node_class -cne 'REVIEW_TOOL_SOURCE') {
            throw "Review-tool node declaration is missing or misclassified: $reviewId"
        }
    }
    foreach ($edge in $Contracts.Edges) {
        if (-not $nodeIds.Contains([string]$edge.from) -or
            -not $nodeIds.Contains([string]$edge.to)) {
            throw "Declared edge has an unknown endpoint: $($edge.ordinal)"
        }
    }

    $providerKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($provider in $Contracts.Providers) {
        if (-not $providerKeys.Add([string]$provider.provider_key)) {
            throw "Duplicate provider key: $($provider.provider_key)"
        }
        if (-not $paths.Contains([string]$provider.source_path)) {
            throw "Provider source is absent from the graph: $($provider.provider_key)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$provider.interface_command)) {
            throw "Provider interface command is absent: $($provider.provider_key)"
        }
    }
    $capabilityKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($capability in $Contracts.Capabilities) {
        if (-not $capabilityKeys.Add([string]$capability.capability_key)) {
            throw "Duplicate external capability: $($capability.capability_key)"
        }
    }

    foreach ($contractPath in @(
            'stage1e_runtime_dependency_contract_v1.dict',
            'stage1e_runtime_provider_contract_v1.dict',
            'stage1e_runtime_external_capability_contract_v1.dict',
            'stage1e_runtime_declared_graph_v1.dict')) {
        $text = [System.IO.File]::ReadAllText((Join-Path `
                $script:Stage1EDependencyBuildRoot "config/$contractPath"))
        if ($text -match '(?i)file_sha256\s+[0-9a-f]{64}' -or
            $text -match '(?i)identity_sha256\s+[0-9a-f]{64}') {
            throw "Dependency declaration contains a populated digest: $contractPath"
        }
    }
    return $true
}

function ConvertTo-Stage1ECanonicalRepositoryPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        throw "Repository path must be relative: $Path"
    }
    $normalized = $Path.Replace('\', '/')
    $components = @($normalized.Split('/'))
    if ($components.Count -eq 0 -or $components -contains '' -or
        $components -contains '.' -or $components -contains '..') {
        throw "Repository path contains a prohibited component: $Path"
    }
    foreach ($component in $components) {
        if ($component -match '~[0-9]' -or $component.Contains(':') -or
            $component.EndsWith('.', [System.StringComparison]::Ordinal) -or
            $component.EndsWith(' ', [System.StringComparison]::Ordinal)) {
            throw "Repository path contains an alias-prone component: $Path"
        }
    }
    return ($components -join '/')
}

function Resolve-Stage1EContainedRepositoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RepositoryPath
    )

    $relative = ConvertTo-Stage1ECanonicalRepositoryPath $RepositoryPath
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $native = $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $root $native))
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Repository path escapes the selected root: $RepositoryPath"
    }
    return $resolved
}

function Get-Stage1ERepositoryRootIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not [System.IO.Directory]::Exists($root)) {
        throw "Repository root does not exist: $root"
    }
    $item = Get-Item -LiteralPath $root -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Repository root is a reparse point: $root"
    }
    $volumeRoot = [System.IO.Path]::GetPathRoot($item.FullName)
    $drive = [System.IO.DriveInfo]::new($volumeRoot)
    return [pscustomobject]@{
        FullName = $item.FullName
        Attributes = [int64]$item.Attributes
        CreationTimeUtcTicks = $item.CreationTimeUtc.Ticks
        VolumeRoot = $volumeRoot
        DriveName = $drive.Name
        DriveFormat = $(if ($drive.IsReady) { $drive.DriveFormat } else { 'NOT_READY' })
    }
}

function Test-Stage1ERepositoryRootIdentityEqual {
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )
    return ($Left.FullName -ceq $Right.FullName -and
        $Left.Attributes -eq $Right.Attributes -and
        $Left.CreationTimeUtcTicks -eq $Right.CreationTimeUtcTicks -and
        $Left.VolumeRoot -ceq $Right.VolumeRoot -and
        $Left.DriveName -ceq $Right.DriveName -and
        $Left.DriveFormat -ceq $Right.DriveFormat)
}

function Resolve-Stage1EContainedSourceWithAncestors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RepositoryPath
    )

    $relative = ConvertTo-Stage1ECanonicalRepositoryPath $RepositoryPath
    $rootIdentity = Get-Stage1ERepositoryRootIdentity $RepositoryRoot
    $root = $rootIdentity.FullName
    $selectedVolume = $rootIdentity.VolumeRoot
    $current = Get-Item -LiteralPath $root -Force
    $components = @($relative.Split('/'))
    for ($index = 0; $index -lt $components.Count; $index++) {
        $component = $components[$index]
        $matches = @(Get-ChildItem -LiteralPath $current.FullName -Force |
            Where-Object { $_.Name -ieq $component })
        if ($matches.Count -ne 1) {
            throw "Declared source component is missing or ambiguous: $relative ($component)"
        }
        $item = $matches[0]
        if ($item.Name -cne $component) {
            throw "Declared source uses a case alias: $relative ($component)"
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) `
            -ne 0) {
            throw "Declared source ancestor is a reparse point: $relative ($component)"
        }
        if ([System.IO.Path]::GetPathRoot($item.FullName) -cne $selectedVolume) {
            throw "Declared source crosses the repository volume: $relative"
        }
        if ($index -lt ($components.Count - 1) -and
            $item -isnot [System.IO.DirectoryInfo]) {
            throw "Declared source ancestor is not a directory: $relative ($component)"
        }
        $current = $item
    }
    if ($current -isnot [System.IO.FileInfo]) {
        throw "Declared source is not a regular file: $relative"
    }
    $resolved = [System.IO.Path]::GetFullPath($current.FullName)
    $expected = Resolve-Stage1EContainedRepositoryPath $root $relative
    if ($resolved -cne $expected) {
        throw "Declared source resolves through a path alias: $relative"
    }
    return [pscustomobject]@{
        Path = $resolved
        RepositoryPath = $relative
        AncestorCount = $components.Count
        VolumeRoot = $selectedVolume
        RepositoryRootIdentity = $rootIdentity
    }
}

function Test-Stage1ESourceMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $rootIdentityBefore = Get-Stage1ERepositoryRootIdentity $root
    $casePaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $trackedCount = 0
    $reviewToolCount = 0
    $ancestorCount = 0
    foreach ($node in $Contracts.Nodes) {
        $relative = [string]$node.repository_path
        $evidence = Resolve-Stage1EContainedSourceWithAncestors $root $relative
        $resolved = $evidence.Path
        $ancestorCount += $evidence.AncestorCount
        if (-not $casePaths.Add($relative)) {
            throw "Repository source path is case-ambiguous: $relative"
        }
        # Avoid --error-unmatch here: under PowerShell's terminating native
        # error policy Git's diagnostic is promoted to an exception before we
        # can classify an intentionally-untracked review-tool source.  The
        # non-error listing is equivalent for membership purposes and keeps
        # stderr-free behavior deterministic.
        $trackedListing = @(& git -C $root ls-files -- $relative)
        if ($trackedListing.Count -eq 0) {
            if ([string]$node.node_class -ceq 'REVIEW_TOOL_SOURCE') {
                $reviewToolCount++
            }
            else {
                throw "Declared repository source is not Git-tracked: $relative"
            }
        }
        else {
            $trackedCount++
        }
        & git -C $root check-ignore --quiet -- $relative
        if ($LASTEXITCODE -eq 0) {
            throw "Declared repository source is ignored: $relative"
        }
    }
    $rootIdentityAfter = Get-Stage1ERepositoryRootIdentity $root
    if (-not (Test-Stage1ERepositoryRootIdentityEqual $rootIdentityBefore `
            $rootIdentityAfter)) {
        throw 'Repository root identity changed during source membership validation.'
    }
    return [pscustomobject]@{
        State = 'MATCH'
        TrackedSourceCount = $trackedCount
        ReviewToolSourceCount = $reviewToolCount
        AncestorEvidenceCount = $ancestorCount
        VolumeRoot = $rootIdentityBefore.VolumeRoot
        RepositoryRootIdentityState = 'STABLE'
        SourceIdentityCreated = $false
        DigestManifestCreated = $false
    }
}

function Get-Stage1ENodeByPathTable {
    param([Parameter(Mandatory = $true)]$Contracts)
    $table = @{}
    foreach ($node in $Contracts.Nodes) {
        $table[[string]$node.repository_path] = $node
    }
    return $table
}

function Get-Stage1ENodeByIdTable {
    param([Parameter(Mandatory = $true)]$Contracts)
    $table = @{}
    foreach ($node in $Contracts.Nodes) { $table[[string]$node.node_id] = $node }
    return $table
}

function Get-Stage1EPowerShellCapabilityKey {
    param([Parameter(Mandatory = $true)][string]$TypeName)

    if ($TypeName -match '^(byte|bool|char|decimal|double|float|int|int16|int32|int64|long|object|sbyte|short|string|uint|uint16|uint32|uint64|ulong|ushort|type|Console|Math)(\[\])?$') {
        return 'POWERSHELL_5_1_AST'
    }
    if ($TypeName -match '^System\.Collections') {
        return 'DOTNET_BCL_COLLECTIONS'
    }
    if ($TypeName -match '^System\.(Text|Globalization)') {
        return 'DOTNET_BCL_TEXT'
    }
    if ($TypeName -match '^System\.Security\.Cryptography') {
        return 'DOTNET_BCL_CRYPTOGRAPHY'
    }
    if ($TypeName -match '^System\.IO') {
        return 'DOTNET_BCL_FILESYSTEM'
    }
    if ($TypeName -match '^System\.(Diagnostics|Threading|DateTime|TimeSpan)') {
        return 'DOTNET_BCL_PROCESS_TIME'
    }
    if ($TypeName -match '^System\.(Environment|EnvironmentVariableTarget|PlatformID|Array|Guid|StringComparer|StringComparison|StringSplitOptions|ArgumentException|InvalidOperationException)$' -or
        $TypeName -match '^System\..*Exception$' -or
        $TypeName -match '^System\.Runtime\.InteropServices') {
        return 'HOST_ENVIRONMENT'
    }
    if ($TypeName -match '^Stage1E\.Runtime\.Host\.V1\.') {
        return 'WINDOWS_PROCESS_CONTROL_API'
    }
    return 'UNKNOWN'
}

function Get-Stage1EStaticVariableKey {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $Name.ToLowerInvariant()
}

function Resolve-Stage1EStaticPowerShellExpression {
    param(
        [Parameter(Mandatory = $true)]$Ast,
        [Parameter(Mandatory = $true)][hashtable]$Variables,
        [Parameter(Mandatory = $true)][hashtable]$PropertyValues,
        [Parameter(Mandatory = $true)][string]$ScriptRoot
    )

    if ($null -eq $Ast) { return @() }
    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return @([string]$Ast.Value)
    }
    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        if ($Ast.NestedExpressions.Count -eq 0) { return @([string]$Ast.Value) }
        return @()
    }
    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $name = Get-Stage1EStaticVariableKey $Ast.VariablePath.UserPath
        if ($name -ceq 'psscriptroot') { return @($ScriptRoot) }
        if ($Variables.ContainsKey($name)) { return @($Variables[$name]) }
        return @()
    }
    if ($Ast -is [System.Management.Automation.Language.MemberExpressionAst] -and
        $Ast.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $member = [string]$Ast.Member.Value
        $key = $member.ToLowerInvariant()
        if ($PropertyValues.ContainsKey($key)) { return @($PropertyValues[$key]) }
        return @()
    }
    if ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        return @(Resolve-Stage1EStaticPowerShellExpression $Ast.Pipeline `
            $Variables $PropertyValues $ScriptRoot)
    }
    if ($Ast -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return @(Resolve-Stage1EStaticPowerShellExpression $Ast.Expression `
            $Variables $PropertyValues $ScriptRoot)
    }
    if ($Ast -is [System.Management.Automation.Language.PipelineAst]) {
        if ($Ast.PipelineElements.Count -ne 1) { return @() }
        return @(Resolve-Stage1EStaticPowerShellExpression `
            $Ast.PipelineElements[0] $Variables $PropertyValues $ScriptRoot)
    }
    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $values = [System.Collections.Generic.List[string]]::new()
        foreach ($element in $Ast.Elements) {
            foreach ($value in @(Resolve-Stage1EStaticPowerShellExpression `
                    $element $Variables $PropertyValues $ScriptRoot)) {
                $values.Add([string]$value)
            }
        }
        return $values.ToArray()
    }
    if ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst] -or
        $Ast -is [System.Management.Automation.Language.SubExpressionAst]) {
        $values = [System.Collections.Generic.List[string]]::new()
        foreach ($statement in $Ast.SubExpression.Statements) {
            foreach ($value in @(Resolve-Stage1EStaticPowerShellExpression `
                    $statement $Variables $PropertyValues $ScriptRoot)) {
                $values.Add([string]$value)
            }
        }
        return $values.ToArray()
    }
    if ($Ast -is [System.Management.Automation.Language.ConvertExpressionAst]) {
        return @(Resolve-Stage1EStaticPowerShellExpression $Ast.Child `
            $Variables $PropertyValues $ScriptRoot)
    }
    if ($Ast -is [System.Management.Automation.Language.BinaryExpressionAst] -and
        $Ast.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
        $left = @(Resolve-Stage1EStaticPowerShellExpression $Ast.Left `
            $Variables $PropertyValues $ScriptRoot)
        $right = @(Resolve-Stage1EStaticPowerShellExpression $Ast.Right `
            $Variables $PropertyValues $ScriptRoot)
        $values = [System.Collections.Generic.List[string]]::new()
        foreach ($leftValue in $left) {
            foreach ($rightValue in $right) {
                $values.Add(([string]$leftValue + [string]$rightValue))
            }
        }
        return $values.ToArray()
    }
    if ($Ast -is [System.Management.Automation.Language.CommandAst] -and
        $Ast.GetCommandName() -ceq 'Join-Path') {
        $arguments = @($Ast.CommandElements | Select-Object -Skip 1 |
            Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
        if ($arguments.Count -lt 2) { return @() }
        $parents = @(Resolve-Stage1EStaticPowerShellExpression $arguments[0] `
            $Variables $PropertyValues $ScriptRoot)
        $children = @(Resolve-Stage1EStaticPowerShellExpression $arguments[1] `
            $Variables $PropertyValues $ScriptRoot)
        $values = [System.Collections.Generic.List[string]]::new()
        foreach ($parent in $parents) {
            foreach ($child in $children) {
                $values.Add((Join-Path ([string]$parent) ([string]$child)))
            }
        }
        return $values.ToArray()
    }
    if ($Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $Ast.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
        $typeName = [string]$Ast.Expression.TypeName.FullName
        $member = [string]$Ast.Member.Value
        if ($typeName -ceq 'System.IO.Path' -and $member -ceq 'GetFullPath' -and
            $Ast.Arguments.Count -eq 1) {
            return @(Resolve-Stage1EStaticPowerShellExpression $Ast.Arguments[0] `
                $Variables $PropertyValues $ScriptRoot)
        }
        if ($typeName -ceq 'System.IO.Path' -and $member -in @('Combine', 'Join')) {
            $argumentValues = @()
            foreach ($argument in $Ast.Arguments) {
                $values = @(Resolve-Stage1EStaticPowerShellExpression $argument `
                    $Variables $PropertyValues $ScriptRoot)
                if ($values.Count -eq 0) { return @() }
                $argumentValues += ,$values
            }
            $results = @('')
            foreach ($values in $argumentValues) {
                $next = [System.Collections.Generic.List[string]]::new()
                foreach ($prefix in $results) {
                    foreach ($value in $values) {
                        if ([string]::IsNullOrEmpty([string]$prefix)) {
                            $next.Add([string]$value)
                        }
                        else { $next.Add((Join-Path ([string]$prefix) ([string]$value))) }
                    }
                }
                $results = @($next.ToArray())
            }
            return $results
        }
    }
    return @()
}

function Get-Stage1ECommandArgumentAst {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst]$Command,
        [string[]]$ParameterNames = @('Name', 'Path', 'LiteralPath')
    )

    $elements = @($Command.CommandElements)
    for ($index = 1; $index -lt $elements.Count; $index++) {
        $element = $elements[$index]
        if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
            $element.ParameterName -in $ParameterNames) {
            if ($null -ne $element.Argument) { return $element.Argument }
            if ($index + 1 -lt $elements.Count) { return $elements[$index + 1] }
            return $null
        }
    }
    foreach ($element in $elements | Select-Object -Skip 1) {
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            return $element
        }
    }
    return $null
}

function Test-Stage1EPowerShellAstIsSourceTime {
    param([Parameter(Mandatory = $true)]$Ast)
    $parent = $Ast.Parent
    while ($null -ne $parent) {
        if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            return $false
        }
        $parent = $parent.Parent
    }
    return $true
}

function ConvertTo-Stage1EPowerShellRepositoryTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][hashtable]$NodesByPath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '[*?]' -or
        $Value -match '(?i)\$env:|PSModulePath|PATH') {
        throw "$Label uses ambient, wildcard, or empty resolution: $Value"
    }
    $candidate = if ([System.IO.Path]::IsPathRooted($Value)) {
        [System.IO.Path]::GetFullPath($Value)
    }
    else { [System.IO.Path]::GetFullPath((Join-Path $SourceDirectory $Value)) }
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label resolves outside the repository: $Value"
    }
    $relative = $candidate.Substring($prefix.Length).Replace('\', '/')
    if (-not $NodesByPath.ContainsKey($relative)) {
        throw "$Label resolves to an undeclared source: $relative"
    }
    return $NodesByPath[$relative]
}

function Get-Stage1EPowerShellDependencyDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot,
        [string[]]$RepositoryPaths
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $nodesByPath = Get-Stage1ENodeByPathTable $Contracts
    if ($null -eq $RepositoryPaths -or $RepositoryPaths.Count -eq 0) {
        $RepositoryPaths = @($Contracts.Nodes | Where-Object {
                $_.node_class -notin @('NON_RUNTIME_SOURCE',
                    'REVIEW_TOOL_SOURCE') -and
                $_.language -in @('POWERSHELL', 'POWERSHELL_DOTNET')
            } | ForEach-Object { [string]$_.repository_path })
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $references = [System.Collections.Generic.List[object]]::new()
    $capabilities = [System.Collections.Generic.List[object]]::new()
    $callbackRecords = [System.Collections.Generic.List[object]]::new()
    $fileReadRecords = [System.Collections.Generic.List[object]]::new()
    $dangerousApiRecords = [System.Collections.Generic.List[object]]::new()
    $environmentRecords = [System.Collections.Generic.List[object]]::new()
    $allowedCallbackNames = @(
        '$specification.interface_command', '$Verifier',
        'TemporaryLeafNameProvider', 'AfterTemporaryClose', 'AfterRename',
        'DigestProvider') | ForEach-Object {
            if ($_ -like '$*') { $_ } else { '$' + $_ }
        }
    $blockedCommands = @(
        'Get-Command', 'Start-Process', 'Invoke-Expression', 'Invoke-Command',
        'powershell', 'powershell.exe', 'pwsh', 'cmd', 'cmd.exe', 'reg',
        'reg.exe')

    foreach ($relative in $RepositoryPaths) {
        $path = Resolve-Stage1EContainedRepositoryPath $root $relative
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -ne 0) {
            throw "PowerShell parse failed for $relative at line $($parseErrors[0].Extent.StartLineNumber)."
        }
        $node = $Contracts.Nodes | Where-Object {
            $_.repository_path -ceq $relative } | Select-Object -First 1
        if ($null -eq $node) { throw "PowerShell discovery root is undeclared: $relative" }
        $records.Add([pscustomobject]@{
                NodeId = [string]$node.node_id
                Path = $relative
                ParseState = 'PARSED'
                Parser = 'System.Management.Automation.Language.Parser'
            })

        $sourceDirectory = [System.IO.Path]::GetDirectoryName($path)
        $variables = @{}
        $propertyValues = @{}
        foreach ($table in @($ast.FindAll({ param($candidate)
                        $candidate -is [System.Management.Automation.Language.HashtableAst]
                    }, $true))) {
            foreach ($pair in $table.KeyValuePairs) {
                $keyValues = @(Resolve-Stage1EStaticPowerShellExpression `
                    $pair.Item1 $variables $propertyValues $sourceDirectory)
                if ($keyValues.Count -ne 1) { continue }
                $key = ([string]$keyValues[0]).ToLowerInvariant()
                $values = @(Resolve-Stage1EStaticPowerShellExpression `
                    $pair.Item2 $variables $propertyValues $sourceDirectory)
                if ($values.Count -eq 0) { continue }
                if (-not $propertyValues.ContainsKey($key)) { $propertyValues[$key] = @() }
                $propertyValues[$key] = @($propertyValues[$key] + $values | Sort-Object -Unique)
            }
        }
        $assignments = @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $candidate.Left -is [System.Management.Automation.Language.VariableExpressionAst]
                }, $true))
        foreach ($assignment in $assignments) {
            $leftName = [string]$assignment.Left.VariablePath.UserPath
            if ($leftName -match '^(?i:env:.*|PROFILE|PWD)$') {
                $sourceTime = Test-Stage1EPowerShellAstIsSourceTime $assignment
                $dangerousApiRecords.Add([pscustomobject]@{
                        Path=$relative; Line=$assignment.Extent.StartLineNumber;
                        Api="ASSIGNMENT:$leftName"; SourceTime=$sourceTime;
                        Classification='ENVIRONMENT_OR_PROCESS_STATE_MUTATION' })
                if ($sourceTime) {
                    throw "Source-time environment/profile/process-state mutation is prohibited in $relative at line $($assignment.Extent.StartLineNumber): $leftName"
                }
            }
        }
        for ($pass = 0; $pass -lt 12; $pass++) {
            $changed = $false
            foreach ($assignment in $assignments) {
                $key = Get-Stage1EStaticVariableKey `
                    $assignment.Left.VariablePath.UserPath
                $values = @(Resolve-Stage1EStaticPowerShellExpression `
                    $assignment.Right $variables $propertyValues $sourceDirectory |
                    Sort-Object -Unique)
                if ($values.Count -eq 0) { continue }
                $joined = $values -join "`n"
                $prior = if ($variables.ContainsKey($key)) {
                    @($variables[$key]) -join "`n"
                } else { '' }
                if ($joined -cne $prior) {
                    $variables[$key] = $values
                    $changed = $true
                }
            }
            if (-not $changed) { break }
        }

        $seenTargets = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)

        foreach ($using in @($ast.FindAll({ param($candidate)
                        $candidate -is [System.Management.Automation.Language.UsingStatementAst]
                    }, $true))) {
            if ([string]$using.UsingStatementKind -ne 'Module') { continue }
            $values = @(Resolve-Stage1EStaticPowerShellExpression $using.Name `
                $variables $propertyValues $sourceDirectory)
            if ($values.Count -eq 0) {
                throw "PowerShell using-module target is unresolved in $relative."
            }
            foreach ($value in $values) {
                $target = ConvertTo-Stage1EPowerShellRepositoryTarget $value `
                    $sourceDirectory $root $nodesByPath 'PowerShell using module'
                if ($seenTargets.Add("$($target.node_id)|POWERSHELL_MODULE")) {
                    $references.Add([pscustomobject]@{ From=[string]$node.node_id;
                        To=[string]$target.node_id; Path=[string]$target.repository_path;
                        Line=$using.Extent.StartLineNumber; Column=$using.Extent.StartColumnNumber;
                        SyntaxKind='UsingStatementAst'; EdgeType='POWERSHELL_MODULE';
                        Resolution='SEMANTIC_STATIC_EXPRESSION' })
                }
            }
        }

        $commands = @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.CommandAst]
                }, $true))
        foreach ($command in $commands) {
            $commandName = $command.GetCommandName()
            if ($commandName -in $blockedCommands) {
                throw "PowerShell ambient or process command is prohibited in $relative at line $($command.Extent.StartLineNumber): $commandName"
            }
            $mutationCommands = @(
                'Set-Content', 'Add-Content', 'Out-File', 'New-Item',
                'Remove-Item', 'Move-Item', 'Copy-Item', 'Rename-Item',
                'Set-Location', 'Push-Location', 'Pop-Location',
                'Set-Item', 'Clear-Content', 'Set-ItemProperty',
                'New-ItemProperty', 'Remove-ItemProperty',
                'Rename-ItemProperty', 'Clear-ItemProperty')
            if ($commandName -in $mutationCommands) {
                $sourceTime = Test-Stage1EPowerShellAstIsSourceTime $command
                $dangerousApiRecords.Add([pscustomobject]@{
                        Path=$relative; Line=$command.Extent.StartLineNumber;
                        Api=$commandName; SourceTime=$sourceTime;
                        Classification='CMDLET_MUTATION' })
                if ($sourceTime) {
                    throw "Source-time mutation cmdlet is prohibited in $relative at line $($command.Extent.StartLineNumber): $commandName"
                }
            }
            if ($commandName -in @('Set-Location', 'Push-Location',
                    'Pop-Location', 'Set-PSDebug')) {
                throw "PowerShell process-state mutation is prohibited in $relative at line $($command.Extent.StartLineNumber): $commandName"
            }
            if ($command.InvocationOperator -eq
                [System.Management.Automation.Language.TokenKind]::Dot) {
                $targetAst = $command.CommandElements[0]
                $values = @(Resolve-Stage1EStaticPowerShellExpression $targetAst `
                    $variables $propertyValues $sourceDirectory)
                if ($values.Count -eq 0) {
                    throw "PowerShell dot-source target is unresolved in $relative at line $($command.Extent.StartLineNumber)."
                }
                foreach ($value in $values) {
                    $target = ConvertTo-Stage1EPowerShellRepositoryTarget $value `
                        $sourceDirectory $root $nodesByPath 'PowerShell dot source'
                    if ($seenTargets.Add("$($target.node_id)|POWERSHELL_DOT_SOURCE")) {
                        $references.Add([pscustomobject]@{ From=[string]$node.node_id;
                            To=[string]$target.node_id; Path=[string]$target.repository_path;
                            Line=$command.Extent.StartLineNumber; Column=$command.Extent.StartColumnNumber;
                            SyntaxKind='CommandAst'; EdgeType='POWERSHELL_DOT_SOURCE';
                            Resolution='SEMANTIC_STATIC_EXPRESSION' })
                    }
                }
            }
            if ($command.InvocationOperator -eq
                [System.Management.Automation.Language.TokenKind]::Ampersand) {
                $commandExpression = $command.CommandElements[0].Extent.Text.Trim()
                if ($commandExpression -notin $allowedCallbackNames) {
                    throw "PowerShell dynamic invocation is unresolved in $relative at line $($command.Extent.StartLineNumber)."
                }
                $callbackRecords.Add([pscustomobject]@{
                        Path=$relative; Line=$command.Extent.StartLineNumber;
                        Callback=$commandExpression;
                        State='EXACT_COMMAND_EXPRESSION_GUARDED_CALLBACK' })
            }
            if ($commandName -ceq 'Import-Module') {
                $targetAst = Get-Stage1ECommandArgumentAst $command @('Name')
                $values = @(Resolve-Stage1EStaticPowerShellExpression $targetAst `
                    $variables $propertyValues $sourceDirectory | Sort-Object -Unique)
                if ($values.Count -eq 0) {
                    throw "PowerShell import target is unresolved in $relative at line $($command.Extent.StartLineNumber)."
                }
                foreach ($value in $values) {
                    $target = ConvertTo-Stage1EPowerShellRepositoryTarget $value `
                        $sourceDirectory $root $nodesByPath 'PowerShell module import'
                    if ($seenTargets.Add("$($target.node_id)|POWERSHELL_MODULE")) {
                        $references.Add([pscustomobject]@{ From=[string]$node.node_id;
                            To=[string]$target.node_id; Path=[string]$target.repository_path;
                            Line=$command.Extent.StartLineNumber; Column=$command.Extent.StartColumnNumber;
                            SyntaxKind='ImportModuleCommandAst'; EdgeType='POWERSHELL_MODULE';
                            Resolution='SEMANTIC_STATIC_EXPRESSION' })
                    }
                }
            }
            if ($commandName -ceq 'Add-Type') {
                $targetAst = Get-Stage1ECommandArgumentAst $command @('Path', 'LiteralPath')
                $values = @(Resolve-Stage1EStaticPowerShellExpression $targetAst `
                    $variables $propertyValues $sourceDirectory | Sort-Object -Unique)
                if ($values.Count -eq 0) {
                    throw "Add-Type source target is unresolved in $relative at line $($command.Extent.StartLineNumber)."
                }
                foreach ($value in $values) {
                    $target = ConvertTo-Stage1EPowerShellRepositoryTarget $value `
                        $sourceDirectory $root $nodesByPath 'Add-Type source'
                    if ($seenTargets.Add("$($target.node_id)|DOTNET_SOURCE_PROVIDER")) {
                        $references.Add([pscustomobject]@{ From=[string]$node.node_id;
                            To=[string]$target.node_id; Path=[string]$target.repository_path;
                            Line=$command.Extent.StartLineNumber; Column=$command.Extent.StartColumnNumber;
                            SyntaxKind='AddTypeCommandAst'; EdgeType='DOTNET_SOURCE_PROVIDER';
                            Resolution='SEMANTIC_STATIC_EXPRESSION' })
                    }
                }
                $dangerousApiRecords.Add([pscustomobject]@{Path=$relative;
                    Line=$command.Extent.StartLineNumber; Api='Add-Type';
                    SourceTime=(Test-Stage1EPowerShellAstIsSourceTime $command);
                    Classification='NATIVE_CODE_LOAD' })
                if (Test-Stage1EPowerShellAstIsSourceTime $command) {
                    throw "Source-time Add-Type is prohibited in $relative."
                }
            }
            if ($commandName -in @('Get-Content', 'Get-Item',
                    'Get-ChildItem', 'Get-FileHash', 'Test-Path',
                    'Import-Clixml', 'Import-Csv', 'Get-ItemProperty',
                    'Get-ItemPropertyValue')) {
                $readAst = Get-Stage1ECommandArgumentAst $command @(
                    'LiteralPath', 'Path', 'FilePath')
                $readValues = @()
                if ($null -ne $readAst) {
                    $readValues = @(Resolve-Stage1EStaticPowerShellExpression `
                        $readAst $variables $propertyValues $sourceDirectory)
                }
                $fileReadRecords.Add([pscustomobject]@{
                        Path=$relative; Line=$command.Extent.StartLineNumber;
                        Api=$commandName;
                        Resolution=$(if($readValues.Count){
                                'STATIC_EXPRESSION'}else{'RUNTIME_BOUND'});
                        SourceTime=(Test-Stage1EPowerShellAstIsSourceTime $command) })
            }
            if ($command.Extent.Text -match
                '(?i)(^|[\s''"])(HKLM:|HKCU:|Registry::)') {
                $environmentRecords.Add([pscustomobject]@{
                        Path=$relative; Line=$command.Extent.StartLineNumber;
                        Variable='REGISTRY_PROVIDER_REFERENCE';
                        SourceTime=(Test-Stage1EPowerShellAstIsSourceTime $command) })
            }
        }

        foreach ($memberCall in @($ast.FindAll({ param($candidate)
                        $candidate -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                        $candidate.Expression -is [System.Management.Automation.Language.TypeExpressionAst]
                    }, $true))) {
            $typeName = [string]$memberCall.Expression.TypeName.FullName
            $memberName = [string]$memberCall.Member.Value
            $api = "$typeName.$memberName"
            $classification = $null
            if ($typeName -ceq 'System.Diagnostics.Process' -and
                $memberName -ceq 'Start') { $classification = 'PROCESS_MUTATION' }
            elseif ($typeName -ceq 'System.Environment' -and
                $memberName -ceq 'SetEnvironmentVariable') {
                $classification = 'ENVIRONMENT_MUTATION'
            }
            elseif ($typeName -ceq 'System.IO.File' -and $memberName -in @(
                    'WriteAllText','WriteAllBytes','WriteAllLines','AppendAllText',
                    'AppendAllLines','Delete','Move','Copy','Replace','Create',
                    'CreateText','OpenWrite')) { $classification = 'FILE_MUTATION' }
            elseif ($typeName -ceq 'System.IO.Directory' -and $memberName -in @(
                    'CreateDirectory','Delete','Move','SetCurrentDirectory')) {
                $classification = 'FILESYSTEM_OR_CWD_MUTATION'
            }
            if ($null -ne $classification) {
                $sourceTime = Test-Stage1EPowerShellAstIsSourceTime $memberCall
                $dangerousApiRecords.Add([pscustomobject]@{Path=$relative;
                    Line=$memberCall.Extent.StartLineNumber;Api=$api;
                    SourceTime=$sourceTime;Classification=$classification})
                if ($sourceTime) {
                    throw "Source-time mutation API is prohibited in $relative at line $($memberCall.Extent.StartLineNumber): $api"
                }
            }
            if ($typeName -ceq 'System.IO.File' -and $memberName -in @(
                    'ReadAllBytes','ReadAllText','ReadAllLines','OpenRead')) {
                $values = @()
                if ($memberCall.Arguments.Count -gt 0) {
                    $values = @(Resolve-Stage1EStaticPowerShellExpression `
                        $memberCall.Arguments[0] $variables $propertyValues `
                        $sourceDirectory)
                }
                $fileReadRecords.Add([pscustomobject]@{Path=$relative;
                    Line=$memberCall.Extent.StartLineNumber;Api=$api;
                    Resolution=$(if($values.Count){'STATIC_EXPRESSION'}else{'RUNTIME_BOUND'});
                    SourceTime=(Test-Stage1EPowerShellAstIsSourceTime $memberCall)})
            }
        }

        # File/schema dependencies are owned by the file-read syntax, not by
        # every string literal in a source.  The reviewed Host contracts keep
        # their schema leaves in explicit File/Path property assignments; bind
        # only those literals when a real read API is present in the same AST.
        $hasFileReadSyntax = @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $candidate.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                    [string]$candidate.Expression.TypeName.FullName -eq 'System.IO.File' -and
                    [string]$candidate.Member.Value -in @('ReadAllBytes','ReadAllText',
                        'ReadAllLines','OpenRead')
                }, $true)).Count -gt 0 -or
            @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.CommandAst] -and
                    $candidate.GetCommandName() -in @(
                        'Read-Stage1EJsonFileBytes','Get-Content','Get-FileHash')
                }, $true)).Count -gt 0
        if ($hasFileReadSyntax) {
            $literalLeaves = @([regex]::Matches(
                    [System.IO.File]::ReadAllText($path),
                    '(?im)\b(?:File|Path|SchemaPath|schema_path)\s*=\s*["'']([^"'']+\.(?:schema\.json|dict))["'']') |
                ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
            foreach ($leaf in $literalLeaves) {
                $candidatePaths = @($Contracts.Nodes | Where-Object {
                        $_.repository_path -like "*/$leaf" })
                if ($candidatePaths.Count -ne 1) {
                    throw "PowerShell file-read target is undeclared or ambiguous in $relative`: $leaf"
                }
                $target = $candidatePaths[0]
                $edgeType = if ($leaf.EndsWith('.dict',
                        [System.StringComparison]::Ordinal)) {
                    'CONFIG_READ'
                } else { 'SCHEMA_PROVIDER' }
                if ($seenTargets.Add("$($target.node_id)|$edgeType")) {
                    $references.Add([pscustomobject]@{
                            From=[string]$node.node_id; To=[string]$target.node_id;
                            Path=[string]$target.repository_path;
                            Line=1; Column=1; SyntaxKind='FileReadPropertySyntax';
                            EdgeType=$edgeType; Resolution='SYNTAX_OWNED_FILE_READ' })
                }
            }
        }

        foreach ($variable in @($ast.FindAll({ param($candidate)
                        $candidate -is [System.Management.Automation.Language.VariableExpressionAst]
                    }, $true))) {
            $name = [string]$variable.VariablePath.UserPath
            if ($name -match '^(?i:env:.*|PROFILE|PWD)$') {
                $environmentRecords.Add([pscustomobject]@{Path=$relative;
                    Line=$variable.Extent.StartLineNumber;Variable=$name;
                    SourceTime=(Test-Stage1EPowerShellAstIsSourceTime $variable)})
            }
        }

        $types = @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.TypeExpressionAst]
                }, $true) | ForEach-Object { $_.TypeName.FullName } |
                Sort-Object -Unique)
        foreach ($typeName in $types) {
            $capability = Get-Stage1EPowerShellCapabilityKey $typeName
            if ($capability -ceq 'UNKNOWN') {
                throw "PowerShell .NET capability is unmapped in $relative`: $typeName"
            }
            $capabilities.Add([pscustomobject]@{
                    Path = $relative
                    TypeName = $typeName
                    CapabilityKey = $capability
                })
        }
    }

    $entryDirectory = Join-Path $root 'fpga/vivado/build/runtime/entrypoint'
    $entryFiles = @(Get-ChildItem -LiteralPath $entryDirectory -File)
    if ($entryFiles.Count -ne 1 -or
        $entryFiles[0].Name -cne 'stage1e_production_runtime_entrypoint_v1.ps1') {
        throw 'PowerShell alternate-entry-point discovery did not find exactly one approved entry point.'
    }

    return [pscustomobject]@{
        Parser = 'System.Management.Automation.Language.Parser'
        ParsedSources = $records.ToArray()
        References = $references.ToArray()
        Capabilities = $capabilities.ToArray()
        GuardedCallbacks = $callbackRecords.ToArray()
        FileReads = $fileReadRecords.ToArray()
        DangerousApis = $dangerousApiRecords.ToArray()
        EnvironmentReferences = $environmentRecords.ToArray()
        SourceTimeMutationCount = @($dangerousApiRecords | Where-Object {
                $_.SourceTime }).Count
        AlternateEntryPoints = @()
        State = 'SEMANTIC_AST_STATIC_DISCOVERY_COMPLETE'
    }
}

function ConvertFrom-Stage1EKeyValueRecord {
    param([Parameter(Mandatory = $true)][string]$Line)
    $record = [ordered]@{}
    foreach ($field in @($Line.Split('|'))) {
        $separator = $field.IndexOf('=')
        if ($separator -lt 1) { throw "Malformed discovery record: $Line" }
        $key = $field.Substring(0, $separator)
        $value = $field.Substring($separator + 1).Replace('\p', '|').
            Replace('\t', "`t").Replace('\n', "`n").Replace('\r', "`r")
        if ($record.Contains($key)) {
            throw "Duplicate discovery record field '$key'."
        }
        $record[$key] = $value
    }
    return $record
}

function Invoke-Stage1ETclDependencyDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TclPath,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    $tcl = [System.IO.Path]::GetFullPath($TclPath)
    if (-not [System.IO.File]::Exists($tcl)) {
        throw "Standalone Tcl does not exist: $tcl"
    }
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $evidence = [System.IO.Path]::GetFullPath($EvidenceRoot)
    if (-not [System.IO.Directory]::Exists($evidence)) {
        $null = [System.IO.Directory]::CreateDirectory($evidence)
    }
    $output = Join-Path $evidence 'stage1e-tcl-static-discovery-v1.records'
    if ([System.IO.File]::Exists($output)) {
        throw "Static discovery evidence already exists: $output"
    }
    $scanner = Join-Path $script:Stage1EDependencyBuildRoot `
        'dependency/stage1e_tcl_dependency_discovery_v1.tcl'
    $graph = Join-Path $script:Stage1EDependencyBuildRoot `
        'config/stage1e_runtime_declared_graph_v1.dict'
    & $tcl $scanner --repository-root $root --graph $graph --output $output
    if ($LASTEXITCODE -ne 0) {
        throw "Tcl static discovery blocked with exit code $LASTEXITCODE."
    }
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($output)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $record = ConvertFrom-Stage1EKeyValueRecord $line
        if ($record.kind -ceq 'BLOCK') {
            throw "Tcl static discovery emitted a blocking record: $($record.code)"
        }
        $records.Add($record)
    }
    return [pscustomobject]@{
        InterfaceVersion = 'stage1e-tcl-dependency-discovery-interface-v1'
        EvidencePath = $output
        Records = $records.ToArray()
        Sources = @($records | Where-Object { $_.kind -ceq 'SOURCE' })
        Edges = @($records | Where-Object { $_.kind -ceq 'EDGE' })
        Providers = @($records | Where-Object { $_.kind -ceq 'PROVIDER' })
        Capabilities = @($records | Where-Object {
                $_.kind -ceq 'CAPABILITY' })
        GuardedCallbacks = @($records | Where-Object {
                $_.kind -ceq 'GUARDED_CALLBACK' })
        State = 'STATIC_DISCOVERY_COMPLETE'
    }
}

function Find-Stage1EJsonReferences {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$References
    )
    if ($null -eq $Value) { return }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ([string]$key -ceq '$ref') {
                $References.Add([string]$Value[$key])
            }
            Find-Stage1EJsonReferences -Value $Value[$key] `
                -References $References
        }
        return
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -ceq '$ref') {
                $References.Add([string]$property.Value)
            }
            Find-Stage1EJsonReferences -Value $property.Value `
                -References $References
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string]) {
        foreach ($item in $Value) {
            Find-Stage1EJsonReferences -Value $item -References $References
        }
    }
}

function Resolve-Stage1EJsonReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Reference,
        [Parameter(Mandatory = $true)][string]$SourceSchemaId,
        [Parameter(Mandatory = $true)]$SchemaRegistry
    )

    $firstHash = $Reference.IndexOf('#')
    if ($firstHash -ge 0 -and
        $Reference.IndexOf('#', $firstHash + 1) -ge 0) {
        throw "JSON schema reference has multiple fragments: $Reference"
    }
    $targetId = if ($firstHash -lt 0) { $Reference }
        else { $Reference.Substring(0, $firstHash) }
    $fragment = if ($firstHash -lt 0) { '' }
        else { $Reference.Substring($firstHash + 1) }
    if ([string]::IsNullOrEmpty($targetId)) { $targetId = $SourceSchemaId }
    if ($targetId -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or
        $targetId -match '[/\\]' -or $targetId -match '[?*]') {
        throw "Network, path, or ambient JSON schema resolution is prohibited: $Reference"
    }
    if (-not $SchemaRegistry.ContainsKey($targetId)) {
        throw "JSON schema reference has no exact unique provider: $Reference"
    }
    if ($fragment.Contains('%')) {
        throw "Percent-decoded JSON Pointer resolution is not admitted: $Reference"
    }
    if ($fragment.Length -gt 0 -and
        -not $fragment.StartsWith('/', [System.StringComparison]::Ordinal)) {
        throw "JSON schema fragment is not a JSON Pointer: $Reference"
    }

    $schema = $SchemaRegistry[$targetId]
    $target = $schema.Value
    if ($fragment.Length -gt 0) {
        $encodedTokens = @($fragment.Substring(1).Split('/'))
        foreach ($encodedToken in $encodedTokens) {
            if ($encodedToken -match '~(?![01])') {
                throw "JSON Pointer contains an invalid escape: $Reference"
            }
            $token = $encodedToken.Replace('~1', '/').Replace('~0', '~')
            if ($target -is [System.Collections.IDictionary]) {
                if (-not $target.Contains($token)) {
                    throw "JSON Pointer object key is missing: $Reference"
                }
                $target = $target[$token]
                continue
            }
            if ($target -is [System.Management.Automation.PSCustomObject]) {
                $property = $target.PSObject.Properties[$token]
                if ($null -eq $property) {
                    throw "JSON Pointer object key is missing: $Reference"
                }
                $target = $property.Value
                continue
            }
            if ($target -is [System.Collections.IList] -and
                $target -isnot [string]) {
                if ($token -notmatch '^(0|[1-9][0-9]*)$') {
                    throw "JSON Pointer array index is noncanonical: $Reference"
                }
                [uint64]$index = 0
                if (-not [uint64]::TryParse($token,
                        [System.Globalization.NumberStyles]::None,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [ref]$index) -or $index -ge [uint64]$target.Count) {
                    throw "JSON Pointer array index is out of range: $Reference"
                }
                $target = $target[[int]$index]
                continue
            }
            throw "JSON Pointer traverses a scalar value: $Reference"
        }
    }
    return [pscustomobject]@{
        Reference = $Reference
        ResolvedSchemaId = [string]$schema.SchemaId
        ResolvedNodeId = [string]$schema.NodeId
        ResolvedPath = [string]$schema.Path
        ResolvedFragment = $(if ($fragment.Length -eq 0) { '#' }
            else { '#' + $fragment })
        Resolution = 'EXACT_SCHEMA_ID_AND_JSON_POINTER'
        Target = $target
    }
}

function Assert-Stage1ESchemaStringArrayForDiscovery {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Value -isnot [System.Collections.IList] -or $Value -is [string]) {
        throw "$Label must be an array."
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($item in $Value) {
        if ($item -isnot [string] -or [string]::IsNullOrEmpty([string]$item) -or
            -not $seen.Add([string]$item)) {
            throw "$Label contains a non-string, empty, or duplicate item."
        }
    }
    return $seen
}

function Assert-Stage1ESchemaMetaNodeForDiscovery {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Node,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $supported = @('$schema','$id','title','$ref','$defs','type','required',
        'additionalProperties','x-stage1e-canonical-order','properties','oneOf',
        'const','enum','minimum','maximum','minLength','maxLength','items',
        'minItems','maxItems','uniqueItems','x-stage1e-format')
    foreach ($keyValue in $Node.Keys) {
        if ([string]$keyValue -notin $supported) {
            throw "Unsupported schema keyword '$keyValue' at $Path."
        }
    }
    if ($Node.Contains('type')) {
        $type = [string]$Node.type
        if ($type -notin @('object','array','string','integer','boolean')) {
            throw "Unsupported schema type '$type' at $Path."
        }
        if ($type -ceq 'object') {
            foreach ($requiredKeyword in @('properties','required',
                    'additionalProperties','x-stage1e-canonical-order')) {
                if (-not $Node.Contains($requiredKeyword)) {
                    throw "Exact object schema at $Path lacks '$requiredKeyword'."
                }
            }
            if ($Node.properties -isnot [System.Collections.IDictionary] -or
                [bool]$Node.additionalProperties) {
                throw "Object schema at $Path is not exact-field closed."
            }
            $required = Assert-Stage1ESchemaStringArrayForDiscovery `
                $Node.required "$Path.required"
            $order = Assert-Stage1ESchemaStringArrayForDiscovery `
                $Node['x-stage1e-canonical-order'] `
                "$Path.x-stage1e-canonical-order"
            if ($required.Count -ne $Node.properties.Count -or
                $order.Count -ne $Node.properties.Count) {
                throw "Object schema at $Path has incomplete canonical metadata."
            }
            $propertyOrdinal = 0
            foreach ($propertyValue in $Node.properties.Keys) {
                $property = [string]$propertyValue
                if (-not $required.Contains($property) -or
                    -not $order.Contains($property) -or
                    [string]$Node['x-stage1e-canonical-order'][$propertyOrdinal] `
                        -cne $property) {
                    throw "Object schema at $Path does not require/order '$property' exactly."
                }
                $child = $Node.properties[$property]
                if ($child -isnot [System.Collections.IDictionary]) {
                    throw "Property schema at $Path.properties.$property is not an object."
                }
                Assert-Stage1ESchemaMetaNodeForDiscovery $child `
                    "$Path.properties.$property"
                $propertyOrdinal++
            }
        }
        elseif ($type -ceq 'array' -and $Node.Contains('items')) {
            if ($Node.items -isnot [System.Collections.IDictionary]) {
                throw "Array item schema at $Path is not an object."
            }
            Assert-Stage1ESchemaMetaNodeForDiscovery $Node.items "$Path.items"
        }
    }
    if ($Node.Contains('oneOf')) {
        if ($Node.oneOf -isnot [System.Collections.IList] -or
            $Node.oneOf.Count -lt 2) { throw "oneOf at $Path is invalid." }
        for ($index = 0; $index -lt $Node.oneOf.Count; $index++) {
            if ($Node.oneOf[$index] -isnot [System.Collections.IDictionary]) {
                throw "oneOf branch at $Path[$index] is not an object."
            }
            Assert-Stage1ESchemaMetaNodeForDiscovery $Node.oneOf[$index] `
                "$Path.oneOf[$index]"
        }
    }
    if ($Node.Contains('$defs')) {
        if ($Node['$defs'] -isnot [System.Collections.IDictionary]) {
            throw "$Path.`$defs is not an object."
        }
        foreach ($nameValue in $Node['$defs'].Keys) {
            $definition = $Node['$defs'][$nameValue]
            if ($definition -isnot [System.Collections.IDictionary]) {
                throw "Definition at $Path.`$defs.$nameValue is not an object."
            }
            Assert-Stage1ESchemaMetaNodeForDiscovery $definition `
                "$Path.`$defs.$nameValue"
        }
    }
}

function Assert-Stage1ERawTclDictionaryTree {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$Depth = 0,
        [switch]$RequireDictionary
    )
    if ($Depth -gt 64) { throw "Tcl dictionary nesting is excessive at $Label." }
    $items = @(ConvertFrom-Stage1ETclList -Text $Text)
    $looksDictionary = ($items.Count -gt 0 -and ($items.Count % 2) -eq 0)
    if ($looksDictionary) {
        for ($index = 0; $index -lt $items.Count; $index += 2) {
            if ([string]$items[$index] -notmatch '^[A-Za-z_$][A-Za-z0-9_:$.-]*$') {
                $looksDictionary = $false
                break
            }
        }
    }
    if ($RequireDictionary -and -not $looksDictionary) {
        throw "$Label is not an alternating raw Tcl dictionary."
    }
    if ($looksDictionary) {
        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
        for ($index = 0; $index -lt $items.Count; $index += 2) {
            $key = [string]$items[$index]
            if (-not $seen.Add($key)) {
                throw "$Label contains duplicate raw key '$key'."
            }
            $value = [string]$items[$index + 1]
            if ($value -match '[\s{}]') {
                Assert-Stage1ERawTclDictionaryTree $value "$Label.$key" `
                    ($Depth + 1)
            }
        }
        return
    }
    foreach ($item in $items) {
        if ([string]$item -match '[\s{}]') {
            Assert-Stage1ERawTclDictionaryTree ([string]$item) $Label `
                ($Depth + 1)
        }
    }
}

function Get-Stage1EJsonAndConfigDependencyDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $jsonRecords = [System.Collections.Generic.List[object]]::new()
    $configRecords = [System.Collections.Generic.List[object]]::new()
    $schemaRegistry = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::Ordinal)
    $canonicalModulePath = Join-Path $root `
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1'
    Microsoft.PowerShell.Core\Import-Module -Name $canonicalModulePath -Force `
        -ErrorAction Stop
    foreach ($node in $Contracts.Nodes | Where-Object {
            $_.node_class -ne 'NON_RUNTIME_SOURCE' -and $_.language -ceq 'JSON' }) {
        $path = Resolve-Stage1EContainedRepositoryPath $root `
            ([string]$node.repository_path)
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and
            $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
            throw "JSON dependency contains a UTF-8 BOM: $($node.repository_path)"
        }
        try {
            $value = stage1e_runtime_canonical_json_v1\ConvertFrom-Stage1ECanonicalJsonBytes `
                -Bytes $bytes
        }
        catch {
            throw "Strict JSON dependency parse failed: $($node.repository_path): $($_.Exception.Message)"
        }
        if ($value -isnot [System.Collections.IDictionary]) {
            throw "JSON schema root is not an object: $($node.repository_path)"
        }
        Assert-Stage1ESchemaMetaNodeForDiscovery $value '$'
        if (-not $value.Contains('$id') -or [string]::IsNullOrWhiteSpace(
                [string]$value['$id'])) {
            throw "JSON schema has no exact id: $($node.repository_path)"
        }
        $schemaId = [string]$value['$id']
        if ($schemaRegistry.ContainsKey($schemaId)) {
            throw "Duplicate JSON schema provider: $schemaId"
        }
        $schemaRegistry[$schemaId] = [pscustomobject]@{
            SchemaId = $schemaId
            NodeId = [string]$node.node_id
            Path = [string]$node.repository_path
            Value = $value
        }
        $references = [System.Collections.Generic.List[string]]::new()
        Find-Stage1EJsonReferences -Value $value -References $references
        $jsonRecords.Add([pscustomobject]@{
                NodeId = [string]$node.node_id
                Path = [string]$node.repository_path
                SchemaId = $schemaId
                RawReferences = @($references.ToArray())
                References = @()
                ParseState = 'STRICT_CANONICAL_JSON_META_VALIDATED'
                CanonicalOrderState = 'COMPLETE_AND_PROPERTY_ORDERED'
                AmbientResolution = 'PROHIBITED'
            })
    }
    foreach ($record in $jsonRecords) {
        $resolvedReferences = [System.Collections.Generic.List[object]]::new()
        foreach ($reference in $record.RawReferences) {
            $resolved = Resolve-Stage1EJsonReference -Reference $reference `
                -SourceSchemaId $record.SchemaId -SchemaRegistry $schemaRegistry
            $resolvedReferences.Add([pscustomobject]@{
                    Reference = [string]$resolved.Reference
                    SourceSchemaId = [string]$record.SchemaId
                    SourceNodeId = [string]$record.NodeId
                    ResolvedSchemaId = [string]$resolved.ResolvedSchemaId
                    ResolvedNodeId = [string]$resolved.ResolvedNodeId
                    ResolvedPath = [string]$resolved.ResolvedPath
                    ResolvedFragment = [string]$resolved.ResolvedFragment
                    Resolution = [string]$resolved.Resolution
                })
        }
        $record.References = $resolvedReferences.ToArray()
    }

    foreach ($node in $Contracts.Nodes | Where-Object {
            $_.node_class -ne 'NON_RUNTIME_SOURCE' -and
            $_.language -ceq 'TCL_DICT' }) {
        $path = Resolve-Stage1EContainedRepositoryPath $root `
            ([string]$node.repository_path)
        $rawBytes = [System.IO.File]::ReadAllBytes($path)
        $rawText = [System.Text.UTF8Encoding]::new($false, $true).
            GetString($rawBytes)
        Assert-Stage1ERawTclDictionaryTree $rawText `
            ([string]$node.repository_path) -RequireDictionary
        $dictionary = ConvertFrom-Stage1ETclDictionary -Text $rawText
        if (-not $dictionary.Contains('schema_version') -or
            [string]$dictionary.schema_version -cne
            [string]$node.interface_version) {
            throw "Configuration contract version mismatch: $($node.repository_path)"
        }
        $requiredTopLevel = @{
            VIVADO_RECORD_CONTRACT = @('schema_version','contract_state',
                'interface_versions','records','enums','controller_state_machine',
                'assembly_boundary','operation_contract','phys_opt_contract',
                'collector_boundary','authority_boundary','qualification_boundary')
            VIVADO_COMMAND_CONTRACT = @('schema_version','contract_state',
                'vivado_version','dispatch_mechanism','project_mode_run',
                'synthesis_run','jobs','wait_timeout_contract','current_run_contract',
                'query_roles','control_roles','report_availability_roles',
                'forbidden_commands','command_ownership','qualification_boundary')
            VIVADO_PROPERTY_MAP = @('schema_version','contract_state','vivado_version',
                'snapshot_points','object_selectors','normalization_rules','properties',
                'graph_bindings','qualification_boundary')
            REPORT_CONTRACT = @('schema_version','contract_state','vivado_version',
                'qualification_state','role_order','role_fields','roles',
                'conditional_roles','attempt_states','continuation_policy',
                'authority_boundary')
            MESSAGE_CONTRACT = @('schema_version','contract_state','qualification_state',
                'severity_order','grouping_key','unknown_identifier_action',
                'unknown_value_rule','conflict_rule','known_fixture_identifiers',
                'message_fields','drc_fields','methodology_fields','timing_fields',
                'clock_cdc_fields','timing_exception_fields','utilization_fields',
                'authority_boundary')
            PARSER_PROFILE_CONTRACT = @('schema_version','contract_state',
                'qualification_state','parser_interface','common_header',
                'common_end_marker','encoding','line_endings','locale',
                'numeric_contract','profiles','terminal_states','profile_match')
            EVIDENCE_RECORD_CONTRACT = @('schema_version','contract_state',
                'canonical_json_interface','atomic_publication_interface',
                'interface_versions','records','enums','policy_stop')
        }
        $null = Test-Stage1EExactList @($dictionary.Keys) `
            $requiredTopLevel[[string]$node.node_id] `
            "Configuration top-level fields for $($node.node_id)"
        $owners = @($Contracts.Edges | Where-Object {
                $_.to -ceq $node.node_id -and $_.edge_type -ceq 'CONFIG_READ' } |
                ForEach-Object { [string]$_.from } | Sort-Object -Unique)
        if ($owners.Count -eq 0) {
            throw "Configuration has no canonical declared owner: $($node.node_id)"
        }
        $configRecords.Add([pscustomobject]@{
                NodeId = [string]$node.node_id
                Path = [string]$node.repository_path
                SchemaVersion = [string]$dictionary.schema_version
                ParseState = 'RAW_RECURSIVE_TCL_DICTIONARY_VALIDATED'
                OwnerNodes = $owners
            })
    }

    $csharpNode = $Contracts.Nodes | Where-Object {
        $_.node_id -ceq 'WINDOWS_PROCESS_CONTROL_SOURCE' } | Select-Object -First 1
    $csharpPath = Resolve-Stage1EContainedRepositoryPath $root `
        ([string]$csharpNode.repository_path)
    $csharp = [System.IO.File]::ReadAllText($csharpPath)
    $libraries = @([regex]::Matches($csharp,
            'DllImport\("([^"]+)"') | ForEach-Object {
            $_.Groups[1].Value.ToLowerInvariant() } | Sort-Object -Unique)
    $null = Test-Stage1EExactList $libraries @('kernel32.dll', 'user32.dll') `
        'Win32 provider libraries'

    return [pscustomobject]@{
        Json = $jsonRecords.ToArray()
        ResolvedJsonReferenceCount = @($jsonRecords.References).Count
        Config = $configRecords.ToArray()
        CSharp = [pscustomobject]@{
            NodeId = 'WINDOWS_PROCESS_CONTROL_SOURCE'
            Path = [string]$csharpNode.repository_path
            Libraries = $libraries
            Capabilities = @('WINDOWS_PROCESS_CONTROL_API',
                'WINDOWS_WINDOW_CONTROL_API')
            ParseState = 'STATIC_PROVIDER_DISCOVERY_COMPLETE'
        }
        State = 'STATIC_DISCOVERY_COMPLETE'
    }
}

function Compare-Stage1EDeclaredAndStaticDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [Parameter(Mandatory = $true)]$PowerShellDiscovery,
        [Parameter(Mandatory = $true)]$TclDiscovery,
        [Parameter(Mandatory = $true)]$DataDiscovery
    )

    $declaredPaths = @($Contracts.Nodes | Where-Object {
            $_.node_class -notin @('NON_RUNTIME_SOURCE',
                'REVIEW_TOOL_SOURCE') } |
            ForEach-Object { [string]$_.repository_path } | Sort-Object -Unique)
    $staticPaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($record in $PowerShellDiscovery.ParsedSources) {
        $null = $staticPaths.Add([string]$record.Path)
    }
    foreach ($record in $TclDiscovery.Sources) {
        $null = $staticPaths.Add([string]$record.path)
    }
    foreach ($record in $DataDiscovery.Json) {
        $null = $staticPaths.Add([string]$record.Path)
    }
    foreach ($record in $DataDiscovery.Config) {
        $null = $staticPaths.Add([string]$record.Path)
    }
    $null = $staticPaths.Add([string]$DataDiscovery.CSharp.Path)
    $observedPaths = @($staticPaths | Sort-Object)
    $null = Test-Stage1EExactList $observedPaths @($declaredPaths | Sort-Object) `
        'Declared/static source nodes'

    $declaredEdgeKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($edge in $Contracts.Edges | Where-Object {
            $_.edge_type -in @('POWERSHELL_MODULE', 'POWERSHELL_DOT_SOURCE',
                'DOTNET_SOURCE_PROVIDER', 'TCL_SOURCE', 'CONFIG_READ',
                'SCHEMA_PROVIDER') -and
            $_.from -notin @($Contracts.ReviewToolNodes) -and
            $_.to -notin @($Contracts.ReviewToolNodes) }) {
        $null = $declaredEdgeKeys.Add(
            "$($edge.from)|$($edge.to)|$($edge.edge_type)")
    }
    $observedEdgeKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($edge in $PowerShellDiscovery.References) {
        $declaredCandidates = @($Contracts.Edges | Where-Object {
                $_.from -ceq $edge.From -and $_.to -ceq $edge.To -and
                $_.edge_type -in @('POWERSHELL_MODULE',
                    'DOTNET_SOURCE_PROVIDER', 'SCHEMA_PROVIDER') })
        if ($declaredCandidates.Count -ne 1) {
            throw "PowerShell static edge is undeclared or ambiguous: $($edge.From) -> $($edge.To)"
        }
        $match = $declaredCandidates[0]
        $null = $observedEdgeKeys.Add(
            "$($match.from)|$($match.to)|$($match.edge_type)")
    }
    foreach ($edge in $TclDiscovery.Edges) {
        $fromNode = $Contracts.Nodes | Where-Object {
            $_.repository_path -ceq $edge.path } | Select-Object -First 1
        if ($null -eq $fromNode) {
            throw "Tcl static edge has an undeclared caller: $($edge.path)"
        }
        $key = "$($fromNode.node_id)|$($edge.target)|$($edge.edge_type)"
        if (-not $declaredEdgeKeys.Contains($key)) {
            throw "Tcl static edge is undeclared: $key"
        }
        $null = $observedEdgeKeys.Add($key)
    }
    foreach ($key in $declaredEdgeKeys) {
        if (-not $observedEdgeKeys.Contains($key)) {
            throw "Declared source/load edge was not statically discovered: $key"
        }
    }

    $declaredCapabilityKeys = @($Contracts.Capabilities.capability_key)
    foreach ($record in $PowerShellDiscovery.Capabilities) {
        if ([string]$record.CapabilityKey -notin $declaredCapabilityKeys) {
            throw "PowerShell static capability is undeclared: $($record.CapabilityKey)"
        }
    }
    foreach ($record in $TclDiscovery.Capabilities) {
        if ([string]$record.capability -notin $declaredCapabilityKeys) {
            throw "Tcl static capability is undeclared: $($record.capability)"
        }
    }
    foreach ($capability in $DataDiscovery.CSharp.Capabilities) {
        if ($capability -notin $declaredCapabilityKeys) {
            throw "C# static capability is undeclared: $capability"
        }
    }

    return [pscustomobject]@{
        State = 'MATCH'
        DeclaredNodeCount = $declaredPaths.Count
        StaticNodeCount = $observedPaths.Count
        DeclaredEdgeCount = $declaredEdgeKeys.Count
        StaticEdgeCount = $observedEdgeKeys.Count
        AlternateEntryPointCount = 0
        UnknownCapabilityCount = 0
        UnresolvedDynamicDependencyCount = 0
    }
}

function Get-Stage1EProviderDefinitionDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot
    )

    $definitions = [System.Collections.Generic.List[object]]::new()
    $exports = [System.Collections.Generic.List[object]]::new()
    $assignments = [System.Collections.Generic.List[object]]::new()
    $sourceNodes = @($Contracts.Nodes | Where-Object {
            $_.node_class -cne 'NON_RUNTIME_SOURCE' -and
            $_.language -in @('POWERSHELL','POWERSHELL_DOTNET','TCL') -and
            $_.repository_path -cne 'NONE' })
    foreach ($node in $sourceNodes) {
        $relative = [string]$node.repository_path
        $path = Resolve-Stage1EContainedRepositoryPath $RepositoryRoot $relative
        if ([string]$node.language -ceq 'TCL') {
            $text = [System.IO.File]::ReadAllText($path)
            foreach ($match in [regex]::Matches($text,
                    '(?m)^[ \t]*proc[ \t]+(?<name>::[A-Za-z_][A-Za-z0-9_:]*)[ \t]+')) {
                $name = $match.Groups['name'].Value
                $leaf = $name.Substring($name.LastIndexOf(':') + 1)
                $escapedLeaf = [regex]::Escape($leaf)
                $versionPattern = ('(?m)^[ \t]*variable[ \t]+{0}[ \t]+' +
                    '(?:\\[ \t]*\r?\n[ \t]*)?' +
                    '(?<value>stage1e-[A-Za-z0-9-]+-v[0-9]+)') -f $escapedLeaf
                $versionMatches = [regex]::Matches($text, $versionPattern)
                $values = @($versionMatches | ForEach-Object {
                        $_.Groups['value'].Value } | Sort-Object -Unique)
                $definitions.Add([pscustomobject]@{
                        Language = 'TCL'
                        Name = $name
                        Path = $relative
                        Line = 1 + [regex]::Matches(
                            $text.Substring(0, $match.Index), "`n").Count
                        InterfaceValues = $values
                        DefinitionKind = 'FULLY_QUALIFIED_PROC'
                    })
            }
            continue
        }

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -ne 0) {
            throw "PowerShell provider source parse failed: $relative"
        }
        $variables = @{}
        $propertyValues = @{}
        $sourceDirectory = [System.IO.Path]::GetDirectoryName($path)
        $assignmentAsts = @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $candidate.Left -is [System.Management.Automation.Language.VariableExpressionAst]
                }, $true))
        for ($pass = 0; $pass -lt 12; $pass++) {
            $changed = $false
            foreach ($assignment in $assignmentAsts) {
                $key = Get-Stage1EStaticVariableKey `
                    $assignment.Left.VariablePath.UserPath
                $values = @(Resolve-Stage1EStaticPowerShellExpression `
                    $assignment.Right $variables $propertyValues $sourceDirectory |
                    Sort-Object -Unique)
                if ($values.Count -eq 0) { continue }
                $prior = if ($variables.ContainsKey($key)) {
                    @($variables[$key]) -join "`n"
                } else { '' }
                if (($values -join "`n") -cne $prior) {
                    $variables[$key] = $values
                    $changed = $true
                }
            }
            if (-not $changed) { break }
        }
        foreach ($key in $variables.Keys) {
            $assignments.Add([pscustomobject]@{
                    Path = $relative
                    Name = [string]$key
                    Values = @($variables[$key])
                })
        }
        $functionAsts = @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true))
        foreach ($functionAst in $functionAsts) {
            $returnValues = [System.Collections.Generic.List[string]]::new()
            foreach ($returnAst in @($functionAst.Body.FindAll({ param($candidate)
                            $candidate -is [System.Management.Automation.Language.ReturnStatementAst]
                        }, $true))) {
                if ($null -eq $returnAst.Pipeline) { continue }
                foreach ($value in @(Resolve-Stage1EStaticPowerShellExpression `
                        $returnAst.Pipeline $variables $propertyValues $sourceDirectory)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                        $returnValues.Add([string]$value)
                    }
                }
            }
            $definitions.Add([pscustomobject]@{
                    Language = 'POWERSHELL'
                    Name = [string]$functionAst.Name
                    Path = $relative
                    Line = $functionAst.Extent.StartLineNumber
                    InterfaceValues = @($returnValues | Sort-Object -Unique)
                    DefinitionKind = 'FUNCTION_DEFINITION_AST'
                })
        }
        $exportCommands = @($ast.FindAll({ param($candidate)
                    $candidate -is [System.Management.Automation.Language.CommandAst] -and
                    $candidate.GetCommandName() -ceq 'Export-ModuleMember'
                }, $true))
        if ($exportCommands.Count -gt 0 -and
            [System.IO.Path]::GetExtension($path) -cne '.psm1') {
            throw "A PowerShell script attempts a module export: $relative"
        }
        $exportNames = [System.Collections.Generic.List[string]]::new()
        foreach ($exportCommand in $exportCommands) {
            $exportAst = Get-Stage1ECommandArgumentAst $exportCommand @('Function')
            $values = @(Resolve-Stage1EStaticPowerShellExpression $exportAst `
                $variables $propertyValues $sourceDirectory)
            if ($values.Count -eq 0) {
                throw "PowerShell module export is dynamic or ambient: $relative"
            }
            foreach ($value in $values) {
                if ([string]::IsNullOrWhiteSpace([string]$value) -or
                    [string]$value -match '[*?]') {
                    throw "PowerShell module export is empty or wildcarded: $relative"
                }
                $exportNames.Add([string]$value)
            }
        }
        if ($exportCommands.Count -eq 0 -and
            [System.IO.Path]::GetExtension($path) -ceq '.psm1') {
            foreach ($functionAst in $functionAsts) {
                $exportNames.Add([string]$functionAst.Name)
            }
        }
        foreach ($exportName in @($exportNames | Sort-Object -Unique)) {
            if (@($functionAsts | Where-Object {
                        $_.Name -ceq $exportName }).Count -ne 1) {
                throw "PowerShell module export has no exact local definition in ${relative}: $exportName"
            }
            $exports.Add([pscustomobject]@{
                    Name = $exportName
                    Path = $relative
                    ExportKind = $(if ($exportCommands.Count -eq 0) {
                            'EFFECTIVE_DEFAULT_MODULE_EXPORT'
                        } else { 'EXPLICIT_EXPORT_MODULE_MEMBER' })
                })
        }
    }
    return [pscustomobject]@{
        Definitions = $definitions.ToArray()
        Exports = $exports.ToArray()
        Assignments = $assignments.ToArray()
        State = 'SOURCE_DERIVED_PROVIDER_DEFINITIONS_DISCOVERED'
    }
}

function Test-Stage1EProviderUniqueness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot
    )

    $providerKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($provider in $Contracts.Providers) {
        if (-not $providerKeys.Add([string]$provider.provider_key)) {
            throw "Duplicate provider key: $($provider.provider_key)"
        }
        $sourceNode = $Contracts.Nodes | Where-Object {
            $_.repository_path -ceq $provider.source_path } |
            Select-Object -First 1
        if ($null -eq $sourceNode -or
            $sourceNode.node_class -ceq 'NON_RUNTIME_SOURCE') {
            throw "Provider is owned by a missing or non-runtime source: $($provider.provider_key)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$provider.interface_command)) {
            throw "Provider has no exact interface-command binding: $($provider.provider_key)"
        }
    }
    $sourceDefinitions = Get-Stage1EProviderDefinitionDiscovery $Contracts `
        -RepositoryRoot $RepositoryRoot
    foreach ($provider in $Contracts.Providers) {
        $language = [string]$provider.language
        $command = [string]$provider.interface_command
        $sourcePath = [string]$provider.source_path
        $expectedVersion = [string]$provider.interface_version
        if ($provider.provider_key -ceq 'ENTRY_POINT_INTERFACE') {
            if ($command -cne [System.IO.Path]::GetFileName($sourcePath) -or
                [System.IO.Path]::GetExtension($sourcePath) -cne '.ps1') {
                throw 'Entry-point Provider is not bound to its exact script command.'
            }
            $entryAssignments = @($sourceDefinitions.Assignments | Where-Object {
                    $_.Path -ceq $sourcePath -and
                    $_.Name -ceq 'entryinterfaceversion' })
            if ($entryAssignments.Count -ne 1 -or
                @($entryAssignments[0].Values).Count -ne 1 -or
                [string]$entryAssignments[0].Values[0] -cne $expectedVersion) {
                throw 'Entry-point Provider interface version is not source-derived.'
            }
            continue
        }
        $definitionLanguage = if ($language -ceq 'TCL') { 'TCL' }
            else { 'POWERSHELL' }
        $matches = @($sourceDefinitions.Definitions | Where-Object {
                $_.Language -ceq $definitionLanguage -and
                $_.Name -ceq $command })
        if ($matches.Count -ne 1) {
            throw "Provider interface command is missing or multiply defined: $($provider.provider_key) ($command)"
        }
        if ([string]$matches[0].Path -cne $sourcePath) {
            throw "Provider interface command is defined by the wrong source: $($provider.provider_key)"
        }
        if (@($matches[0].InterfaceValues).Count -ne 1 -or
            [string]$matches[0].InterfaceValues[0] -cne $expectedVersion) {
            throw "Provider interface version differs from its source definition: $($provider.provider_key)"
        }
        if ($definitionLanguage -ceq 'POWERSHELL') {
            $exportMatches = @($sourceDefinitions.Exports | Where-Object {
                    $_.Name -ceq $command })
            if ($exportMatches.Count -ne 1 -or
                [string]$exportMatches[0].Path -cne $sourcePath) {
                throw "PowerShell Provider export ownership is missing, duplicate, or ambient: $($provider.provider_key)"
            }
        }
    }
    $hashProviders = @($Contracts.Providers | Where-Object {
            $_.provider_key -in @('HASH_PROVIDER_POWERSHELL',
                'HASH_PROVIDER_TCL') })
    if ($hashProviders.Count -ne 2 -or
        @($hashProviders.interface_version | Sort-Object -Unique).Count -ne 1 -or
        $hashProviders[0].interface_version -cne
        'stage1e-runtime-sha256-provider-interface-v1') {
        throw 'HASH_PROVIDER does not resolve to the exact PowerShell/Tcl pair.'
    }
    $expectedHashPaths = @{
        HASH_PROVIDER_POWERSHELL =
            'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1'
        HASH_PROVIDER_TCL =
            'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl'
    }
    foreach ($hashProvider in $hashProviders) {
        if ([string]$hashProvider.source_path -cne
            $expectedHashPaths[[string]$hashProvider.provider_key]) {
            throw "HASH_PROVIDER source substitution detected: $($hashProvider.provider_key)"
        }
    }
    $unexpectedHashProvider = @($Contracts.Providers | Where-Object {
            $_.provider_key -like 'HASH_PROVIDER_*' -and
            $_.provider_key -notin @('HASH_PROVIDER_POWERSHELL',
                'HASH_PROVIDER_TCL') })
    if ($unexpectedHashProvider.Count -ne 0) {
        throw 'A hidden second HASH_PROVIDER is declared.'
    }
    $hashAdapter = $Contracts.Providers | Where-Object {
        $_.provider_key -ceq 'HASH_ADAPTER_POWERSHELL' } |
        Select-Object -First 1
    $adapterNode = $Contracts.Nodes | Where-Object {
        $_.repository_path -ceq
            'fpga/vivado/build/dependency/stage1e_runtime_dependency_closure_v1.psm1' } |
        Select-Object -First 1
    if ($null -eq $hashAdapter -or $null -eq $adapterNode -or
        $adapterNode.node_class -cne 'REVIEW_TOOL_SOURCE' -or
        $hashAdapter.interface_version -cne
            $script:Stage1EDependencyHashAdapterInterface -or
        $hashAdapter.source_path -cne [string]$adapterNode.repository_path) {
        throw 'Public empty-byte hash adapter is absent or mis-owned.'
    }

    $expectedChildren = @(ConvertFrom-Stage1ETclList -Text `
        $Contracts.Dependency.child_provider_order)
    foreach ($child in $expectedChildren) {
        if ($child -notin @($Contracts.Providers.provider_key)) {
            throw "Declared child provider has no unique source owner: $child"
        }
    }

    $sourceCheck = $Contracts.Nodes | Where-Object {
        $_.node_id -ceq 'LEGACY_SOURCE_CHECK' } | Select-Object -First 1
    if ($null -eq $sourceCheck -or
        $sourceCheck.node_class -cne 'NON_RUNTIME_SOURCE' -or
        $sourceCheck.termination -cne 'HISTORICAL_NON_PRODUCTION') {
        throw 'source_check.tcl is not classified historical/non-production.'
    }
    if (@($Contracts.Edges | Where-Object {
                $_.from -ceq 'LEGACY_SOURCE_CHECK' -or
                $_.to -ceq 'LEGACY_SOURCE_CHECK' }).Count -ne 0) {
        throw 'source_check.tcl is production-reachable in the declared graph.'
    }
    foreach ($node in $Contracts.Nodes | Where-Object {
            $_.node_class -notin @('NON_RUNTIME_SOURCE',
                'REVIEW_TOOL_SOURCE') }) {
        $path = Resolve-Stage1EContainedRepositoryPath $RepositoryRoot `
            ([string]$node.repository_path)
        if ([System.IO.Path]::GetExtension($path) -notin @('.ps1', '.psm1',
                '.tcl', '.cs', '.json', '.dict')) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        if ($text.Contains('source_check.tcl') -or
            $text.Contains('::stage1d::source_check::')) {
            throw "source_check.tcl is referenced by production source: $($node.repository_path)"
        }
    }
    return [pscustomobject]@{
        State = 'MATCH'
        ProviderCount = $Contracts.Providers.Count
        DeclaredProviderKeyUniqueness = 'MATCH'
        SourceDerivedProviderDefinitionUniqueness = 'MATCH'
        SourceDefinitionCount = @($sourceDefinitions.Definitions | Where-Object {
                $_.Name -in @($Contracts.Providers.interface_command) }).Count
        PowerShellExportOwnership = 'EXACT_LOCAL_MODULE_EXPORT_MATCH'
        TclProcOwnership = 'EXACT_FULLY_QUALIFIED_PROC_MATCH'
        HashContractCount = 1
        HashImplementationCount = 2
        PublicHashAdapterCount = 1
        PublicHashAdapterInterface =
            $script:Stage1EDependencyHashAdapterInterface
        HiddenHashProviderCount = 0
        SourceCheckDisposition = 'HISTORICAL_NON_PRODUCTION_NOT_REACHABLE'
    }
}

function Test-Stage1ECandidateReachability {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Contracts)

    $roots = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($record in @(ConvertFrom-Stage1ERecordList -Text `
            $Contracts.Dependency.candidate_roots)) {
        foreach ($root in @(ConvertFrom-Stage1ETclList -Text $record.roots)) {
            $null = $roots.Add($root)
        }
    }
    $reachable = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($root in $roots) { $null = $reachable.Add($root); $queue.Enqueue($root) }
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($edge in $Contracts.Edges | Where-Object {
                $_.from -ceq $current -and
                $_.edge_type -in @('POWERSHELL_MODULE', 'TCL_SOURCE',
                    'DOTNET_SOURCE_PROVIDER', 'SCHEMA_PROVIDER', 'CONFIG_READ') }) {
            if ($reachable.Add([string]$edge.to)) {
                $queue.Enqueue([string]$edge.to)
            }
        }
    }
    foreach ($node in $Contracts.Nodes | Where-Object {
            $_.node_class -eq 'DIRECT_RUNTIME_SOURCE' }) {
        if (-not $reachable.Contains([string]$node.node_id)) {
            throw "Direct runtime source is unreachable in the disconnected candidate: $($node.node_id)"
        }
    }
    foreach ($node in $Contracts.Nodes | Where-Object {
            $_.node_class -eq 'NON_RUNTIME_SOURCE' }) {
        if ($reachable.Contains([string]$node.node_id)) {
            throw "Non-runtime source is candidate-reachable: $($node.node_id)"
        }
    }
    return [pscustomobject]@{
        State = 'MATCH'
        ReachableNodeCount = $reachable.Count
        DirectRoleCount = 8
        PublicAssemblyConnected = $false
        ReachabilityClass = 'DISCONNECTED_CANDIDATE_ROOT_SET'
    }
}

function Read-Stage1ETraceRecords {
    param([Parameter(Mandatory = $true)][string]$Path)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $records.Add((ConvertFrom-Stage1EKeyValueRecord $line))
    }
    return $records.ToArray()
}

function Invoke-Stage1EDisconnectedSafeLoadTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TclPath,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $evidence = [System.IO.Path]::GetFullPath($EvidenceRoot)
    if ($evidence.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Safe-load evidence root must be external to the repository.'
    }
    if (-not [System.IO.Directory]::Exists($evidence)) {
        $null = [System.IO.Directory]::CreateDirectory($evidence)
    }
    $hostOutput = Join-Path $evidence 'host-safe-load-v1.records'
    $hostRehearsalOutput = $hostOutput + '.rehearsal'
    $vivadoOutput = Join-Path $evidence 'vivado-safe-load-v1.records'
    $postOutput = Join-Path $evidence 'postprocess-safe-load-v1.records'
    foreach ($path in @($hostOutput, $hostRehearsalOutput, $vivadoOutput, $postOutput)) {
        if ([System.IO.File]::Exists($path)) {
            throw "Safe-load evidence already exists: $path"
        }
    }

    $powershell = Join-Path $PSHOME 'powershell.exe'
    if (-not [System.IO.File]::Exists($powershell)) {
        throw 'Exact Windows PowerShell executable is unavailable.'
    }
    $hostTrace = Join-Path $script:Stage1EDependencyBuildRoot `
        'dependency/stage1e_host_safe_load_trace_v1.ps1'
    $hostMessages = @(& $powershell -NoLogo -NoProfile -NonInteractive `
        -ExecutionPolicy Bypass -File $hostTrace -RepositoryRoot $root `
        -OutputPath $hostOutput)
    if ($LASTEXITCODE -ne 0) {
        throw "Host safe-load trace failed with exit code $LASTEXITCODE."
    }

    $tcl = [System.IO.Path]::GetFullPath($TclPath)
    if (-not [System.IO.File]::Exists($tcl)) {
        throw "Standalone Tcl does not exist: $tcl"
    }
    $tclTrace = Join-Path $script:Stage1EDependencyBuildRoot `
        'dependency/stage1e_tcl_safe_load_trace_v1.tcl'
    $vivadoMessages = @(& $tcl $tclTrace --repository-root $root `
        --output $vivadoOutput --scenario VIVADO)
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado-domain safe-load trace failed with exit code $LASTEXITCODE."
    }
    $postMessages = @(& $tcl $tclTrace --repository-root $root `
        --output $postOutput --scenario POSTPROCESS)
    if ($LASTEXITCODE -ne 0) {
        throw "Post-process safe-load trace failed with exit code $LASTEXITCODE."
    }

    $host = @(Read-Stage1ETraceRecords $hostOutput)
    $hostRehearsal = @(Read-Stage1ETraceRecords $hostRehearsalOutput)
    $vivado = @(Read-Stage1ETraceRecords $vivadoOutput)
    $post = @(Read-Stage1ETraceRecords $postOutput)
    foreach ($record in @($host + $vivado + $post)) {
        if ($record.attempt_state -in @('FAILED', 'BLOCKED')) {
            throw "Safe-load trace contains a blocking success-scenario event: $($record.reason)"
        }
    }
    return [pscustomobject]@{
        State = 'DISCONNECTED_CANDIDATE_SAFE_LOAD_TRACE'
        Host = $host
        HostObserved = $host
        HostRehearsal = $hostRehearsal
        HostTraceClass = 'DECLARED_ASSEMBLY_REHEARSAL'
        Vivado = $vivado
        Postprocess = $post
        EvidencePaths = @($hostOutput, $hostRehearsalOutput, $vivadoOutput, $postOutput)
        VivadoInvoked = $false
        ProcessLaunchedByCandidate = $false
        IdentityCreated = $false
    }
}

function Get-Stage1ETraceNodeByPath {
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $node = $Contracts.Nodes | Where-Object {
        $_.repository_path -ceq $Path } | Select-Object -First 1
    if ($null -eq $node) { throw "Trace source path is not a declared node: $Path" }
    return $node
}

function Get-Stage1ETraceFieldValue {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][string]$Field
    )
    if ($Record -is [System.Collections.IDictionary]) {
        if (-not $Record.Contains($Field)) {
            throw "Trace record field is missing: $Field"
        }
        return $Record[$Field]
    }
    $property = $Record.PSObject.Properties[$Field]
    if ($null -eq $property) { throw "Trace record field is missing: $Field" }
    return $property.Value
}

function Assert-Stage1ETraceAttemptPairs {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$Scenario
    )
    $groups = @($Records | Where-Object {
            [string]$_.attempt_id -ne 'NONE' } | Group-Object {
                [string]$_.attempt_id })
    foreach ($group in $groups) {
        $rows = @($group.Group | Sort-Object { [int]$_.ordinal })
        if ($rows.Count -ne 2 -or
            [string]$rows[0].attempt_state -cne 'ATTEMPTED' -or
            [string]$rows[1].attempt_state -notin @(
                'LOADED','FAILED','OPTIONAL_NOT_LOADED','BLOCKED') -or
            [int]$rows[0].load_ordinal -le 0 -or
            [int]$rows[0].load_ordinal -ne [int]$rows[1].load_ordinal -or
            [int]$rows[1].ordinal -le [int]$rows[0].ordinal) {
            throw "Trace attempt/terminal pair is structurally invalid in ${Scenario}: $($group.Name)"
        }
        foreach ($field in @('scenario','domain','requester','target',
                'edge_type','source_path','provider','interface_version',
                'interface_command','declared_edge','predicate','evidence_class')) {
            if ([string](Get-Stage1ETraceFieldValue $rows[0] $field) -cne
                [string](Get-Stage1ETraceFieldValue $rows[1] $field)) {
                throw "Trace pair binding differs in $Scenario for $($group.Name): $field"
            }
        }
    }
}

function Compare-Stage1EDeclaredStaticAndTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Contracts,
        [Parameter(Mandatory = $true)]$StaticComparison,
        [Parameter(Mandatory = $true)]$Trace
    )

    if ($StaticComparison.State -cne 'MATCH') {
        throw 'Declared/static comparison did not pass before trace comparison.'
    }
    $hostObservedRecords = if ($null -ne $Trace.HostObserved) {
        @($Trace.HostObserved)
    } else { @($Trace.Host) }
    $scenarioRecords = @{
        HOST_DISCONNECTED_SAFE_LOAD = $hostObservedRecords
        VIVADO_DISCONNECTED_SAFE_LOAD = @($Trace.Vivado)
        POSTPROCESS_DISCONNECTED_SAFE_LOAD = @($Trace.Postprocess)
    }
    $results = [System.Collections.Generic.List[object]]::new()
    $nodeById = Get-Stage1ENodeByIdTable $Contracts
    $edgeRecords = @($Contracts.Edges)
    foreach ($projection in $Contracts.TraceExpectedOccurrences) {
        $scenario = [string]$projection.scenario
        $records = @($scenarioRecords[$scenario])
        if ($records.Count -eq 0) { throw "Trace scenario is missing: $scenario" }
        $domain = switch ($scenario) {
            'HOST_DISCONNECTED_SAFE_LOAD' { 'HOST_POWERSHELL' }
            'VIVADO_DISCONNECTED_SAFE_LOAD' { 'VIVADO_TCL' }
            default { 'HOST_POSTPROCESS_TCL' }
        }
        foreach ($record in $records) {
            if ([string]$record.scenario -cne $scenario -or
                [string]$record.domain -cne $domain) {
                throw "Trace scenario/domain binding differs at ordinal $($record.ordinal)."
            }
            if ([string]$record.evidence_class -cne 'OBSERVED_SAFE_LOAD_TRACE') {
                throw "Declared rehearsal record was mixed into observed trace: $scenario"
            }
        }
        $ordinals = @($records | ForEach-Object { [int]$_.ordinal })
        for ($index = 0; $index -lt $ordinals.Count; $index++) {
            if ($ordinals[$index] -ne ($index + 1)) {
                throw "Trace event order/ordinal differs in $scenario."
            }
        }
        $null = Assert-Stage1ETraceAttemptPairs $records $scenario
        $starts = @($records | Where-Object {
                $_.attempt_state -ceq 'ATTEMPTED' } | Sort-Object {
                    [int]$_.ordinal })
        $expectedKeyObjects = @(ConvertFrom-Stage1ETclList -Text $projection.keys |
            ForEach-Object { ,@(ConvertFrom-Stage1ETclList -Text $_) })
        $providerProjection = $Contracts.TraceProviderOrder | Where-Object {
            $_.scenario -ceq $scenario } | Select-Object -First 1
        if ($null -eq $providerProjection) {
            throw "Trace provider projection is missing: $scenario"
        }
        $expectedProviders = @(ConvertFrom-Stage1ETclList -Text `
            $providerProjection.providers)
        if ($starts.Count -ne ($expectedKeyObjects.Count + $expectedProviders.Count)) {
            throw "Unexpected trace attempt count in $scenario."
        }
        if ($starts.Count -eq 0 -or [int]$starts[0].load_ordinal -le 0) {
            throw "Trace load ordinal sequence is missing in $scenario."
        }
        $firstLoadOrdinal = [int]$starts[0].load_ordinal
        $actualOccurrenceKeys = [System.Collections.Generic.List[string]]::new()
        $providerIndex = 0
        $occurrenceIndex = 0
        for ($startIndex = 0; $startIndex -lt $starts.Count; $startIndex++) {
            $record = $starts[$startIndex]
            $expectedLoadOrdinal = $firstLoadOrdinal + $startIndex
            if ([int]$record.load_ordinal -ne $expectedLoadOrdinal) {
                throw "Trace load order differs in $scenario at $($record.ordinal)."
            }
            $pair = @($records | Where-Object {
                    [string]$_.attempt_id -ceq [string]$record.attempt_id } |
                Sort-Object { [int]$_.ordinal })
            if ($pair.Count -ne 2 -or [int]$pair[1].load_ordinal -ne $expectedLoadOrdinal) {
                throw "Trace attempt/terminal load binding differs in $scenario."
            }
            $isProvider = [string]$record.kind -ceq 'PROVIDER'
            if ($isProvider) {
                if ($providerIndex -ge $expectedProviders.Count -or
                    [string]$record.provider -cne $expectedProviders[$providerIndex]) {
                    throw "Exact provider observation order differs in $scenario."
                }
                $providerIndex++
                $provider = $Contracts.Providers | Where-Object {
                    $_.provider_key -ceq [string]$record.provider } |
                    Select-Object -First 1
                if ($null -eq $provider -or
                    [string]$record.requester -cne [string]$record.target -or
                    [string]$record.edge_type -cne 'PROVIDER_OBSERVATION' -or
                    [string]$record.declared_edge -cne 'PROVIDER_OBSERVATION' -or
                    [string]$record.predicate -cne 'INTERFACE_VERSION_CONFIRMED' -or
                    [string]$record.provider -cne [string]$provider.provider_key -or
                    [string]$record.source_path -cne [string]$provider.source_path -or
                    [string]$record.interface_version -cne [string]$provider.interface_version -or
                    [string]$record.interface_command -cne [string]$provider.interface_command -or
                    (([string]$provider.process_domains -split '\s+') -notcontains $domain)) {
                    throw "Provider/interface observation differs in $scenario at $($record.ordinal)."
                }
                if ([string]$pair[1].attempt_state -cne 'LOADED') {
                    throw "Provider terminal state differs in $scenario."
                }
                continue
            }
            if ($occurrenceIndex -ge $expectedKeyObjects.Count) {
                throw "Unexpected non-provider trace attempt in $scenario."
            }
            $key = $expectedKeyObjects[$occurrenceIndex]
            $occurrenceIndex++
            $requester = [string]$key[0]
            $target = [string]$key[1]
            $edgeType = [string]$key[2]
            $actualKey = "$($record.requester)|$($record.target)|$($record.edge_type)"
            $actualOccurrenceKeys.Add($actualKey)
            if ([string]$record.requester -cne $requester -or
                [string]$record.target -cne $target -or
                [string]$record.edge_type -cne $edgeType) {
                throw "Exact trace requester/target/edge/order differs in $scenario."
            }
            if (-not $nodeById.ContainsKey($requester) -or
                -not $nodeById.ContainsKey($target)) {
                throw "Trace requester or target node is undeclared in $scenario."
            }
            $node = $nodeById[$target]
            if ([string]$record.source_path -cne [string]$node.repository_path -or
                [string]$record.declared_edge -cne $edgeType) {
                throw "Trace target/source/declared-edge binding differs in $scenario at $($record.ordinal)."
            }
            $matches = @($edgeRecords | Where-Object {
                    $_.from -ceq $requester -and $_.to -ceq $target -and
                    $_.edge_type -ceq $edgeType -and
                    $_.scenario -in @($scenario, 'ALWAYS_SOURCE',
                        'CONTRACT_CONFIGURATION', 'SOURCE_LOAD',
                        'PROVIDER_MISSING', 'PROCESS_PROVIDER_DEFERRED') -and
                    (([string]$_.domain -split '\s+') -contains $domain) })
            $matches += @($Contracts.ReviewTraceEdges | Where-Object {
                    $_.requester -ceq $requester -and $_.target -ceq $target -and
                    $_.edge_type -ceq $edgeType -and $_.scenario -ceq $scenario -and
                    [string]$_.domain -ceq $domain })
            if ($matches.Count -ne 1) {
                throw "Observed trace edge is undeclared or ambiguous in ${scenario}: $requester -> $target ($edgeType)."
            }
            $expectedTerminalState = if ($edgeType -eq 'DOTNET_SOURCE_PROVIDER' -or
                ($requester -ceq $target -and $edgeType -eq 'TCL_SOURCE')) {
                'OPTIONAL_NOT_LOADED'
            } else { 'LOADED' }
            $expectedPredicate = if ($edgeType -in @('CONFIG_READ','SCHEMA_PROVIDER')) {
                'FILE_READ'
            } elseif ($edgeType -eq 'DOTNET_SOURCE_PROVIDER') {
                'PROCESS_PROVIDER_DEFERRED'
            } elseif ($requester -ceq $target -and $edgeType -eq 'TCL_SOURCE') {
                'PROVIDER_ALREADY_LOADED_GUARDED_SOURCE'
            } elseif ($domain -eq 'HOST_POWERSHELL') {
                'CONTROLLED_INTERNAL_HARNESS'
            } else { 'CONTROLLED_SOURCE' }
            $expectedProvider = 'NONE'
            $expectedInterface = switch ($edgeType) {
                'DOTNET_SOURCE_PROVIDER' { 'stage1e-windows-process-control-interface-v1' }
                default { 'NONE' }
            }
            if ($requester -ceq $target -and $edgeType -eq 'TCL_SOURCE') {
                $selfProvider = $Contracts.Providers | Where-Object {
                    $_.source_path -ceq [string]$node.repository_path -and
                    (([string]$_.process_domains -split '\s+') -contains $domain) } |
                    Select-Object -First 1
                if ($null -eq $selfProvider) { throw "Self-load provider is undeclared in $scenario." }
                $expectedProvider = [string]$selfProvider.provider_key
                $expectedInterface = [string]$selfProvider.interface_version
            } elseif ($edgeType -eq 'DOTNET_SOURCE_PROVIDER') {
                $expectedProvider = 'WINDOWS_PROCESS_CONTROL'
            }
            if ([string]$record.provider -cne $expectedProvider -or
                [string]$record.interface_version -cne $expectedInterface -or
                [string]$record.interface_command -cne 'NONE' -or
                [string]$record.predicate -cne $expectedPredicate -or
                [string]$pair[1].attempt_state -cne $expectedTerminalState) {
                throw "Trace provider/interface/attempt/predicate differs in $scenario at $($record.ordinal)."
            }
        }
        if ($providerIndex -ne $expectedProviders.Count -or
            $occurrenceIndex -ne $expectedKeyObjects.Count) {
            throw "Trace occurrence/provider inventory differs in $scenario."
        }
        $expectedKeys = @($expectedKeyObjects | ForEach-Object { $_ -join '|' })
        if (($actualOccurrenceKeys -join "`n") -cne ($expectedKeys -join "`n")) {
            throw "Exact trace requester/target/edge/order differs in $scenario."
        }
        $results.Add([pscustomobject]@{
                Scenario = $scenario
                State = 'EXACT_EDGE_PROVIDER_INTERFACE_ORDER_MATCH'
                ExpectedOccurrenceCount = $expectedKeyObjects.Count
                ObservedOccurrenceCount = $actualOccurrenceKeys.Count
                AttemptEventCount = $starts.Count
                LoadedEventCount = @($records | Where-Object {
                        $_.attempt_state -ceq 'LOADED' }).Count
                TotalEventCount = $records.Count
                ProviderOrderState = 'MATCH'
                PreActionChronologyState = 'ATTEMPT_PRECEDES_ACTION_TERMINAL'
            })
    }
    if ([string]$Trace.HostTraceClass -ceq 'DECLARED_ASSEMBLY_REHEARSAL' -and
        @($Trace.HostRehearsal).Count -eq 0) {
        throw 'Host trace rehearsal classification has no separated rehearsal records.'
    }
    $allRecords = @($Trace.HostObserved + $Trace.Vivado + $Trace.Postprocess)
    $pathGroups = @($allRecords | Where-Object {
            $_.attempt_state -ceq 'LOADED' -and $_.source_path -ne 'NONE' } |
            Group-Object { [string]$_.source_path } |
            Where-Object { $_.Count -gt 1 })
    return [pscustomobject]@{
        State = 'DISCONNECTED_CANDIDATE_CLOSURE_VALIDATED'
        Scenarios = $results.ToArray()
        RepeatedLoadPathCount = $pathGroups.Count
        ExactTraceComparisonState = 'MATCH'
        HostTraceClassification = [string]$Trace.HostTraceClass
        HostObservedSafeLoadClosure = $false
        HostRehearsalRecordCount = @($Trace.HostRehearsal).Count
        PublicRuntimeAssemblyConnected = $false
        FinalProductionClosureProven = $false
    }
}

function Invoke-Stage1EHashProviderBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TclPath,
        [string]$RepositoryRoot = $script:Stage1EDependencyRepositoryRoot,
        [Parameter(Mandatory = $true)][string]$EvidenceRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $evidence = [System.IO.Path]::GetFullPath($EvidenceRoot)
    if ($evidence.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Hash-bootstrap evidence must be external to the repository.'
    }
    if (-not [System.IO.Directory]::Exists($evidence)) {
        $null = [System.IO.Directory]::CreateDirectory($evidence)
    }
    $vectorRoot = Join-Path $evidence 'vectors'
    if ([System.IO.Directory]::Exists($vectorRoot)) {
        throw "Hash-bootstrap vector root already exists: $vectorRoot"
    }
    $null = [System.IO.Directory]::CreateDirectory($vectorRoot)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $ascii = [System.Text.Encoding]::ASCII
    $vectors = [ordered]@{
        '01_empty.bin' = [byte[]]@()
        '02_abc.bin' = $ascii.GetBytes('abc')
        '03_multiblock_standard.bin' = $ascii.GetBytes(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')
        '04_utf8.bin' = $utf8.GetBytes('电流保护')
        '05_binary.bin' = [byte[]](0..255)
        '06_lf.bin' = $ascii.GetBytes("line`n")
        '07_crlf.bin' = $ascii.GetBytes("line`r`n")
        '08_canonical_json.bin' = $utf8.GetBytes("{`"a`":1}`n")
        '09_len55.bin' = $ascii.GetBytes(('a' * 55))
        '10_len56.bin' = $ascii.GetBytes(('a' * 56))
        '11_len63.bin' = $ascii.GetBytes(('a' * 63))
        '12_len64.bin' = $ascii.GetBytes(('a' * 64))
        '13_len65.bin' = $ascii.GetBytes(('a' * 65))
        '14_raw_file.bin' = [byte[]]@(0xff, 0x00, 0x80, 0x0a, 0x0d, 0x7f)
    }
    foreach ($name in $vectors.Keys) {
        [System.IO.File]::WriteAllBytes((Join-Path $vectorRoot $name),
            [byte[]]$vectors[$name])
    }

    $providerPath = Join-Path $root `
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.psm1'
    Microsoft.PowerShell.Core\Import-Module -Name $providerPath -Force `
        -ErrorAction Stop
    if ((Get-Stage1ESha256ProviderInterfaceVersion) -cne
        'stage1e-runtime-sha256-provider-interface-v1') {
        throw 'PowerShell hash-provider interface mismatch.'
    }
    if ((Get-Stage1EDependencyHashAdapterInterfaceVersion) -cne
        'stage1e-prt02e-sha256-empty-byte-adapter-interface-v1') {
        throw 'E-owned public hash-adapter interface mismatch.'
    }
    $powershellDigests = @{}
    $acceptedPowerShellDigests = @{}
    foreach ($name in $vectors.Keys) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $vectorRoot $name))
        # This is the versioned E-owned public adapter.  It is invoked through
        # its ordinary public byte[] parameter for every vector, including the
        # zero-byte vector; no ParameterAttribute metadata is mutated.
        $powershellDigests[$name] = Get-Stage1EDependencySha256Hex -Bytes $bytes
        if ($bytes.Length -gt 0) {
            $acceptedPowerShellDigests[$name] = Get-Stage1ESha256Hex -Bytes $bytes
        }
    }

    $tclOutput = Join-Path $evidence 'tcl-hash-bootstrap-v1.records'
    $tclScript = Join-Path $script:Stage1EDependencyBuildRoot `
        'dependency/stage1e_hash_bootstrap_v1.tcl'
    $tclProvider = Join-Path $root `
        'fpga/vivado/build/lib/stage1e_runtime_canonical_json_v1.tcl'
    & ([System.IO.Path]::GetFullPath($TclPath)) $tclScript `
        --provider $tclProvider --vector-root $vectorRoot --output $tclOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Tcl hash bootstrap failed with exit code $LASTEXITCODE."
    }
    $tclDigests = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($tclOutput)) {
        $fields = $line.Split('|')
        if ($fields.Count -ne 2 -or $tclDigests.ContainsKey($fields[0])) {
            throw 'Tcl hash-bootstrap output is malformed or duplicated.'
        }
        $tclDigests[$fields[0]] = $fields[1]
    }

    $independentDigests = @{}
    foreach ($name in $vectors.Keys) {
        # This platform verifier is implemented by the signed built-in
        # Microsoft.PowerShell.Utility module and never calls either candidate
        # provider or either project adapter.
        $platform = Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath `
            (Join-Path $vectorRoot $name) -Algorithm SHA256
        $digest = ([string]$platform.Hash).ToLowerInvariant()
        if ($digest -notmatch '^[0-9a-f]{64}$') {
            throw "Independent platform digest is invalid for $name."
        }
        $independentDigests[$name] = $digest
    }

    $known = @{
        '01_empty.bin' =
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        '02_abc.bin' =
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        '03_multiblock_standard.bin' =
            '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
    }
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $vectors.Keys) {
        $ps = [string]$powershellDigests[$name]
        $tcl = [string]$tclDigests[$name]
        $independent = [string]$independentDigests[$name]
        if ($ps -cne $tcl -or $ps -cne $independent) {
            throw "Hash-provider disagreement for vector $name."
        }
        $acceptedState = if ($acceptedPowerShellDigests.ContainsKey($name)) {
            if ([string]$acceptedPowerShellDigests[$name] -cne $ps) {
                throw "Accepted PowerShell primitive disagrees for vector $name."
            }
            'MATCH_NON_EMPTY'
        } else { 'NOT_CONFORMANT_EMPTY_VECTOR' }
        if ($known.ContainsKey($name) -and $ps -cne $known[$name]) {
            throw "Hash-provider standard-vector mismatch for $name."
        }
        $records.Add([pscustomobject]@{
                Vector = $name
                ByteCount = ([byte[]]$vectors[$name]).Length
                Digest = $ps
                PowerShell = 'MATCH'
                AcceptedPowerShellPrimitive = $acceptedState
                Tcl = 'MATCH'
                Independent = 'MATCH'
                InvocationMode = 'PUBLIC_E_OWNED_BYTE_ARRAY_ADAPTER'
            })
    }
    if (-not ([byte[]]$vectors['08_canonical_json.bin'])[-1] -eq 0x0a) {
        throw 'Canonical JSON bootstrap vector lacks its exact final LF.'
    }
    return [pscustomobject]@{
        State = 'HASH_PROVIDER_BOOTSTRAP_VALIDATED'
        ContractCount = 1
        CandidateImplementationCount = 2
        PublicAdapterInterface =
            'stage1e-prt02e-sha256-empty-byte-adapter-interface-v1'
        IndependentVerifier =
            'Microsoft.PowerShell.Utility/Get-FileHash/SHA256'
        VectorCount = $records.Count
        Records = $records.ToArray()
        TextSemantics = 'UTF8_NO_BOM_EXACT_TEXT_BYTES'
        RawSemantics = 'EXACT_BINARY_FILE_BYTES'
        EmptyVectorAdapter = 'PUBLIC_E_OWNED_ADAPTER_CONFORMANT'
        AcceptedPowerShellPrimitiveConformance = 'NON_EMPTY_VECTORS_ONLY'
        ImplementationIndependence =
            'CROSS_LANGUAGE_AND_PLATFORM_VERIFIER_WITH_SHARED_SHA256_BACKEND'
        IdentityCreated = $false
        ManifestCreated = $false
    }
}
