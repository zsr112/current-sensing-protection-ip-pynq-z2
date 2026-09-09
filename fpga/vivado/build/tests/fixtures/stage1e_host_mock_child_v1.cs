using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Stage1E.Runtime.Tests.HostFixture.V1
{
    internal static class Program
    {
        private static readonly ManualResetEvent WindowReady =
            new ManualResetEvent(false);
        private static readonly ManualResetEvent WindowClosed =
            new ManualResetEvent(false);
        private static NativeMethods.WindowProcedure windowProcedure;

        private static int Main(string[] arguments)
        {
            if (arguments.Length < 1)
            {
                Console.Error.WriteLine("fixture_mode_missing");
                return 64;
            }
            try
            {
                switch (arguments[0])
                {
                    case "normal":
                        Console.WriteLine("fixture_normal_stdout");
                        Console.Error.WriteLine("fixture_normal_stderr");
                        return 0;
                    case "nonzero":
                        Console.WriteLine("fixture_nonzero_stdout");
                        Console.Error.WriteLine("fixture_nonzero_stderr");
                        return ParseInt(arguments, 1, 17);
                    case "long":
                    case "forced":
                        Thread.Sleep(ParseInt(arguments, 1, 60000));
                        return 0;
                    case "output":
                        return EmitOutput(ParseInt(arguments, 1, 2048));
                    case "heartbeat":
                        return EmitHeartbeats(arguments, false);
                    case "silence":
                        return EmitHeartbeats(arguments, true);
                    case "heartbeat-partial-complete":
                        return EmitPartialThenCompleteHeartbeat(arguments);
                    case "heartbeat-terminal-partial":
                        return EmitTerminalPartialHeartbeat(arguments);
                    case "heartbeat-mutation":
                        return EmitMutatedHeartbeat(arguments);
                    case "heartbeat-final-lf":
                        return EmitFinalLfHeartbeat(arguments);
                    case "descendant-parent":
                    case "fast-descendant-parent":
                    case "fast-undeclared-parent":
                        return RunDescendant(arguments);
                    case "active-limit-parent":
                        return AttemptActiveProcessLimit(arguments);
                    case "descendant-child":
                        Thread.Sleep(ParseInt(arguments, 1, 500));
                        return 0;
                    case "graceful":
                        return RunGracefulWindow(
                            ParseInt(arguments, 1, 60000));
                    case "cwd-env":
                        return ReportCwdAndEnvironment(arguments);
                    case "arguments":
                        return ReportArguments(arguments);
                    case "breakaway":
                        return AttemptBreakaway(arguments);
                    case "handle-sentinel":
                        return VerifyInheritedHandles(arguments);
                    default:
                        Console.Error.WriteLine(
                            "fixture_mode_unknown=" + arguments[0]);
                        return 65;
                }
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(
                    "fixture_exception=" + exception.GetType().FullName +
                    ":" + exception.Message);
                return 70;
            }
        }

        private static int EmitOutput(int lineCount)
        {
            string payload = new string('x', 256);
            for (int index = 0; index < lineCount; index++)
            {
                Console.Out.WriteLine(
                    "stdout_{0:D6}_{1}", index, payload);
                Console.Error.WriteLine(
                    "stderr_{0:D6}_{1}", index, payload);
            }
            return 0;
        }

        private static int EmitHeartbeats(
            string[] arguments, bool silenceAfterStartup)
        {
            if (arguments.Length < 7)
            {
                throw new ArgumentException(
                    "heartbeat mode needs path, execution, attempt, count, interval, exit code");
            }
            string path = arguments[1];
            string execution = arguments[2];
            string attempt = arguments[3];
            int count = Int32.Parse(arguments[4], CultureInfo.InvariantCulture);
            int interval = Int32.Parse(arguments[5], CultureInfo.InvariantCulture);
            int exitCode = Int32.Parse(arguments[6], CultureInfo.InvariantCulture);
            AppendHeartbeat(path, execution, attempt, 1, "STARTUP");
            if (silenceAfterStartup)
            {
                Thread.Sleep(Math.Max(interval, 1));
                return exitCode;
            }
            for (int sequence = 2; sequence <= count; sequence++)
            {
                Thread.Sleep(interval);
                AppendHeartbeat(
                    path, execution, attempt, sequence, "HEARTBEAT");
            }
            return exitCode;
        }

        private static void AppendHeartbeat(
            string path,
            string execution,
            string attempt,
            int sequence,
            string eventClass)
        {
            string line = BuildHeartbeatLine(
                execution, attempt, sequence, eventClass);
            AppendSharedText(path, line);
        }

        private static string BuildHeartbeatLine(
            string execution,
            string attempt,
            int sequence,
            string eventClass)
        {
            int pid = Process.GetCurrentProcess().Id;
            string authority =
                "{\"qualification_decision\":\"NONE\"," +
                "\"authorization_issue\":\"NONE\"," +
                "\"authorization_consumption\":\"NOT_OWNED\"," +
                "\"engineering_acceptance\":\"NONE\"," +
                "\"bitstream_xsa_generation\":\"NONE\"," +
                "\"artifact_collection\":\"NONE\"," +
                "\"publication\":\"NONE\"," +
                "\"hardware_manager\":\"NONE\"," +
                "\"board_access\":\"NONE\"}";
            return
                "{\"schema_version\":\"stage1e-runtime-host-heartbeat-event-v1\"," +
                "\"execution_id\":\"" + EscapeJson(execution) + "\"," +
                "\"attempt_id\":\"" + EscapeJson(attempt) + "\"," +
                "\"sequence\":" + sequence.ToString(
                    CultureInfo.InvariantCulture) + "," +
                "\"emitter_role\":\"ROOT_PROCESS\"," +
                "\"emitter_pid\":" + pid.ToString(
                    CultureInfo.InvariantCulture) + "," +
                "\"event_class\":\"" + eventClass + "\"," +
                "\"phase\":\"HOST_FIXTURE\"," +
                "\"emitter_time_utc\":\"" + DateTime.UtcNow.ToString(
                    "o", CultureInfo.InvariantCulture) + "\"," +
                "\"telemetry_authority\":\"NONE\"," +
                "\"authority_boundary\":" + authority + "}\n";
        }

        private static void AppendSharedText(string path, string value)
        {
            string line = value;
            byte[] bytes = new UTF8Encoding(false, true).GetBytes(line);
            using (FileStream stream = new FileStream(
                path,
                FileMode.Append,
                FileAccess.Write,
                FileShare.Read,
                4096,
                FileOptions.WriteThrough))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush(true);
            }
        }

        private static int EmitPartialThenCompleteHeartbeat(string[] arguments)
        {
            RequireHeartbeatArguments(arguments, 5);
            string line = BuildHeartbeatLine(
                arguments[2], arguments[3], 1, "STARTUP");
            int split = Math.Max(1, line.Length - 17);
            AppendSharedText(arguments[1], line.Substring(0, split));
            Thread.Sleep(ParseInt(arguments, 4, 250));
            AppendSharedText(arguments[1], line.Substring(split));
            Thread.Sleep(100);
            return 0;
        }

        private static int EmitTerminalPartialHeartbeat(string[] arguments)
        {
            RequireHeartbeatArguments(arguments, 4);
            string line = BuildHeartbeatLine(
                arguments[2], arguments[3], 1, "STARTUP");
            AppendSharedText(arguments[1], line.Substring(0, line.Length - 7));
            return 0;
        }

        private static int EmitMutatedHeartbeat(string[] arguments)
        {
            RequireHeartbeatArguments(arguments, 5);
            string line = BuildHeartbeatLine(
                arguments[2], arguments[3], 1, "STARTUP");
            AppendSharedText(arguments[1], line);
            Thread.Sleep(ParseInt(arguments, 4, 200));
            using (FileStream stream = new FileStream(
                arguments[1], FileMode.Open, FileAccess.ReadWrite,
                FileShare.Read, 4096, FileOptions.WriteThrough))
            {
                stream.Position = 2;
                int prior = stream.ReadByte();
                stream.Position = 2;
                stream.WriteByte((byte)(prior == (int)'s' ? 't' : 's'));
                stream.Flush(true);
            }
            Thread.Sleep(300);
            return 0;
        }

        private static int EmitFinalLfHeartbeat(string[] arguments)
        {
            RequireHeartbeatArguments(arguments, 5);
            Thread.Sleep(ParseInt(arguments, 4, 100));
            AppendHeartbeat(
                arguments[1], arguments[2], arguments[3], 1, "STARTUP");
            return 0;
        }

        private static void RequireHeartbeatArguments(
            string[] arguments, int minimumLength)
        {
            if (arguments.Length < minimumLength)
            {
                throw new ArgumentException(
                    "heartbeat test mode arguments are incomplete");
            }
        }

        private static int RunDescendant(string[] arguments)
        {
            int duration = ParseInt(arguments, 1, 1000);
            string executable = Process.GetCurrentProcess().MainModule.FileName;
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = executable;
            startInfo.Arguments = QuoteWindowsArgument("descendant-child") +
                " " + QuoteWindowsArgument(duration.ToString(
                    CultureInfo.InvariantCulture));
            startInfo.WorkingDirectory = Environment.CurrentDirectory;
            startInfo.UseShellExecute = false;
            Process child = Process.Start(startInfo);
            Console.WriteLine("fixture_descendant_pid=" + child.Id.ToString(
                CultureInfo.InvariantCulture));
            child.WaitForExit();
            return child.ExitCode;
        }

        private static int AttemptActiveProcessLimit(string[] arguments)
        {
            try
            {
                RunDescendant(new string[] {
                    "descendant-parent",
                    ParseInt(arguments, 1, 0).ToString(
                        CultureInfo.InvariantCulture)
                });
                Console.Error.WriteLine("active_limit_not_enforced=1");
                return 92;
            }
            catch (Exception exception)
            {
                Console.WriteLine(
                    "active_limit_blocked=" + exception.GetType().FullName);
                Thread.Sleep(200);
                return 0;
            }
        }

        private static int VerifyInheritedHandles(string[] arguments)
        {
            if (arguments.Length < 2)
            {
                throw new ArgumentException("sentinel handle value is missing");
            }
            long value = Int64.Parse(arguments[1], CultureInfo.InvariantCulture);
            NativeMethods.SetLastError(0);
            uint sentinelType = NativeMethods.GetFileType(new IntPtr(value));
            int sentinelError = Marshal.GetLastWin32Error();
            bool sentinelInvalid = sentinelType == NativeMethods.FILE_TYPE_UNKNOWN &&
                sentinelError == NativeMethods.ERROR_INVALID_HANDLE;
            IntPtr stdin = NativeMethods.GetStdHandle(
                NativeMethods.STD_INPUT_HANDLE);
            IntPtr stdout = NativeMethods.GetStdHandle(
                NativeMethods.STD_OUTPUT_HANDLE);
            IntPtr stderr = NativeMethods.GetStdHandle(
                NativeMethods.STD_ERROR_HANDLE);
            bool stdinValid = IsValidFileHandle(stdin);
            bool stdoutValid = IsValidFileHandle(stdout);
            bool stderrValid = IsValidFileHandle(stderr);
            int stdinValue = Console.In.Read();
            Console.WriteLine("sentinel_invalid=" +
                (sentinelInvalid ? "1" : "0"));
            Console.WriteLine("stdin_valid=" + (stdinValid ? "1" : "0"));
            Console.WriteLine("stdin_eof=" + (stdinValue == -1 ? "1" : "0"));
            Console.WriteLine("stdout_valid=" + (stdoutValid ? "1" : "0"));
            Console.Error.WriteLine(
                "stderr_valid=" + (stderrValid ? "1" : "0"));
            return sentinelInvalid && stdinValid && stdoutValid && stderrValid &&
                stdinValue == -1 ? 0 : 93;
        }

        private static bool IsValidFileHandle(IntPtr handle)
        {
            if (handle == IntPtr.Zero ||
                handle == NativeMethods.INVALID_HANDLE_VALUE)
            {
                return false;
            }
            NativeMethods.SetLastError(0);
            uint fileType = NativeMethods.GetFileType(handle);
            return fileType != NativeMethods.FILE_TYPE_UNKNOWN ||
                Marshal.GetLastWin32Error() != NativeMethods.ERROR_INVALID_HANDLE;
        }

        private static int RunGracefulWindow(int maximumMilliseconds)
        {
            Thread thread = new Thread(WindowThread);
            thread.IsBackground = true;
            thread.Start();
            if (!WindowReady.WaitOne(5000))
            {
                Console.Error.WriteLine("fixture_window_not_ready");
                return 71;
            }
            Console.WriteLine("fixture_window_ready=1");
            if (!WindowClosed.WaitOne(maximumMilliseconds))
            {
                Console.Error.WriteLine("fixture_window_close_timeout");
                return 72;
            }
            thread.Join(5000);
            Console.WriteLine("fixture_window_closed=1");
            return 0;
        }

        private static void WindowThread()
        {
            windowProcedure = WindowCallback;
            string className = "Stage1EHostFixtureWindowV1";
            NativeMethods.WNDCLASS windowClass = new NativeMethods.WNDCLASS();
            windowClass.lpfnWndProc = windowProcedure;
            windowClass.hInstance = NativeMethods.GetModuleHandleW(null);
            windowClass.lpszClassName = className;
            ushort atom = NativeMethods.RegisterClassW(ref windowClass);
            if (atom == 0)
            {
                WindowReady.Set();
                return;
            }
            IntPtr window = NativeMethods.CreateWindowExW(
                0,
                className,
                "Stage1E Host Fixture",
                0,
                0,
                0,
                100,
                100,
                IntPtr.Zero,
                IntPtr.Zero,
                windowClass.hInstance,
                IntPtr.Zero);
            WindowReady.Set();
            if (window == IntPtr.Zero) { return; }
            NativeMethods.MSG message;
            while (NativeMethods.GetMessageW(
                out message, IntPtr.Zero, 0, 0) > 0)
            {
                NativeMethods.TranslateMessage(ref message);
                NativeMethods.DispatchMessageW(ref message);
            }
        }

        private static IntPtr WindowCallback(
            IntPtr window, uint message, IntPtr wParam, IntPtr lParam)
        {
            if (message == NativeMethods.WM_CLOSE)
            {
                NativeMethods.DestroyWindow(window);
                return IntPtr.Zero;
            }
            if (message == NativeMethods.WM_DESTROY)
            {
                WindowClosed.Set();
                NativeMethods.PostQuitMessage(0);
                return IntPtr.Zero;
            }
            return NativeMethods.DefWindowProcW(
                window, message, wParam, lParam);
        }

        private static int ReportCwdAndEnvironment(string[] arguments)
        {
            Console.WriteLine("cwd=" + Environment.CurrentDirectory);
            List<string> names = new List<string>();
            foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
            {
                names.Add((string)entry.Key);
            }
            names.Sort(StringComparer.OrdinalIgnoreCase);
            Console.WriteLine("environment_count=" + names.Count.ToString(
                CultureInfo.InvariantCulture));
            Console.WriteLine("environment_names=" + String.Join(",", names.ToArray()));
            foreach (string name in names)
            {
                Console.WriteLine(
                    "environment_" + name + "=" +
                    Environment.GetEnvironmentVariable(name));
            }
            return 0;
        }

        private static int ReportArguments(string[] arguments)
        {
            for (int index = 1; index < arguments.Length; index++)
            {
                Console.WriteLine(
                    "argument_{0:D3}={1}", index - 1, arguments[index]);
            }
            return 0;
        }

        private static int AttemptBreakaway(string[] arguments)
        {
            string executable = Process.GetCurrentProcess().MainModule.FileName;
            string commandLine = QuoteWindowsArgument(executable) + " " +
                QuoteWindowsArgument("descendant-child") + " " +
                QuoteWindowsArgument("10000");
            NativeMethods.STARTUPINFO startup = new NativeMethods.STARTUPINFO();
            startup.cb = Marshal.SizeOf(typeof(NativeMethods.STARTUPINFO));
            NativeMethods.PROCESS_INFORMATION processInformation;
            bool created = NativeMethods.CreateProcessW(
                executable,
                new StringBuilder(commandLine),
                IntPtr.Zero,
                IntPtr.Zero,
                false,
                NativeMethods.CREATE_BREAKAWAY_FROM_JOB,
                IntPtr.Zero,
                Environment.CurrentDirectory,
                ref startup,
                out processInformation);
            if (!created)
            {
                Console.WriteLine("breakaway_blocked=" +
                    Marshal.GetLastWin32Error().ToString(
                        CultureInfo.InvariantCulture));
                return 0;
            }
            try
            {
                NativeMethods.TerminateProcess(
                    processInformation.hProcess, 0xE0000003U);
                NativeMethods.WaitForSingleObject(
                    processInformation.hProcess, 5000);
            }
            finally
            {
                NativeMethods.CloseHandle(processInformation.hThread);
                NativeMethods.CloseHandle(processInformation.hProcess);
            }
            Console.Error.WriteLine("breakaway_unexpectedly_succeeded=1");
            return 91;
        }

        private static string EscapeJson(string value)
        {
            StringBuilder builder = new StringBuilder();
            foreach (char character in value)
            {
                switch (character)
                {
                    case '"': builder.Append("\\\""); break;
                    case '\\': builder.Append("\\\\"); break;
                    case '\b': builder.Append("\\b"); break;
                    case '\f': builder.Append("\\f"); break;
                    case '\n': builder.Append("\\n"); break;
                    case '\r': builder.Append("\\r"); break;
                    case '\t': builder.Append("\\t"); break;
                    default:
                        if (character < 0x20)
                        {
                            builder.Append("\\u");
                            builder.Append(((int)character).ToString(
                                "x4", CultureInfo.InvariantCulture));
                        }
                        else { builder.Append(character); }
                        break;
                }
            }
            return builder.ToString();
        }

        private static string QuoteWindowsArgument(string value)
        {
            StringBuilder builder = new StringBuilder();
            builder.Append('"');
            int backslashes = 0;
            foreach (char character in value)
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
            return builder.ToString();
        }

        private static int ParseInt(
            string[] arguments, int index, int defaultValue)
        {
            if (arguments.Length <= index) { return defaultValue; }
            return Int32.Parse(arguments[index], CultureInfo.InvariantCulture);
        }
    }

    internal static class NativeMethods
    {
        internal const uint WM_CLOSE = 0x0010;
        internal const uint WM_DESTROY = 0x0002;
        internal const uint CREATE_BREAKAWAY_FROM_JOB = 0x01000000;
        internal const int STD_INPUT_HANDLE = -10;
        internal const int STD_OUTPUT_HANDLE = -11;
        internal const int STD_ERROR_HANDLE = -12;
        internal const uint FILE_TYPE_UNKNOWN = 0x0000;
        internal const int ERROR_INVALID_HANDLE = 6;
        internal static readonly IntPtr INVALID_HANDLE_VALUE =
            new IntPtr(-1);

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        internal delegate IntPtr WindowProcedure(
            IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        internal struct WNDCLASS
        {
            internal uint style;
            internal WindowProcedure lpfnWndProc;
            internal int cbClsExtra;
            internal int cbWndExtra;
            internal IntPtr hInstance;
            internal IntPtr hIcon;
            internal IntPtr hCursor;
            internal IntPtr hbrBackground;
            internal string lpszMenuName;
            internal string lpszClassName;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct POINT
        {
            internal int x;
            internal int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct MSG
        {
            internal IntPtr hwnd;
            internal uint message;
            internal UIntPtr wParam;
            internal IntPtr lParam;
            internal uint time;
            internal POINT point;
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
        internal struct PROCESS_INFORMATION
        {
            internal IntPtr hProcess;
            internal IntPtr hThread;
            internal uint dwProcessId;
            internal uint dwThreadId;
        }

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        internal static extern ushort RegisterClassW(ref WNDCLASS windowClass);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        internal static extern IntPtr CreateWindowExW(
            uint extendedStyle,
            string className,
            string windowName,
            uint style,
            int x,
            int y,
            int width,
            int height,
            IntPtr parent,
            IntPtr menu,
            IntPtr instance,
            IntPtr parameter);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern int GetMessageW(
            out MSG message, IntPtr window, uint minimum, uint maximum);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool TranslateMessage(ref MSG message);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        internal static extern IntPtr DispatchMessageW(ref MSG message);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        internal static extern IntPtr DefWindowProcW(
            IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool DestroyWindow(IntPtr window);

        [DllImport("user32.dll")]
        internal static extern void PostQuitMessage(int exitCode);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        internal static extern IntPtr GetModuleHandleW(string moduleName);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern IntPtr GetStdHandle(int standardHandle);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern uint GetFileType(IntPtr handle);

        [DllImport("kernel32.dll")]
        internal static extern void SetLastError(uint errorCode);

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
            ref STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool TerminateProcess(
            IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern uint WaitForSingleObject(
            IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CloseHandle(IntPtr handle);
    }
}
