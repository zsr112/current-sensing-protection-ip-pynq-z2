Set-StrictMode -Version Latest

$canonicalModule = Join-Path $PSScriptRoot 'stage1e_runtime_canonical_json_v1.psm1'
$envelopeModule = Join-Path $PSScriptRoot 'stage1e_runtime_envelope_contract_v1.psm1'
$publicationModule = Join-Path $PSScriptRoot 'stage1e_runtime_atomic_publication_v1.psm1'
Import-Module -Name $canonicalModule -Force -ErrorAction Stop
Import-Module -Name $envelopeModule -Force -ErrorAction Stop
Import-Module -Name $publicationModule -Force -ErrorAction Stop

$script:Stage1EHostBoundaryContractInterface =
    'stage1e-host-boundary-contract-interface-v1'
$script:Stage1EHostSupportedSchemaKeywords = @(
    '$schema', '$id', 'title', '$ref', '$defs',
    'type', 'required', 'additionalProperties',
    'x-stage1e-canonical-order', 'properties',
    'oneOf', 'const', 'enum', 'minimum', 'maximum',
    'minLength', 'maxLength', 'items', 'minItems', 'maxItems',
    'uniqueItems', 'x-stage1e-format'
)
$script:Stage1EHostSchemaSpecifications = [object[]]@(
    [ordered]@{ Role = 'failure'; File = 'stage1e_runtime_failure_record_v1.schema.json'; Id = 'stage1e-runtime-failure-record-v1' }
    [ordered]@{ Role = 'common'; File = 'stage1e_runtime_host_common_v1.schema.json'; Id = 'stage1e-runtime-host-common-v1' }
    [ordered]@{ Role = 'requirements'; File = 'stage1e_runtime_host_requirements_v1.schema.json'; Id = 'stage1e-runtime-host-requirements-v1' }
    [ordered]@{ Role = 'launcher_request'; File = 'stage1e_runtime_host_launcher_request_v1.schema.json'; Id = 'stage1e-runtime-host-launcher-request-v1' }
    [ordered]@{ Role = 'preflight'; File = 'stage1e_runtime_host_preflight_observation_v1.schema.json'; Id = 'stage1e-runtime-host-preflight-observation-v1' }
    [ordered]@{ Role = 'process_instance'; File = 'stage1e_runtime_host_process_instance_v1.schema.json'; Id = 'stage1e-runtime-host-process-instance-v1' }
    [ordered]@{ Role = 'process_ledger'; File = 'stage1e_runtime_host_process_ledger_v1.schema.json'; Id = 'stage1e-runtime-host-process-ledger-v1' }
    [ordered]@{ Role = 'heartbeat'; File = 'stage1e_runtime_host_heartbeat_event_v1.schema.json'; Id = 'stage1e-runtime-host-heartbeat-event-v1' }
    [ordered]@{ Role = 'timeout_ledger'; File = 'stage1e_runtime_host_timeout_termination_ledger_v1.schema.json'; Id = 'stage1e-runtime-host-timeout-termination-ledger-v1' }
    [ordered]@{ Role = 'host_result'; File = 'stage1e_runtime_host_component_result_v1.schema.json'; Id = 'stage1e-runtime-host-component-result-v1' }
)

function Get-Stage1EHostBoundaryContractInterfaceVersion {
    return $script:Stage1EHostBoundaryContractInterface
}

function Assert-Stage1EHostSchemaNode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Node,
        [Parameter(Mandatory = $true)][string]$Path
    )

    foreach ($keyValue in $Node.Keys) {
        $key = [string]$keyValue
        if ($script:Stage1EHostSupportedSchemaKeywords -cnotcontains $key) {
            throw [System.IO.InvalidDataException]::new(
                "Unsupported host schema keyword '$key' at $Path.")
        }
    }
    if ($Node.Contains('type') -and [string]$Node.type -ceq 'object') {
        foreach ($name in @(
                'required', 'additionalProperties',
                'x-stage1e-canonical-order', 'properties')) {
            if (-not $Node.Contains($name)) {
                throw [System.IO.InvalidDataException]::new(
                    "Exact object schema at $Path lacks '$name'.")
            }
        }
        if ([bool]$Node.additionalProperties -or
            $Node.properties -isnot [System.Collections.IDictionary]) {
            throw [System.IO.InvalidDataException]::new(
                "Object schema at $Path is not exact-field closed.")
        }
        $required = @($Node.required)
        $order = @($Node['x-stage1e-canonical-order'])
        if ($required.Count -ne $Node.properties.Count -or
            $order.Count -ne $Node.properties.Count) {
            throw [System.IO.InvalidDataException]::new(
                "Object schema at $Path has incomplete field metadata.")
        }
        $requiredSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
        $orderSet = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
        foreach ($nameValue in $required) {
            if (-not $requiredSet.Add([string]$nameValue)) {
                throw [System.IO.InvalidDataException]::new(
                    "Object schema at $Path repeats a required field.")
            }
        }
        foreach ($nameValue in $order) {
            if (-not $orderSet.Add([string]$nameValue)) {
                throw [System.IO.InvalidDataException]::new(
                    "Object schema at $Path repeats an ordered field.")
            }
        }
        foreach ($nameValue in $Node.properties.Keys) {
            $name = [string]$nameValue
            if (-not $requiredSet.Contains($name) -or
                -not $orderSet.Contains($name)) {
                throw [System.IO.InvalidDataException]::new(
                    "Object schema at $Path does not require and order '$name'.")
            }
            Assert-Stage1EHostSchemaNode $Node.properties[$name] `
                "$Path.properties.$name"
        }
    }
    elseif ($Node.Contains('type') -and [string]$Node.type -ceq 'array' -and
        $Node.Contains('items')) {
        Assert-Stage1EHostSchemaNode $Node.items "$Path.items"
    }
    if ($Node.Contains('oneOf')) {
        foreach ($index in 0..($Node.oneOf.Count - 1)) {
            Assert-Stage1EHostSchemaNode $Node.oneOf[$index] `
                "$Path.oneOf[$index]"
        }
    }
    if ($Node.Contains('$defs')) {
        foreach ($nameValue in $Node['$defs'].Keys) {
            $name = [string]$nameValue
            Assert-Stage1EHostSchemaNode $Node['$defs'][$name] `
                "$Path.`$defs.$name"
        }
    }
}

function Import-Stage1EHostBoundaryContract {
    [CmdletBinding()]
    param([string]$SchemaRoot = $PSScriptRoot)

    $root = [System.IO.Path]::GetFullPath($SchemaRoot)
    $registry = [ordered]@{}
    $schemas = [ordered]@{}
    $paths = [ordered]@{}
    foreach ($specification in $script:Stage1EHostSchemaSpecifications) {
        $path = Join-Path $root $specification.File
        if (-not [System.IO.File]::Exists($path)) {
            throw [System.IO.FileNotFoundException]::new(
                "Required Stage 1E host schema is missing: $path", $path)
        }
        $schema = ConvertFrom-Stage1ECanonicalJsonBytes `
            -Bytes (Read-Stage1EJsonFileBytes -LiteralPath $path)
        if (-not $schema.Contains('$schema') -or
            [string]$schema['$schema'] -cne 'stage1e-schema-subset-v1' -or
            -not $schema.Contains('$id') -or
            [string]$schema['$id'] -cne [string]$specification.Id) {
            throw [System.IO.InvalidDataException]::new(
                "Host schema identity or subset mismatch: $path")
        }
        Assert-Stage1EHostSchemaNode $schema '$'
        if ($registry.Contains([string]$specification.Id)) {
            throw [System.IO.InvalidDataException]::new(
                "Duplicate host schema identity '$($specification.Id)'.")
        }
        $registry.Add([string]$specification.Id, $schema)
        $schemas.Add([string]$specification.Role, $schema)
        $paths.Add([string]$specification.Role,
            [System.IO.Path]::GetFullPath($path))
    }
    return [ordered]@{
        interface_version = $script:Stage1EHostBoundaryContractInterface
        schema_registry = $registry
        schemas = $schemas
        schema_paths = $paths
    }
}

function Get-Stage1EHostAuthorityBoundary {
    return [ordered]@{
        qualification_decision = 'NONE'
        authorization_issue = 'NONE'
        authorization_consumption = 'NOT_OWNED'
        engineering_acceptance = 'NONE'
        bitstream_xsa_generation = 'NONE'
        artifact_collection = 'NONE'
        publication = 'NONE'
        hardware_manager = 'NONE'
        board_access = 'NONE'
    }
}

function Get-Stage1EHostRequirementsRecord {
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary]$Contract =
            (Import-Stage1EHostBoundaryContract)
    )

    $record = [ordered]@{
        schema_version = 'stage1e-runtime-host-requirements-v1'
        contract_state = 'FOUNDATION_ONLY_REVIEW_REQUIRED'
        supported_platform = 'WINDOWS'
        process_provider_interface =
            'stage1e-windows-process-control-interface-v1'
        launcher_interface =
            'stage1e-production-runtime-launcher-interface-v1'
        observer_interface =
            'stage1e-production-host-observer-interface-v1'
        containment_mode = 'JOB_OBJECT_ASSIGN_BEFORE_RESUME'
        job_kill_on_close = $true
        job_breakaway_policy = 'PROHIBITED'
        child_handle_inheritance_policy =
            'STARTUPINFOEX_EXACT_STDIO_ALLOW_LIST'
        job_topology_evidence =
            'COMPLETION_PORT_PLUS_SNAPSHOT_RECONCILIATION'
        execution_process_limit_policy =
            'SUM_EXPECTED_TOPOLOGY_MAXIMUM_COUNT'
        required_process_evidence = [object[]]@(
            'PID', 'CREATION_TIME', 'CANONICAL_IMAGE',
            'EXPECTED_IMAGE_COMPARISON', 'PARENT_RELATIONSHIP',
            'JOB_MEMBERSHIP', 'DIRECT_OBSERVATION_HANDLE',
            'TERMINAL_EXIT_STATE')
        maximum_processes = 32
        environment_name_comparison = 'ORDINAL_IGNORE_CASE'
        environment_inheritance_policy = 'EXPLICIT_ALLOW_LIST_ONLY'
        required_environment_names = [object[]]@(
            'SystemRoot', 'TEMP', 'TMP', 'STAGE1E_CACHE_ROOT',
            'STAGE1E_ENCODING', 'STAGE1E_LOCALE', 'TZ')
        prohibited_environment_names = [object[]]@(
            'PATH', 'PATHEXT', 'PSModulePath', 'TCL_LIBRARY',
            'TCLLIBPATH', 'XILINX_VIVADO')
        foundation_path_checks = [object[]]@(
            'LITERAL_ABSOLUTE_PATH', 'STRUCTURED_COMPONENT_CONTAINMENT',
            'EXISTING_REPARSE_POINT_REJECTION', 'ROLE_ROOT_SEPARATION')
        advanced_path_hardening_state =
            'DEFERRED_FUTURE_HOST_CONTRACT'
        graceful_termination_modes = [object[]]@('WINDOW_CLOSE', 'NONE')
        authority_boundary = Get-Stage1EHostAuthorityBoundary
    }
    $null = Assert-Stage1EHostRecord -Role requirements -Record $record `
        -Contract $Contract
    return $record
}

function Get-Stage1EHostSchema {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )

    if ($Contract.schemas.Contains($Role)) {
        return $Contract.schemas[$Role]
    }
    switch ($Role) {
        'process_event' {
            return $Contract.schemas.process_ledger['$defs'].process_event
        }
        'job_event' {
            return $Contract.schemas.process_ledger['$defs'].job_event
        }
        'timeout_event' {
            return $Contract.schemas.timeout_ledger['$defs'].timeout_termination_event
        }
        default {
            throw [System.ArgumentException]::new(
                "Unknown Stage 1E host schema role '$Role'.")
        }
    }
}

function Assert-Stage1EHostRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )

    $schema = Get-Stage1EHostSchema -Role $Role -Contract $Contract
    $null = Assert-Stage1EJsonSchemaValue -Value $Record -Schema $schema `
        -RootSchema $schema -SchemaRegistry $Contract.schema_registry
    if ($Role -ceq 'launcher_request') {
        $null = Assert-Stage1EHostLauncherRequestSemantics $Record $Contract
    }
    elseif ($Role -ceq 'host_result') {
        $null = Assert-Stage1EHostResultSemantics $Record
    }
    elseif ($Role -ceq 'process_ledger') {
        $null = Assert-Stage1EHostProcessLedgerSemantics $Record
    }
    return $true
}

function ConvertTo-Stage1EHostRecordBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )

    $null = Assert-Stage1EHostRecord -Role $Role -Record $Record `
        -Contract $Contract
    $schema = Get-Stage1EHostSchema -Role $Role -Contract $Contract
    return ConvertTo-Stage1ECanonicalJsonBytes -Value $Record -Schema $schema `
        -SchemaRegistry $Contract.schema_registry
}

function ConvertFrom-Stage1EHostRecordBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )

    $schema = Get-Stage1EHostSchema -Role $Role -Contract $Contract
    $record = ConvertFrom-Stage1ECanonicalJsonEnvelope -Bytes $Bytes `
        -Schema $schema -SchemaRegistry $Contract.schema_registry
    $null = Assert-Stage1EHostRecord -Role $Role -Record $record `
        -Contract $Contract
    return $record
}

function Publish-Stage1EHostRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$BoundaryPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )

    $bytes = ConvertTo-Stage1EHostRecordBytes -Role $Role -Record $Record `
        -Contract $Contract
    $verifier = {
        param([byte[]]$PublishedBytes)
        $null = ConvertFrom-Stage1EHostRecordBytes -Role $Role `
            -Bytes $PublishedBytes -Contract $Contract
        return $true
    }
    return Publish-Stage1EAtomicBytes -LiteralPath $LiteralPath -Bytes $bytes `
        -BoundaryPath $BoundaryPath -Verifier $verifier
}

function Add-Stage1EHostJournalRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$BoundaryPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )

    if ($Role -cnotin @('process_event', 'timeout_event', 'heartbeat')) {
        throw [System.ArgumentException]::new(
            "Host journal role is not appendable: $Role")
    }
    if (-not (Test-Stage1EHostPathWithinBoundary $LiteralPath $BoundaryPath)) {
        throw [System.IO.IOException]::new(
            'Host journal path is outside its declared boundary.')
    }
    $parent = [System.IO.Path]::GetDirectoryName(
        [System.IO.Path]::GetFullPath($LiteralPath))
    if (-not [System.IO.Directory]::Exists($parent)) {
        throw [System.IO.DirectoryNotFoundException]::new(
            "Host journal parent does not exist: $parent")
    }
    $bytes = ConvertTo-Stage1EHostRecordBytes -Role $Role -Record $Record `
        -Contract $Contract
    $stream = [System.IO.FileStream]::new(
        $LiteralPath, [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read,
        4096, [System.IO.FileOptions]::WriteThrough)
    try {
        if ($stream.Length -gt 0) {
            $null = $stream.Seek(-1, [System.IO.SeekOrigin]::End)
            if ($stream.ReadByte() -ne 0x0a) {
                throw [System.IO.InvalidDataException]::new(
                    'Host journal has a trailing partial record.')
            }
        }
        $null = $stream.Seek(0, [System.IO.SeekOrigin]::End)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        return [ordered]@{
            append_state = 'APPENDED'
            path = [System.IO.Path]::GetFullPath($LiteralPath)
            appended_byte_count = [int64]$bytes.Length
            total_byte_count = [int64]$stream.Length
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-Stage1EHostPathComponents {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath(
        $Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrEmpty($root)) {
        throw [System.IO.InvalidDataException]::new(
            "Host path has no structured root: $Path")
    }
    $components = [System.Collections.Generic.List[string]]::new()
    $components.Add($root.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar))
    $relative = $full.Substring($root.Length).Trim(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if ($relative.Length -gt 0) {
        foreach ($component in $relative.Split(
                [char[]]@(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar),
                [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $components.Add($component)
        }
    }
    return [object[]]$components.ToArray()
}

function Test-Stage1EHostPathEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    try {
        $leftParts = @(Get-Stage1EHostPathComponents $Left)
        $rightParts = @(Get-Stage1EHostPathComponents $Right)
    }
    catch { return $false }
    if ($leftParts.Count -ne $rightParts.Count) { return $false }
    for ($index = 0; $index -lt $leftParts.Count; $index++) {
        if (-not ([string]$leftParts[$index]).Equals(
                [string]$rightParts[$index],
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Test-Stage1EHostPathWithinBoundary {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Boundary
    )

    try {
        $candidateParts = @(Get-Stage1EHostPathComponents $Candidate)
        $boundaryParts = @(Get-Stage1EHostPathComponents $Boundary)
    }
    catch { return $false }
    if ($candidateParts.Count -lt $boundaryParts.Count) { return $false }
    for ($index = 0; $index -lt $boundaryParts.Count; $index++) {
        if (-not ([string]$candidateParts[$index]).Equals(
                [string]$boundaryParts[$index],
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Test-Stage1EHostPathsDisjoint {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )
    return (-not (Test-Stage1EHostPathWithinBoundary $Left $Right) -and
        -not (Test-Stage1EHostPathWithinBoundary $Right $Left))
}

function Join-Stage1EHostCanonicalPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Leaf
    )
    if ([System.IO.Path]::GetFileName($Leaf) -cne $Leaf -or
        $Leaf.IndexOf('/') -ge 0 -or $Leaf.IndexOf('\') -ge 0) {
        throw [System.IO.InvalidDataException]::new(
            "Derived host path leaf is not literal: $Leaf")
    }
    return ([System.IO.Path]::Combine(
            $Root.Replace('/', [System.IO.Path]::DirectorySeparatorChar),
            $Leaf)).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
}

function New-Stage1EHostLauncherProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ValidatedRequest,
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [Parameter(Mandatory = $true)][string]$ExpectedRequestIdentity,
        [Parameter(Mandatory = $true)]
        [ValidateSet('CONTROLLER_PROCEED', 'FIXED_NON_VIVADO_TEST_PROCEED')]
        [string]$LaunchGate,
        [System.Collections.IDictionary]$EnvelopeContract =
            (Import-Stage1EEnvelopeContract),
        [System.Collections.IDictionary]$HostContract =
            (Import-Stage1EHostBoundaryContract)
    )

    $null = Assert-Stage1ERequestEnvelope -Record $ValidatedRequest `
        -Contract $EnvelopeContract `
        -ExpectedRequestIdentity $ExpectedRequestIdentity
    $launch = $ValidatedRequest.launch_contract
    $evidence = $ValidatedRequest.evidence_contract
    if ([string]$evidence.request_path -cne $RequestPath -or
        [string]$ValidatedRequest.request_identity -cne
            $ExpectedRequestIdentity) {
        throw [System.IO.InvalidDataException]::new(
            'Host projection request path or expected identity differs from the validated request.')
    }
    $systemRoot = [System.Environment]::GetEnvironmentVariable(
        'SystemRoot', [System.EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrEmpty($systemRoot)) {
        throw [System.InvalidOperationException]::new(
            'The exact SystemRoot parent value is unavailable.')
    }
    $environment = [object[]]@(
        [ordered]@{ name = 'SystemRoot'; value = $systemRoot; source = 'PARENT_EXACT'; sensitive = $false },
        [ordered]@{ name = 'TEMP'; value = [string]$launch.temporary_root; source = 'REQUEST_TEMPORARY_ROOT'; sensitive = $false },
        [ordered]@{ name = 'TMP'; value = [string]$launch.temporary_root; source = 'REQUEST_TEMPORARY_ROOT'; sensitive = $false },
        [ordered]@{ name = 'STAGE1E_CACHE_ROOT'; value = [string]$launch.cache_root; source = 'REQUEST_CACHE_ROOT'; sensitive = $false },
        [ordered]@{ name = 'STAGE1E_ENCODING'; value = [string]$launch.encoding; source = 'REQUEST_ENCODING'; sensitive = $false },
        [ordered]@{ name = 'STAGE1E_LOCALE'; value = [string]$launch.locale; source = 'REQUEST_LOCALE'; sensitive = $false },
        [ordered]@{ name = 'TZ'; value = [string]$launch.time_zone; source = 'REQUEST_TIME_ZONE'; sensitive = $false }
    )
    $milliseconds = [ordered]@{}
    foreach ($binding in @(
            [object[]]@('startup', 'startup_seconds'),
            [object[]]@('child_discovery', 'child_discovery_seconds'),
            [object[]]@('heartbeat_silence', 'heartbeat_silence_seconds'),
            [object[]]@('graceful_termination', 'graceful_termination_seconds'),
            [object[]]@('total_lifetime', 'total_lifetime_seconds'))) {
        $milliseconds.Add([string]$binding[0],
            ([int64]$ValidatedRequest.timeout_contract[$binding[1]] * 1000))
    }
    $componentRoot = [string]$evidence.component_result_root
    $record = [ordered]@{
        schema_version = 'stage1e-runtime-host-launcher-request-v1'
        projection_state = 'IMMUTABLE_VALIDATED_REQUEST_PROJECTION'
        request_path = [string]$RequestPath
        expected_request_identity = [string]$ExpectedRequestIdentity
        request_identity = [string]$ValidatedRequest.request_identity
        execution_id = [string]$ValidatedRequest.execution_id
        attempt_id = [string]$ValidatedRequest.attempt_id
        source_identity = [string]$ValidatedRequest.source_identity
        runtime_backend_identity =
            [string]$ValidatedRequest.runtime_backend_identity
        environment_identity = [string]$ValidatedRequest.environment_identity
        workspace_identity = [string]$ValidatedRequest.workspace_identity
        dependency_closure_identity =
            [string]$ValidatedRequest.dependency_closure_identity
        launch_gate = $LaunchGate
        executable_path = [string]$launch.vivado_executable_path
        expected_image_path = [string]$launch.vivado_executable_path
        argument_vector = [object[]]@($launch.argument_vector)
        cwd = [string]$launch.cwd
        workspace_root = [string]$launch.workspace_root
        xil_root = [string]$launch.xil_root
        source_root = [string]$launch.source_root
        request_root = [string]$launch.request_root
        evidence_root = [string]$launch.evidence_root
        log_root = [string]$launch.log_root
        journal_root = [string]$launch.journal_root
        temporary_root = [string]$launch.temporary_root
        cache_root = [string]$launch.cache_root
        preflight_result_path = [string]$evidence.host_observation_result_path
        process_ledger_path = [string]$evidence.launch_result_path
        process_event_journal_path = Join-Stage1EHostCanonicalPath `
            $launch.journal_root 'stage1e-host-process-events.ndjson'
        timeout_termination_ledger_path = Join-Stage1EHostCanonicalPath `
            $componentRoot 'stage1e-host-timeout-termination-ledger.json'
        timeout_event_journal_path = Join-Stage1EHostCanonicalPath `
            $launch.journal_root `
            'stage1e-host-timeout-termination-events.ndjson'
        heartbeat_path = Join-Stage1EHostCanonicalPath $launch.journal_root `
            'stage1e-host-heartbeat.ndjson'
        stdout_path = Join-Stage1EHostCanonicalPath $launch.log_root `
            'stage1e-host-stdout.log'
        stderr_path = Join-Stage1EHostCanonicalPath $launch.log_root `
            'stage1e-host-stderr.log'
        host_result_path = [string]$evidence.host_result_path
        expected_vivado_result_path = [string]$evidence.vivado_result_path
        environment = $environment
        expected_topology = [object[]]@(
            [ordered]@{
                role = 'ROOT_PROCESS'
                image_path = [string]$launch.vivado_executable_path
                parent_role = 'HOST_LAUNCHER'
                minimum_count = 1
                maximum_count = 1
            })
        startup_timeout_ms = [int64]$milliseconds.startup
        child_discovery_timeout_ms = [int64]$milliseconds.child_discovery
        heartbeat_silence_timeout_ms =
            [int64]$milliseconds.heartbeat_silence
        graceful_termination_timeout_ms =
            [int64]$milliseconds.graceful_termination
        terminal_observation_timeout_ms =
            [int64]$milliseconds.graceful_termination
        total_lifetime_timeout_ms = [int64]$milliseconds.total_lifetime
        observation_interval_ms = 50
        heartbeat_required = $true
        graceful_termination_mode = 'WINDOW_CLOSE'
        no_fallback = $true
        authority_boundary = Get-Stage1EHostAuthorityBoundary
    }
    $null = Assert-Stage1EHostRecord -Role launcher_request -Record $record `
        -Contract $HostContract
    return $record
}

function Assert-Stage1EHostLauncherRequestSemantics {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Record,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Contract
    )

    if ([string]$Record.request_identity -cne
        [string]$Record.expected_request_identity) {
        throw [System.IO.InvalidDataException]::new(
            'Host request and expected request identities differ.')
    }
    if (-not (Test-Stage1EHostPathEqual $Record.cwd `
            $Record.workspace_root) -or
        -not (Test-Stage1EHostPathEqual $Record.xil_root `
            (Join-Stage1EHostCanonicalPath $Record.workspace_root '.Xil'))) {
        throw [System.IO.InvalidDataException]::new(
            'Host cwd, workspace, and .Xil bindings are inconsistent.')
    }
    foreach ($pair in @(
            [object[]]@('source_root', 'workspace_root'),
            [object[]]@('source_root', 'evidence_root'),
            [object[]]@('workspace_root', 'evidence_root'))) {
        if (-not (Test-Stage1EHostPathsDisjoint `
                $Record[$pair[0]] $Record[$pair[1]])) {
            throw [System.IO.InvalidDataException]::new(
                "Host roots overlap: $($pair[0]) and $($pair[1]).")
        }
    }
    foreach ($binding in @(
            [object[]]@('request_path', 'request_root'),
            [object[]]@('log_root', 'evidence_root'),
            [object[]]@('journal_root', 'evidence_root'),
            [object[]]@('temporary_root', 'workspace_root'),
            [object[]]@('cache_root', 'workspace_root'),
            [object[]]@('preflight_result_path', 'evidence_root'),
            [object[]]@('process_ledger_path', 'evidence_root'),
            [object[]]@('process_event_journal_path', 'journal_root'),
            [object[]]@('timeout_termination_ledger_path', 'evidence_root'),
            [object[]]@('timeout_event_journal_path', 'journal_root'),
            [object[]]@('heartbeat_path', 'journal_root'),
            [object[]]@('stdout_path', 'log_root'),
            [object[]]@('stderr_path', 'log_root'),
            [object[]]@('host_result_path', 'evidence_root'),
            [object[]]@('expected_vivado_result_path', 'evidence_root'))) {
        if (-not (Test-Stage1EHostPathWithinBoundary `
                $Record[$binding[0]] $Record[$binding[1]])) {
            throw [System.IO.InvalidDataException]::new(
                "Host path '$($binding[0])' is outside '$($binding[1])'.")
        }
        if (Test-Stage1EHostPathWithinBoundary `
                $Record[$binding[0]] $Record.source_root) {
            throw [System.IO.InvalidDataException]::new(
                "Host runtime output is inside the source root: $($binding[0])")
        }
    }
    $outputNames = @(
        'preflight_result_path', 'process_ledger_path',
        'process_event_journal_path', 'timeout_termination_ledger_path',
        'timeout_event_journal_path', 'heartbeat_path', 'stdout_path',
        'stderr_path', 'host_result_path', 'expected_vivado_result_path')
    for ($left = 0; $left -lt $outputNames.Count; $left++) {
        for ($right = $left + 1; $right -lt $outputNames.Count; $right++) {
            if (Test-Stage1EHostPathEqual $Record[$outputNames[$left]] `
                    $Record[$outputNames[$right]]) {
                throw [System.IO.InvalidDataException]::new(
                    'Host evidence roles reuse one path.')
            }
        }
    }
    $requirements = Get-Stage1EHostRequirementsRecord -Contract $Contract
    $environmentNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $allowedEnvironmentNames =
        [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
    foreach ($requiredName in $requirements.required_environment_names) {
        $null = $allowedEnvironmentNames.Add([string]$requiredName)
    }
    foreach ($entry in $Record.environment) {
        $name = [string]$entry.name
        if ($name.IndexOf('=') -ge 0 -or -not $environmentNames.Add($name)) {
            throw [System.IO.InvalidDataException]::new(
                "Host environment name is duplicated or ambiguous: $name")
        }
        if (-not $allowedEnvironmentNames.Contains($name)) {
            throw [System.IO.InvalidDataException]::new(
                "Host environment name is not in the exact allow-list: $name")
        }
        if (@($requirements.prohibited_environment_names) -icontains $name) {
            throw [System.IO.InvalidDataException]::new(
                "Host environment contains prohibited name '$name'.")
        }
        if ([bool]$entry.sensitive) {
            throw [System.IO.InvalidDataException]::new(
                "Foundation environment entry cannot be sensitive: $name")
        }
        switch -CaseSensitive ($name) {
            'SystemRoot' {
                $valid = ([string]$entry.source -ceq 'PARENT_EXACT' -and
                    -not [string]::IsNullOrEmpty([string]$entry.value))
            }
            { $_ -ceq 'TEMP' -or $_ -ceq 'TMP' } {
                $valid = ([string]$entry.source -ceq
                        'REQUEST_TEMPORARY_ROOT' -and
                    [string]$entry.value -ceq [string]$Record.temporary_root)
            }
            'STAGE1E_CACHE_ROOT' {
                $valid = ([string]$entry.source -ceq 'REQUEST_CACHE_ROOT' -and
                    [string]$entry.value -ceq [string]$Record.cache_root)
            }
            'STAGE1E_ENCODING' {
                $valid = ([string]$entry.source -ceq 'REQUEST_ENCODING' -and
                    [string]$entry.value -ceq 'UTF-8')
            }
            'STAGE1E_LOCALE' {
                $valid = ([string]$entry.source -ceq 'REQUEST_LOCALE' -and
                    [string]$entry.value -ceq 'INVARIANT')
            }
            'TZ' {
                $valid = ([string]$entry.source -ceq 'REQUEST_TIME_ZONE' -and
                    [string]$entry.value -ceq 'UTC')
            }
            default { $valid = $false }
        }
        if (-not $valid) {
            throw [System.IO.InvalidDataException]::new(
                "Host environment value/source binding differs: $name")
        }
    }
    if ($environmentNames.Count -ne $allowedEnvironmentNames.Count) {
        throw [System.IO.InvalidDataException]::new(
            'Host environment does not equal the exact allow-list.')
    }
    foreach ($name in $requirements.required_environment_names) {
        if (-not $environmentNames.Contains([string]$name)) {
            throw [System.IO.InvalidDataException]::new(
                "Host environment lacks required name '$name'.")
        }
    }
    $rootTopology = @($Record.expected_topology |
        Where-Object { [string]$_.role -ceq 'ROOT_PROCESS' })
    if ($rootTopology.Count -ne 1 -or
        [string]$rootTopology[0].parent_role -cne 'HOST_LAUNCHER' -or
        [int64]$rootTopology[0].minimum_count -ne 1 -or
        [int64]$rootTopology[0].maximum_count -ne 1 -or
        -not (Test-Stage1EHostPathEqual $rootTopology[0].image_path `
            $Record.expected_image_path)) {
        throw [System.IO.InvalidDataException]::new(
            'Host topology does not define exactly one expected root process.')
    }
    foreach ($topology in $Record.expected_topology) {
        if ([int64]$topology.minimum_count -gt
            [int64]$topology.maximum_count) {
            throw [System.IO.InvalidDataException]::new(
                'Host topology minimum exceeds its maximum.')
        }
    }
    $topologySet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $maximumProcessCount = [int64]0
    foreach ($topology in $Record.expected_topology) {
        $topologyKey = "$($topology.role)|$($topology.image_path)|$(
            $topology.parent_role)"
        if (-not $topologySet.Add($topologyKey)) {
            throw [System.IO.InvalidDataException]::new(
                'Host topology contains an ambiguous duplicate requirement.')
        }
        $maximumProcessCount += [int64]$topology.maximum_count
    }
    if ($maximumProcessCount -gt [int64]$requirements.maximum_processes) {
        throw [System.IO.InvalidDataException]::new(
            'Host topology exceeds the reviewed process-count limit.')
    }
    foreach ($timeoutName in @(
            'startup_timeout_ms', 'child_discovery_timeout_ms',
            'heartbeat_silence_timeout_ms',
            'graceful_termination_timeout_ms',
            'terminal_observation_timeout_ms')) {
        if ([int64]$Record[$timeoutName] -gt
            [int64]$Record.total_lifetime_timeout_ms) {
            throw [System.IO.InvalidDataException]::new(
                "Host timeout '$timeoutName' exceeds total lifetime.")
        }
    }
    return $true
}

function Assert-Stage1EHostProcessLedgerSemantics {
    param([System.Collections.IDictionary]$Record)

    if ([int64]$Record.resume_count -gt
        [int64]$Record.creation_attempt_count) {
        throw [System.IO.InvalidDataException]::new(
            'Process ledger resume count exceeds its creation-attempt count.')
    }
    for ($index = 0; $index -lt $Record.events.Count; $index++) {
        if ([int64]$Record.events[$index].ordinal -ne ($index + 1)) {
            throw [System.IO.InvalidDataException]::new(
                'Process ledger event ordinals are not append-only contiguous.')
        }
    }
    for ($index = 0; $index -lt $Record.job_events.Count; $index++) {
        if ([int64]$Record.job_events[$index].sequence -ne ($index + 1)) {
            throw [System.IO.InvalidDataException]::new(
                'Job event sequences are not append-only contiguous.')
        }
    }
    if ([string]$Record.terminal_tree_state -ceq 'TERMINAL' -and
        $Record.terminal_snapshot_process_ids.Count -ne 0) {
        throw [System.IO.InvalidDataException]::new(
            'A terminal process ledger retains current Job members.')
    }
    if ([int64]$Record.heartbeat_final_cursor.complete_offset -gt
        [int64]$Record.heartbeat_final_cursor.observed_byte_count) {
        throw [System.IO.InvalidDataException]::new(
            'Heartbeat final cursor exceeds the observed byte count.')
    }
    if ([bool]$Record.heartbeat_final_cursor.trailing_partial -and
        [string]$Record.heartbeat_final_cursor.terminal_read_state -cne
            'PARTIAL') {
        throw [System.IO.InvalidDataException]::new(
            'A terminal heartbeat partial is not explicitly preserved.')
    }
    return $true
}

function Assert-Stage1EHostResultSemantics {
    param([System.Collections.IDictionary]$Record)

    $hasFailure = $Record.first_failure -is
        [System.Collections.IDictionary]
    if ([string]$Record.launcher_state -ceq 'PROCESS_EXITED') {
        if ([string]$Record.terminal_status -cne 'COMPLETED' -or
            $hasFailure -or [string]$Record.first_failure -cne 'NONE' -or
            [string]$Record.process_effect -cne 'EXITED_OBSERVED' -or
            [int64]$Record.creation_attempt_count -ne 1 -or
            [int64]$Record.resume_count -ne 1 -or
            $Record.exit_code -is [string]) {
            throw [System.IO.InvalidDataException]::new(
                'PROCESS_EXITED host result has inconsistent terminal fields.')
        }
    }
    else {
        if ([string]$Record.terminal_status -ceq 'COMPLETED' -or
            -not $hasFailure) {
            throw [System.IO.InvalidDataException]::new(
                'A non-exited host result must preserve a blocking failure.')
        }
    }
    if ([string]$Record.launcher_state -ceq 'LAUNCH_NOT_ATTEMPTED' -and
        ([int64]$Record.creation_attempt_count -ne 0 -or
            [int64]$Record.resume_count -ne 0 -or
            [string]$Record.process_effect -cne 'NOT_STARTED' -or
            [string]$Record.authorization_effect -cne 'NOT_TOUCHED')) {
        throw [System.IO.InvalidDataException]::new(
            'LAUNCH_NOT_ATTEMPTED host result has process side effects.')
    }
    if ([int64]$Record.resume_count -gt
        [int64]$Record.creation_attempt_count) {
        throw [System.IO.InvalidDataException]::new(
            'Host result resumed more processes than it created.')
    }
    if ([int64]$Record.resume_count -eq 0 -and
        [string]$Record.authorization_effect -cne 'NOT_TOUCHED') {
        throw [System.IO.InvalidDataException]::new(
            'An unresumed host process changed authorization state.')
    }
    if ($hasFailure) {
        $firstOrdinal = [int64]$Record.first_failure.first_failure_ordinal
        foreach ($secondary in $Record.secondary_failures) {
            if ([int64]$secondary.first_failure_ordinal -le $firstOrdinal) {
                throw [System.IO.InvalidDataException]::new(
                    'A secondary failure precedes or replaces the first failure.')
            }
        }
    }
    return $true
}

Export-ModuleMember -Function @(
    'Get-Stage1EHostBoundaryContractInterfaceVersion'
    'Import-Stage1EHostBoundaryContract'
    'Get-Stage1EHostAuthorityBoundary'
    'Get-Stage1EHostRequirementsRecord'
    'Assert-Stage1EHostRecord'
    'ConvertTo-Stage1EHostRecordBytes'
    'ConvertFrom-Stage1EHostRecordBytes'
    'Publish-Stage1EHostRecord'
    'Add-Stage1EHostJournalRecord'
    'Test-Stage1EHostPathEqual'
    'Test-Stage1EHostPathWithinBoundary'
    'Test-Stage1EHostPathsDisjoint'
    'New-Stage1EHostLauncherProjection'
)
