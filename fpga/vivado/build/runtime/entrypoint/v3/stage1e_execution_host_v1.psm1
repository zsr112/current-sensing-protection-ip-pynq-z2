Set-StrictMode -Version Latest

$script:Stage1EExecutionHostInterface =
    'stage1e-execution-host-supervision-interface-v1'
$script:Stage1EUtf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Stage1EResidualDrainGraceMilliseconds = 5000

function Get-Stage1EExecutionHostInterfaceVersion {
    return $script:Stage1EExecutionHostInterface
}

function New-Stage1EExecutionFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [byte[]]$Bytes = [byte[]]@()
    )

    $parent = [System.IO.Path]::GetDirectoryName($LiteralPath)
    if ([string]::IsNullOrEmpty($parent) -or
        -not [System.IO.Directory]::Exists($parent)) {
        throw "Controlled-file parent does not exist: $LiteralPath"
    }
    $stream = [System.IO.File]::Open($LiteralPath,
        [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    try {
        if ($Bytes.Length -gt 0) { $stream.Write($Bytes, 0, $Bytes.Length) }
    }
    finally {
        $stream.Dispose()
    }
}

function Write-Stage1EExecutionJournal {
    param(
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Detail = 'NONE'
    )

    $safeEvent = ConvertTo-Stage1EExecutionTsvField $Event
    $safeDetail = ConvertTo-Stage1EExecutionTsvField $Detail
    $line = ("{0}`t{1}`t{2}`n" -f
        [DateTime]::UtcNow.ToString('o'), $safeEvent, $safeDetail)
    $stream = [System.IO.File]::Open($JournalPath,
        [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read)
    try {
        $bytes = $script:Stage1EUtf8NoBom.GetBytes($line)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $stream.Dispose()
    }
}

function ConvertTo-Stage1EExecutionTsvField {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    return $Value.Replace('\', '\\').Replace("`t", '\t').
        Replace("`r", '\r').Replace("`n", '\n')
}

function ConvertTo-Stage1EExecutionQuotedArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }
        if ($character -eq '"') {
            $null = $builder.Append(('\' * (($backslashCount * 2) + 1)))
            $null = $builder.Append('"')
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            $null = $builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        $null = $builder.Append($character)
    }
    if ($backslashCount -gt 0) {
        $null = $builder.Append(('\' * ($backslashCount * 2)))
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-Stage1EExecutionBatchArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.IndexOf([char]0) -ge 0 -or $Value.IndexOf("`r") -ge 0 -or
        $Value.IndexOf("`n") -ge 0 -or $Value.IndexOf('"') -ge 0 -or
        $Value.IndexOf('%') -ge 0 -or $Value.IndexOf('!') -ge 0) {
        throw 'Batch invocation arguments contain a command-interpreter expansion character.'
    }
    return '"' + $Value + '"'
}

function Set-Stage1EExecutionProcessTarget {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )

    $extension = [System.IO.Path]::GetExtension($Executable).ToLowerInvariant()
    switch ($extension) {
        '.exe' {
            $StartInfo.FileName = $Executable
            $StartInfo.Arguments = (@($ArgumentList | ForEach-Object {
                        ConvertTo-Stage1EExecutionQuotedArgument ([string]$_)
                    }) -join ' ')
            return 'DIRECT_EXECUTABLE'
        }
        '.bat' {
            $commandInterpreter = [Environment]::GetEnvironmentVariable('ComSpec')
            if ([string]::IsNullOrWhiteSpace($commandInterpreter) -or
                -not [System.IO.File]::Exists($commandInterpreter) -or
                [System.IO.Path]::GetFileName($commandInterpreter) -cne 'cmd.exe') {
                throw 'The current Windows command interpreter is unavailable.'
            }
            $commandParts = [System.Collections.Generic.List[string]]::new()
            $commandParts.Add((ConvertTo-Stage1EExecutionBatchArgument $Executable))
            foreach ($argument in $ArgumentList) {
                $commandParts.Add((ConvertTo-Stage1EExecutionBatchArgument ([string]$argument)))
            }
            $StartInfo.FileName = $commandInterpreter
            $StartInfo.Arguments = '/d /s /c "' + ($commandParts -join ' ') + '"'
            return 'WINDOWS_COMMAND_INTERPRETER'
        }
        default {
            throw 'The supervised executable must have the exact .exe or .bat extension.'
        }
    }
}

function Initialize-Stage1EExecutionNativeProcessQuery {
    if ($null -ne ('Stage1EExecutionNativeProcess' -as [type])) {
        return
    }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Stage1EExecutionNativeProcess
{
    [StructLayout(LayoutKind.Sequential)]
    public struct ProcessBasicInformation
    {
        public IntPtr Reserved1;
        public IntPtr PebBaseAddress;
        public IntPtr Reserved2_0;
        public IntPtr Reserved2_1;
        public IntPtr UniqueProcessId;
        public IntPtr InheritedFromUniqueProcessId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(
        uint desiredAccess, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);

    [DllImport("ntdll.dll")]
    public static extern int NtQueryInformationProcess(
        IntPtr processHandle,
        int processInformationClass,
        out ProcessBasicInformation processInformation,
        int processInformationLength,
        out int returnLength);
}
'@ -ErrorAction Stop
}

function Get-Stage1EExecutionParentProcessId {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    Initialize-Stage1EExecutionNativeProcessQuery
    $handle = [Stage1EExecutionNativeProcess]::OpenProcess(
        [uint32]0x1000, $false, [uint32]$ProcessId)
    if ($handle -eq [IntPtr]::Zero) { return $null }
    try {
        $information = New-Object Stage1EExecutionNativeProcess+ProcessBasicInformation
        $returnLength = 0
        $status = [Stage1EExecutionNativeProcess]::NtQueryInformationProcess(
            $handle, 0, [ref]$information,
            [Runtime.InteropServices.Marshal]::SizeOf($information),
            [ref]$returnLength)
        if ($status -ne 0) { return $null }
        return [int64]$information.InheritedFromUniqueProcessId.ToInt64()
    }
    finally {
        $null = [Stage1EExecutionNativeProcess]::CloseHandle($handle)
    }
}

function Get-Stage1EExecutionDescendantProcessIds {
    param([Parameter(Mandatory = $true)][int]$RootProcessId)

    $processRows = [System.Collections.Generic.List[object]]::new()
    foreach ($process in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            $parentProcessId = Get-Stage1EExecutionParentProcessId -ProcessId $process.Id
            if ($null -ne $parentProcessId) {
                $processRows.Add([pscustomobject]@{
                    ProcessId = [int]$process.Id
                    ParentProcessId = [int64]$parentProcessId
                })
            }
        }
        catch [System.ArgumentException] {
            continue
        }
        finally {
            $process.Dispose()
        }
    }
    $known = [System.Collections.Generic.HashSet[int]]::new()
    $null = $known.Add($RootProcessId)
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($row in $processRows) {
            if ($known.Contains($row.ParentProcessId) -and
                $known.Add($row.ProcessId)) {
                $changed = $true
            }
        }
    }
    return [int[]]@($known | Where-Object { $_ -ne $RootProcessId } |
        Sort-Object)
}

function Stop-Stage1EExecutionProcessTree {
    param([Parameter(Mandatory = $true)][int]$RootProcessId)

    $ids = [System.Collections.Generic.HashSet[int]]::new()
    $null = $ids.Add($RootProcessId)
    for ($iteration = 0; $iteration -lt 3; $iteration++) {
        try {
            foreach ($childId in Get-Stage1EExecutionDescendantProcessIds $RootProcessId) {
                $null = $ids.Add($childId)
            }
        }
        catch {
            break
        }
        Start-Sleep -Milliseconds 50
    }
    foreach ($processId in @($ids | Sort-Object -Descending)) {
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
        }
        catch [System.ArgumentException] {
            continue
        }
        catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            continue
        }
    }
}

function Write-Stage1EExecutionCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Truncate,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $bytes = $script:Stage1EUtf8NoBom.GetBytes($Text)
        if ($bytes.Length -gt 0) { $stream.Write($bytes, 0, $bytes.Length) }
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-Stage1EExecutionProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath,
        [Parameter(Mandatory = $true)][string]$JournalPath,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    if ($TimeoutSeconds -lt 1) { throw 'TimeoutSeconds must be positive.' }
    foreach ($path in @($StdoutPath, $StderrPath)) {
        if ([System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path)) {
            throw "Controlled capture path already exists: $path"
        }
        New-Stage1EExecutionFile -LiteralPath $path
    }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $invocationKind = Set-Stage1EExecutionProcessTarget -StartInfo $startInfo `
        -Executable $Executable -ArgumentList $ArgumentList
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = $null
    $stdoutTask = $null
    $stderrTask = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $observedChildren = [System.Collections.Generic.HashSet[int]]::new()
    $timedOut = $false
    $interrupted = $false
    try {
        Write-Stage1EExecutionJournal $JournalPath 'PROCESS_STARTING' (
            "$invocationKind $Executable")
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) { throw 'The controlled process did not start.' }
        $rootProcessId = [int]$process.Id
        Write-Stage1EExecutionJournal $JournalPath 'PROCESS_STARTED' $rootProcessId
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        while (-not $process.HasExited) {
            try {
                foreach ($childId in Get-Stage1EExecutionDescendantProcessIds $rootProcessId) {
                    if ($observedChildren.Add($childId)) {
                        Write-Stage1EExecutionJournal $JournalPath 'DESCENDANT_OBSERVED' $childId
                    }
                }
            }
            catch {
                Write-Stage1EExecutionJournal $JournalPath 'DESCENDANT_OBSERVATION_FAILED' $_.Exception.Message
                throw 'Unable to observe the controlled process tree.'
            }
            if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                Write-Stage1EExecutionJournal $JournalPath 'TIMEOUT_DETECTED' $TimeoutSeconds
                Stop-Stage1EExecutionProcessTree $rootProcessId
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if ($null -ne $process -and -not $process.HasExited) {
            $null = $process.WaitForExit(5000)
        }
        $residualChildren = @()
        $drainRequired = $false
        $drainDeadline = [DateTime]::UtcNow.AddMilliseconds(
            $script:Stage1EResidualDrainGraceMilliseconds)
        while ($true) {
            try {
                $residualChildren = @(
                    Get-Stage1EExecutionDescendantProcessIds $rootProcessId)
            }
            catch {
                Write-Stage1EExecutionJournal $JournalPath `
                    'RESIDUAL_OBSERVATION_FAILED' $_.Exception.Message
                throw 'Unable to verify residual descendant processes.'
            }
            if ($residualChildren.Count -eq 0) {
                if ($drainRequired) {
                    Write-Stage1EExecutionJournal $JournalPath `
                        'DESCENDANT_DRAIN_COMPLETED' `
                        $script:Stage1EResidualDrainGraceMilliseconds
                }
                break
            }
            foreach ($childId in $residualChildren) {
                if ($observedChildren.Add($childId)) {
                    Write-Stage1EExecutionJournal $JournalPath `
                        'DESCENDANT_DRAIN_OBSERVED' $childId
                }
            }
            if (-not $drainRequired) {
                $drainRequired = $true
                Write-Stage1EExecutionJournal $JournalPath `
                    'DESCENDANT_DRAIN_STARTED' `
                    $script:Stage1EResidualDrainGraceMilliseconds
            }
            if ([DateTime]::UtcNow -ge $drainDeadline) {
                Write-Stage1EExecutionJournal $JournalPath `
                    'DESCENDANT_DRAIN_EXPIRED' $residualChildren.Count
                break
            }
            Start-Sleep -Milliseconds 100
        }
        foreach ($childId in $residualChildren) {
            $null = $observedChildren.Add($childId)
            Write-Stage1EExecutionJournal $JournalPath 'RESIDUAL_DESCENDANT_DETECTED' $childId
        }
        if ($residualChildren.Count -gt 0) {
            Stop-Stage1EExecutionProcessTree $rootProcessId
        }
        if ($null -ne $stdoutTask) { $null = $stdoutTask.Wait(5000) }
        if ($null -ne $stderrTask) { $null = $stderrTask.Wait(5000) }
        $stdout = if ($null -ne $stdoutTask -and $stdoutTask.IsCompleted) {
            [string]$stdoutTask.Result
        } else { '' }
        $stderr = if ($null -ne $stderrTask -and $stderrTask.IsCompleted) {
            [string]$stderrTask.Result
        } else { '' }
        Write-Stage1EExecutionCapture -Path $StdoutPath -Text $stdout
        Write-Stage1EExecutionCapture -Path $StderrPath -Text $stderr
        $exitCode = if ($process.HasExited) { [string]$process.ExitCode } else { 'STILL_ACTIVE' }
        $state = if ($timedOut) { 'TIMED_OUT' }
        elseif ($residualChildren.Count -gt 0) { 'RESIDUAL_PROCESS_DETECTED' }
        else { 'COMPLETED' }
        Write-Stage1EExecutionJournal $JournalPath 'PROCESS_TERMINAL' $state
        return [ordered]@{
            state = $state
            root_process_id = [string]$rootProcessId
            exit_code = $exitCode
            elapsed_milliseconds = [string][int64]$stopwatch.ElapsedMilliseconds
            timeout_detected = [bool]$timedOut
            interrupted = [bool]$interrupted
            observed_descendant_ids = [int[]]@($observedChildren | Sort-Object)
            residual_descendant_ids = [int[]]$residualChildren
            invocation_kind = $invocationKind
        }
    }
    catch {
        $interrupted = $true
        if ($null -ne $process) {
            try { Stop-Stage1EExecutionProcessTree ([int]$process.Id) } catch {}
        }
        Write-Stage1EExecutionJournal $JournalPath 'PROCESS_SUPERVISION_FAILED' $_.Exception.Message
        throw
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
        if ($stopwatch.IsRunning) { $stopwatch.Stop() }
    }
}

Export-ModuleMember -Function @(
    'Get-Stage1EExecutionHostInterfaceVersion'
    'New-Stage1EExecutionFile'
    'Write-Stage1EExecutionJournal'
    'Invoke-Stage1EExecutionProcess'
)
