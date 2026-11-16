using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace CodexAccountSwitcher.Core;

internal static class DesktopProcessTree
{
    // Capture only descendants of the already matched Desktop processes. A separately
    // launched CLI may use the same codex.exe as Desktop's app-server and must survive.
    internal static void IncludeDescendants(List<Process> processes)
    {
        foreach (var process in processes)
        {
            try { if (!process.HasExited) _ = process.Handle; }
            catch (InvalidOperationException) when (process.HasExited) { }
            catch (Win32Exception) when (process.HasExited) { }
        }
        var children = ReadParentProcessIds().ToLookup(pair => pair.Parent, pair => pair.Id);
        var included = processes.Select(process => process.Id).ToHashSet();
        for (var index = 0; index < processes.Count; index++)
        {
            var parent = processes[index];
            if (parent.Id == Environment.ProcessId)
                throw new IOException("Codex Desktop contains the switcher process. Close Desktop manually before switching; the account was not changed.");
            if (parent.HasExited) continue;
            var parentStarted = parent.StartTime;
            foreach (var id in children[parent.Id])
            {
                if (included.Contains(id)) continue;
                Process? child = null;
                try
                {
                    child = Process.GetProcessById(id);
                    _ = child.Handle; // Pin the process identity until close and exit verification finish.
                    // Parent PIDs in a snapshot can refer to an older process with a reused PID.
                    if (child.HasExited || child.StartTime < parentStarted) continue;
                    processes.Add(child);
                    included.Add(id);
                    child = null;
                }
                catch (ArgumentException) { } // Exited before opening a handle.
                catch (InvalidOperationException) when (child?.HasExited == true) { }
                catch (Win32Exception) when (child?.HasExited == true) { }
                finally { child?.Dispose(); }
            }
        }
    }

    private static List<(int Id, int Parent)> ReadParentProcessIds()
    {
        using var snapshot = CreateToolhelp32Snapshot(2 /* TH32CS_SNAPPROCESS */, 0);
        if (snapshot.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf<ProcessEntry>() };
        var result = new List<(int, int)>();
        if (!Process32FirstW(snapshot, ref entry)) throw new Win32Exception(Marshal.GetLastWin32Error());
        do { result.Add(((int)entry.ProcessId, (int)entry.ParentProcessId)); }
        while (Process32NextW(snapshot, ref entry));
        var error = Marshal.GetLastWin32Error();
        if (error != 18 /* ERROR_NO_MORE_FILES */) throw new Win32Exception(error);
        return result;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ProcessEntry
    {
        internal uint Size, Usage, ProcessId;
        internal UIntPtr DefaultHeapId;
        internal uint ModuleId, Threads, ParentProcessId;
        internal int BasePriority;
        internal uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] internal string? Executable;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeFileHandle CreateToolhelp32Snapshot(uint flags, uint processId);
    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32FirstW(SafeFileHandle snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32NextW(SafeFileHandle snapshot, ref ProcessEntry entry);
}
