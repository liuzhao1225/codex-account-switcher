using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CodexAccountSwitcher.Core;

public sealed record WindowsUpdateManifest(
    string Version,
    string Tag,
    string Url,
    long Size,
    string Sha256,
    string ReleaseNotesUrl,
    string Signature);

public sealed record AvailableWindowsUpdate(
    Version Version,
    string Tag,
    Uri DownloadUri,
    long Size,
    string Sha256,
    Uri ReleaseNotesUri,
    string Signature);

public sealed record StagedWindowsUpdate(string StagingDirectory, string ExecutablePath);

public static class WindowsUpdater
{
    public const string FeedUrl = "https://liuzhao1225.github.io/codex-account-switcher/updates/windows/latest.json";
    public const string PublicKeySpkiBase64 = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+9/dptkfIXM8UbAAkCpAAaATdoDzaz71x3FZtX0dBPLzEKja+Ff+A10Z6Nnmx7J8GYU/Y8WzpPUnbm2iV9jNag==";
    public const string Repository = "liuzhao1225/codex-account-switcher";
    public const string AssetName = "Codex-Account-Switcher-windows-x64.exe";
    public const long MaxDownloadBytes = 256L * 1024 * 1024;

    private static readonly Regex SemverRegex = new(@"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z");
    private static readonly Regex Sha256Regex = new(@"\A[0-9a-f]{64}\z", RegexOptions.IgnoreCase);
    private static readonly JsonSerializerOptions ManifestJsonOptions = new() { PropertyNameCaseInsensitive = true };

    public static byte[] CanonicalPayload(string version, string tag, string url, long size, string sha256)
    {
        var payload = string.Join(
            "\n",
            "codex-account-switcher-windows-update-v1",
            version,
            tag,
            url,
            size.ToString(CultureInfo.InvariantCulture),
            sha256.ToLowerInvariant());
        return Encoding.UTF8.GetBytes(payload);
    }

    public static bool VerifySignature(
        string version,
        string tag,
        string url,
        long size,
        string sha256,
        string signatureBase64,
        string publicKeySpkiBase64 = PublicKeySpkiBase64)
    {
        if (string.IsNullOrWhiteSpace(signatureBase64) || string.IsNullOrWhiteSpace(publicKeySpkiBase64))
            return false;
        try
        {
            var signature = Convert.FromBase64String(signatureBase64.Trim());
            if (signature.Length != 64) return false;
            var keyBytes = Convert.FromBase64String(publicKeySpkiBase64.Trim());
            using var ecdsa = ECDsa.Create();
            ecdsa.ImportSubjectPublicKeyInfo(keyBytes, out _);
            var payload = CanonicalPayload(version, tag, url, size, sha256);
            return ecdsa.VerifyData(
                payload,
                signature,
                HashAlgorithmName.SHA256,
                DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        }
        catch (Exception ex) when (ex is FormatException or CryptographicException or ArgumentException)
        {
            return false;
        }
    }

    public static AvailableWindowsUpdate? ParseAndVerifyManifest(
        string json,
        Version currentVersion,
        string publicKeySpkiBase64 = PublicKeySpkiBase64)
    {
        var manifest = JsonSerializer.Deserialize<WindowsUpdateManifest>(json, ManifestJsonOptions)
            ?? throw new InvalidDataException("Empty Windows update manifest.");

        if (string.IsNullOrEmpty(manifest.Version) || !SemverRegex.IsMatch(manifest.Version))
            throw new InvalidDataException("Invalid Windows update version.");
        if (manifest.Tag != "v" + manifest.Version)
            throw new InvalidDataException("Mismatched Windows update tag.");

        var expectedUrl = $"https://github.com/{Repository}/releases/download/{manifest.Tag}/{AssetName}";
        var expectedNotes = $"https://github.com/{Repository}/releases/tag/{manifest.Tag}";
        if (manifest.Url != expectedUrl || manifest.ReleaseNotesUrl != expectedNotes)
            throw new InvalidDataException("Unexpected Windows update URL.");
        if (manifest.Size <= 0 || manifest.Size > MaxDownloadBytes)
            throw new InvalidDataException("Invalid Windows update file size.");
        if (string.IsNullOrEmpty(manifest.Sha256) || !Sha256Regex.IsMatch(manifest.Sha256))
            throw new InvalidDataException("Invalid Windows update checksum format.");

        if (!VerifySignature(
            manifest.Version,
            manifest.Tag,
            manifest.Url,
            manifest.Size,
            manifest.Sha256,
            manifest.Signature,
            publicKeySpkiBase64))
        {
            throw new CryptographicException("Invalid Windows update signature.");
        }

        var nextVersion = NormalizeThreePart(Version.Parse(manifest.Version));
        if (nextVersion <= NormalizeThreePart(currentVersion)) return null;

        return new AvailableWindowsUpdate(
            nextVersion,
            manifest.Tag,
            new Uri(manifest.Url),
            manifest.Size,
            manifest.Sha256.ToLowerInvariant(),
            new Uri(manifest.ReleaseNotesUrl),
            manifest.Signature);
    }

    public static bool CanWriteToDirectory(string? targetExecutablePath)
    {
        if (string.IsNullOrWhiteSpace(targetExecutablePath)) return false;
        try
        {
            var fullPath = Path.GetFullPath(targetExecutablePath);
            var directory = Path.GetDirectoryName(fullPath);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory)) return false;
            SecureFiles.RejectLinks(fullPath);
            var probe = Path.Combine(directory, $".switcher-write-probe-{Guid.NewGuid():N}.tmp");
            using (File.Create(probe, 1, FileOptions.DeleteOnClose)) { }
            return true;
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or NotSupportedException)
        {
            return false;
        }
    }

    public static async Task<StagedWindowsUpdate> DownloadAndVerifyAsync(
        AvailableWindowsUpdate update,
        string updatesRoot,
        HttpClient http,
        IProgress<int>? progress,
        CancellationToken ct,
        string publicKeySpkiBase64 = PublicKeySpkiBase64)
    {
        if (!VerifySignature(
            update.Version.ToString(3),
            update.Tag,
            update.DownloadUri.AbsoluteUri,
            update.Size,
            update.Sha256,
            update.Signature,
            publicKeySpkiBase64))
        {
            throw new CryptographicException("Invalid Windows update signature.");
        }
        if (update.Size <= 0 || update.Size > MaxDownloadBytes)
            throw new InvalidDataException("Invalid Windows update file size.");

        var root = Path.GetFullPath(updatesRoot);
        SecureFiles.CreatePrivateDirectory(root);
        var stagingDir = Path.Combine(root, "staging-" + Guid.NewGuid().ToString("N"));
        SecureFiles.CreatePrivateDirectory(stagingDir);
        var stagedExe = Path.Combine(stagingDir, AssetName);

        try
        {
            using var response = await http.GetAsync(update.DownloadUri, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength is { } contentLength && contentLength != update.Size)
                throw new CryptographicException("Downloaded Windows update length does not match signed manifest.");

            long totalRead = 0;
            var lastReported = -1;
            using var hasher = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            await using (var network = await response.Content.ReadAsStreamAsync(ct))
            await using (var destination = new FileStream(
                stagedExe, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, useAsync: true))
            {
                var buffer = new byte[81920];
                int read;
                while ((read = await network.ReadAsync(buffer.AsMemory(0, buffer.Length), ct)) > 0)
                {
                    totalRead += read;
                    if (totalRead > update.Size || totalRead > MaxDownloadBytes)
                        throw new CryptographicException("Downloaded Windows update exceeded declared size.");
                    await destination.WriteAsync(buffer.AsMemory(0, read), ct);
                    hasher.AppendData(buffer, 0, read);
                    var percent = (int)Math.Clamp(totalRead * 100L / update.Size, 0L, 100L);
                    if (percent != lastReported)
                    {
                        lastReported = percent;
                        progress?.Report(percent);
                    }
                }
                await destination.FlushAsync(ct);
            }

            if (totalRead != update.Size)
                throw new CryptographicException("Downloaded Windows update was incomplete.");

            var actualSha256 = Convert.ToHexString(hasher.GetHashAndReset()).ToLowerInvariant();
            if (!string.Equals(actualSha256, update.Sha256, StringComparison.Ordinal))
                throw new CryptographicException("Downloaded Windows update checksum mismatch.");

            progress?.Report(100);
            return new StagedWindowsUpdate(stagingDir, stagedExe);
        }
        catch
        {
            TryDeleteOwnedDirectory(root, stagingDir);
            throw;
        }
    }

    public static async Task ApplyUpdateAsync(
        string stagedExePath,
        string targetExePath,
        int parentPid,
        string stagingDirectory,
        bool relaunchInBackground,
        bool launchTarget = true,
        CancellationToken ct = default)
    {
        if (parentPid > 0 && parentPid != Environment.ProcessId)
        {
            try
            {
                using var parent = Process.GetProcessById(parentPid);
                using var waitLimit = CancellationTokenSource.CreateLinkedTokenSource(ct);
                waitLimit.CancelAfter(TimeSpan.FromSeconds(20));
                await parent.WaitForExitAsync(waitLimit.Token);
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException) { }
        }

        ct.ThrowIfCancellationRequested();
        var fullStaged = Path.GetFullPath(stagedExePath);
        var fullTarget = Path.GetFullPath(targetExePath);
        SecureFiles.RejectLinks(fullStaged);
        SecureFiles.RejectLinks(fullTarget);

        var tempNew = fullTarget + ".new";
        var backupOld = fullTarget + ".old";
        var expectedHash = ComputeSha256(fullStaged);

        File.Copy(fullStaged, tempNew, overwrite: true);
        if (!string.Equals(ComputeSha256(tempNew), expectedHash, StringComparison.Ordinal))
        {
            TryDeleteFile(tempNew);
            throw new CryptographicException("Copied update binary failed integrity verification.");
        }

        var hadTarget = File.Exists(fullTarget);
        var movedToBackup = false;
        try
        {
            if (File.Exists(backupOld))
                await RetryIoAsync(() => File.Delete(backupOld), ct);

            if (hadTarget)
            {
                await RetryIoAsync(() => File.Move(fullTarget, backupOld, overwrite: true), ct);
                movedToBackup = true;
            }

            await RetryIoAsync(() => File.Move(tempNew, fullTarget, overwrite: false), ct);
        }
        catch
        {
            if (movedToBackup && !File.Exists(fullTarget) && File.Exists(backupOld))
            {
                await RetryIoAsync(() => File.Move(backupOld, fullTarget, overwrite: false), CancellationToken.None);
            }
            TryDeleteFile(tempNew);
            throw;
        }

        if (launchTarget)
        {
            var start = new ProcessStartInfo(fullTarget)
            {
                UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(fullTarget) ?? Environment.CurrentDirectory,
            };
            start.ArgumentList.Add("--cleanup-update");
            start.ArgumentList.Add(stagingDirectory);
            start.ArgumentList.Add("--wait-pid");
            start.ArgumentList.Add(Environment.ProcessId.ToString(CultureInfo.InvariantCulture));
            if (relaunchInBackground)
                start.ArgumentList.Add("--background");

            using var started = Process.Start(start) ?? throw new IOException("Could not relaunch the updated application.");
        }
    }

    public static void CleanupAfterUpdate(
        string targetExePath,
        string updatesRoot,
        string? stagingDirectory,
        int? waitPid)
    {
        if (waitPid is > 0 && waitPid.Value != Environment.ProcessId)
        {
            try
            {
                using var helper = Process.GetProcessById(waitPid.Value);
                helper.WaitForExit(10_000);
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException) { }
        }

        var fullTarget = Path.GetFullPath(targetExePath);
        var backupOld = fullTarget + ".old";
        var tempNew = fullTarget + ".new";
        RetryBestEffort(() => { if (File.Exists(backupOld)) File.Delete(backupOld); });
        RetryBestEffort(() => { if (File.Exists(tempNew)) File.Delete(tempNew); });

        var root = Path.GetFullPath(updatesRoot);
        if (!string.IsNullOrWhiteSpace(stagingDirectory))
        {
            RetryBestEffort(() =>
            {
                if (Directory.Exists(stagingDirectory))
                    SecureFiles.DeleteOwnedDirectory(root, stagingDirectory);
            });
        }
        CleanupStaleStagingDirectories(root);
    }

    public static void CleanupStaleStagingDirectories(string updatesRoot)
    {
        try
        {
            var root = Path.GetFullPath(updatesRoot);
            if (!Directory.Exists(root)) return;
            var cutoff = DateTime.UtcNow.AddHours(-1);
            foreach (var directory in Directory.EnumerateDirectories(root, "staging-*"))
            {
                try
                {
                    if (Directory.GetCreationTimeUtc(directory) < cutoff)
                        SecureFiles.DeleteOwnedDirectory(root, directory);
                }
                catch { }
            }
        }
        catch { }
    }

    private static Version NormalizeThreePart(Version version) =>
        new(version.Major, Math.Max(version.Minor, 0), Math.Max(version.Build, 0));

    public static string ComputeSha256(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static async Task RetryIoAsync(Action action, CancellationToken ct)
    {
        for (var attempt = 0; ; attempt++)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                action();
                return;
            }
            catch (Exception ex) when (attempt < 14 && ex is IOException or UnauthorizedAccessException)
            {
                await Task.Delay(300, ct);
            }
        }
    }

    private static void RetryBestEffort(Action action)
    {
        for (var attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                action();
                return;
            }
            catch (Exception ex) when (attempt < 9 && ex is IOException or UnauthorizedAccessException)
            {
                Thread.Sleep(300);
            }
            catch { return; }
        }
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private static void TryDeleteOwnedDirectory(string root, string directory)
    {
        try { if (Directory.Exists(directory)) SecureFiles.DeleteOwnedDirectory(root, directory); } catch { }
    }
}
