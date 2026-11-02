using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Contains("--worker"))
        {
            if (args.Contains("--parent")) StartWorker("--worker");
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, $"child-{Environment.ProcessId}.ready"), "ready");
            Thread.Sleep(Timeout.Infinite);
            return;
        }
        var mode = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "mode.txt"));
        if (mode == "tree") StartWorker("--worker --parent");
        if (mode == "headless")
        {
            Record("ready");
            Thread.Sleep(Timeout.Infinite);
            return;
        }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new DesktopFixture(mode));
    }

    private static void StartWorker(string arguments)
    {
        using var child = Process.Start(new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "codex.exe"), arguments)
            { UseShellExecute = false, CreateNoWindow = true });
    }

    private static void Record(string action) => File.AppendAllText(Path.Combine(AppContext.BaseDirectory, "events.txt"), action + "\n");

    private sealed class DesktopFixture : Form
    {
        private readonly string mode;
        protected override bool ShowWithoutActivation => true;

        public DesktopFixture(string mode)
        {
            this.mode = mode;
            Text = "Codex process termination test fixture";
            ClientSize = new Size(360, 90);
            FormBorderStyle = FormBorderStyle.FixedSingle;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;
            if (mode == "minimized") WindowState = FormWindowState.Minimized;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            Record("ready");
            if (mode == "unresponsive") Thread.Sleep(Timeout.Infinite);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            e.Cancel = true;
            Hide();
            Record("hidden");
            base.OnFormClosing(e);
        }
    }
}