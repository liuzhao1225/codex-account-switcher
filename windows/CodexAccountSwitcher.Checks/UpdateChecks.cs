using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CodexAccountSwitcher.Core;

internal static class UpdateChecks
{
    private const string CrossLangPublicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEkeWTKfZIKx3GnWkh5xBlkyWt10Uhd7iJ0vnjlxDR8Ola1nSSc+wDED/iA8UNoy9bDrU7lHQCfN5dZo5MFByp7A==";
    private const string CrossLangManifestJson = """
        {
          "version": "0.2.1",
          "tag": "v0.2.1",
          "url": "https://github.com/liuzhao1225/codex-account-switcher/releases/download/v0.2.1/Codex-Account-Switcher-windows-x64.exe",
          "size": 123456,
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "releaseNotesUrl": "https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.2.1",
          "signature": "ejLJeqnLSWnne4afPqt0SqG+CuCuSf+JHyuSA8AmO+WVkOiwAEijmvx4XyjNK3HuOQfBq03c+0iuJwHO2BQr1g=="
        }
        """;

    public static async Task<int> RunAsync()
    {
        var root = Path.Combine(Path.GetTempPath(), "switcher-win-update-check-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(root);
            VerifyCrossLanguageNodeSignature();
            await VerifyDownloadAndTamperRejectionAsync(root);
            await VerifySwapAndCleanupAsync(root);
            Console.WriteLine("PASS: Node<->.NET P-256 signature verification, streaming download checks, two-process atomic swap, and cleanup.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
        finally
        {
            SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root);
        }
    }

    private static void VerifyCrossLanguageNodeSignature()
    {
        var available = WindowsUpdater.ParseAndVerifyManifest(CrossLangManifestJson, new Version(0, 2, 0), CrossLangPublicKey);
        Require(available != null && available.Version == new Version(0, 2, 1), "Signed 0.2.1 manifest must be accepted for 0.2.0.");
        Require(WindowsUpdater.ParseAndVerifyManifest(CrossLangManifestJson, new Version(0, 2, 1), CrossLangPublicKey) == null,
            "Equal version must not trigger an update.");
        Require(WindowsUpdater.ParseAndVerifyManifest(CrossLangManifestJson, new Version(0, 2, 1, 0), CrossLangPublicKey) == null,
            "Four-part assembly version equal in 3 parts must not trigger an update.");
        Require(WindowsUpdater.ParseAndVerifyManifest(CrossLangManifestJson, new Version(0, 3, 0), CrossLangPublicKey) == null,
            "Downgrade version must not trigger an update.");

        RequireThrows<CryptographicException>(() =>
            WindowsUpdater.ParseAndVerifyManifest(CrossLangManifestJson.Replace("123456", "123457"), new Version(0, 2, 0), CrossLangPublicKey),
            "Tampered size must fail signature verification.");
        RequireThrows<CryptographicException>(() =>
            WindowsUpdater.ParseAndVerifyManifest(CrossLangManifestJson.Replace("aaaa", "baaa"), new Version(0, 2, 0), CrossLangPublicKey),
            "Tampered SHA-256 must fail signature verification.");
        RequireThrows<InvalidDataException>(() =>
            WindowsUpdater.ParseAndVerifyManifest(CrossLangManifestJson.Replace("liuzhao1225/codex-account-switcher/releases/download", "evil.example/releases/download"), new Version(0, 2, 0), CrossLangPublicKey),
            "Untrusted download host must be rejected.");
    }

    private static async Task VerifyDownloadAndTamperRejectionAsync(string root)
    {
        var updatesRoot = Path.Combine(root, "updates");
        var payload = new byte[200_000];
        Random.Shared.NextBytes(payload);
        var sha256 = Convert.ToHexString(SHA256.HashData(payload)).ToLowerInvariant();
        const string version = "0.2.1";
        const string tag = "v0.2.1";
        var url = $"https://github.com/{WindowsUpdater.Repository}/releases/download/{tag}/{WindowsUpdater.AssetName}";

        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var pubSpki = Convert.ToBase64String(key.ExportSubjectPublicKeyInfo());
        var sig = Convert.ToBase64String(key.SignData(
            WindowsUpdater.CanonicalPayload(version, tag, url, payload.Length, sha256),
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation));

        var manifestJson = JsonSerializer.Serialize(new
        {
            version,
            tag,
            url,
            size = payload.Length,
            sha256,
            releaseNotesUrl = $"https://github.com/{WindowsUpdater.Repository}/releases/tag/{tag}",
            signature = sig,
        });
        var update = WindowsUpdater.ParseAndVerifyManifest(manifestJson, new Version(0, 2, 0), pubSpki)
            ?? throw new InvalidOperationException("Signed ephemeral manifest did not parse.");

        var progressReports = new List<int>();
        using (var http = new HttpClient(new StubHandler(() => payload)))
        {
            var staged = await WindowsUpdater.DownloadAndVerifyAsync(
                update, updatesRoot, http, new SynchronousProgress(progressReports.Add), CancellationToken.None, pubSpki);
            Require(File.Exists(staged.ExecutablePath), "Verified download must stay on disk.");
            Require((await File.ReadAllBytesAsync(staged.ExecutablePath)).SequenceEqual(payload), "Downloaded bytes must match exactly.");
            Require(progressReports.Contains(100), "Progress reporting must reach 100%.");
            var acl = new FileInfo(staged.ExecutablePath).GetAccessControl();
            Require(acl.AreAccessRulesProtected, "Staged update binary must use a private user ACL.");
            Require(acl.GetAccessRules(true, true, typeof(System.Security.Principal.SecurityIdentifier)).Count == 1,
                "Staged update binary must grant only the current user access.");
            SecureFiles.DeleteOwnedDirectory(updatesRoot, staged.StagingDirectory);
        }

        // Corrupt one byte in transit: must reject and delete staging directory.
        var corrupted = (byte[])payload.Clone();
        corrupted[42] ^= 0xFF;
        using (var http = new HttpClient(new StubHandler(() => corrupted)))
        {
            var threw = false;
            try { await WindowsUpdater.DownloadAndVerifyAsync(update, updatesRoot, http, null, CancellationToken.None, pubSpki); }
            catch (CryptographicException) { threw = true; }
            Require(threw, "Corrupted payload must throw CryptographicException.");
            Require(!Directory.EnumerateDirectories(updatesRoot).Any(), "Failed download must remove its staging directory.");
        }

        // Oversized stream: must reject and delete staging directory.
        var oversized = new byte[payload.Length + 1024];
        using (var http = new HttpClient(new StubHandler(() => oversized, omitContentLength: true)))
        {
            var threw = false;
            try { await WindowsUpdater.DownloadAndVerifyAsync(update, updatesRoot, http, null, CancellationToken.None, pubSpki); }
            catch (CryptographicException) { threw = true; }
            Require(threw, "Oversized stream must be rejected.");
            Require(!Directory.EnumerateDirectories(updatesRoot).Any(), "Oversized download must clean up staging directory.");
        }
    }

    private static async Task VerifySwapAndCleanupAsync(string root)
    {
        var installDir = Path.Combine(root, "install");
        var updatesRoot = Path.Combine(root, "updates");
        var stagingDir = Path.Combine(updatesRoot, "staging-test");
        Directory.CreateDirectory(installDir);
        SecureFiles.CreatePrivateDirectory(updatesRoot);
        SecureFiles.CreatePrivateDirectory(stagingDir);

        var targetExe = Path.Combine(installDir, WindowsUpdater.AssetName);
        var stagedExe = Path.Combine(stagingDir, WindowsUpdater.AssetName);
        Require(WindowsUpdater.CanWriteToDirectory(targetExe), "Writable directory probe must return true.");
        Require(!WindowsUpdater.CanWriteToDirectory(Path.Combine(root, "missing-dir", WindowsUpdater.AssetName)),
            "Missing directory probe must return false.");

        var oldBytes = Encoding.UTF8.GetBytes("old-exe-v0.2.0");
        var newBytes = Encoding.UTF8.GetBytes("new-exe-v0.2.1-verified-payload");
        await File.WriteAllBytesAsync(targetExe, oldBytes);
        await File.WriteAllBytesAsync(stagedExe, newBytes);

        // Spawn a brief real process so ApplyUpdateAsync exercises WaitForExitAsync(parentPid).
        using var parent = Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 2 127.0.0.1 >nul")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
        }) ?? throw new IOException("Could not start fixture parent process.");

        await WindowsUpdater.ApplyUpdateAsync(
            stagedExe,
            targetExe,
            parent.Id,
            stagingDir,
            relaunchInBackground: false,
            launchTarget: false);

        Require(parent.HasExited, "ApplyUpdateAsync must wait for the old parent PID to exit.");
        Require((await File.ReadAllBytesAsync(targetExe)).SequenceEqual(newBytes), "Target EXE must contain new verified bytes after swap.");
        Require(File.Exists(targetExe + ".old") && (await File.ReadAllBytesAsync(targetExe + ".old")).SequenceEqual(oldBytes),
            "Backup .old must retain previous EXE bytes until cleanup.");

        WindowsUpdater.CleanupAfterUpdate(targetExe, updatesRoot, stagingDir, waitPid: null);
        Require(!File.Exists(targetExe + ".old"), "Cleanup must delete .old backup binary.");
        Require(!File.Exists(targetExe + ".new"), "Cleanup must leave no .new temp binary.");
        Require(!Directory.Exists(stagingDir), "Cleanup must remove staging directory.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private static void RequireThrows<TException>(Action action, string message) where TException : Exception
    {
        try { action(); }
        catch (TException) { return; }
        throw new Exception(message);
    }

    private sealed class SynchronousProgress(Action<int> callback) : IProgress<int>
    {
        public void Report(int value) => callback(value);
    }

    private sealed class StubHandler(Func<byte[]> bytesFactory, bool omitContentLength = false) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var data = bytesFactory();
            HttpContent content = omitContentLength
                ? new StreamContent(new MemoryStream(data))
                : new ByteArrayContent(data);
            if (!omitContentLength) content.Headers.ContentLength = data.Length;
            content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
        }
    }
}
