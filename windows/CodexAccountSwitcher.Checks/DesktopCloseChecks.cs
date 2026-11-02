using System.Diagnostics;
using System.Runtime.InteropServices;
using CodexAccountSwitcher.Core;

internal static class DesktopCloseChecks
{
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();

    public static async Task<int> RunAsync(string fixtureExecutable)
    {
        var root = Path.Combine(Path.GetTempPath(), "codex-desktop-close-check-" + Guid.NewGuid().ToString("N"));
        var oldExecutable = Path.Combine(root, "OpenAI.Codex_1.0.0.0_x64__fixture", "app", "ChatGPT.exe");
        var newExecutable = Path.Combine(root, "OpenAI.Codex_2.0.0.0_x64__fixture", "app", "ChatGPT.exe");
        Directory.CreateDirectory(Path.GetDirectoryName(oldExecutable)!);
        Directory.CreateDirectory(Path.GetDirectoryName(newExecutable)!);
        try
        {
            await VerifyRunningPackageIdentityAsync();
            CopyFixture(fixtureExecutable, Path.GetDirectoryName(oldExecutable)!);
            CopyFixture(fixtureExecutable, Path.GetDirectoryName(newExecutable)!);
            var installedVersion = 1;
            var discoveryCount = 0;
            var controller = new DesktopController(cancellationToken =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                discoveryCount++;
                return Task.FromResult(new DesktopInstallation(installedVersion == 1 ? oldExecutable : newExecutable));
            });

            Prepare(oldExecutable);
            await controller.OpenAsync(CancellationToken.None);
            await WaitUntilReadyAsync(oldExecutable);
            await controller.CloseAsync(CancellationToken.None);
            Require(!IsRunning(oldExecutable), "The version 1 fixture should be terminated.");
            Require(ReadEvents(oldExecutable).SequenceEqual(["ready"]), "Termination must bypass window-close-to-tray behavior.");

            installedVersion = 2;
            Prepare(newExecutable);
            await controller.OpenAsync(CancellationToken.None);
            await WaitUntilReadyAsync(newExecutable);
            var staleController = new DesktopController(_ => Task.FromResult(new DesktopInstallation(oldExecutable)));
            await staleController.CloseAsync(CancellationToken.None);
            Require(IsRunning(newExecutable), "An old package path must not terminate a process at the updated path.");
            await controller.CloseAsync(CancellationToken.None);
            Require(!IsRunning(newExecutable), "The refreshed package path should close the updated fixture.");
            Require(discoveryCount == 4, "Each open and close operation should discover the current package path.");
            Console.WriteLine("PASS: visible Desktop exits; each open and close rediscovers the Store path.");

            await VerifyTrayCloseAsync(controller, newExecutable);
            foreach (var mode in new[] { "minimized", "headless", "unresponsive" })
                await VerifyBackgroundCloseAsync(controller, newExecutable, mode);
            await VerifyIsolationAsync(controller, newExecutable, oldExecutable);
            await VerifyProcessTreeAsync(controller, newExecutable);
            await VerifyCancellationAsync(controller, newExecutable);
            await VerifyMultipleProcessesAsync(controller, newExecutable);
            await VerifySelfProtectionAsync();
            await controller.CloseAsync(CancellationToken.None);
            Console.WriteLine("PASS: closing an already stopped Desktop is harmless.");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        finally
        {
            StopFixture(oldExecutable);
            StopFixture(newExecutable);
            StopFixture(Path.Combine(Path.GetDirectoryName(newExecutable)!, "codex.exe"));
            SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root);
        }
    }

    private static async Task VerifyTrayCloseAsync(DesktopController controller, string executable)
    {
        Prepare(executable);
        await controller.OpenAsync(CancellationToken.None);
        await WaitUntilReadyAsync(executable);
        using (var fixture = FindFixture(executable))
            Require(fixture!.CloseMainWindow(), "The fixture must accept window close.");
        await UntilAsync(() => ReadEvents(executable).Contains("hidden"));
        using (var hidden = FindFixture(executable))
            Require(hidden is not null && hidden.MainWindowHandle == IntPtr.Zero,
                "Window close should leave a hidden running process, reproducing #29.");
        await controller.CloseAsync(CancellationToken.None);
        Require(!IsRunning(executable), "Termination must reach an already hidden tray process.");
        Require(ReadEvents(executable).SequenceEqual(["ready", "hidden"]), "Closing must not send another window message.");
        Console.WriteLine("PASS: an already hidden tray process exits.");
    }

    private static async Task VerifyBackgroundCloseAsync(DesktopController controller, string executable, string mode)
    {
        Prepare(executable, mode);
        await controller.OpenAsync(CancellationToken.None);
        await WaitUntilReadyAsync(executable);
        using (var fixture = FindFixture(executable))
        {
            if (mode == "minimized") Require(IsIconic(fixture!.MainWindowHandle), "The fixture must start minimized.");
            if (mode == "headless") Require(fixture!.MainWindowHandle == IntPtr.Zero, "The headless fixture must have no window.");
        }
        await controller.CloseAsync(CancellationToken.None, TimeSpan.FromSeconds(5));
        Require(!IsRunning(executable), $"The {mode} process should exit without window interaction.");
        Require(ReadEvents(executable).SequenceEqual(["ready"]), "Closing must not send window messages.");
        Console.WriteLine($"PASS: {mode} Desktop exits without keyboard input or window activation.");
    }

    private static async Task VerifyIsolationAsync(DesktopController controller, string executable, string unrelatedExecutable)
    {
        Prepare(unrelatedExecutable);
        var unrelated = new DesktopController(_ => Task.FromResult(new DesktopInstallation(unrelatedExecutable)));
        Prepare(executable);
        await unrelated.OpenAsync(CancellationToken.None);
        await WaitUntilReadyAsync(unrelatedExecutable);
        await controller.OpenAsync(CancellationToken.None);
        await WaitUntilReadyAsync(executable);
        using (var fixture = FindFixture(executable))
            Require(GetForegroundWindow() != fixture!.MainWindowHandle, "The target fixture must be in the background.");
        await controller.CloseAsync(CancellationToken.None);
        Require(!IsRunning(executable), "The selected Desktop should exit.");
        Require(IsRunning(unrelatedExecutable) && ReadEvents(unrelatedExecutable).SequenceEqual(["ready"]),
            "The same-named process at a different path must remain untouched.");
        await unrelated.CloseAsync(CancellationToken.None);
        Console.WriteLine("PASS: background Desktop exits; a same-named process at another path survives.");
    }

    private static async Task VerifyProcessTreeAsync(DesktopController controller, string executable)
    {
        var directory = Path.GetDirectoryName(executable)!;
        var workerExecutable = Path.Combine(directory, "codex.exe");
        File.Copy(executable, workerExecutable, overwrite: true);
        // The independent CLI uses the very same binary as Desktop's children.
        using var independent = Process.Start(new ProcessStartInfo(workerExecutable, "--worker")
            { UseShellExecute = false, CreateNoWindow = true })!;
        var children = new List<Process>();
        try
        {
            await UntilAsync(() => File.Exists(Path.Combine(directory, $"child-{independent.Id}.ready")));
            Prepare(executable, "tree");
            await controller.OpenAsync(CancellationToken.None);
            await WaitUntilReadyAsync(executable);
            await UntilAsync(() => Directory.GetFiles(directory, "child-*.ready").Length == 3);
            foreach (var path in Directory.GetFiles(directory, "child-*.ready"))
            {
                var id = int.Parse(Path.GetFileNameWithoutExtension(path)[6..]);
                if (id == independent.Id) continue;
                var child = Process.GetProcessById(id);
                _ = child.Handle;
                children.Add(child);
            }
            Require(children.Count == 2, "The fixture must create both a child and a grandchild.");
            await controller.CloseAsync(CancellationToken.None);
            Require(!IsRunning(executable) && children.All(child => child.HasExited),
                "Close must wait for Desktop, its app-server child and grandchild to exit.");
            Require(!independent.HasExited, "The independently launched CLI using the same binary must survive.");
            Console.WriteLine("PASS: Desktop child and grandchild exit before return; an independent CLI using the same binary survives.");
        }
        finally
        {
            foreach (var child in children)
            {
                if (!child.HasExited) { child.Kill(entireProcessTree: true); child.WaitForExit(5000); }
                child.Dispose();
            }
            if (!independent.HasExited) { independent.Kill(entireProcessTree: true); independent.WaitForExit(5000); }
        }
    }

    private static async Task VerifyCancellationAsync(DesktopController controller, string executable)
    {
        Prepare(executable, "headless");
        await controller.OpenAsync(CancellationToken.None);
        await WaitUntilReadyAsync(executable);
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try
        {
            await controller.CloseAsync(cancelled.Token);
            throw new InvalidOperationException("A cancelled handoff must stop before terminating Desktop.");
        }
        catch (OperationCanceledException) { }
        Require(IsRunning(executable), "Pre-cancellation must preserve the process.");
        await controller.CloseAsync(CancellationToken.None);
        Console.WriteLine("PASS: pre-cancellation preserves the running Desktop.");
    }

    private static async Task VerifyMultipleProcessesAsync(DesktopController controller, string executable)
    {
        Prepare(executable, "headless");
        await controller.OpenAsync(CancellationToken.None);
        await WaitUntilReadyAsync(executable);
        await controller.OpenAsync(CancellationToken.None);
        await UntilAsync(() => ReadEvents(executable).Length == 2);
        await controller.CloseAsync(CancellationToken.None);
        Require(!IsRunning(executable), "All processes matching the installation must exit.");
        Console.WriteLine("PASS: multiple matching processes all exit.");
    }

    private static async Task VerifySelfProtectionAsync()
    {
        var controller = new DesktopController(_ => Task.FromResult(new DesktopInstallation(Environment.ProcessPath!)));
        try
        {
            await controller.CloseAsync(CancellationToken.None);
            throw new InvalidOperationException("A tree containing the caller must be rejected.");
        }
        catch (IOException ex) when (ex.Message.Contains("switcher process")) { }
        Console.WriteLine("PASS: a tree containing the switcher fails before terminating processes.");
    }

    private static void Prepare(string executable, string mode = "window")
    {
        var directory = Path.GetDirectoryName(executable)!;
        File.WriteAllText(Path.Combine(directory, "mode.txt"), mode);
        File.WriteAllText(Path.Combine(directory, "events.txt"), "");
    }

    private static string[] ReadEvents(string executable)
    {
        var path = Path.Combine(Path.GetDirectoryName(executable)!, "events.txt");
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries);
    }

    private static Task WaitUntilReadyAsync(string executable) => UntilAsync(() => ReadEvents(executable).Contains("ready"));

    private static bool IsRunning(string executable)
    {
        using var fixture = FindFixture(executable);
        return fixture is not null;
    }

    private static async Task UntilAsync(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!condition()) await Task.Delay(50, timeout.Token);
    }

    private static void CopyFixture(string executable, string destination)
    {
        foreach (var file in Directory.EnumerateFiles(Path.GetDirectoryName(Path.GetFullPath(executable))!))
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), overwrite: true);
    }

    private static async Task VerifyRunningPackageIdentityAsync()
    {
        DesktopInstallation installation;
        try { installation = await DesktopController.DiscoverAsync(null); }
        catch (FileNotFoundException) { return; }
        if (installation.AppUserModelId is null) return;
        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(installation.Executable)))
        {
            try
            {
                if (!string.Equals(process.MainModule?.FileName, installation.Executable, StringComparison.OrdinalIgnoreCase)) continue;
                var oldPackagePath = Path.Combine(Path.GetTempPath(), "old-store-version", Path.GetFileName(installation.Executable));
                Require(DesktopController.MatchesInstallation(process, new DesktopInstallation(oldPackagePath, installation.AppUserModelId)),
                    "A running packaged Codex process should still match after its package path changes.");
                Console.WriteLine("PASS: running Store app matched by stable identity after a simulated path change (read-only check).");
                return;
            }
            finally { process.Dispose(); }
        }
    }

    private static Process? FindFixture(string executable)
    {
        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(executable)))
        {
            try
            {
                if (!process.HasExited && string.Equals(process.MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase)) return process;
            }
            catch (InvalidOperationException) { }
            process.Dispose();
        }
        return null;
    }

    private static void StopFixture(string executable)
    {
        using var process = FindFixture(executable);
        if (process is not null && !process.HasExited)
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit(5000);
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
