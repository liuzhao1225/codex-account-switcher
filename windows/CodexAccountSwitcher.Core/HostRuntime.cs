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
        using var payload = new MemoryStream(); resource.CopyTo(payload);
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Account Switcher Runtime");
        payload.Position = 0;
        return EnsureExtracted(payload, root);
    }

    internal static string EnsureExtracted(Stream payload, string root)
    {
        var digest = Convert.ToHexString(SHA256.HashData(payload)); payload.Position = 0;
        SecureFiles.CreatePrivateDirectory(root);
        var destination = Path.Combine(root, digest); SecureFiles.CreatePrivateDirectory(destination);
        using var archive = new ZipArchive(payload, ZipArchiveMode.Read);
        foreach (var entry in archive.Entries) {
            if (entry.FullName != entry.Name || entry.Name is "." or ".." || string.IsNullOrEmpty(entry.Name))
                throw new IOException("Invalid runtime archive entry.");
            var file = Path.Combine(destination, entry.Name); SecureFiles.RejectLinks(file);
            if (File.Exists(file)) {
                using var existing = File.OpenRead(file);
                using var expected = entry.Open();
                if (SHA256.HashData(existing).AsSpan().SequenceEqual(SHA256.HashData(expected))) continue;
            }
            using var bytes = new MemoryStream();
            using (var input = entry.Open()) input.CopyTo(bytes);
            SecureFiles.AtomicWrite(file, bytes.ToArray());
        }
        var host = Path.Combine(destination, "SwitcherHost.exe");
        if (!File.Exists(host)) throw new IOException("The runtime archive has no Swift host.");
        return host;
    }
}
