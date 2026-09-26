using System.Drawing;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new Form
        {
            Text = "Codex package update test fixture",
            ClientSize = new Size(360, 90),
            FormBorderStyle = FormBorderStyle.FixedToolWindow,
            StartPosition = FormStartPosition.CenterScreen,
            ShowInTaskbar = true
        });
    }
}
