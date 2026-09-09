Set-StrictMode -Version Latest

$script:Stage1EProductionRuntimeAssemblyAdapterInterface =
    'stage1e-production-runtime-assembly-adapter-interface-v1'
$script:Stage1EActivationModulePath = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../lib/stage1e_runtime_activation_contract_v1.psm1'))
$script:Stage1EActivationProvider = 'ACTIVATION_CONTRACT_MODULE'
$script:Stage1EActivationProviderInterface =
    'stage1e-runtime-activation-contract-interface-v1'
Microsoft.PowerShell.Core\Import-Module -Name $script:Stage1EActivationModulePath `
    -ErrorAction Stop

function Get-Stage1EProductionRuntimeAssemblyAdapterInterfaceVersion {
    return $script:Stage1EProductionRuntimeAssemblyAdapterInterface
}

function ConvertTo-Stage1EAssemblyAdapterCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).Replace(
        [System.IO.Path]::DirectorySeparatorChar, '/')
}

function New-Stage1EConnectedAssemblyRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ValidatedRequest,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$EntryPointPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ActivationContract
    )
    if (-not (Test-Path -LiteralPath $script:Stage1EActivationModulePath) -or
        [string](Get-Stage1ERuntimeActivationContractInterfaceVersion) -cne
            $script:Stage1EActivationProviderInterface) {
        throw "Assembly adapter requires $script:Stage1EActivationProvider."
    }
    $null = Assert-Stage1ERuntimeActivationContract $ActivationContract
    $root = ConvertTo-Stage1EAssemblyAdapterCanonicalPath $RepositoryRoot
    $entry = ConvertTo-Stage1EAssemblyAdapterCanonicalPath $EntryPointPath
    $selected = ConvertTo-Stage1EAssemblyAdapterCanonicalPath (
        Join-Path $RepositoryRoot `
            ([string]$ActivationContract.selected_entry_root.source_path))
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $entry, $selected)) {
        throw 'Assembly adapter rejected an alternate production entry root.'
    }
    $sealedRoot = [string]$ValidatedRequest.launch_contract.source_root
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
            $root, $sealedRoot)) {
        throw 'Assembly adapter source root differs from the sealed request.'
    }
    $evidenceRoot = [string]$ValidatedRequest.launch_contract.evidence_root
    if ([string]::IsNullOrWhiteSpace($evidenceRoot)) {
        throw 'Assembly adapter received an empty evidence root.'
    }
    return [ordered]@{
        schema_version = 'stage1e-connected-runtime-assembly-request-v1'
        request_identity = [string]$ValidatedRequest.request_identity
        execution_id = [string]$ValidatedRequest.execution_id
        attempt_id = [string]$ValidatedRequest.attempt_id
        source_identity = [string]$ValidatedRequest.source_identity
        workspace_identity = [string]$ValidatedRequest.workspace_identity
        runtime_backend_reference =
            [string]$ValidatedRequest.runtime_backend_identity
        runtime_backend_reference_state = 'UNVERIFIED_REQUEST_REFERENCE'
        repository_root = $root
        entry_point_path = $entry
        evidence_root = $evidenceRoot
        authorization_effect = 'NOT_TOUCHED'
        process_effect = 'NOT_STARTED'
        candidate_effect = 'NOT_CREATED'
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EProductionRuntimeAssemblyAdapterInterfaceVersion'
    'New-Stage1EConnectedAssemblyRequest'
)
