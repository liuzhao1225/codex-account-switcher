using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace CodexAccountSwitcher.Core;

public sealed record DesktopInstallation(string Executable, string? AppUserModelId = null);

public sealed class DesktopController(Func<CancellationToken, Task<DesktopInstallation>> discover)
{
    private const int ErrorInsufficientBuffer = 122;
    private const int ErrorSuccess = 0;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetApplicationUserModelId(IntPtr process, ref uint length, StringBuilder? appUserModelId);

    public static async Task<DesktopInstallation> DiscoverAsync(string? explicitPath, CancellationToken ct = default)
    {
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            var full = Path.GetFullPath(explicitPath);
            if (!File.Exists(full) || !Path.GetExtension(full).Equals(".exe", StringComparison.OrdinalIgnoreCase))
                throw new FileNotFoundException("The configured Codex Desktop executable was not found.");
            return new(full);
        }
        // The Store package executable may be named ChatGPT.exe. Discover from the manifest;
        // process-name matching alone can close unrelated apps or a codex.exe CLI.
        const string script = "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $p = Get-AppxPackage -Name OpenAI.Codex | Select-Object -First 1; if ($p) { [xml]$m = Get-Content -LiteralPath (Join-Path $p.InstallLocation 'AppxManifest.xml'); $a = @($m.Package.Applications.Application)[0]; @{ executable = (Join-Path $p.InstallLocation $a.Executable); appId = ($p.PackageFamilyName + '!' + $a.Id) } | ConvertTo-Json -Compress }";
        var powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        var info = new ProcessStartInfo(powershell) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = System.Text.Encoding.UTF8 };
        info.ArgumentList.Add("-NoProfile"); info.ArgumentList.Add("-NonInteractive");
        info.ArgumentList.Add("-Command"); info.ArgumentList.Add(script);
        using var process = Process.Start(info) ?? throw new IOException("Could not inspect the Codex Desktop installation.");
        var output = process.StandardOutput.ReadToEndAsync(ct);
        var errors = process.StandardError.ReadToEndAsync(ct);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch { if (!process.HasExited) process.Kill(entireProcessTree: true); throw; }
        var json = await output; await errors;
        if (process.ExitCode != 0) throw new IOException("Could not inspect the Codex Desktop installation.");
        if (!string.IsNullOrWhiteSpace(json))
        {
            using var document = JsonDocument.Parse(json);
            var path = document.RootElement.GetProperty("executable").GetString();
            if (path != null && File.Exists(path)) return new(path, document.RootElement.GetProperty("appId").GetString());
        }
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        foreach (var relative in new[] { @"Programs\Codex\Codex.exe", @"OpenAI\Codex\Codex.exe" })
        {
            var path = Path.Combine(local, relative);
            if (File.Exists(path)) return new(path);
        }
        throw new FileNotFoundException("Codex Desktop was not found. Install Codex Desktop before switching.");
    }

    private static List<Process> FindDesktopProcesses(DesktopInstallation installation)
    {
        var result = new List<Process>();
        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(installation.Executable)))
        {
            try
            {
                if (!process.HasExited && MatchesInstallation(process, installation))
                { result.Add(process); continue; }
            }
            catch (System.ComponentModel.Win32Exception)
            {
                process.Dispose();
                foreach (var match in result) match.Dispose();
                throw new IOException("Could not inspect a matching Desktop process. Close Codex Desktop manually before switching.");
            }
            catch (InvalidOperationException) { }
            process.Dispose();
        }
        return result;
    }

    internal static bool MatchesInstallation(Process process, DesktopInstallation installation)
    {
        // AUMIDs stay stable across Store package versions; a running app can retain its old install path after an update.
        if (installation.AppUserModelId is { } expectedAppUserModelId &&
            ReadApplicationUserModelId(process) is { } actualAppUserModelId)
            return string.Equals(actualAppUserModelId, expectedAppUserModelId, StringComparison.OrdinalIgnoreCase);

        return string.Equals(process.MainModule?.FileName, installation.Executable, StringComparison.OrdinalIgnoreCase);
    }

    private static string? ReadApplicationUserModelId(Process process)
    {
        uint length = 0;
        var result = GetApplicationUserModelId(process.Handle, ref length, null);
        if (result != ErrorInsufficientBuffer || length == 0) return null;

        var value = new StringBuilder((int)length);
        result = GetApplicationUserModelId(process.Handle, ref length, value);
        return result == ErrorSuccess ? value.ToString() : null;
    }

    public async Task CloseAsync(CancellationToken cancellationToken)
    {
        // Store package paths are versioned, so resolve the executable for every handoff.
        var installation = await discover(cancellationToken);
        var initial = FindDesktopProcesses(installation);
        try
        {
            if (initial.Count == 0) return;
            var requested = false;
            foreach (var process in initial)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!process.HasExited && process.MainWindowHandle != IntPtr.Zero)
                {
                    if (!process.CloseMainWindow()) throw new IOException("Codex Desktop rejected the normal close request.");
                    requested = true;
                }
            }
            if (!requested) throw new IOException("Codex Desktop is running without a closable window. Quit it manually before switching.");
            var stopwatch = Stopwatch.StartNew();
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var remaining = FindDesktopProcesses(installation);
                var count = remaining.Count;
                foreach (var process in remaining) process.Dispose();
                if (count == 0) return;
                if (stopwatch.Elapsed > TimeSpan.FromSeconds(30))
                    throw new TimeoutException("Codex Desktop did not exit within 30 seconds. Finish its tasks and quit it manually; the account was not changed.");
                await Task.Delay(200, cancellationToken);
            }
        }
        finally { foreach (var process in initial) process.Dispose(); }
    }

    public async Task OpenAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var installation = await discover(cancellationToken);
        var info = installation.AppUserModelId == null
            ? new ProcessStartInfo(installation.Executable) { UseShellExecute = true }
            : new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"))
                { UseShellExecute = false, CreateNoWindow = true };
        if (installation.AppUserModelId != null) info.ArgumentList.Add("shell:AppsFolder\\" + installation.AppUserModelId);
        using var launched = Process.Start(info) ?? throw new IOException("Codex Desktop could not be opened; the selected account remains active.");
        var stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < TimeSpan.FromSeconds(15))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var running = FindDesktopProcesses(installation);
            var count = running.Count;
            foreach (var process in running) process.Dispose();
            if (count > 0) return;
            await Task.Delay(250, cancellationToken);
        }
        throw new IOException("Codex Desktop did not start within 15 seconds. Open it manually; the selected account remains active.");
    }
}
