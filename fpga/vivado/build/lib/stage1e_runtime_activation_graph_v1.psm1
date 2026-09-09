Set-StrictMode -Version Latest

$script:Stage1EPrt03ActivationGraphInterface =
    'stage1e-prt03-activation-graph-interface-v1'
$script:Stage1EPrt03BuildRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..'))
$script:Stage1EPrt03RepositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $script:Stage1EPrt03BuildRoot '../../..'))
$script:Stage1EPrt03GraphPath = Join-Path $script:Stage1EPrt03BuildRoot `
    'config/stage1e_runtime_activation_graph_v1.dict'
$script:Stage1EPrt03DependencyModulePath = Join-Path `
    $script:Stage1EPrt03BuildRoot `
    'dependency/stage1e_runtime_dependency_closure_v1.psm1'
$script:Stage1EAcceptedGraphPath = Join-Path $script:Stage1EPrt03BuildRoot `
    'config/stage1e_runtime_declared_graph_v1.dict'

Microsoft.PowerShell.Core\Import-Module -Name `
    $script:Stage1EPrt03DependencyModulePath -ErrorAction Stop

$script:Stage1EPrt03TopFields = @(
    'schema_version', 'interface_version', 'graph_state',
    'selected_assembly_root', 'nodes', 'edges',
    'accepted_closure_reference', 'static_discovery_contract')
$script:Stage1EPrt03RootFields = @(
    'node_id', 'repository_path', 'interface_version', 'process_domain',
    'alternate_root_action')
$script:Stage1EPrt03NodeFields = @(
    'ordinal', 'node_id', 'node_class', 'repository_path', 'language',
    'owner', 'interface_command', 'interface_version', 'process_domains')
$script:Stage1EPrt03EdgeFields = @(
    'ordinal', 'requester', 'target', 'edge_type', 'target_path',
    'source_location', 'provider', 'interface_version', 'process_domain',
    'load_ordinal', 'order_constraint', 'observation_class',
    'referenced_edge_type')
$script:Stage1EPrt03ClosureFields = @(
    'reference_id', 'graph_path', 'graph_schema_version',
    'dependency_interface_version', 'expected_node_count',
    'expected_direct_role_count', 'reference_state',
    'live_transitive_state', 'full_transitive_state')
$script:Stage1EPrt03DiscoveryFields = @(
    'schema_version', 'discovery_state', 'required_node_count',
    'required_edge_count', 'dynamic_dependency_action',
    'undeclared_dependency_action', 'wrong_owner_action',
    'wrong_interface_action', 'alternate_root_action')
$script:Stage1EPrt03LedgerHeaderFields = @(
    'schema_version', 'interface_version', 'ledger_type',
    'publication_state', 'observation_mode', 'request_identity',
    'execution_id', 'attempt_id', 'source_identity', 'record_count')
$script:Stage1EPrt03LedgerRecordFields = @(
    'record_kind', 'requester', 'target', 'source_path', 'provider',
    'interface_version', 'domain', 'load_ordinal', 'attempt_state',
    'edge_type', 'evidence_source')
$script:Stage1EPrt03ReceiptFields = @(
    'schema_version', 'interface_version', 'ledger_type', 'ledger_path',
    'publication_state', 'ledger_byte_count', 'ledger_sha256',
    'request_identity', 'execution_id', 'attempt_id')

function Get-Stage1EPrt03ActivationGraphInterfaceVersion {
    return $script:Stage1EPrt03ActivationGraphInterface
}

function Get-Stage1EPrt03ActivationGraphPath {
    return [System.IO.Path]::GetFullPath($script:Stage1EPrt03GraphPath)
}

function Assert-Stage1EPrt03ExactFields {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $actual = @($Record.Keys | ForEach-Object { [string]$_ })
    if (($actual -join '|') -cne ($Expected -join '|')) {
        throw "$Label has an incorrect exact field set/order."
    }
}

function ConvertFrom-Stage1EPrt03RecordList {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $ordinal = 0
    foreach ($record in @(ConvertFrom-Stage1ERecordList -Text $Text)) {
        $ordinal++
        Assert-Stage1EPrt03ExactFields $record $Fields "$Label $ordinal"
        if ([string]$record.ordinal -cne [string]$ordinal) {
            throw "$Label has a noncanonical ordinal at $ordinal."
        }
        $records.Add($record)
    }
    return $records.ToArray()
}

function Get-Stage1EPrt03ProductionSourcePaths {
    $specifications = @(
        @('config', 'stage1e_runtime_activation_*_v1.dict'),
        @('lib', 'stage1e_runtime_activation_*_v1.psm1'),
        @('adapters', 'stage1e_production_runtime_assembly_*_v1.psm1'),
        @('controller', 'stage1e_production_runtime_assembly_*_v1.psm1'),
        @('runtime/assembly', 'stage1e_connected_*_v1.*'),
        @('runtime/entrypoint/v2', 'stage1e_*_v2.ps1'))
    $paths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($specification in $specifications) {
        $directory = Join-Path $script:Stage1EPrt03BuildRoot $specification[0]
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -File `
                -Filter $specification[1])) {
            $relative = $file.FullName.Substring(
                $script:Stage1EPrt03RepositoryRoot.TrimEnd('\','/').Length).
                TrimStart('\','/').Replace('\','/')
            $null = $paths.Add($relative)
        }
    }
    return @($paths | Sort-Object)
}

function Import-Stage1EPrt03ActivationGraph {
    [CmdletBinding()]
    param([string]$Path = $script:Stage1EPrt03GraphPath)

    $raw = Read-Stage1ETclDictionaryFile -Path $Path
    Assert-Stage1EPrt03ExactFields $raw $script:Stage1EPrt03TopFields `
        'PRT03 activation graph'
    $root = ConvertFrom-Stage1ETclDictionary -Text $raw.selected_assembly_root
    Assert-Stage1EPrt03ExactFields $root $script:Stage1EPrt03RootFields `
        'PRT03 selected assembly root'
    $closure = ConvertFrom-Stage1ETclDictionary `
        -Text $raw.accepted_closure_reference
    Assert-Stage1EPrt03ExactFields $closure $script:Stage1EPrt03ClosureFields `
        'PRT03 accepted closure reference'
    $discovery = ConvertFrom-Stage1ETclDictionary `
        -Text $raw.static_discovery_contract
    Assert-Stage1EPrt03ExactFields $discovery `
        $script:Stage1EPrt03DiscoveryFields 'PRT03 static discovery contract'
    $graph = [ordered]@{
        schema_version = [string]$raw.schema_version
        interface_version = [string]$raw.interface_version
        graph_state = [string]$raw.graph_state
        selected_assembly_root = $root
        nodes = @(ConvertFrom-Stage1EPrt03RecordList $raw.nodes `
            $script:Stage1EPrt03NodeFields 'PRT03 activation node')
        edges = @(ConvertFrom-Stage1EPrt03RecordList $raw.edges `
            $script:Stage1EPrt03EdgeFields 'PRT03 activation edge')
        accepted_closure_reference = $closure
        static_discovery_contract = $discovery
    }
    $null = Assert-Stage1EPrt03ActivationGraph $graph
    return $graph
}

function Assert-Stage1EPrt03ActivationGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Graph
    )
    Assert-Stage1EPrt03ExactFields $Graph $script:Stage1EPrt03TopFields `
        'Parsed PRT03 activation graph'
    if ([string]$Graph.schema_version -cne
            'stage1e-prt03-activation-graph-v1' -or
        [string]$Graph.interface_version -cne
            $script:Stage1EPrt03ActivationGraphInterface -or
        [string]$Graph.graph_state -cne 'PRT03_ACTIVATION_GRAPH_DECLARED') {
        throw 'PRT03 activation graph identity or state differs.'
    }
    $root = $Graph.selected_assembly_root
    if ([string]$root.node_id -cne 'CONNECTED_HOST_ASSEMBLY' -or
        [string]$root.interface_version -cne
            'stage1e-connected-host-assembly-interface-v1' -or
        [string]$root.process_domain -cne 'HOST_POWERSHELL' -or
        [string]$root.alternate_root_action -cne 'BLOCK') {
        throw 'PRT03 activation graph selected an alternate assembly root.'
    }

    $discoveredPaths = @(Get-Stage1EPrt03ProductionSourcePaths)
    $declaredPaths = @($Graph.nodes | ForEach-Object {
            [string]$_.repository_path } | Sort-Object)
    if (($discoveredPaths -join '|') -cne ($declaredPaths -join '|')) {
        throw 'PRT03 activation graph source membership differs from the independent production inventory.'
    }
    if ($Graph.nodes.Count -ne
            [int]$Graph.static_discovery_contract.required_node_count -or
        $Graph.edges.Count -ne
            [int]$Graph.static_discovery_contract.required_edge_count) {
        throw 'PRT03 activation graph node or edge count differs.'
    }
    foreach ($field in @('node_id', 'repository_path')) {
        $values = @($Graph.nodes | ForEach-Object { [string]$_[$field] })
        if (@($values | Sort-Object -Unique).Count -ne $values.Count) {
            throw "PRT03 activation graph has duplicate $field values."
        }
    }
    foreach ($node in $Graph.nodes) {
        $null = Resolve-Stage1EContainedSourceWithAncestors `
            -RepositoryRoot $script:Stage1EPrt03RepositoryRoot `
            -RepositoryPath ([string]$node.repository_path)
    }
    $nodeIds = @($Graph.nodes.node_id)
    $seenEdges = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($edge in $Graph.edges) {
        if ([string]$edge.requester -notin $nodeIds -or
            ([string]$edge.target -notin $nodeIds -and
                [string]$edge.target -cne 'PRT02_E_AE_GRAPH')) {
            throw "PRT03 activation edge has an unknown endpoint: $($edge.ordinal)"
        }
        $requester = @($Graph.nodes | Where-Object {
                [string]$_.node_id -ceq [string]$edge.requester })
        if ($requester.Count -ne 1 -or
            [string]$edge.source_location -cne
                [string]$requester[0].repository_path) {
            throw "PRT03 activation edge source ownership differs: $($edge.ordinal)"
        }
        $key = "$($edge.requester)|$($edge.target_path)|$($edge.edge_type)"
        if (-not $seenEdges.Add($key)) {
            throw "PRT03 activation graph has a duplicate edge: $key"
        }
        if ([string]$edge.observation_class -ceq 'DIRECT_CONNECTED_ASSEMBLY') {
            if ([int]$edge.load_ordinal -lt 1 -or
                [string]$edge.referenced_edge_type -cne 'NONE') {
                throw 'PRT03 direct observation edge has invalid ordering or reference state.'
            }
        }
        elseif ([int]$edge.load_ordinal -ne 0) {
            throw 'PRT03 non-direct edge must not claim a live load ordinal.'
        }
    }
    $direct = @($Graph.edges | Where-Object {
            [string]$_.observation_class -ceq 'DIRECT_CONNECTED_ASSEMBLY' } |
        Sort-Object { [int]$_.load_ordinal })
    if ($direct.Count -ne 6) {
        throw 'PRT03 direct connected assembly must contain exactly six operations.'
    }
    for ($index = 0; $index -lt $direct.Count; $index++) {
        if ([int]$direct[$index].load_ordinal -ne ($index + 1)) {
            throw 'PRT03 direct connected assembly order is not contiguous.'
        }
    }
    $closure = $Graph.accepted_closure_reference
    if ([string]$closure.reference_id -cne 'PRT02_E_AE_GRAPH' -or
        [string]$closure.graph_schema_version -cne
            'stage1e-runtime-declared-graph-v1' -or
        [string]$closure.dependency_interface_version -cne
            'stage1e-runtime-dependency-closure-interface-v1' -or
        [int]$closure.expected_node_count -ne 58 -or
        [int]$closure.expected_direct_role_count -ne 8 -or
        [string]$closure.live_transitive_state -cne
            'AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED' -or
        [string]$closure.full_transitive_state -cne
            'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN') {
        throw 'PRT03 accepted A-E closure reference differs.'
    }
    return $true
}

function Get-Stage1EPrt03PathTables {
    param([Parameter(Mandatory = $true)]$Graph)
    $prt03 = @{}
    foreach ($node in $Graph.nodes) {
        $prt03[[string]$node.repository_path] = $node
    }
    $accepted = Import-Stage1EDependencyContracts `
        -BuildRoot $script:Stage1EPrt03BuildRoot
    $null = Assert-Stage1EDependencyContracts $accepted
    $ae = @{}
    foreach ($node in $accepted.Nodes) {
        $ae[[string]$node.repository_path] = $node
    }
    $ae['fpga/vivado/build/config/stage1e_runtime_declared_graph_v1.dict'] =
        [pscustomobject]@{ node_id = 'PRT02_E_AE_GRAPH' }
    return [pscustomobject]@{ Prt03 = $prt03; Accepted = $ae; Contracts = $accepted }
}

function Resolve-Stage1EPrt03Leaf {
    param(
        [Parameter(Mandatory = $true)][string]$Leaf,
        [Parameter(Mandatory = $true)]$Tables
    )
    $matches = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($Tables.Prt03.Keys) + @($Tables.Accepted.Keys)) {
        if ([System.IO.Path]::GetFileName([string]$path) -ceq $Leaf) {
            $matches.Add([string]$path)
        }
    }
    $unique = @($matches | Sort-Object -Unique)
    if ($unique.Count -ne 1) {
        throw "PRT03 static dependency leaf is missing or ambiguous: $Leaf"
    }
    return $unique[0]
}

function Get-Stage1EPrt03StaticDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Graph,
        [System.Collections.IDictionary]$SourceOverrides = @{}
    )
    $null = Assert-Stage1EPrt03ActivationGraph $Graph
    $tables = Get-Stage1EPrt03PathTables $Graph
    $references = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $leafPattern = '(?i)\b(stage1e_[a-z0-9_]+\.(?:psm1|tcl|dict))\b'

    foreach ($relative in @(Get-Stage1EPrt03ProductionSourcePaths)) {
        if ($relative -match '\.dict$') { continue }
        $path = Join-Path $script:Stage1EPrt03RepositoryRoot $relative
        $text = if ($SourceOverrides.Contains($relative)) {
            [string]$SourceOverrides[$relative]
        }
        else { [System.IO.File]::ReadAllText($path) }
        $requesters = @($Graph.nodes | Where-Object {
                [string]$_.repository_path -ceq $relative })
        if ($requesters.Count -ne 1) {
            throw "PRT03 static discovery source has no unique owner: $relative"
        }
        $requester = [string]$requesters[0].node_id

        if ($relative -match '\.ps(m)?1$') {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $text, $relative, [ref]$tokens, [ref]$errors)
            if ($errors.Count -ne 0) {
                throw "PRT03 PowerShell static discovery parse failed: $relative"
            }
            foreach ($command in @($ast.FindAll({ param($candidate)
                            $candidate -is [System.Management.Automation.Language.CommandAst]
                        }, $true))) {
                $name = [string]$command.GetCommandName()
                if ($name.Contains('\')) { $name = $name.Split('\')[-1] }
                if ($name -ceq 'Import-Module') {
                    $argument = Get-Stage1ECommandArgumentAst $command @('Name')
                    if ($null -eq $argument -or
                        $argument.Extent.Text -match '(?i)\$env:|\$\(') {
                        throw "PRT03 dynamic module import is prohibited in $relative."
                    }
                }
                if ($command.InvocationOperator -eq
                    [System.Management.Automation.Language.TokenKind]::Dot -and
                    $command.Extent.Text -notmatch $leafPattern) {
                    throw "PRT03 dynamic dot-source is prohibited in $relative."
                }
            }
        }
        elseif ($relative -match '\.tcl$') {
            $sourceCount = [regex]::Matches($text,
                '(?im)^\s*source\s+').Count
            $sourceLeafCount = @([regex]::Matches($text, $leafPattern) |
                ForEach-Object { $_.Groups[1].Value } |
                Where-Object { $_ -match '\.tcl$' } | Sort-Object -Unique).Count
            if ($sourceCount -ne $sourceLeafCount) {
                throw "PRT03 dynamic Tcl source is prohibited in $relative."
            }
        }

        $leaves = @([regex]::Matches($text, $leafPattern) |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        foreach ($leaf in $leaves) {
            if ($leaf -ceq [System.IO.Path]::GetFileName($relative)) { continue }
            $targetPath = Resolve-Stage1EPrt03Leaf $leaf $tables
            $declared = @($Graph.edges | Where-Object {
                    [string]$_.requester -ceq $requester -and
                    [string]$_.target_path -ceq $targetPath })
            if ($declared.Count -ne 1) {
                throw "PRT03 static dependency is undeclared or ambiguous: $relative -> $targetPath"
            }
            $edge = $declared[0]
            if ($text.IndexOf([string]$edge.interface_version,
                    [System.StringComparison]::Ordinal) -lt 0) {
                throw "PRT03 static dependency interface is not source-bound: $relative -> $targetPath"
            }
            $key = "$requester|$targetPath|$($edge.edge_type)"
            if ($seen.Add($key)) {
                $references.Add([pscustomobject]@{
                        Requester = $requester
                        Target = [string]$edge.target
                        TargetPath = $targetPath
                        EdgeType = [string]$edge.edge_type
                        Provider = [string]$edge.provider
                        InterfaceVersion = [string]$edge.interface_version
                        SourceLocation = $relative
                        State = 'SEMANTIC_STATIC_REFERENCE'
                    })
            }
        }

        foreach ($edge in @($Graph.edges | Where-Object {
                    [string]$_.requester -ceq $requester -and
                    [string]$_.edge_type -ceq 'PROVIDER_INTERFACE' })) {
            if ($text.IndexOf([string]$edge.provider,
                    [System.StringComparison]::Ordinal) -lt 0 -or
                $text.IndexOf([string]$edge.interface_version,
                    [System.StringComparison]::Ordinal) -lt 0) {
                throw "PRT03 provider interface is not statically owned by $relative."
            }
        }
    }

    foreach ($node in $Graph.nodes | Where-Object {
            [string]$_.interface_command -notin @('NONE',
                'SCRIPT_PARAMETER_SURFACE') }) {
        $source = [System.IO.File]::ReadAllText((Join-Path `
                $script:Stage1EPrt03RepositoryRoot $node.repository_path))
        if ([string]$node.language -ceq 'POWERSHELL') {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $source, [string]$node.repository_path,
                [ref]$tokens, [ref]$errors)
            $definitions = @($ast.FindAll({ param($candidate)
                        $candidate -is
                            [System.Management.Automation.Language.FunctionDefinitionAst]
                    }, $true) | Where-Object {
                    [string]$_.Name -ceq [string]$node.interface_command })
            if ($errors.Count -ne 0 -or $definitions.Count -ne 1) {
                throw "PRT03 interface owner is missing or duplicate: $($node.node_id)"
            }
        }
        elseif ([string]$node.language -ceq 'TCL') {
            $escaped = [regex]::Escape([string]$node.interface_command)
            if ([regex]::Matches($source,
                    "(?m)^proc\s+$escaped\s+").Count -ne 1) {
                throw "PRT03 Tcl interface owner is missing or duplicate: $($node.node_id)"
            }
        }
    }

    return [pscustomobject]@{
        State = 'PRT03_STATIC_DISCOVERY_COMPLETE'
        SourceCount = @(Get-Stage1EPrt03ProductionSourcePaths).Count
        ReferenceCount = $references.Count
        References = $references.ToArray()
        DynamicDependencyCount = 0
        AlternateRootCount = 0
    }
}

function Compare-Stage1EPrt03DeclaredAndStatic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Graph,
        [Parameter(Mandatory = $true)]$Discovery
    )
    if ([string]$Discovery.State -cne 'PRT03_STATIC_DISCOVERY_COMPLETE' -or
        [int]$Discovery.DynamicDependencyCount -ne 0 -or
        [int]$Discovery.AlternateRootCount -ne 0) {
        throw 'PRT03 static discovery is not eligible for comparison.'
    }
    $declared = @($Graph.edges | ForEach-Object {
            "$($_.requester)|$($_.target_path)|$($_.edge_type)" } | Sort-Object)
    $observed = @($Discovery.References | ForEach-Object {
            "$($_.Requester)|$($_.TargetPath)|$($_.EdgeType)" } | Sort-Object)
    if (($declared -join "`n") -cne ($observed -join "`n")) {
        throw 'PRT03 declared/static dependency comparison differs.'
    }
    return [ordered]@{
        schema_version = 'stage1e-prt03-static-comparison-v1'
        comparison_state = 'MATCH'
        declared_source_count = $Graph.nodes.Count
        static_source_count = [int]$Discovery.SourceCount
        declared_edge_count = $Graph.edges.Count
        static_edge_count = [int]$Discovery.ReferenceCount
        unresolved_dynamic_count = 0
        alternate_root_count = 0
    }
}

function Get-Stage1EPrt03ExpectedDirectLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Graph
    )
    $null = Assert-Stage1EPrt03ActivationGraph $Graph
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($edge in @($Graph.edges | Where-Object {
                [string]$_.observation_class -ceq
                    'DIRECT_CONNECTED_ASSEMBLY' } |
            Sort-Object { [int]$_.load_ordinal })) {
        $records.Add([ordered]@{
                requester = [string]$edge.requester
                target = [string]$edge.target
                source_path = [string]$edge.target_path
                provider = [string]$edge.provider
                interface_version = [string]$edge.interface_version
                domain = [string]$edge.process_domain
                load_ordinal = [int]$edge.load_ordinal
                attempt_state = 'LOADED'
                edge_type = [string]$edge.edge_type
                evidence_source = 'NATURAL_RUNTIME_OBSERVATION'
            })
    }
    return $records.ToArray()
}

function ConvertFrom-Stage1EPrt03SealedValue {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        if ($Value[$index] -ne '\') {
            $null = $builder.Append($Value[$index])
            continue
        }
        if ($index + 1 -ge $Value.Length) { throw 'Truncated sealed escape.' }
        $index++
        switch ($Value[$index]) {
            '\' { $null = $builder.Append('\') }
            'p' { $null = $builder.Append('|') }
            't' { $null = $builder.Append("`t") }
            'r' { $null = $builder.Append("`r") }
            'n' { $null = $builder.Append("`n") }
            default { throw 'Unknown sealed escape.' }
        }
    }
    return $builder.ToString()
}

function ConvertFrom-Stage1EPrt03SealedLine {
    param([Parameter(Mandatory = $true)][string]$Line)
    $record = [ordered]@{}
    foreach ($field in $Line.Split('|')) {
        $separator = $field.IndexOf('=')
        if ($separator -lt 1) { throw 'Malformed PRT03 sealed field.' }
        $name = $field.Substring(0, $separator)
        if ($record.Contains($name)) { throw "Duplicate sealed field: $name" }
        $record[$name] = ConvertFrom-Stage1EPrt03SealedValue `
            $field.Substring($separator + 1)
    }
    return $record
}

function Compare-Stage1EPrt03DirectAssemblyLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LedgerPath,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$RequestIdentity,
        [Parameter(Mandatory = $true)][string]$ExecutionId,
        [Parameter(Mandatory = $true)][string]$AttemptId,
        [Parameter(Mandatory = $true)][string]$SourceIdentity,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Graph
    )
    $ledgerFull = [System.IO.Path]::GetFullPath($LedgerPath)
    $receiptFull = [System.IO.Path]::GetFullPath($ReceiptPath)
    $ledgerBytes = [System.IO.File]::ReadAllBytes($ledgerFull)
    $ledgerText = [System.Text.UTF8Encoding]::new($false, $true).
        GetString($ledgerBytes)
    if (-not $ledgerText.EndsWith("`n",
            [System.StringComparison]::Ordinal)) {
        throw 'PRT03 direct ledger lacks its canonical final LF.'
    }
    $lines = @($ledgerText.TrimEnd("`n").Split("`n"))
    $header = ConvertFrom-Stage1EPrt03SealedLine $lines[0]
    Assert-Stage1EPrt03ExactFields $header `
        $script:Stage1EPrt03LedgerHeaderFields 'PRT03 direct ledger header'
    if ([string]$header.schema_version -cne
            'stage1e-prt03-direct-assembly-ledger-v1' -or
        [string]$header.interface_version -cne
            $script:Stage1EPrt03ActivationGraphInterface -or
        [string]$header.ledger_type -cne 'PRT03_DIRECT_ASSEMBLY_LEDGER' -or
        [string]$header.publication_state -cne 'SEALED' -or
        [string]$header.observation_mode -cne 'NATURAL_FIXED_ASSEMBLY' -or
        [string]$header.request_identity -cne $RequestIdentity -or
        [string]$header.execution_id -cne $ExecutionId -or
        [string]$header.attempt_id -cne $AttemptId -or
        [string]$header.source_identity -cne $SourceIdentity) {
        throw 'PRT03 direct ledger header identity, binding, or observation mode differs.'
    }
    $expected = @(Get-Stage1EPrt03ExpectedDirectLedger $Graph)
    if ([int]$header.record_count -ne $expected.Count -or
        $lines.Count -ne ($expected.Count + 1)) {
        throw 'PRT03 direct ledger record count differs.'
    }
    $actual = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $record = ConvertFrom-Stage1EPrt03SealedLine $lines[$index + 1]
        Assert-Stage1EPrt03ExactFields $record `
            $script:Stage1EPrt03LedgerRecordFields `
            "PRT03 direct ledger record $($index + 1)"
        if ([string]$record.record_kind -cne 'RECORD' -or
            [string]$record.evidence_source -cne
                'NATURAL_RUNTIME_OBSERVATION') {
            throw 'Expected-derived replay cannot satisfy PRT03 Actual evidence.'
        }
        $actual.Add($record)
        foreach ($field in @('requester', 'target', 'source_path', 'provider',
                'interface_version', 'domain', 'load_ordinal',
                'attempt_state', 'edge_type', 'evidence_source')) {
            if ([string]$record[$field] -cne
                [string]$expected[$index][$field]) {
                throw "PRT03 Actual/Expected mismatch at $($index + 1): $field"
            }
        }
    }

    $receiptText = [System.Text.UTF8Encoding]::new($false, $true).GetString(
        [System.IO.File]::ReadAllBytes($receiptFull))
    $receipt = ConvertFrom-Stage1EPrt03SealedLine $receiptText
    Assert-Stage1EPrt03ExactFields $receipt `
        $script:Stage1EPrt03ReceiptFields 'PRT03 direct ledger receipt'
    $digest = Get-Stage1EDependencySha256Hex -Bytes $ledgerBytes
    $canonicalLedgerPath = $ledgerFull.Replace('\','/')
    if ([string]$receipt.schema_version -cne
            'stage1e-prt03-direct-assembly-ledger-receipt-v1' -or
        [string]$receipt.interface_version -cne
            $script:Stage1EPrt03ActivationGraphInterface -or
        [string]$receipt.ledger_type -cne 'PRT03_DIRECT_ASSEMBLY_LEDGER' -or
        [string]$receipt.ledger_path -cne $canonicalLedgerPath -or
        [string]$receipt.publication_state -cne 'PUBLISHED' -or
        [int64]$receipt.ledger_byte_count -ne $ledgerBytes.Length -or
        [string]$receipt.ledger_sha256 -cne $digest -or
        [string]$receipt.request_identity -cne $RequestIdentity -or
        [string]$receipt.execution_id -cne $ExecutionId -or
        [string]$receipt.attempt_id -cne $AttemptId) {
        throw 'PRT03 direct ledger receipt differs.'
    }
    return [ordered]@{
        schema_version = 'stage1e-prt03-direct-ledger-comparison-v1'
        comparison_state = 'MATCH'
        expected_source = 'PRT03_ACTIVATION_GRAPH'
        actual_source = 'REOPENED_SEALED_NATURAL_OBSERVATION'
        record_count = $actual.Count
        ledger_sha256 = $digest
        direct_assembly_state = 'PRT03_DIRECT_CONNECTED_ASSEMBLY_VALIDATED'
    }
}

function Assert-Stage1EPrt03AcceptedClosureReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Graph
    )
    $null = Assert-Stage1EPrt03ActivationGraph $Graph
    $reference = $Graph.accepted_closure_reference
    if (-not [System.IO.File]::Exists($script:Stage1EAcceptedGraphPath) -or
        [string]$reference.graph_path -cne
            'fpga/vivado/build/config/stage1e_runtime_declared_graph_v1.dict') {
        throw 'PRT03 accepted graph reference path differs.'
    }
    $contracts = Import-Stage1EDependencyContracts `
        -BuildRoot $script:Stage1EPrt03BuildRoot
    $null = Assert-Stage1EDependencyContracts $contracts
    $directRoles = @($contracts.Nodes | Where-Object {
            [string]$_.node_class -ceq 'DIRECT_RUNTIME_SOURCE' })
    if ([string]$contracts.Graph.schema_version -cne
            [string]$reference.graph_schema_version -or
        $contracts.Nodes.Count -ne [int]$reference.expected_node_count -or
        $directRoles.Count -ne [int]$reference.expected_direct_role_count -or
        [string](Get-Stage1EDependencyClosureInterfaceVersion) -cne
            [string]$reference.dependency_interface_version) {
        throw 'PRT03 accepted PRT02-E closure reference does not match the committed graph.'
    }
    return [ordered]@{
        schema_version = 'stage1e-prt03-ae-closure-reference-result-v1'
        reference_id = [string]$reference.reference_id
        reference_state = 'MATCH'
        accepted_graph_state = [string]$contracts.Graph.graph_state
        accepted_node_count = $contracts.Nodes.Count
        accepted_direct_role_count = $directRoles.Count
        live_transitive_state =
            'AE_ACCEPTED_DISCONNECTED_CLOSURE_REFERENCED'
        full_transitive_state =
            'HOST_FULL_TRANSITIVE_LIVE_CLOSURE_NOT_PROVEN'
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EPrt03ActivationGraphInterfaceVersion'
    'Get-Stage1EPrt03ActivationGraphPath'
    'Get-Stage1EPrt03ProductionSourcePaths'
    'Import-Stage1EPrt03ActivationGraph'
    'Assert-Stage1EPrt03ActivationGraph'
    'Get-Stage1EPrt03StaticDiscovery'
    'Compare-Stage1EPrt03DeclaredAndStatic'
    'Get-Stage1EPrt03ExpectedDirectLedger'
    'Compare-Stage1EPrt03DirectAssemblyLedger'
    'Assert-Stage1EPrt03AcceptedClosureReference'
)
