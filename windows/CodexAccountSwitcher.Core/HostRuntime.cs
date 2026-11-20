using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;

namespace CodexAccountSwitcher.Core;

public static class HostRuntime
{
    public static string Resolve(Assembly application)
    {
        if (Environment.GetEnvironmentVariable("CODEX_SWITCHER_HOST_PATH") is { Length: > 0 } development)
            return Path.GetFullPath(development);
        using var resource = application.GetManifestResourceStream("SwitcherRuntime.zip")
            ?? throw new FileNotFoundException("The shared Swift runtime is missing. Build with scripts/package-windows.ps1.");
        using var payload = new MemoryStream();
        resource.CopyTo(payload);
        var digest = Convert.ToHexString(SHA256.HashData(payload.GetBuffer().AsSpan(0, (int)payload.Length)));
        payload.Position = 0;
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Account Switcher Runtime");
        SecureFiles.CreatePrivateDirectory(root);
        var destination = Path.Combine(root, digest);
        var host = Path.Combine(destination, "SwitcherHost.exe");
        var marker = Path.Combine(destination, ".extracted");
        if (File.Exists(marker) && File.Exists(host)) {
            CleanupStaleRuntimes(root, digest);
            return host;
        }
        SecureFiles.CreatePrivateDirectory(destination);
        using var archive = new ZipArchive(payload, ZipArchiveMode.Read);
        foreach (var entry in archive.Entries) {
            if (entry.FullName != entry.Name || entry.Name is "." or ".." || string.IsNullOrEmpty(entry.Name))
                throw new IOException("Invalid runtime archive entry.");
            var file = Path.Combine(destination, entry.Name);
            SecureFiles.RejectLinks(file);
            using var bytes = new MemoryStream();
            using (var input = entry.Open()) input.CopyTo(bytes);
            SecureFiles.AtomicWrite(file, bytes.ToArray());
        }
        if (!File.Exists(host)) throw new IOException("The runtime archive has no Swift host.");
        SecureFiles.AtomicWrite(marker, "ok"u8.ToArray());
        CleanupStaleRuntimes(root, digest);
        return host;
    }

    private static void CleanupStaleRuntimes(string root, string activeDigest)
    {
        try {
            foreach (var directory in Directory.EnumerateDirectories(root)) {
                if (string.Equals(Path.GetFileName(directory), activeDigest, StringComparison.OrdinalIgnoreCase)) continue;
                try { SecureFiles.DeleteOwnedDirectory(root, directory); } catch { /* May be in use by an exiting instance. */ }
            }
        } catch { }
    }
}
