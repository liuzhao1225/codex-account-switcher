using System.Security.AccessControl;
using System.Security.Principal;

namespace CodexAccountSwitcher.Core;

public static class SecureFiles
{
    private static readonly SecurityIdentifier User = WindowsIdentity.GetCurrent().User
        ?? throw new InvalidOperationException("Windows user identity is unavailable.");

    public static void RejectLinks(string path)
    {
        for (var current = Path.GetFullPath(path); !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current))
                && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Account storage cannot use symbolic links or junctions.");
    }

    public static void CreatePrivateDirectory(string path)
    {
        RejectLinks(path);
        var security = new DirectorySecurity();
        security.SetOwner(User);
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new FileSystemAccessRule(User, FileSystemRights.FullControl,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        var directory = new DirectoryInfo(path);
        directory.Create(security);
        directory.SetAccessControl(security);
    }

    public static void AtomicWrite(string destination, byte[] bytes)
    {
        RejectLinks(destination);
        var directory = Path.GetDirectoryName(Path.GetFullPath(destination))!;
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".switcher-{Guid.NewGuid():N}.tmp");
        var security = new FileSecurity();
        security.SetOwner(User);
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new FileSystemAccessRule(User, FileSystemRights.FullControl, AccessControlType.Allow));
        try
        {
            using (var stream = FileSystemAclExtensions.Create(new FileInfo(temporary), FileMode.CreateNew,
                FileSystemRights.FullControl, FileShare.None, 4096, FileOptions.WriteThrough, security))
            {
                stream.Write(bytes);
                stream.Flush(true);
            }
            // Same-volume rename, with the new file's restrictive ACL. Never truncate active auth.
            File.Move(temporary, destination, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public static void DeleteOwnedDirectory(string root, string path)
    {
        var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var fullPath = Path.GetFullPath(path);
        if (!fullPath.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
            throw new IOException("Cleanup path is outside account storage.");
        RejectLinks(fullPath);
        if (!Directory.Exists(fullPath)) return;
        // Check each level before descending; do not traverse reparse points.
        CheckTree(fullPath);
        Directory.Delete(fullPath, recursive: true);
    }

    private static void CheckTree(string path)
    {
        foreach (var entry in Directory.EnumerateFileSystemEntries(path))
        {
            RejectLinks(entry);
            if (Directory.Exists(entry)) CheckTree(entry);
        }
    }
}
