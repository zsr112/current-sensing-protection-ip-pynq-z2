Set-StrictMode -Version Latest

$contractModule = Join-Path $PSScriptRoot 'stage1e_host_boundary_contract_v1.psm1'
Import-Module -Name $contractModule -Force -ErrorAction Stop

$script:Stage1EWindowsProcessControlInterface =
    'stage1e-windows-process-control-interface-v1'
$script:Stage1EWindowsProcessControlSource = Join-Path $PSScriptRoot `
    'stage1e_windows_process_control_v1.cs'

function Get-Stage1EWindowsProcessControlInterfaceVersion {
    return $script:Stage1EWindowsProcessControlInterface
}

function Import-Stage1EWindowsProcessControlProvider {
    [CmdletBinding()]
    param()

    if (-not [System.IO.File]::Exists(
            $script:Stage1EWindowsProcessControlSource)) {
        throw [System.IO.FileNotFoundException]::new(
            'The reviewed Stage 1E Win32 process-control source is missing.',
            $script:Stage1EWindowsProcessControlSource)
    }
    $providerType = 'Stage1E.Runtime.Host.V1.ControlledProcess' -as [type]
    if ($null -eq $providerType) {
        Add-Type -Path $script:Stage1EWindowsProcessControlSource `
            -ErrorAction Stop
        $providerType = 'Stage1E.Runtime.Host.V1.ControlledProcess' -as [type]
    }
    if ($null -eq $providerType -or
        [string]$providerType::InterfaceVersion -cne
            $script:Stage1EWindowsProcessControlInterface) {
        throw [System.InvalidOperationException]::new(
            'The loaded Win32 process-control provider interface differs.')
    }
    return [ordered]@{
        interface_version = $script:Stage1EWindowsProcessControlInterface
        source_path = [System.IO.Path]::GetFullPath(
            $script:Stage1EWindowsProcessControlSource)
        provider_type = $providerType.FullName
    }
}

function ConvertTo-Stage1EWindowsNativePath {
    param([Parameter(Mandatory = $true)][string]$CanonicalPath)
    return [System.IO.Path]::GetFullPath($CanonicalPath.Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar))
}

function New-Stage1EWindowsControlledProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LauncherRequest,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$HostContract
    )

    if ([System.Environment]::OSVersion.Platform -ne
        [System.PlatformID]::Win32NT) {
        throw [System.PlatformNotSupportedException]::new(
            'Stage 1E process control v1 supports Windows only.')
    }
    $null = Assert-Stage1EHostRecord -Role launcher_request `
        -Record $LauncherRequest -Contract $HostContract
    $null = Import-Stage1EWindowsProcessControlProvider
    $names = [string[]]@($LauncherRequest.environment |
        ForEach-Object { [string]$_.name })
    $values = [string[]]@($LauncherRequest.environment |
        ForEach-Object { [string]$_.value })
    $arguments = [string[]]@($LauncherRequest.argument_vector |
        ForEach-Object { [string]$_ })
    $maximumProcesses = [int64]0
    foreach ($topologyRequirement in $LauncherRequest.expected_topology) {
        $maximumProcesses += [int64]$topologyRequirement.maximum_count
    }
    if ($maximumProcesses -lt 1 -or $maximumProcesses -gt 32) {
        throw [System.InvalidOperationException]::new(
            'The exact expected-topology maximum sum is outside the HOST bound.')
    }
    $request = [Stage1E.Runtime.Host.V1.ProcessLaunchRequest]::new(
        (ConvertTo-Stage1EWindowsNativePath $LauncherRequest.executable_path),
        (ConvertTo-Stage1EWindowsNativePath `
            $LauncherRequest.expected_image_path),
        $arguments,
        (ConvertTo-Stage1EWindowsNativePath $LauncherRequest.cwd),
        $names,
        $values,
        (ConvertTo-Stage1EWindowsNativePath $LauncherRequest.stdout_path),
        (ConvertTo-Stage1EWindowsNativePath $LauncherRequest.stderr_path),
        ([int]$maximumProcesses))
    return [Stage1E.Runtime.Host.V1.ControlledProcess]::CreateContainedSuspended(
        $request)
}

function Resume-Stage1EWindowsControlledProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    return $Process.ResumeOnce()
}

function Get-Stage1EWindowsProcessObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    return [object[]]@($Process.Observe())
}

function Get-Stage1EWindowsJobEventObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    return [object[]]@($Process.GetJobEvents())
}

function Get-Stage1EWindowsCurrentJobProcessIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    return [uint32[]]@($Process.GetCurrentJobProcessIds())
}

function Wait-Stage1EWindowsRootProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds
    )
    return $Process.WaitForRootExit($TimeoutMilliseconds)
}

function Wait-Stage1EWindowsJobEmpty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds,
        [Parameter(Mandatory = $true)][int]$ObservationIntervalMilliseconds
    )
    return $Process.WaitForJobEmpty(
        $TimeoutMilliseconds, $ObservationIntervalMilliseconds)
}

function Test-Stage1EWindowsJobEmpty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    return $Process.IsJobEmpty()
}

function Request-Stage1EWindowsGracefulTermination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    return $Process.RequestWindowClose()
}

function Stop-Stage1EWindowsContainedProcessTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process,
        [uint32]$ExitCode = 3758096386
    )
    $Process.TerminateContainedTree($ExitCode)
}

function Get-Stage1EWindowsRootExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    [uint32]$exitCode = 0
    $available = $Process.TryGetRootExitCode([ref]$exitCode)
    return [ordered]@{
        available = [bool]$available
        exit_code = if ($available) { [int64]$exitCode } else { 'STILL_ACTIVE' }
    }
}

function Complete-Stage1EWindowsOutputCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds
    )
    return $Process.CompleteCapture($TimeoutMilliseconds)
}

function Close-Stage1EWindowsControlledProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process
    )
    $Process.Dispose()
}

Export-ModuleMember -Function @(
    'Get-Stage1EWindowsProcessControlInterfaceVersion'
    'Import-Stage1EWindowsProcessControlProvider'
    'New-Stage1EWindowsControlledProcess'
    'Resume-Stage1EWindowsControlledProcess'
    'Get-Stage1EWindowsProcessObservation'
    'Get-Stage1EWindowsJobEventObservation'
    'Get-Stage1EWindowsCurrentJobProcessIds'
    'Wait-Stage1EWindowsRootProcess'
    'Wait-Stage1EWindowsJobEmpty'
    'Test-Stage1EWindowsJobEmpty'
    'Request-Stage1EWindowsGracefulTermination'
    'Stop-Stage1EWindowsContainedProcessTree'
    'Get-Stage1EWindowsRootExitCode'
    'Complete-Stage1EWindowsOutputCapture'
    'Close-Stage1EWindowsControlledProcess'
)
