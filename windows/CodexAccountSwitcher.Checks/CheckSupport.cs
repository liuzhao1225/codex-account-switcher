namespace CodexAccountSwitcher.Checks;

internal static class CheckSupport
{
    public const string CrossLangPublicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEkeWTKfZIKx3GnWkh5xBlkyWt10Uhd7iJ0vnjlxDR8Ola1nSSc+wDED/iA8UNoy9bDrU7lHQCfN5dZo5MFByp7A==";
    public const string CrossLangManifestJson = """
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

    public static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    public static void RequireThrows<TException>(Action action, string message) where TException : Exception
    {
        try { action(); }
        catch (TException) { return; }
        throw new InvalidOperationException(message);
    }

    public static async Task UntilAsync(Func<bool> condition, int timeoutSeconds = 10, int pollMilliseconds = 50)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        while (!condition()) await Task.Delay(pollMilliseconds, timeout.Token);
    }
}
