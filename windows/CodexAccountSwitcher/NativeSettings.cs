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

public sealed class NativeSettings
{
    private const string Key = @"Software\CodexAccountSwitcher";
    private const string Run = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private CancellationTokenSource? downloadCancellation;

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
    public Uri? UpdatePage => AvailableUpdate?.ReleaseNotesUri;
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
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("CodexAccountSwitcher/" + Version);
            var json = await http.GetStringAsync(WindowsUpdater.FeedUrl);
            AvailableUpdate = WindowsUpdater.ParseAndVerifyManifest(json, new Version(Version));
        }
        catch (CryptographicException) { UpdateError = "update_verify_failed"; }
        catch (Exception) { UpdateError = "update_check_failed"; }
        finally { IsChecking = false; Changed?.Invoke(); }
    }

    public void CancelUpdate() => downloadCancellation?.Cancel();

    public async Task InstallUpdateAsync(Func<Task<bool>> prepareForRestart, bool relaunchInBackground, string updatesRoot)
    {
        if (AvailableUpdate is not { } update || IsInstalling) return;
        var currentExe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(currentExe) || !WindowsUpdater.CanWriteToDirectory(currentExe))
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
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("CodexAccountSwitcher/" + Version);
            var progress = new Progress<int>(percent =>
            {
                if (DownloadPercent != percent)
                {
                    DownloadPercent = percent;
                    Changed?.Invoke();
                }
            });
            staged = await WindowsUpdater.DownloadAndVerifyAsync(update, updatesRoot, http, progress, cts.Token);
            DownloadPercent = null;
            downloadCancellation = null;
            Changed?.Invoke();

            if (!await prepareForRestart())
            {
                TryDeleteDirectory(updatesRoot, staged.StagingDirectory);
                IsInstalling = false;
                Changed?.Invoke();
                return;
            }

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

            using var helper = Process.Start(start) ?? throw new IOException("Could not start update installer.");
            Application.Current?.Shutdown(0);
        }
        catch (OperationCanceledException)
        {
            if (staged != null) TryDeleteDirectory(updatesRoot, staged.StagingDirectory);
            IsInstalling = false;
            DownloadPercent = null;
            downloadCancellation = null;
            Changed?.Invoke();
        }
        catch (CryptographicException)
        {
            if (staged != null) TryDeleteDirectory(updatesRoot, staged.StagingDirectory);
            UpdateError = "update_verify_failed";
            IsInstalling = false;
            DownloadPercent = null;
            downloadCancellation = null;
            Changed?.Invoke();
        }
        catch (Exception)
        {
            if (staged != null) TryDeleteDirectory(updatesRoot, staged.StagingDirectory);
            UpdateError = "update_download_failed";
            IsInstalling = false;
            DownloadPercent = null;
            downloadCancellation = null;
            Changed?.Invoke();
        }
        finally
        {
            downloadCancellation = null;
            cts.Dispose();
        }
    }

    public void OpenUpdate()
    {
        if (UpdatePage != null) Process.Start(new ProcessStartInfo(UpdatePage.AbsoluteUri) { UseShellExecute = true })?.Dispose();
    }

    private static void TryDeleteDirectory(string updatesRoot, string directory)
    {
        try { SecureFiles.DeleteOwnedDirectory(updatesRoot, directory); } catch { }
    }
}
