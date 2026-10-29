using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        string scriptText;
        using (var scriptStream = typeof(Program).Assembly.GetManifestResourceStream("CCPlusTool.ps1"))
        {
            if (scriptStream == null)
            {
                MessageBox.Show("The embedded CCPlusTool.ps1 resource is missing.", "Start CC+", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            using (var reader = new StreamReader(scriptStream, Encoding.UTF8))
            {
                scriptText = reader.ReadToEnd();
            }
        }
        string tempScriptPath = Path.Combine(Path.GetTempPath(), "CCPlusTool_" + Guid.NewGuid().ToString("N") + ".ps1");

        try
        {
            File.WriteAllText(tempScriptPath, scriptText, new UTF8Encoding(false));

            string powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                @"System32\\WindowsPowerShell\\v1.0\\powershell.exe"
            );

            var workingDir = AppContext.BaseDirectory;
            var psi = new ProcessStartInfo
            {
                FileName = powershellPath,
                Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + tempScriptPath + "\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = workingDir
            };
            psi.Environment["CCPLUS_WORKING_DIR"] = workingDir;

            using (var process = Process.Start(psi))
            {
                process.WaitForExit();
                if (process.ExitCode != 0)
                {
                    MessageBox.Show(
                        "CC+ exited with an error.",
                        "Start CC+",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning
                    );
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Failed to launch CC+:\n" + ex.Message,
                "Start CC+",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        }
        finally
        {
            try
            {
                if (File.Exists(tempScriptPath))
                {
                    File.Delete(tempScriptPath);
                }
            }
            catch
            {
            }
        }
    }
}
