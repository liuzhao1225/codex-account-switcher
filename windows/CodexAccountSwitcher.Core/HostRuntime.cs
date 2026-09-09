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
        var digest = Convert.ToHexString(SHA256.HashData(payload.ToArray())); payload.Position = 0;
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Account Switcher Runtime");
        SecureFiles.CreatePrivateDirectory(root);
        var destination = Path.Combine(root, digest); SecureFiles.CreatePrivateDirectory(destination);
        using var archive = new ZipArchive(payload, ZipArchiveMode.Read);
        foreach (var entry in archive.Entries) {
            if (entry.FullName != entry.Name || entry.Name is "." or ".." || string.IsNullOrEmpty(entry.Name))
                throw new IOException("Invalid runtime archive entry.");
            var file = Path.Combine(destination, entry.Name); SecureFiles.RejectLinks(file);
            using var bytes = new MemoryStream(); using (var input = entry.Open()) input.CopyTo(bytes);
            var expected = bytes.ToArray();
            if (!File.Exists(file) || !SHA256.HashData(File.ReadAllBytes(file)).SequenceEqual(SHA256.HashData(expected)))
                SecureFiles.AtomicWrite(file, expected);
        }
        var host = Path.Combine(destination, "SwitcherHost.exe");
        if (!File.Exists(host)) throw new IOException("The runtime archive has no Swift host.");
        return host;
    }
}
