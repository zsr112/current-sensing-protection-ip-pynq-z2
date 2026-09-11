using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace Stage1E.Runtime.Host.V1
{
    public sealed class ProcessControlException : Exception
    {
        public string Operation { get; private set; }
        public int NativeErrorCode { get; private set; }
        public bool ProcessCreationAttempted { get; private set; }
        public bool ProcessCreated { get; private set; }
        public uint ProcessId { get; private set; }

        public ProcessControlException(
            string operation,
            string message,
            int nativeErrorCode,
            bool processCreationAttempted,
            bool processCreated,
            uint processId,
            Exception inner)
            : base(message, inner)
        {
            Operation = operation;
            NativeErrorCode = nativeErrorCode;
            ProcessCreationAttempted = processCreationAttempted;
            ProcessCreated = processCreated;
            ProcessId = processId;
        }
    }

    public sealed class ProcessLaunchRequest
    {
        public string ExecutablePath { get; private set; }
        public string ExpectedImagePath { get; private set; }
        public string[] Arguments { get; private set; }
        public string WorkingDirectory { get; private set; }
        public string[] EnvironmentNames { get; private set; }
        public string[] EnvironmentValues { get; private set; }
        public string StandardOutputPath { get; private set; }
        public string StandardErrorPath { get; private set; }
        public int MaximumProcesses { get; private set; }

        public ProcessLaunchRequest(
            string executablePath,
            string expectedImagePath,
            string[] arguments,
            string workingDirectory,
            string[] environmentNames,
            string[] environmentValues,
            string standardOutputPath,
            string standardErrorPath,
            int maximumProcesses)
        {
            ExecutablePath = RequireAbsoluteFilePath(
                executablePath, "executablePath", true);
            ExpectedImagePath = RequireAbsoluteFilePath(
                expectedImagePath, "expectedImagePath", true);
            WorkingDirectory = RequireAbsoluteDirectoryPath(
                workingDirectory, "workingDirectory");
            StandardOutputPath = RequireAbsoluteFilePath(
                standardOutputPath, "standardOutputPath", false);
            StandardErrorPath = RequireAbsoluteFilePath(
                standardErrorPath, "standardErrorPath", false);
            if (String.Equals(
                    StandardOutputPath,
                    StandardErrorPath,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new ArgumentException(
                    "Standard output and standard error paths must differ.");
            }
            if (arguments == null)
            {
                throw new ArgumentNullException("arguments");
            }
            Arguments = (string[])arguments.Clone();
            for (int index = 0; index < Arguments.Length; index++)
            {
                if (Arguments[index] == null || Arguments[index].IndexOf('\0') >= 0)
                {
                    throw new ArgumentException(
                        "An argument is null or contains NUL.", "arguments");
                }
            }
            if (environmentNames == null || environmentValues == null ||
                environmentNames.Length != environmentValues.Length)
            {
                throw new ArgumentException(
                    "Environment name and value arrays must have equal length.");
            }
            EnvironmentNames = (string[])environmentNames.Clone();
            EnvironmentValues = (string[])environmentValues.Clone();
            HashSet<string> seen = new HashSet<string>(
                StringComparer.OrdinalIgnoreCase);
            for (int index = 0; index < EnvironmentNames.Length; index++)
            {
                string name = EnvironmentNames[index];
                string value = EnvironmentValues[index];
                if (String.IsNullOrEmpty(name) || name.IndexOf('=') >= 0 ||
                    name.IndexOf('\0') >= 0 || value == null ||
                    value.IndexOf('\0') >= 0 || !seen.Add(name))
                {
                    throw new ArgumentException(
                        "The explicit environment contains an invalid or duplicate name/value.");
                }
            }
            if (maximumProcesses < 1 || maximumProcesses > 32)
            {
                throw new ArgumentOutOfRangeException("maximumProcesses");
            }
            MaximumProcesses = maximumProcesses;
        }

        private static string RequireAbsoluteFilePath(
            string value, string name, bool mustExist)
        {
            if (String.IsNullOrEmpty(value) || !Path.IsPathRooted(value))
            {
                throw new ArgumentException(
                    "Path must be explicit and absolute.", name);
            }
            string full = Path.GetFullPath(value);
            if (mustExist && !File.Exists(full))
            {
                throw new FileNotFoundException(
                    "Required exact executable does not exist.", full);
            }
            string parent = Path.GetDirectoryName(full);
            if (String.IsNullOrEmpty(parent) || !Directory.Exists(parent))
            {
                throw new DirectoryNotFoundException(
                    "Path parent does not exist: " + parent);
            }
            return full;
        }

        private static string RequireAbsoluteDirectoryPath(
            string value, string name)
        {
            if (String.IsNullOrEmpty(value) || !Path.IsPathRooted(value))
            {
                throw new ArgumentException(
                    "Directory path must be explicit and absolute.", name);
            }
            string full = Path.GetFullPath(value);
            if (!Directory.Exists(full))
            {
                throw new DirectoryNotFoundException(
                    "Required directory does not exist: " + full);
            }
            return full;
        }
    }

    public sealed class ProcessObservation
    {
        public uint ProcessId { get; internal set; }
        public uint ParentProcessId { get; internal set; }
        public bool ParentProcessIdAvailable { get; internal set; }
        public bool CreationTimeAvailable { get; internal set; }
        public DateTime CreationTimeUtc { get; internal set; }
        public bool ImagePathAvailable { get; internal set; }
        public string ImagePath { get; internal set; }
        public bool JobMembershipAvailable { get; internal set; }
        public bool IsInJob { get; internal set; }
        public bool ExitStateAvailable { get; internal set; }
        public bool HasExited { get; internal set; }
        public bool ExitCodeAvailable { get; internal set; }
        public uint ExitCode { get; internal set; }
        public bool RetainedHandle { get; internal set; }
        public bool ObservationHandleAvailable { get; internal set; }
    }

    public sealed class JobEventObservation
    {
        public long Sequence { get; internal set; }
        public uint NativeMessageType { get; internal set; }
        public string EventType { get; internal set; }
        public bool ProcessIdAvailable { get; internal set; }
        public uint ProcessId { get; internal set; }
        public bool ParentProcessIdAvailable { get; internal set; }
        public uint ParentProcessId { get; internal set; }
        public bool CreationTimeAvailable { get; internal set; }
        public DateTime CreationTimeUtc { get; internal set; }
        public bool ImagePathAvailable { get; internal set; }
        public string ImagePath { get; internal set; }
        public bool ObservationHandleAvailable { get; internal set; }
        public bool RetainedHandle { get; internal set; }
        public bool JobMembershipAvailable { get; internal set; }
        public bool IsInJob { get; internal set; }
        public bool ExitStateAvailable { get; internal set; }
        public bool HasExited { get; internal set; }
        public bool ExitCodeAvailable { get; internal set; }
        public uint ExitCode { get; internal set; }
        public long ReceiptMonotonicTicks { get; internal set; }
        public long ReceiptElapsedMilliseconds { get; internal set; }
        public string AvailabilityState { get; internal set; }
        public string[] Conflicts { get; internal set; }
    }

    public sealed class WindowCloseResult
    {
        public int WindowsFound { get; internal set; }
        public int MessagesPosted { get; internal set; }
        public bool RequestIssued
        {
            get { return MessagesPosted > 0; }
        }
    }

    internal sealed class SafeKernelHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        internal SafeKernelHandle() : base(true) { }
        internal SafeKernelHandle(IntPtr handle, bool ownsHandle)
            : base(ownsHandle)
        {
            SetHandle(handle);
        }

        protected override bool ReleaseHandle()
        {
            return NativeMethods.CloseHandle(handle);
        }
    }

    internal sealed class TrackedProcess : IDisposable
    {
        internal uint ProcessId;
        internal uint ParentProcessId;
        internal bool ParentProcessIdAvailable;
        internal SafeKernelHandle Handle;
        internal bool CreationTimeAvailable;
        internal DateTime CreationTimeUtc;
        internal bool ImagePathAvailable;
        internal string ImagePath;
        internal bool JobMembershipAvailable;
        internal bool IsInJob;

        public void Dispose()
        {
            if (Handle != null)
            {
                Handle.Dispose();
                Handle = null;
            }
        }
    }

    public sealed class ControlledProcess : IDisposable
    {
        private readonly object sync = new object();
        private SafeKernelHandle processHandle;
        private SafeKernelHandle primaryThreadHandle;
        private SafeKernelHandle jobHandle;
        private SafeKernelHandle completionPortHandle;
        private FileStream stdoutReadStream;
        private FileStream stderrReadStream;
        private FileStream stdoutWriteStream;
        private FileStream stderrWriteStream;
        private Task stdoutCopyTask;
        private Task stderrCopyTask;
        private Task jobEventPumpTask;
        private readonly object jobEventSync = new object();
        private readonly List<JobEventObservation> jobEvents =
            new List<JobEventObservation>();
        private readonly Dictionary<uint, TrackedProcess> trackedProcesses =
            new Dictionary<uint, TrackedProcess>();
        private readonly ManualResetEvent activeProcessZero =
            new ManualResetEvent(false);
        private volatile bool stopJobEventPump;
        private bool disposed;
        private bool resumed;
        private bool forcedTerminationRequested;
        private readonly uint rootParentProcessId;
        private readonly DateTime rootCreationTimeUtc;
        private readonly string rootImagePath;
        private readonly int maximumProcesses;
        private readonly long monotonicOriginTicks;

        public const string InterfaceVersion =
            "stage1e-windows-process-control-interface-v1";

        public uint ProcessId { get; private set; }
        public bool CreatedSuspended { get; private set; }
        public bool JobAssignedBeforeResume { get; private set; }
        public bool MembershipVerifiedBeforeResume { get; private set; }
        public bool CompletionPortAssociatedBeforeCreate { get; private set; }
        public bool RootNewProcessObservedBeforeResume { get; private set; }
        public int CreationAttemptCount { get { return 1; } }
        public int ResumeCount { get; private set; }
        public uint ResumePreviousCount { get; private set; }
        public int ForcedTerminationCount { get; private set; }
        public int ExecutionProcessLimit { get { return maximumProcesses; } }
        public string ObservedImagePath { get { return rootImagePath; } }
        public DateTime CreationTimeUtc { get { return rootCreationTimeUtc; } }
        public uint ParentProcessId { get { return rootParentProcessId; } }

        private ControlledProcess(
            SafeKernelHandle process,
            SafeKernelHandle thread,
            SafeKernelHandle job,
            SafeKernelHandle completionPort,
            uint processId,
            uint parentProcessId,
            DateTime creationTimeUtc,
            string imagePath,
            int maxProcesses,
            FileStream stdoutReader,
            FileStream stderrReader,
            FileStream stdoutWriter,
            FileStream stderrWriter,
            long eventOriginTicks,
            JobEventObservation[] initialJobEvents)
        {
            processHandle = process;
            primaryThreadHandle = thread;
            jobHandle = job;
            completionPortHandle = completionPort;
            ProcessId = processId;
            rootParentProcessId = parentProcessId;
            rootCreationTimeUtc = creationTimeUtc;
            rootImagePath = imagePath;
            maximumProcesses = maxProcesses;
            monotonicOriginTicks = eventOriginTicks;
            stdoutReadStream = stdoutReader;
            stderrReadStream = stderrReader;
            stdoutWriteStream = stdoutWriter;
            stderrWriteStream = stderrWriter;
            CreatedSuspended = true;
            JobAssignedBeforeResume = true;
            MembershipVerifiedBeforeResume = true;
            CompletionPortAssociatedBeforeCreate = true;
            foreach (JobEventObservation jobEvent in initialJobEvents)
            {
                jobEvents.Add(jobEvent);
                if (jobEvent.EventType == "NEW_PROCESS" &&
                    jobEvent.ProcessIdAvailable &&
                    jobEvent.ProcessId == ProcessId)
                {
                    RootNewProcessObservedBeforeResume = true;
                }
            }
            if (!RootNewProcessObservedBeforeResume)
            {
                throw new ProcessControlException(
                    "GetQueuedCompletionStatus",
                    "The root NEW_PROCESS completion event was not observed before resume.",
                    0, true, true, processId, null);
            }
            StartCaptureTasks();
            StartJobEventPump();
        }

        public static ControlledProcess CreateContainedSuspended(
            ProcessLaunchRequest request)
        {
            if (request == null)
            {
                throw new ArgumentNullException("request");
            }

            SafeKernelHandle job = null;
            SafeKernelHandle completionPort = null;
            SafeKernelHandle process = null;
            SafeKernelHandle thread = null;
            IntPtr stdoutRead = IntPtr.Zero;
            IntPtr stdoutWrite = IntPtr.Zero;
            IntPtr stderrRead = IntPtr.Zero;
            IntPtr stderrWrite = IntPtr.Zero;
            IntPtr stdinRead = IntPtr.Zero;
            IntPtr stdinWrite = IntPtr.Zero;
            IntPtr environmentBlock = IntPtr.Zero;
            IntPtr attributeList = IntPtr.Zero;
            IntPtr inheritedHandleList = IntPtr.Zero;
            bool attributeListInitialized = false;
            FileStream stdoutReader = null;
            FileStream stderrReader = null;
            FileStream stdoutWriter = null;
            FileStream stderrWriter = null;
            bool creationAttempted = false;
            bool processCreated = false;
            uint processId = 0;
            long eventOriginTicks = System.Diagnostics.Stopwatch.GetTimestamp();

            try
            {
                job = CreateConfiguredJob(
                    request.MaximumProcesses, out completionPort);
                CreateAnonymousPipe(out stdoutRead, out stdoutWrite, true);
                CreateAnonymousPipe(out stderrRead, out stderrWrite, true);
                CreateAnonymousPipe(out stdinRead, out stdinWrite, false);

                stdoutReader = new FileStream(
                    new SafeFileHandle(stdoutRead, true),
                    FileAccess.Read, 4096, false);
                stdoutRead = IntPtr.Zero;
                stderrReader = new FileStream(
                    new SafeFileHandle(stderrRead, true),
                    FileAccess.Read, 4096, false);
                stderrRead = IntPtr.Zero;
                stdoutWriter = new FileStream(
                    request.StandardOutputPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.Read,
                    4096,
                    FileOptions.WriteThrough);
                stderrWriter = new FileStream(
                    request.StandardErrorPath,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.Read,
                    4096,
                    FileOptions.WriteThrough);

                NativeMethods.STARTUPINFOEX startup =
                    new NativeMethods.STARTUPINFOEX();
                startup.StartupInfo.cb = Marshal.SizeOf(
                    typeof(NativeMethods.STARTUPINFOEX));
                startup.StartupInfo.dwFlags =
                    NativeMethods.STARTF_USESTDHANDLES;
                startup.StartupInfo.hStdInput = stdinRead;
                startup.StartupInfo.hStdOutput = stdoutWrite;
                startup.StartupInfo.hStdError = stderrWrite;
                ConfigureExactInheritedHandleList(
                    stdinRead,
                    stdoutWrite,
                    stderrWrite,
                    out attributeList,
                    out inheritedHandleList,
                    out attributeListInitialized);
                startup.lpAttributeList = attributeList;
                NativeMethods.PROCESS_INFORMATION processInformation;
                StringBuilder commandLine = new StringBuilder(
                    BuildCommandLine(request.ExecutablePath, request.Arguments));
                environmentBlock = BuildEnvironmentBlock(
                    request.EnvironmentNames, request.EnvironmentValues);

                creationAttempted = true;
                bool created = NativeMethods.CreateProcessW(
                    request.ExecutablePath,
                    commandLine,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    true,
                    NativeMethods.CREATE_SUSPENDED |
                        NativeMethods.CREATE_UNICODE_ENVIRONMENT |
                        NativeMethods.EXTENDED_STARTUPINFO_PRESENT,
                    environmentBlock,
                    request.WorkingDirectory,
                    ref startup,
                    out processInformation);
                if (!created)
                {
                    ThrowNative(
                        "CreateProcessW", true, false, 0,
                        "The exact suspended process creation failed.");
                }
                processCreated = true;
                processId = processInformation.dwProcessId;
                process = new SafeKernelHandle(
                    processInformation.hProcess, true);
                thread = new SafeKernelHandle(
                    processInformation.hThread, true);

                CloseRawHandle(ref stdoutWrite);
                CloseRawHandle(ref stderrWrite);
                CloseRawHandle(ref stdinRead);
                CloseRawHandle(ref stdinWrite);

                if (!NativeMethods.AssignProcessToJobObject(
                        job.DangerousGetHandle(), process.DangerousGetHandle()))
                {
                    ThrowNative(
                        "AssignProcessToJobObject", true, true, processId,
                        "The suspended process could not be assigned to its Job Object.");
                }
                bool inJob;
                if (!NativeMethods.IsProcessInJob(
                        process.DangerousGetHandle(),
                        job.DangerousGetHandle(),
                        out inJob) || !inJob)
                {
                    ThrowNative(
                        "IsProcessInJob", true, true, processId,
                        "Job membership could not be verified before resume.");
                }

                string observedImage = QueryImagePath(
                    process.DangerousGetHandle());
                if (!PathsEqual(observedImage, request.ExpectedImagePath))
                {
                    throw new ProcessControlException(
                        "QueryFullProcessImageNameW",
                        "The created process image differs from the exact expected image.",
                        0,
                        true,
                        true,
                        processId,
                        null);
                }
                DateTime creationTime = QueryCreationTime(
                    process.DangerousGetHandle());
                uint parentProcessId = QueryParentProcessId(processId);
                JobEventObservation[] initialJobEvents =
                    ObserveInitialRootJobEvent(
                        completionPort.DangerousGetHandle(),
                        job.DangerousGetHandle(),
                        process.DangerousGetHandle(),
                        processId,
                        parentProcessId,
                        creationTime,
                        observedImage,
                        eventOriginTicks);

                ControlledProcess result = new ControlledProcess(
                    process,
                    thread,
                    job,
                    completionPort,
                    processId,
                    parentProcessId,
                    creationTime,
                    observedImage,
                    request.MaximumProcesses,
                    stdoutReader,
                    stderrReader,
                    stdoutWriter,
                    stderrWriter,
                    eventOriginTicks,
                    initialJobEvents);
                process = null;
                thread = null;
                job = null;
                completionPort = null;
                stdoutReader = null;
                stderrReader = null;
                stdoutWriter = null;
                stderrWriter = null;
                return result;
            }
            catch (ProcessControlException)
            {
                if (processCreated)
                {
                    TerminateFailedCreation(job, process);
                }
                throw;
            }
            catch (Exception exception)
            {
                if (processCreated)
                {
                    TerminateFailedCreation(job, process);
                }
                throw new ProcessControlException(
                    "CreateContainedSuspended",
                    "Controlled process creation failed: " + exception.Message,
                    (exception is Win32Exception)
                        ? ((Win32Exception)exception).NativeErrorCode : 0,
                    creationAttempted,
                    processCreated,
                    processId,
                    exception);
            }
            finally
            {
                if (environmentBlock != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(environmentBlock);
                }
                if (attributeListInitialized && attributeList != IntPtr.Zero)
                {
                    NativeMethods.DeleteProcThreadAttributeList(attributeList);
                }
                if (attributeList != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(attributeList);
                }
                if (inheritedHandleList != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(inheritedHandleList);
                }
                CloseRawHandle(ref stdoutRead);
                CloseRawHandle(ref stdoutWrite);
                CloseRawHandle(ref stderrRead);
                CloseRawHandle(ref stderrWrite);
                CloseRawHandle(ref stdinRead);
                CloseRawHandle(ref stdinWrite);
                if (stdoutReader != null) { stdoutReader.Dispose(); }
                if (stderrReader != null) { stderrReader.Dispose(); }
                if (stdoutWriter != null) { stdoutWriter.Dispose(); }
                if (stderrWriter != null) { stderrWriter.Dispose(); }
                if (thread != null) { thread.Dispose(); }
                if (process != null) { process.Dispose(); }
                if (job != null) { job.Dispose(); }
                if (completionPort != null) { completionPort.Dispose(); }
            }
        }

        public uint ResumeOnce()
        {
            lock (sync)
            {
                ThrowIfDisposed();
                if (resumed)
                {
                    throw new InvalidOperationException(
                        "The primary thread may be resumed only once.");
                }
                uint previous = NativeMethods.ResumeThread(
                    primaryThreadHandle.DangerousGetHandle());
                if (previous == UInt32.MaxValue)
                {
                    ThrowNative(
                        "ResumeThread", true, true, ProcessId,
                        "The contained primary thread could not be resumed.");
                }
                if (previous != 1)
                {
                    throw new ProcessControlException(
                        "ResumeThread",
                        "The primary thread suspend count was not exactly one.",
                        0,
                        true,
                        true,
                        ProcessId,
                        null);
                }
                resumed = true;
                ResumeCount = 1;
                ResumePreviousCount = previous;
                return previous;
            }
        }

        public bool WaitForRootExit(int timeoutMilliseconds)
        {
            ThrowIfInvalidTimeout(timeoutMilliseconds);
            lock (sync)
            {
                ThrowIfDisposed();
                uint result = NativeMethods.WaitForSingleObject(
                    processHandle.DangerousGetHandle(),
                    (uint)timeoutMilliseconds);
                if (result == NativeMethods.WAIT_OBJECT_0) { return true; }
                if (result == NativeMethods.WAIT_TIMEOUT) { return false; }
                ThrowNative(
                    "WaitForSingleObject", true, true, ProcessId,
                    "The root process wait failed.");
                return false;
            }
        }

        public bool WaitForJobEmpty(
            int timeoutMilliseconds, int observationIntervalMilliseconds)
        {
            ThrowIfInvalidTimeout(timeoutMilliseconds);
            if (observationIntervalMilliseconds < 1)
            {
                throw new ArgumentOutOfRangeException(
                    "observationIntervalMilliseconds");
            }
            long start = Environment.TickCount;
            while (true)
            {
                if (IsJobEmpty())
                {
                    return true;
                }
                long elapsed = unchecked((uint)(Environment.TickCount - start));
                if (elapsed >= timeoutMilliseconds) { return false; }
                int remaining = timeoutMilliseconds - (int)elapsed;
                Thread.Sleep(Math.Min(observationIntervalMilliseconds, remaining));
            }
        }

        public bool IsJobEmpty()
        {
            lock (sync)
            {
                ThrowIfDisposed();
                return QueryJobProcessIds().Length == 0 &&
                    HasCompleteTerminalJobEvents();
            }
        }

        private bool HasCompleteTerminalJobEvents()
        {
            return activeProcessZero.WaitOne(0);
        }

        public uint[] GetCurrentJobProcessIds()
        {
            lock (sync)
            {
                ThrowIfDisposed();
                return QueryJobProcessIds();
            }
        }

        public JobEventObservation[] GetJobEvents()
        {
            lock (jobEventSync)
            {
                return jobEvents.ToArray();
            }
        }

        public ProcessObservation[] Observe()
        {
            lock (sync)
            {
                ThrowIfDisposed();
                Dictionary<uint, uint> parents = QueryProcessParents();
                List<ProcessObservation> observations =
                    new List<ProcessObservation>();
                observations.Add(ObserveHandle(
                    ProcessId,
                    rootParentProcessId,
                    true,
                    processHandle.DangerousGetHandle(),
                    true,
                    rootCreationTimeUtc,
                    rootImagePath,
                    true,
                    true));
                uint[] members = QueryJobProcessIds();
                HashSet<uint> currentMembers = new HashSet<uint>(members);
                lock (jobEventSync)
                {
                    foreach (TrackedProcess tracked in trackedProcesses.Values)
                    {
                        if (tracked.ProcessId == ProcessId) { continue; }
                        if (tracked.Handle == null || tracked.Handle.IsInvalid)
                        {
                            ProcessObservation unavailable =
                                new ProcessObservation();
                            unavailable.ProcessId = tracked.ProcessId;
                            unavailable.ParentProcessId = tracked.ParentProcessId;
                            unavailable.ParentProcessIdAvailable =
                                tracked.ParentProcessIdAvailable;
                            unavailable.CreationTimeAvailable =
                                tracked.CreationTimeAvailable;
                            unavailable.CreationTimeUtc = tracked.CreationTimeUtc;
                            unavailable.ImagePathAvailable =
                                tracked.ImagePathAvailable;
                            unavailable.ImagePath = tracked.ImagePath;
                            unavailable.JobMembershipAvailable =
                                tracked.JobMembershipAvailable;
                            unavailable.IsInJob = tracked.IsInJob;
                            observations.Add(unavailable);
                            continue;
                        }
                        observations.Add(ObserveHandle(
                            tracked.ProcessId,
                            tracked.ParentProcessId,
                            tracked.ParentProcessIdAvailable,
                            tracked.Handle.DangerousGetHandle(),
                            true,
                            tracked.CreationTimeAvailable
                                ? (DateTime?)tracked.CreationTimeUtc : null,
                            tracked.ImagePathAvailable
                                ? tracked.ImagePath : null,
                            tracked.JobMembershipAvailable,
                            tracked.IsInJob));
                    }
                    foreach (uint member in currentMembers)
                    {
                        if (member == ProcessId ||
                            trackedProcesses.ContainsKey(member))
                        {
                            continue;
                        }
                        ProcessObservation unavailable =
                            new ProcessObservation();
                        unavailable.ProcessId = member;
                        unavailable.ParentProcessId = parents.ContainsKey(member)
                            ? parents[member] : 0;
                        unavailable.ParentProcessIdAvailable =
                            parents.ContainsKey(member);
                        unavailable.JobMembershipAvailable = true;
                        unavailable.IsInJob = true;
                        observations.Add(unavailable);
                    }
                }
                if (observations.Count > maximumProcesses)
                {
                    throw new ProcessControlException(
                        "QueryInformationJobObject",
                        "Observed job membership exceeds the reviewed process limit.",
                        0, true, true, ProcessId, null);
                }
                observations.Sort(delegate(
                    ProcessObservation left, ProcessObservation right)
                {
                    if (left.ProcessId == ProcessId) { return -1; }
                    if (right.ProcessId == ProcessId) { return 1; }
                    return left.ProcessId.CompareTo(right.ProcessId);
                });
                return observations.ToArray();
            }
        }

        public WindowCloseResult RequestWindowClose()
        {
            lock (sync)
            {
                ThrowIfDisposed();
                WindowCloseResult result = new WindowCloseResult();
                uint[] processIds = QueryJobProcessIds();
                HashSet<uint> members = new HashSet<uint>(processIds);
                NativeMethods.EnumWindowsProc callback = delegate(
                    IntPtr window, IntPtr parameter)
                {
                    uint windowProcessId;
                    NativeMethods.GetWindowThreadProcessId(
                        window, out windowProcessId);
                    if (members.Contains(windowProcessId))
                    {
                        result.WindowsFound++;
                        if (NativeMethods.PostMessageW(
                                window, NativeMethods.WM_CLOSE,
                                IntPtr.Zero, IntPtr.Zero))
                        {
                            result.MessagesPosted++;
                        }
                    }
                    return true;
                };
                // EnumWindows may return zero when the contained console tree
                // has no top-level windows and does not reliably set last error.
                // That is a graceful-mechanism-unavailable observation, not a
                // reason to skip the required forced escalation.
                NativeMethods.EnumWindows(callback, IntPtr.Zero);
                GC.KeepAlive(callback);
                return result;
            }
        }

        public void TerminateContainedTree(uint exitCode)
        {
            lock (sync)
            {
                ThrowIfDisposed();
                if (forcedTerminationRequested)
                {
                    throw new InvalidOperationException(
                        "Forced contained-tree termination may be requested only once.");
                }
                forcedTerminationRequested = true;
                ForcedTerminationCount = 1;
                if (!NativeMethods.TerminateJobObject(
                        jobHandle.DangerousGetHandle(), exitCode))
                {
                    ThrowNative(
                        "TerminateJobObject", true, true, ProcessId,
                        "Forced contained-tree termination failed.");
                }
            }
        }

        public bool TryGetRootExitCode(out uint exitCode)
        {
            lock (sync)
            {
                ThrowIfDisposed();
                uint value;
                if (!NativeMethods.GetExitCodeProcess(
                        processHandle.DangerousGetHandle(), out value))
                {
                    ThrowNative(
                        "GetExitCodeProcess", true, true, ProcessId,
                        "The root process exit code could not be observed.");
                }
                exitCode = value;
                return value != NativeMethods.STILL_ACTIVE;
            }
        }

        public bool CompleteCapture(int timeoutMilliseconds)
        {
            ThrowIfInvalidTimeout(timeoutMilliseconds);
            Task[] tasks;
            lock (sync)
            {
                ThrowIfDisposed();
                tasks = new Task[] { stdoutCopyTask, stderrCopyTask };
            }
            return Task.WaitAll(tasks, timeoutMilliseconds);
        }

        public void Dispose()
        {
            Task eventPump = null;
            lock (sync)
            {
                if (disposed) { return; }
                disposed = true;
                stopJobEventPump = true;
                if (completionPortHandle != null &&
                    !completionPortHandle.IsInvalid)
                {
                    NativeMethods.PostQueuedCompletionStatus(
                        completionPortHandle.DangerousGetHandle(),
                        0,
                        NativeMethods.SHUTDOWN_COMPLETION_KEY,
                        IntPtr.Zero);
                }
                eventPump = jobEventPumpTask;
                if (jobHandle != null && !jobHandle.IsInvalid)
                {
                    jobHandle.Dispose();
                }
                if (processHandle != null && !processHandle.IsInvalid)
                {
                    NativeMethods.WaitForSingleObject(
                        processHandle.DangerousGetHandle(), 5000);
                }
                if (primaryThreadHandle != null)
                {
                    primaryThreadHandle.Dispose();
                }
                if (processHandle != null)
                {
                    processHandle.Dispose();
                }
            }
            if (eventPump != null)
            {
                try { eventPump.Wait(5000); }
                catch (AggregateException) { }
            }
            lock (jobEventSync)
            {
                foreach (TrackedProcess tracked in trackedProcesses.Values)
                {
                    tracked.Dispose();
                }
                trackedProcesses.Clear();
            }
            activeProcessZero.Dispose();
            if (completionPortHandle != null)
            {
                completionPortHandle.Dispose();
                completionPortHandle = null;
            }
            try
            {
                Task.WaitAll(
                    new Task[] { stdoutCopyTask, stderrCopyTask }, 5000);
            }
            catch (AggregateException) { }
        }

        private void StartCaptureTasks()
        {
            FileStream stdoutReader = stdoutReadStream;
            FileStream stderrReader = stderrReadStream;
            FileStream stdoutWriter = stdoutWriteStream;
            FileStream stderrWriter = stderrWriteStream;
            stdoutReadStream = null;
            stderrReadStream = null;
            stdoutWriteStream = null;
            stderrWriteStream = null;
            stdoutCopyTask = Task.Factory.StartNew(delegate
            {
                using (stdoutReader)
                using (stdoutWriter)
                {
                    stdoutReader.CopyTo(stdoutWriter);
                    stdoutWriter.Flush(true);
                }
            }, CancellationToken.None,
                TaskCreationOptions.LongRunning,
                TaskScheduler.Default);
            stderrCopyTask = Task.Factory.StartNew(delegate
            {
                using (stderrReader)
                using (stderrWriter)
                {
                    stderrReader.CopyTo(stderrWriter);
                    stderrWriter.Flush(true);
                }
            }, CancellationToken.None,
                TaskCreationOptions.LongRunning,
                TaskScheduler.Default);
        }

        private void StartJobEventPump()
        {
            jobEventPumpTask = Task.Factory.StartNew(delegate
            {
                while (!stopJobEventPump)
                {
                    uint nativeMessage;
                    UIntPtr completionKey;
                    IntPtr overlapped;
                    bool received = NativeMethods.GetQueuedCompletionStatus(
                        completionPortHandle.DangerousGetHandle(),
                        out nativeMessage,
                        out completionKey,
                        out overlapped,
                        100);
                    if (!received)
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error == NativeMethods.WAIT_TIMEOUT)
                        {
                            continue;
                        }
                        if (stopJobEventPump)
                        {
                            break;
                        }
                        AppendCompletionPortFailure(error);
                        break;
                    }
                    if (completionKey == NativeMethods.SHUTDOWN_COMPLETION_KEY)
                    {
                        break;
                    }
                    if (completionKey != NativeMethods.JOB_COMPLETION_KEY)
                    {
                        AppendCompletionPortFailure(0);
                        continue;
                    }
                    uint processId = unchecked((uint)overlapped.ToInt64());
                    AppendJobEvent(nativeMessage, processId);
                }
            }, CancellationToken.None,
                TaskCreationOptions.LongRunning,
                TaskScheduler.Default);
        }

        private void AppendCompletionPortFailure(int error)
        {
            JobEventObservation jobEvent = NewJobEvent(
                NativeMethods.JOB_OBJECT_MSG_COMPLETION_PORT_FAILURE, 0);
            jobEvent.EventType = "COMPLETION_PORT_FAILURE";
            jobEvent.AvailabilityState = "CONFLICT";
            jobEvent.Conflicts = new string[] {
                error == 0
                    ? "The Job completion key did not match the associated Job."
                    : "GetQueuedCompletionStatus failed: " +
                        new Win32Exception(error).Message
            };
            AppendJobEventRecord(jobEvent);
        }

        private void AppendJobEvent(uint nativeMessage, uint processId)
        {
            JobEventObservation jobEvent = NewJobEvent(
                nativeMessage, processId);
            if (IsProcessJobMessage(nativeMessage) && processId != 0)
            {
                CaptureJobProcessEvidence(jobEvent);
            }
            else
            {
                jobEvent.AvailabilityState = "COMPLETE";
                jobEvent.Conflicts = new string[0];
            }
            AppendJobEventRecord(jobEvent);
            if (nativeMessage == NativeMethods.JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO)
            {
                activeProcessZero.Set();
            }
        }

        private JobEventObservation NewJobEvent(
            uint nativeMessage, uint processId)
        {
            long receiptTicks = System.Diagnostics.Stopwatch.GetTimestamp();
            JobEventObservation jobEvent = new JobEventObservation();
            jobEvent.NativeMessageType = nativeMessage;
            jobEvent.EventType = GetJobEventType(nativeMessage);
            jobEvent.ProcessIdAvailable =
                IsProcessJobMessage(nativeMessage) && processId != 0;
            jobEvent.ProcessId = processId;
            jobEvent.ReceiptMonotonicTicks = receiptTicks;
            jobEvent.ReceiptElapsedMilliseconds = MonotonicElapsedMilliseconds(
                monotonicOriginTicks, receiptTicks);
            jobEvent.AvailabilityState = "UNAVAILABLE";
            jobEvent.Conflicts = new string[0];
            return jobEvent;
        }

        private void CaptureJobProcessEvidence(JobEventObservation jobEvent)
        {
            List<string> conflicts = new List<string>();
            IntPtr handle = IntPtr.Zero;
            bool retained = false;
            TrackedProcess tracked = null;
            if (jobEvent.ProcessId == ProcessId)
            {
                handle = processHandle.DangerousGetHandle();
                retained = true;
                jobEvent.ParentProcessId = rootParentProcessId;
                jobEvent.ParentProcessIdAvailable = true;
                jobEvent.CreationTimeUtc = rootCreationTimeUtc;
                jobEvent.CreationTimeAvailable = true;
                jobEvent.ImagePath = rootImagePath;
                jobEvent.ImagePathAvailable = true;
                jobEvent.JobMembershipAvailable = true;
                jobEvent.IsInJob = true;
            }
            else
            {
                lock (jobEventSync)
                {
                    trackedProcesses.TryGetValue(jobEvent.ProcessId, out tracked);
                    if (jobEvent.NativeMessageType ==
                            NativeMethods.JOB_OBJECT_MSG_NEW_PROCESS &&
                        tracked != null)
                    {
                        conflicts.Add(
                            "A duplicate NEW_PROCESS event reused an active PID.");
                    }
                    if (tracked == null)
                    {
                        tracked = CaptureTrackedProcess(jobEvent.ProcessId);
                        trackedProcesses[jobEvent.ProcessId] = tracked;
                    }
                }
                if (tracked != null)
                {
                    jobEvent.ParentProcessId = tracked.ParentProcessId;
                    jobEvent.ParentProcessIdAvailable =
                        tracked.ParentProcessIdAvailable;
                    jobEvent.CreationTimeUtc = tracked.CreationTimeUtc;
                    jobEvent.CreationTimeAvailable =
                        tracked.CreationTimeAvailable;
                    jobEvent.ImagePath = tracked.ImagePath;
                    jobEvent.ImagePathAvailable = tracked.ImagePathAvailable;
                    jobEvent.JobMembershipAvailable =
                        tracked.JobMembershipAvailable;
                    jobEvent.IsInJob = tracked.IsInJob;
                    if (tracked.Handle != null && !tracked.Handle.IsInvalid)
                    {
                        handle = tracked.Handle.DangerousGetHandle();
                        retained = true;
                    }
                }
            }
            jobEvent.ObservationHandleAvailable =
                handle != IntPtr.Zero &&
                handle != NativeMethods.INVALID_HANDLE_VALUE;
            jobEvent.RetainedHandle = retained;
            if (jobEvent.ObservationHandleAvailable)
            {
                uint exitCode;
                if (NativeMethods.GetExitCodeProcess(handle, out exitCode))
                {
                    jobEvent.ExitStateAvailable = true;
                    jobEvent.HasExited = exitCode != NativeMethods.STILL_ACTIVE;
                    if (jobEvent.HasExited)
                    {
                        jobEvent.ExitCodeAvailable = true;
                        jobEvent.ExitCode = exitCode;
                    }
                }
            }
            if (!jobEvent.ParentProcessIdAvailable)
            {
                conflicts.Add("The process parent PID was unavailable.");
            }
            if (!jobEvent.CreationTimeAvailable)
            {
                conflicts.Add("The process creation time was unavailable.");
            }
            if (!jobEvent.ImagePathAvailable)
            {
                conflicts.Add("The canonical process image was unavailable.");
            }
            if (!jobEvent.ObservationHandleAvailable)
            {
                conflicts.Add("An observation handle was unavailable.");
            }
            if (!jobEvent.JobMembershipAvailable || !jobEvent.IsInJob)
            {
                conflicts.Add("Direct Job membership evidence was unavailable or false.");
            }
            if ((jobEvent.NativeMessageType ==
                    NativeMethods.JOB_OBJECT_MSG_EXIT_PROCESS ||
                jobEvent.NativeMessageType ==
                    NativeMethods.JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS) &&
                (!jobEvent.ExitStateAvailable || !jobEvent.HasExited))
            {
                conflicts.Add("The terminal process exit state was unavailable.");
            }
            jobEvent.Conflicts = conflicts.ToArray();
            jobEvent.AvailabilityState = conflicts.Count == 0
                ? "COMPLETE" : "UNAVAILABLE";
        }

        private TrackedProcess CaptureTrackedProcess(uint processId)
        {
            TrackedProcess tracked = new TrackedProcess();
            tracked.ProcessId = processId;
            Dictionary<uint, uint> parents = QueryProcessParents();
            if (parents.ContainsKey(processId))
            {
                tracked.ParentProcessId = parents[processId];
                tracked.ParentProcessIdAvailable = true;
            }
            tracked.Handle = OpenObservationHandle(processId);
            if (tracked.Handle == null)
            {
                return tracked;
            }
            try
            {
                tracked.CreationTimeUtc = QueryCreationTime(
                    tracked.Handle.DangerousGetHandle());
                tracked.CreationTimeAvailable = true;
            }
            catch (ProcessControlException) { }
            try
            {
                tracked.ImagePath = QueryImagePath(
                    tracked.Handle.DangerousGetHandle());
                tracked.ImagePathAvailable = true;
            }
            catch (ProcessControlException) { }
            bool inJob;
            if (NativeMethods.IsProcessInJob(
                    tracked.Handle.DangerousGetHandle(),
                    jobHandle.DangerousGetHandle(),
                    out inJob))
            {
                tracked.JobMembershipAvailable = true;
                tracked.IsInJob = inJob;
            }
            return tracked;
        }

        private void AppendJobEventRecord(JobEventObservation jobEvent)
        {
            lock (jobEventSync)
            {
                jobEvent.Sequence = jobEvents.Count + 1;
                jobEvents.Add(jobEvent);
            }
        }

        private static JobEventObservation[] ObserveInitialRootJobEvent(
            IntPtr completionPort,
            IntPtr job,
            IntPtr process,
            uint processId,
            uint parentProcessId,
            DateTime creationTimeUtc,
            string imagePath,
            long originTicks)
        {
            List<JobEventObservation> observed =
                new List<JobEventObservation>();
            long start = Environment.TickCount;
            while (true)
            {
                long elapsed = unchecked((uint)(Environment.TickCount - start));
                if (elapsed >= 5000)
                {
                    throw new ProcessControlException(
                        "GetQueuedCompletionStatus",
                        "The root NEW_PROCESS completion event was not available before resume.",
                        unchecked((int)NativeMethods.WAIT_TIMEOUT),
                        true, true, processId, null);
                }
                uint nativeMessage;
                UIntPtr completionKey;
                IntPtr overlapped;
                bool received = NativeMethods.GetQueuedCompletionStatus(
                    completionPort,
                    out nativeMessage,
                    out completionKey,
                    out overlapped,
                    (uint)(5000 - elapsed));
                if (!received)
                {
                    ThrowNative(
                        "GetQueuedCompletionStatus", true, true, processId,
                        "The pre-resume Job event could not be received.");
                }
                if (completionKey != NativeMethods.JOB_COMPLETION_KEY)
                {
                    throw new ProcessControlException(
                        "GetQueuedCompletionStatus",
                        "The pre-resume Job completion key conflicted.",
                        0, true, true, processId, null);
                }
                uint eventProcessId = unchecked((uint)overlapped.ToInt64());
                long receiptTicks =
                    System.Diagnostics.Stopwatch.GetTimestamp();
                JobEventObservation jobEvent = new JobEventObservation();
                jobEvent.Sequence = observed.Count + 1;
                jobEvent.NativeMessageType = nativeMessage;
                jobEvent.EventType = GetJobEventType(nativeMessage);
                jobEvent.ProcessIdAvailable =
                    IsProcessJobMessage(nativeMessage) && eventProcessId != 0;
                jobEvent.ProcessId = eventProcessId;
                jobEvent.ReceiptMonotonicTicks = receiptTicks;
                jobEvent.ReceiptElapsedMilliseconds =
                    MonotonicElapsedMilliseconds(originTicks, receiptTicks);
                jobEvent.Conflicts = new string[0];
                if (nativeMessage == NativeMethods.JOB_OBJECT_MSG_NEW_PROCESS &&
                    eventProcessId == processId)
                {
                    jobEvent.ParentProcessId = parentProcessId;
                    jobEvent.ParentProcessIdAvailable = true;
                    jobEvent.CreationTimeUtc = creationTimeUtc;
                    jobEvent.CreationTimeAvailable = true;
                    jobEvent.ImagePath = imagePath;
                    jobEvent.ImagePathAvailable = true;
                    jobEvent.ObservationHandleAvailable = true;
                    jobEvent.RetainedHandle = true;
                    bool inJob;
                    if (NativeMethods.IsProcessInJob(process, job, out inJob))
                    {
                        jobEvent.JobMembershipAvailable = true;
                        jobEvent.IsInJob = inJob;
                    }
                    uint exitCode;
                    if (NativeMethods.GetExitCodeProcess(process, out exitCode))
                    {
                        jobEvent.ExitStateAvailable = true;
                        jobEvent.HasExited =
                            exitCode != NativeMethods.STILL_ACTIVE;
                        if (jobEvent.HasExited)
                        {
                            jobEvent.ExitCodeAvailable = true;
                            jobEvent.ExitCode = exitCode;
                        }
                    }
                    jobEvent.AvailabilityState =
                        jobEvent.JobMembershipAvailable && jobEvent.IsInJob
                            ? "COMPLETE" : "UNAVAILABLE";
                    if (jobEvent.AvailabilityState != "COMPLETE")
                    {
                        jobEvent.Conflicts = new string[] {
                            "Pre-resume root Job membership was unavailable."
                        };
                    }
                    observed.Add(jobEvent);
                    return observed.ToArray();
                }
                jobEvent.AvailabilityState = "CONFLICT";
                jobEvent.Conflicts = new string[] {
                    "An unexpected Job event preceded the root NEW_PROCESS event."
                };
                observed.Add(jobEvent);
            }
        }

        private static bool IsProcessJobMessage(uint nativeMessage)
        {
            return nativeMessage == NativeMethods.JOB_OBJECT_MSG_NEW_PROCESS ||
                nativeMessage == NativeMethods.JOB_OBJECT_MSG_EXIT_PROCESS ||
                nativeMessage ==
                    NativeMethods.JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS;
        }

        private static string GetJobEventType(uint nativeMessage)
        {
            switch (nativeMessage)
            {
                case NativeMethods.JOB_OBJECT_MSG_NEW_PROCESS:
                    return "NEW_PROCESS";
                case NativeMethods.JOB_OBJECT_MSG_EXIT_PROCESS:
                    return "EXIT_PROCESS";
                case NativeMethods.JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS:
                    return "ABNORMAL_EXIT_PROCESS";
                case NativeMethods.JOB_OBJECT_MSG_ACTIVE_PROCESS_LIMIT:
                    return "ACTIVE_PROCESS_LIMIT";
                case NativeMethods.JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO:
                    return "ACTIVE_PROCESS_ZERO";
                default:
                    return "UNKNOWN_JOB_MESSAGE";
            }
        }

        private static long MonotonicElapsedMilliseconds(
            long originTicks, long receiptTicks)
        {
            long delta = receiptTicks - originTicks;
            return (delta * 1000L) /
                System.Diagnostics.Stopwatch.Frequency;
        }

        private ProcessObservation ObserveHandle(
            uint processId,
            uint parentProcessId,
            bool parentProcessIdAvailable,
            IntPtr handle,
            bool retained,
            DateTime? knownCreationTime,
            string knownImagePath,
            bool knownJobMembershipAvailable,
            bool knownIsInJob)
        {
            ProcessObservation observation = new ProcessObservation();
            observation.ProcessId = processId;
            observation.ParentProcessId = parentProcessId;
            observation.ParentProcessIdAvailable = parentProcessIdAvailable;
            observation.RetainedHandle = retained;
            observation.ObservationHandleAvailable =
                handle != IntPtr.Zero &&
                handle != NativeMethods.INVALID_HANDLE_VALUE;
            try
            {
                observation.CreationTimeUtc = knownCreationTime.HasValue
                    ? knownCreationTime.Value : QueryCreationTime(handle);
                observation.CreationTimeAvailable = true;
            }
            catch (ProcessControlException) { }
            try
            {
                observation.ImagePath = knownImagePath ?? QueryImagePath(handle);
                observation.ImagePathAvailable = true;
            }
            catch (ProcessControlException) { }
            bool inJob;
            if (NativeMethods.IsProcessInJob(
                    handle, jobHandle.DangerousGetHandle(), out inJob))
            {
                observation.JobMembershipAvailable = true;
                observation.IsInJob = inJob;
            }
            else if (knownJobMembershipAvailable)
            {
                observation.JobMembershipAvailable = true;
                observation.IsInJob = knownIsInJob;
            }
            uint exitCode;
            if (NativeMethods.GetExitCodeProcess(handle, out exitCode))
            {
                observation.ExitStateAvailable = true;
                observation.HasExited = exitCode != NativeMethods.STILL_ACTIVE;
                if (observation.HasExited)
                {
                    observation.ExitCodeAvailable = true;
                    observation.ExitCode = exitCode;
                }
            }
            return observation;
        }

        private uint[] QueryJobProcessIds()
        {
            int capacity = Math.Max(maximumProcesses, 4);
            while (true)
            {
                int size = 8 + (IntPtr.Size * capacity);
                IntPtr buffer = Marshal.AllocHGlobal(size);
                try
                {
                    uint returned;
                    if (!NativeMethods.QueryInformationJobObject(
                            jobHandle.DangerousGetHandle(),
                            NativeMethods.JobObjectBasicProcessIdList,
                            buffer,
                            (uint)size,
                            out returned))
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error == NativeMethods.ERROR_MORE_DATA)
                        {
                            capacity *= 2;
                            if (capacity > 64)
                            {
                                throw new ProcessControlException(
                                    "QueryInformationJobObject",
                                    "Job process membership exceeds the bounded query.",
                                    error, true, true, ProcessId, null);
                            }
                            continue;
                        }
                        ThrowNativeWithCode(
                            "QueryInformationJobObject", error,
                            "Job process membership could not be observed.");
                    }
                    uint assigned = (uint)Marshal.ReadInt32(buffer, 0);
                    uint inList = (uint)Marshal.ReadInt32(buffer, 4);
                    if (assigned > (uint)capacity || inList > (uint)capacity)
                    {
                        capacity = (int)Math.Max(assigned, inList);
                        continue;
                    }
                    uint[] processIds = new uint[inList];
                    for (int index = 0; index < inList; index++)
                    {
                        IntPtr value = Marshal.ReadIntPtr(
                            buffer, 8 + (index * IntPtr.Size));
                        processIds[index] = unchecked((uint)value.ToInt64());
                    }
                    return processIds;
                }
                finally
                {
                    Marshal.FreeHGlobal(buffer);
                }
            }
        }

        private void ThrowIfDisposed()
        {
            if (disposed)
            {
                throw new ObjectDisposedException("ControlledProcess");
            }
        }

        private static void ThrowIfInvalidTimeout(int milliseconds)
        {
            if (milliseconds < 0)
            {
                throw new ArgumentOutOfRangeException("milliseconds");
            }
        }

        private static ProcessObservation ObserveUnavailable(uint processId)
        {
            ProcessObservation observation = new ProcessObservation();
            observation.ProcessId = processId;
            return observation;
        }

        private static SafeKernelHandle CreateConfiguredJob(
            int maxProcesses, out SafeKernelHandle completionPort)
        {
            completionPort = null;
            IntPtr raw = NativeMethods.CreateJobObjectW(IntPtr.Zero, null);
            if (raw == IntPtr.Zero)
            {
                ThrowNative(
                    "CreateJobObjectW", false, false, 0,
                    "The process containment Job Object could not be created.");
            }
            SafeKernelHandle job = new SafeKernelHandle(raw, true);
            IntPtr information = IntPtr.Zero;
            IntPtr associationInformation = IntPtr.Zero;
            try
            {
                IntPtr rawCompletionPort = NativeMethods.CreateIoCompletionPort(
                    NativeMethods.INVALID_HANDLE_VALUE,
                    IntPtr.Zero,
                    UIntPtr.Zero,
                    1);
                if (rawCompletionPort == IntPtr.Zero)
                {
                    ThrowNative(
                        "CreateIoCompletionPort", false, false, 0,
                        "The Job completion port could not be created.");
                }
                completionPort = new SafeKernelHandle(
                    rawCompletionPort, true);
                NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits =
                    new NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                limits.BasicLimitInformation.LimitFlags =
                    NativeMethods.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE |
                    NativeMethods.JOB_OBJECT_LIMIT_ACTIVE_PROCESS;
                limits.BasicLimitInformation.ActiveProcessLimit =
                    (uint)maxProcesses;
                int size = Marshal.SizeOf(
                    typeof(NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
                information = Marshal.AllocHGlobal(size);
                Marshal.StructureToPtr(limits, information, false);
                if (!NativeMethods.SetInformationJobObject(
                        job.DangerousGetHandle(),
                        NativeMethods.JobObjectExtendedLimitInformation,
                        information,
                        (uint)size))
                {
                    ThrowNative(
                        "SetInformationJobObject", false, false, 0,
                        "Kill-on-close/no-breakaway job limits could not be configured.");
                }
                NativeMethods.JOBOBJECT_ASSOCIATE_COMPLETION_PORT association =
                    new NativeMethods.JOBOBJECT_ASSOCIATE_COMPLETION_PORT();
                association.CompletionKey = NativeMethods.JOB_COMPLETION_KEY;
                association.CompletionPort =
                    completionPort.DangerousGetHandle();
                int associationSize = Marshal.SizeOf(
                    typeof(NativeMethods.JOBOBJECT_ASSOCIATE_COMPLETION_PORT));
                associationInformation = Marshal.AllocHGlobal(associationSize);
                Marshal.StructureToPtr(
                    association, associationInformation, false);
                if (!NativeMethods.SetInformationJobObject(
                        job.DangerousGetHandle(),
                        NativeMethods.JobObjectAssociateCompletionPortInformation,
                        associationInformation,
                        (uint)associationSize))
                {
                    ThrowNative(
                        "SetInformationJobObject", false, false, 0,
                        "The Job completion port could not be associated before process creation.");
                }
                return job;
            }
            catch
            {
                job.Dispose();
                if (completionPort != null)
                {
                    completionPort.Dispose();
                    completionPort = null;
                }
                throw;
            }
            finally
            {
                if (information != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(information);
                }
                if (associationInformation != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(associationInformation);
                }
            }
        }

        private static void ConfigureExactInheritedHandleList(
            IntPtr stdinRead,
            IntPtr stdoutWrite,
            IntPtr stderrWrite,
            out IntPtr attributeList,
            out IntPtr inheritedHandleList,
            out bool attributeListInitialized)
        {
            attributeList = IntPtr.Zero;
            inheritedHandleList = IntPtr.Zero;
            attributeListInitialized = false;
            UIntPtr size = UIntPtr.Zero;
            NativeMethods.InitializeProcThreadAttributeList(
                IntPtr.Zero, 1, 0, ref size);
            int firstError = Marshal.GetLastWin32Error();
            if (size == UIntPtr.Zero ||
                firstError != NativeMethods.ERROR_INSUFFICIENT_BUFFER)
            {
                throw new ProcessControlException(
                    "InitializeProcThreadAttributeList",
                    "The exact child handle attribute-list size could not be established. " +
                        new Win32Exception(firstError).Message,
                    firstError,
                    false,
                    false,
                    0,
                    new Win32Exception(firstError));
            }
            attributeList = Marshal.AllocHGlobal(
                checked((int)size.ToUInt64()));
            if (!NativeMethods.InitializeProcThreadAttributeList(
                    attributeList, 1, 0, ref size))
            {
                ThrowNative(
                    "InitializeProcThreadAttributeList", false, false, 0,
                    "The exact child handle attribute list could not be initialized.");
            }
            attributeListInitialized = true;
            inheritedHandleList = Marshal.AllocHGlobal(IntPtr.Size * 3);
            Marshal.WriteIntPtr(
                inheritedHandleList, 0 * IntPtr.Size, stdinRead);
            Marshal.WriteIntPtr(
                inheritedHandleList, 1 * IntPtr.Size, stdoutWrite);
            Marshal.WriteIntPtr(
                inheritedHandleList, 2 * IntPtr.Size, stderrWrite);
            if (!NativeMethods.UpdateProcThreadAttribute(
                    attributeList,
                    0,
                    NativeMethods.PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                    inheritedHandleList,
                    new UIntPtr((uint)(IntPtr.Size * 3)),
                    IntPtr.Zero,
                    IntPtr.Zero))
            {
                ThrowNative(
                    "UpdateProcThreadAttribute", false, false, 0,
                    "The exact stdin/stdout/stderr child handle allow-list could not be installed.");
            }
        }

        private static void CreateAnonymousPipe(
            out IntPtr readHandle,
            out IntPtr writeHandle,
            bool parentReads)
        {
            NativeMethods.SECURITY_ATTRIBUTES security =
                new NativeMethods.SECURITY_ATTRIBUTES();
            security.nLength = Marshal.SizeOf(
                typeof(NativeMethods.SECURITY_ATTRIBUTES));
            security.bInheritHandle = 1;
            security.lpSecurityDescriptor = IntPtr.Zero;
            if (!NativeMethods.CreatePipe(
                    out readHandle, out writeHandle, ref security, 0))
            {
                ThrowNative(
                    "CreatePipe", false, false, 0,
                    "An anonymous child I/O pipe could not be created.");
            }
            IntPtr parentHandle = parentReads ? readHandle : writeHandle;
            if (!NativeMethods.SetHandleInformation(
                    parentHandle, NativeMethods.HANDLE_FLAG_INHERIT, 0))
            {
                CloseRawHandle(ref readHandle);
                CloseRawHandle(ref writeHandle);
                ThrowNative(
                    "SetHandleInformation", false, false, 0,
                    "Parent pipe inheritance could not be disabled.");
            }
        }

        private static IntPtr BuildEnvironmentBlock(
            string[] names, string[] values)
        {
            List<KeyValuePair<string, string>> entries =
                new List<KeyValuePair<string, string>>();
            for (int index = 0; index < names.Length; index++)
            {
                entries.Add(new KeyValuePair<string, string>(
                    names[index], values[index]));
            }
            entries.Sort(delegate(
                KeyValuePair<string, string> left,
                KeyValuePair<string, string> right)
            {
                int comparison = StringComparer.OrdinalIgnoreCase.Compare(
                    left.Key, right.Key);
                if (comparison != 0) { return comparison; }
                return StringComparer.Ordinal.Compare(left.Key, right.Key);
            });
            StringBuilder builder = new StringBuilder();
            foreach (KeyValuePair<string, string> entry in entries)
            {
                builder.Append(entry.Key);
                builder.Append('=');
                builder.Append(entry.Value);
                builder.Append('\0');
            }
            builder.Append('\0');
            return Marshal.StringToHGlobalUni(builder.ToString());
        }

        private static string BuildCommandLine(
            string executablePath, string[] arguments)
        {
            StringBuilder builder = new StringBuilder();
            AppendQuotedArgument(builder, executablePath);
            foreach (string argument in arguments)
            {
                builder.Append(' ');
                AppendQuotedArgument(builder, argument);
            }
            return builder.ToString();
        }

        private static void AppendQuotedArgument(
            StringBuilder builder, string argument)
        {
            builder.Append('"');
            int backslashes = 0;
            foreach (char character in argument)
            {
                if (character == '\\')
                {
                    backslashes++;
                    continue;
                }
                if (character == '"')
                {
                    builder.Append('\\', (backslashes * 2) + 1);
                    builder.Append('"');
                    backslashes = 0;
                    continue;
                }
                if (backslashes > 0)
                {
                    builder.Append('\\', backslashes);
                    backslashes = 0;
                }
                builder.Append(character);
            }
            if (backslashes > 0)
            {
                builder.Append('\\', backslashes * 2);
            }
            builder.Append('"');
        }

        private static bool PathsEqual(string left, string right)
        {
            return String.Equals(
                Path.GetFullPath(left),
                Path.GetFullPath(right),
                StringComparison.OrdinalIgnoreCase);
        }

        private static string QueryImagePath(IntPtr process)
        {
            StringBuilder builder = new StringBuilder(32768);
            uint length = (uint)builder.Capacity;
            if (!NativeMethods.QueryFullProcessImageNameW(
                    process, 0, builder, ref length))
            {
                ThrowNative(
                    "QueryFullProcessImageNameW", true, true, 0,
                    "The exact process image path could not be observed.");
            }
            return Path.GetFullPath(builder.ToString());
        }

        private static DateTime QueryCreationTime(IntPtr process)
        {
            NativeMethods.FILETIME creation;
            NativeMethods.FILETIME exit;
            NativeMethods.FILETIME kernel;
            NativeMethods.FILETIME user;
            if (!NativeMethods.GetProcessTimes(
                    process, out creation, out exit, out kernel, out user))
            {
                ThrowNative(
                    "GetProcessTimes", true, true, 0,
                    "The process creation time could not be observed.");
            }
            long value = ((long)creation.dwHighDateTime << 32) |
                (uint)creation.dwLowDateTime;
            return DateTime.FromFileTimeUtc(value);
        }

        private static uint QueryParentProcessId(uint processId)
        {
            Dictionary<uint, uint> parents = QueryProcessParents();
            return parents.ContainsKey(processId) ? parents[processId] : 0;
        }

        private static Dictionary<uint, uint> QueryProcessParents()
        {
            Dictionary<uint, uint> result = new Dictionary<uint, uint>();
            IntPtr snapshot = NativeMethods.CreateToolhelp32Snapshot(
                NativeMethods.TH32CS_SNAPPROCESS, 0);
            if (snapshot == NativeMethods.INVALID_HANDLE_VALUE)
            {
                ThrowNative(
                    "CreateToolhelp32Snapshot", true, true, 0,
                    "The process topology snapshot could not be created.");
            }
            try
            {
                NativeMethods.PROCESSENTRY32 entry =
                    new NativeMethods.PROCESSENTRY32();
                entry.dwSize = (uint)Marshal.SizeOf(
                    typeof(NativeMethods.PROCESSENTRY32));
                if (!NativeMethods.Process32FirstW(snapshot, ref entry))
                {
                    ThrowNative(
                        "Process32FirstW", true, true, 0,
                        "The process topology snapshot could not be read.");
                }
                do
                {
                    result[entry.th32ProcessID] = entry.th32ParentProcessID;
                    entry.dwSize = (uint)Marshal.SizeOf(
                        typeof(NativeMethods.PROCESSENTRY32));
                }
                while (NativeMethods.Process32NextW(snapshot, ref entry));
            }
            finally
            {
                NativeMethods.CloseHandle(snapshot);
            }
            return result;
        }

        private static SafeKernelHandle OpenObservationHandle(uint processId)
        {
            IntPtr handle = NativeMethods.OpenProcess(
                NativeMethods.PROCESS_QUERY_LIMITED_INFORMATION |
                    NativeMethods.SYNCHRONIZE,
                false,
                processId);
            if (handle == IntPtr.Zero) { return null; }
            return new SafeKernelHandle(handle, true);
        }

        private static void TerminateFailedCreation(
            SafeKernelHandle job, SafeKernelHandle process)
        {
            if (job != null && !job.IsInvalid)
            {
                NativeMethods.TerminateJobObject(
                    job.DangerousGetHandle(), 0xE0000001U);
            }
            if (process != null && !process.IsInvalid)
            {
                NativeMethods.TerminateProcess(
                    process.DangerousGetHandle(), 0xE0000001U);
            }
            if (process != null && !process.IsInvalid)
            {
                NativeMethods.WaitForSingleObject(
                    process.DangerousGetHandle(), 5000);
            }
        }

        private static void CloseRawHandle(ref IntPtr handle)
        {
            if (handle != IntPtr.Zero &&
                handle != NativeMethods.INVALID_HANDLE_VALUE)
            {
                NativeMethods.CloseHandle(handle);
                handle = IntPtr.Zero;
            }
        }

        private static void ThrowNative(
            string operation,
            bool attempted,
            bool created,
            uint processId,
            string message)
        {
            int error = Marshal.GetLastWin32Error();
            throw new ProcessControlException(
                operation,
                message + " " + new Win32Exception(error).Message,
                error,
                attempted,
                created,
                processId,
                new Win32Exception(error));
        }

        private static void ThrowNativeWithCode(
            string operation, int error, string message)
        {
            throw new ProcessControlException(
                operation,
                message + " " + new Win32Exception(error).Message,
                error,
                true,
                true,
                0,
                new Win32Exception(error));
        }
    }

    internal static class NativeMethods
    {
        internal const uint CREATE_SUSPENDED = 0x00000004;
        internal const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        internal const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
        internal const uint STARTF_USESTDHANDLES = 0x00000100;
        internal const uint HANDLE_FLAG_INHERIT = 0x00000001;
        internal const uint JOB_OBJECT_LIMIT_ACTIVE_PROCESS = 0x00000008;
        internal const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        internal const int JobObjectBasicProcessIdList = 3;
        internal const int JobObjectAssociateCompletionPortInformation = 7;
        internal const int JobObjectExtendedLimitInformation = 9;
        internal const uint JOB_OBJECT_MSG_ACTIVE_PROCESS_LIMIT = 3;
        internal const uint JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO = 4;
        internal const uint JOB_OBJECT_MSG_NEW_PROCESS = 6;
        internal const uint JOB_OBJECT_MSG_EXIT_PROCESS = 7;
        internal const uint JOB_OBJECT_MSG_ABNORMAL_EXIT_PROCESS = 8;
        internal const uint JOB_OBJECT_MSG_COMPLETION_PORT_FAILURE =
            0xffffffff;
        internal const uint WAIT_OBJECT_0 = 0x00000000;
        internal const uint WAIT_TIMEOUT = 0x00000102;
        internal const uint STILL_ACTIVE = 259;
        internal const int ERROR_MORE_DATA = 234;
        internal const int ERROR_INSUFFICIENT_BUFFER = 122;
        internal const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x00001000;
        internal const uint SYNCHRONIZE = 0x00100000;
        internal const uint TH32CS_SNAPPROCESS = 0x00000002;
        internal const uint WM_CLOSE = 0x0010;
        internal static readonly IntPtr INVALID_HANDLE_VALUE =
            new IntPtr(-1);
        internal static readonly UIntPtr JOB_COMPLETION_KEY =
            new UIntPtr(0x5331454aU);
        internal static readonly UIntPtr SHUTDOWN_COMPLETION_KEY =
            new UIntPtr(0x53314553U);
        internal static readonly UIntPtr PROC_THREAD_ATTRIBUTE_HANDLE_LIST =
            new UIntPtr(0x00020002U);

        [StructLayout(LayoutKind.Sequential)]
        internal struct SECURITY_ATTRIBUTES
        {
            internal int nLength;
            internal IntPtr lpSecurityDescriptor;
            internal int bInheritHandle;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        internal struct STARTUPINFO
        {
            internal int cb;
            internal string lpReserved;
            internal string lpDesktop;
            internal string lpTitle;
            internal uint dwX;
            internal uint dwY;
            internal uint dwXSize;
            internal uint dwYSize;
            internal uint dwXCountChars;
            internal uint dwYCountChars;
            internal uint dwFillAttribute;
            internal uint dwFlags;
            internal short wShowWindow;
            internal short cbReserved2;
            internal IntPtr lpReserved2;
            internal IntPtr hStdInput;
            internal IntPtr hStdOutput;
            internal IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct STARTUPINFOEX
        {
            internal STARTUPINFO StartupInfo;
            internal IntPtr lpAttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct PROCESS_INFORMATION
        {
            internal IntPtr hProcess;
            internal IntPtr hThread;
            internal uint dwProcessId;
            internal uint dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            internal long PerProcessUserTimeLimit;
            internal long PerJobUserTimeLimit;
            internal uint LimitFlags;
            internal UIntPtr MinimumWorkingSetSize;
            internal UIntPtr MaximumWorkingSetSize;
            internal uint ActiveProcessLimit;
            internal UIntPtr Affinity;
            internal uint PriorityClass;
            internal uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct IO_COUNTERS
        {
            internal ulong ReadOperationCount;
            internal ulong WriteOperationCount;
            internal ulong OtherOperationCount;
            internal ulong ReadTransferCount;
            internal ulong WriteTransferCount;
            internal ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            internal JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            internal IO_COUNTERS IoInfo;
            internal UIntPtr ProcessMemoryLimit;
            internal UIntPtr JobMemoryLimit;
            internal UIntPtr PeakProcessMemoryUsed;
            internal UIntPtr PeakJobMemoryUsed;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct JOBOBJECT_ASSOCIATE_COMPLETION_PORT
        {
            internal UIntPtr CompletionKey;
            internal IntPtr CompletionPort;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct FILETIME
        {
            internal uint dwLowDateTime;
            internal uint dwHighDateTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        internal struct PROCESSENTRY32
        {
            internal uint dwSize;
            internal uint cntUsage;
            internal uint th32ProcessID;
            internal IntPtr th32DefaultHeapID;
            internal uint th32ModuleID;
            internal uint cntThreads;
            internal uint th32ParentProcessID;
            internal int pcPriClassBase;
            internal uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            internal string szExeFile;
        }

        internal delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        internal static extern IntPtr CreateJobObjectW(
            IntPtr jobAttributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            uint informationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool QueryInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            uint informationLength,
            out uint returnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool AssignProcessToJobObject(
            IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsProcessInJob(
            IntPtr process, IntPtr job, out bool result);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool TerminateJobObject(
            IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CreateProcessW(
            string applicationName,
            StringBuilder commandLine,
            IntPtr processAttributes,
            IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags,
            IntPtr environment,
            string currentDirectory,
            ref STARTUPINFOEX startupInfo,
            out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool InitializeProcThreadAttributeList(
            IntPtr attributeList,
            int attributeCount,
            int flags,
            ref UIntPtr size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UpdateProcThreadAttribute(
            IntPtr attributeList,
            uint flags,
            UIntPtr attribute,
            IntPtr value,
            UIntPtr size,
            IntPtr previousValue,
            IntPtr returnSize);

        [DllImport("kernel32.dll")]
        internal static extern void DeleteProcThreadAttributeList(
            IntPtr attributeList);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern IntPtr CreateIoCompletionPort(
            IntPtr fileHandle,
            IntPtr existingCompletionPort,
            UIntPtr completionKey,
            uint numberOfConcurrentThreads);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetQueuedCompletionStatus(
            IntPtr completionPort,
            out uint numberOfBytesTransferred,
            out UIntPtr completionKey,
            out IntPtr overlapped,
            uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PostQueuedCompletionStatus(
            IntPtr completionPort,
            uint numberOfBytesTransferred,
            UIntPtr completionKey,
            IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern uint WaitForSingleObject(
            IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetExitCodeProcess(
            IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetProcessTimes(
            IntPtr process,
            out FILETIME creation,
            out FILETIME exit,
            out FILETIME kernel,
            out FILETIME user);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool QueryFullProcessImageNameW(
            IntPtr process,
            uint flags,
            StringBuilder executableName,
            ref uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern IntPtr OpenProcess(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
            uint processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool TerminateProcess(
            IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CreatePipe(
            out IntPtr readPipe,
            out IntPtr writePipe,
            ref SECURITY_ATTRIBUTES pipeAttributes,
            uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetHandleInformation(
            IntPtr handle, uint mask, uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern IntPtr CreateToolhelp32Snapshot(
            uint flags, uint processId);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool Process32FirstW(
            IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool Process32NextW(
            IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnumWindows(
            EnumWindowsProc callback, IntPtr parameter);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern uint GetWindowThreadProcessId(
            IntPtr window, out uint processId);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PostMessageW(
            IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    }
}
