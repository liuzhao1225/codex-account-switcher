using System.Diagnostics;
using CodexAccountSwitcher.Core;

internal static class DesktopCloseChecks
{
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

            await controller.OpenAsync(CancellationToken.None);
            await WaitForWindowAsync(oldExecutable);
            await controller.CloseAsync(CancellationToken.None);
            Require(FindFixture(oldExecutable) is null, "The version 1 fixture should close through its main window.");

            // Simulate a Store update moving ChatGPT.exe to a new versioned package directory.
            installedVersion = 2;
            await controller.OpenAsync(CancellationToken.None);
            await WaitForWindowAsync(newExecutable);

            // This fixed old path reproduces the cached-installation failure: it cannot see the new process.
            var staleController = new DesktopController(_ => Task.FromResult(new DesktopInstallation(oldExecutable)));
            await staleController.CloseAsync(CancellationToken.None);
            Require(FindFixture(newExecutable) is not null, "A stale package path must not claim the updated fixture was closed.");

            // The same long-lived controller must resolve the updated path again for the next handoff.
            await controller.CloseAsync(CancellationToken.None);
            Require(FindFixture(newExecutable) is null, "The refreshed package path should close the updated fixture.");
            Require(discoveryCount == 4, "Each open and close operation should discover the current package path.");

            Console.WriteLine("PASS: a versioned Store-path update is discovered for each open and close; normal window close exits the matching process.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
        finally
        {
            StopFixture(oldExecutable);
            StopFixture(newExecutable);
            SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root);
        }
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
                if (!string.Equals(process.MainModule?.FileName, installation.Executable, StringComparison.OrdinalIgnoreCase))
                    continue;

                var oldPackagePath = Path.Combine(Path.GetTempPath(), "old-store-version", Path.GetFileName(installation.Executable));
                Require(DesktopController.MatchesInstallation(process,
                    new DesktopInstallation(oldPackagePath, installation.AppUserModelId)),
                    "A running packaged Codex process should still match after its package path changes.");
                Console.WriteLine("PASS: the running packaged Codex process matched through its stable app identity after a simulated path change.");
                return;
            }
            finally { process.Dispose(); }
        }
    }

    private static async Task WaitForWindowAsync(string executable)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!timeout.IsCancellationRequested)
        {
            using var fixture = FindFixture(executable);
            if (fixture is { MainWindowHandle: var handle } && handle != IntPtr.Zero) return;
            await Task.Delay(100, timeout.Token);
        }
        throw new TimeoutException("The isolated desktop fixture did not create a main window.");
    }

    private static Process? FindFixture(string executable)
    {
        foreach (var process in Process.GetProcessesByName("ChatGPT"))
        {
            try
            {
                if (!process.HasExited && string.Equals(process.MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase))
                    return process;
            }
            catch (InvalidOperationException) { }
            process.Dispose();
        }
        return null;
    }

    private static void StopFixture(string executable)
    {
        foreach (var process in Process.GetProcessesByName("ChatGPT"))
        {
            try
            {
                if (string.Equals(process.MainModule?.FileName, executable, StringComparison.OrdinalIgnoreCase) && !process.HasExited)
                    process.Kill(entireProcessTree: true);
            }
            catch (Exception) { }
            finally { process.Dispose(); }
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
