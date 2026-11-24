using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using CodexAccountSwitcher.Core;
using Microsoft.Win32;

namespace CodexAccountSwitcher;

public sealed record UpdateRestartHooks(Func<bool> TryBegin, Action Cancel, Func<Task> Complete);

public sealed class NativeSettings
{
    private const string Key = @"Software\CodexAccountSwitcher";
    private const string Run = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private readonly Func<TimeSpan, HttpClient> createHttpClient;
    private readonly Func<string, bool> canWriteToDirectory;
    private readonly Func<ProcessStartInfo, Process?> startProcess;
    private readonly Action<Uri> openUri;
    private readonly Func<string?> currentProcessPath;
    private readonly string publicKeySpkiBase64;
    private CancellationTokenSource? downloadCancellation;

    public NativeSettings()
        : this(null, null, null, null, null, WindowsUpdater.PublicKeySpkiBase64)
    {
    }

    internal NativeSettings(
        Func<TimeSpan, HttpClient>? createHttpClient,
        Func<string, bool>? canWriteToDirectory,
        Func<ProcessStartInfo, Process?>? startProcess,
        Action<Uri>? openUri,
        Func<string?>? currentProcessPath,
        string publicKeySpkiBase64)
    {
        this.createHttpClient = createHttpClient ?? (timeout => new HttpClient { Timeout = timeout });
        this.canWriteToDirectory = canWriteToDirectory ?? WindowsUpdater.CanWriteToDirectory;
        this.startProcess = startProcess ?? Process.Start;
        this.openUri = openUri ?? (uri => Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true })?.Dispose());
        this.currentProcessPath = currentProcessPath ?? (() => Environment.ProcessPath);
        this.publicKeySpkiBase64 = publicKeySpkiBase64;
    }

    public string Version => typeof(NativeSettings).Assembly.GetName().Version!.ToString(3);
    public bool LaunchAtLogin
    {
        get { using var key = Registry.CurrentUser.OpenSubKey(Run); return key?.GetValue("CodexAccountSwitcher") is string; }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(Run);
            if (value) key.SetValue("CodexAccountSwitcher", "\"" + Environment.ProcessPath + "\" --background");
            else key.DeleteValue("CodexAccountSwitcher", false);
        }
    }
    public bool AutomaticallyCheckUpdates
    {
        get { using var key = Registry.CurrentUser.OpenSubKey(Key); return key?.GetValue("AutomaticallyCheckUpdates") is not int number || number != 0; }
        set { using var key = Registry.CurrentUser.CreateSubKey(Key); key.SetValue("AutomaticallyCheckUpdates", value ? 1 : 0); }
    }
    public AvailableWindowsUpdate? AvailableUpdate { get; private set; }
    public bool IsChecking { get; private set; }
    public bool IsInstalling { get; private set; }
    public int? DownloadPercent { get; private set; }
    public bool CanCancelInstall => IsInstalling && downloadCancellation != null && DownloadPercent != null;
    public string? UpdateError { get; private set; }
    public event Action? Changed;

    public async Task CheckUpdatesAsync()
    {
        if (IsChecking || IsInstalling) return;
        IsChecking = true;
        UpdateError = null;
        Changed?.Invoke();
        try
        {
            using var http = createHttpClient(TimeSpan.FromSeconds(15));
            http.DefaultRequestHeaders.UserAgent.ParseAdd("CodexAccountSwitcher/" + Version);
            var json = await http.GetStringAsync(WindowsUpdater.FeedUrl);
            AvailableUpdate = WindowsUpdater.ParseAndVerifyManifest(json, new Version(Version), publicKeySpkiBase64);
        }
        catch (CryptographicException) { UpdateError = "update_verify_failed"; }
        catch (Exception) { UpdateError = "update_check_failed"; }
        finally { IsChecking = false; Changed?.Invoke(); }
    }

    public void CancelUpdate() => downloadCancellation?.Cancel();

    public async Task InstallUpdateAsync(UpdateRestartHooks restartHooks, bool relaunchInBackground, string updatesRoot)
    {
        if (AvailableUpdate is not { } update || IsInstalling) return;
        var currentExe = currentProcessPath();
        if (string.IsNullOrEmpty(currentExe) || !canWriteToDirectory(currentExe))
        {
            UpdateError = "update_readonly_fallback";
            OpenUpdate();
            Changed?.Invoke();
            return;
        }

        IsInstalling = true;
        DownloadPercent = 0;
        UpdateError = null;
        var cts = new CancellationTokenSource();
        downloadCancellation = cts;
        Changed?.Invoke();

        StagedWindowsUpdate? staged = null;
        var restartReserved = false;
        var completedRestart = false;
        try
        {
            using var http = createHttpClient(TimeSpan.FromMinutes(10));
            http.DefaultRequestHeaders.UserAgent.ParseAdd("CodexAccountSwitcher/" + Version);
            var progress = new Progress<int>(percent =>
            {
                if (DownloadPercent != percent)
                {
                    DownloadPercent = percent;
                    Changed?.Invoke();
                }
            });
            staged = await WindowsUpdater.DownloadAndVerifyAsync(
                update, updatesRoot, http, progress, cts.Token, publicKeySpkiBase64);
            DownloadPercent = null;
            downloadCancellation = null;
            Changed?.Invoke();

            if (!restartHooks.TryBegin())
            {
                WindowsUpdater.TryDeleteOwnedDirectory(updatesRoot, staged.StagingDirectory);
                staged = null;
                return;
            }
            restartReserved = true;

            var start = new ProcessStartInfo(staged.ExecutablePath)
            {
                UseShellExecute = false,
                WorkingDirectory = staged.StagingDirectory,
            };
            start.ArgumentList.Add("--apply-update");
            start.ArgumentList.Add("--target");
            start.ArgumentList.Add(currentExe);
            start.ArgumentList.Add("--parent-pid");
            start.ArgumentList.Add(Environment.ProcessId.ToString(CultureInfo.InvariantCulture));
            start.ArgumentList.Add("--staging");
            start.ArgumentList.Add(staged.StagingDirectory);
            if (relaunchInBackground)
                start.ArgumentList.Add("--background");

            try
            {
                using var helper = startProcess(start) ?? throw new IOException("Could not start update installer.");
            }
            catch (Exception ex)
            {
                restartHooks.Cancel();
                restartReserved = false;
                WindowsUpdater.TryDeleteOwnedDirectory(updatesRoot, staged.StagingDirectory);
                staged = null;
                UpdateError = ex.Message;
                return;
            }

            // Ownership of the staging directory transfers to the launched helper process.
            staged = null;
            restartReserved = false;
            completedRestart = true;
            await restartHooks.Complete();
        }
        catch (Exception ex)
        {
            if (restartReserved) restartHooks.Cancel();
            if (staged != null) WindowsUpdater.TryDeleteOwnedDirectory(updatesRoot, staged.StagingDirectory);
            UpdateError = ex switch
            {
                OperationCanceledException => null,
                CryptographicException => "update_verify_failed",
                _ => "update_download_failed",
            };
        }
        finally
        {
            IsInstalling = false;
            DownloadPercent = null;
            downloadCancellation = null;
            cts.Dispose();
            if (!completedRestart) Changed?.Invoke();
        }
    }

    private void OpenUpdate()
    {
        if (AvailableUpdate?.ReleaseNotesUri is { } uri) openUri(uri);
    }
}
