using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Forms;

internal static class NativeTests
{
    internal static int Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "CCPlusTest_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var manifest = Path.Combine(root, "vpm-manifest.json");
            File.WriteAllText(manifest, "{\"name\":\"Test\",\"dependencies\":{\"com.example.existing\":{\"version\":\"1.0.0\",\"custom\":true}}}");
            var backup = ManifestStore.Backup(manifest, root);
            ManifestStore.Change(manifest, new Dictionary<string, string> { ["com.example.added"] = "2.0.0" });
            var updated = ManifestStore.Read(manifest);
            if (updated["name"]?.ToString() != "Test" || updated["dependencies"]?["com.example.existing"]?["custom"]?.ToString() != "true" || ManifestStore.Dependencies(manifest)["com.example.added"] != "2.0.0") return 1;
            ManifestStore.Change(manifest, removals: new[] { "com.example.added" });
            if (ManifestStore.Dependencies(manifest).ContainsKey("com.example.added")) return 2;
            File.Copy(backup, manifest, true);
            if (ManifestStore.Dependencies(manifest)["com.example.existing"] != "1.0.0") return 3;
            var repo = Path.Combine(root, "repo.json");
            File.WriteAllText(repo, "{\"repo\":{\"packages\":{\"com.example.added\":{\"versions\":{\"1.0.0\":{},\"2.0.0\":{\"displayName\":\"Example\"}}}}}}");
            var catalog = PackageCatalog.Load(new[] { repo });
            if (catalog.Count != 1 || catalog[0].Name != "Example" || catalog[0].Version != "2.0.0") return 6;
            using var window = new NativeWindow();
            window.Show();
            Application.DoEvents();
            var tabs = window.Controls.OfType<TabControl>().Single();
            if (tabs.TabPages.Count != 2 || tabs.TabPages[0].Text != "Packages" || tabs.TabPages[1].Text != "Settings") return 4;
            if (AllControls(window).OfType<Button>().Any(button => button.Text is "Find Projects" or "Search Drives")) return 7;
            var settings = tabs.TabPages[1];
            var settingsButtons = AllControls(settings).OfType<Button>().ToArray();
            if (!settingsButtons.Any(button => button.Text == "Clear Cache") || settingsButtons.Any(button => button.Text is "Settings Health Check" or "Repair Settings JSON")) return 8;
            var actions = AllControls(tabs.TabPages[0]).OfType<DataGridView>().Single().Rows.Cast<DataGridViewRow>()
                .Select(row => row.Cells["Action"].Value?.ToString()).OfType<string>().ToArray();
            var firstAdd = Array.IndexOf(actions, "Add");
            if (firstAdd >= 0 && actions.Skip(firstAdd).Contains("Remove")) return 9;
            window.Close();
            return 0;
        }
        catch { return 5; }
        finally { Directory.Delete(root, true); }
    }

    private static IEnumerable<Control> AllControls(Control parent)
    {
        foreach (Control child in parent.Controls)
        {
            yield return child;
            foreach (var descendant in AllControls(child)) yield return descendant;
        }
    }
}