using System;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test") return NativeTests.Run();
        ApplicationConfiguration.Initialize();
        Application.Run(new NativeWindow());
        return 0;
    }
}