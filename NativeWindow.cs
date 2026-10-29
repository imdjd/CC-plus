using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

internal sealed class NativeWindow : Form
{
    private readonly TabControl tabs = new() { Dock = DockStyle.Fill };
    private readonly TabPage packagesTab = new("Packages"), cacheTab = new("Cache"), settingsTab = new("Settings"), projectsTab = new("Find Projects");
    private readonly Label status = new() { AutoSize = true, Padding = new Padding(3) };
    private readonly Label manifestLabel = new() { AutoSize = true, Padding = new Padding(3) };
    private readonly TextBox search = new() { Width = 280, PlaceholderText = "Search packages" };
    private readonly ComboBox filter = new() { Width = 130, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly DataGridView grid = new() { Dock = DockStyle.Fill, AutoGenerateColumns = false, AllowUserToAddRows = false, AllowUserToDeleteRows = false, RowHeadersVisible = false, SelectionMode = DataGridViewSelectionMode.FullRowSelect, MultiSelect = false, BackgroundColor = System.Drawing.Color.White };
    private readonly Button undoButton = new() { Text = "Undo Last Copy", AutoSize = true };
    private readonly TextBox cachePath = new() { Width = 650 };
    private readonly Label cacheInfo = new() { AutoSize = true };
    private readonly Label settingsInfo = new() { AutoSize = true, MaximumSize = new System.Drawing.Size(850, 0) };
    private readonly ListBox projectResults = new() { Dock = DockStyle.Fill, HorizontalScrollbar = true };
    private readonly Button scanButton = new() { Text = "Search Drives", AutoSize = true };
    private readonly Button cancelButton = new() { Text = "Cancel", Enabled = false, AutoSize = true };
    private readonly Label scanInfo = new() { AutoSize = true, Text = "Search is read-only. Inaccessible folders are skipped." };
    private CancellationTokenSource? scanCancellation;
    private List<PackageInfo> catalog = new();
    private string? manifestPath;

    internal NativeWindow()
    {
        Text = "CC+ - VRChat Creator Companion";
        MinimumSize = new System.Drawing.Size(850, 580);
        Size = new System.Drawing.Size(1050, 750);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new System.Drawing.Font("Segoe UI", 9);
        Controls.Add(tabs);
        tabs.TabPages.AddRange(new[] { packagesTab, cacheTab, settingsTab, projectsTab });
        BuildPackages();
        BuildCache();
        BuildSettings();
        BuildProjects();
        manifestPath = new[] { "Avatar", "Avatar 2019" }
            .Select(name => Template(name)).FirstOrDefault(File.Exists);
        cachePath.Text = Path.Combine(ManifestStore.VccRoot, "Repos");
        Reload();
    }

    private static FlowLayoutPanel Row() => new() { Dock = DockStyle.Top, AutoSize = true, WrapContents = true, Padding = new Padding(9), Margin = new Padding(0) };
    private static Button Button(string text, Action onClick)
    {
        var button = new Button { Text = text, AutoSize = true, MinimumSize = new System.Drawing.Size(105, 34), Margin = new Padding(3) };
        button.Click += (_, _) => onClick();
        return button;
    }
    private void Guard(Action action)
    {
        try { action(); }
        catch (Exception exception) { MessageBox.Show(this, exception.Message, "CC+", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
    private bool Confirm(string message) => MessageBox.Show(this, message, "CC+", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;
    private static string Template(string name) => Path.Combine(ManifestStore.VccRoot, "VRCTemplates", name, "Packages", "vpm-manifest.json");
    private string SelectedManifest() => manifestPath is not null && File.Exists(manifestPath) ? manifestPath : throw new FileNotFoundException("Choose a vpm-manifest.json first.");
    private void OpenFolder(string path) => Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });

    private void BuildPackages()
    {
        var top = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(8) };
        packagesTab.Controls.Add(grid);
        packagesTab.Controls.Add(top);
        var actions = Row();
        actions.Controls.Add(Button("Avatar", () => ChooseTemplate("Avatar", "Avatar 2019")));
        actions.Controls.Add(Button("Worlds", () => ChooseTemplate("World", "World 2019")));
        actions.Controls.Add(Button("Open Manifest", OpenManifest));
        actions.Controls.Add(Button("Refresh", Reload));
        actions.Controls.Add(Button("Refresh Repos", async () => await RefreshRepos()));
        top.Controls.Add(actions);
        var bulk = Row();
        bulk.Controls.Add(Button("Restore Repo Packages", () => Guard(RestoreRepoPackages)));
        bulk.Controls.Add(Button("Update All", () => Guard(UpdateAll)));
        bulk.Controls.Add(Button("Add All Installed to Projects", () => Guard(CopyToProjects)));
        undoButton.MinimumSize = new System.Drawing.Size(120, 34);
        undoButton.Click += (_, _) => Guard(UndoCopy);
        bulk.Controls.Add(undoButton);
        top.Controls.Add(bulk);
        var searchRow = Row();
        searchRow.Controls.Add(search);
        filter.Items.AddRange(new object[] { "All", "Installed", "Available" });
        filter.SelectedIndex = 0;
        searchRow.Controls.Add(filter);
        top.Controls.Add(searchRow);
        top.Controls.Add(manifestLabel);
        top.Controls.Add(status);
        search.TextChanged += (_, _) => ShowPackages();
        filter.SelectedIndexChanged += (_, _) => ShowPackages();

        grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "Package", HeaderText = "Package", ReadOnly = true, FillWeight = 35 });
        grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "Id", HeaderText = "Package ID", ReadOnly = true, FillWeight = 38 });
        grid.Columns.Add(new DataGridViewComboBoxColumn { Name = "Version", HeaderText = "Version", FillWeight = 18, FlatStyle = FlatStyle.Flat });
        grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "State", HeaderText = "State", ReadOnly = true, FillWeight = 12 });
        grid.Columns.Add(new DataGridViewButtonColumn { Name = "Action", HeaderText = "Action", FillWeight = 13 });
        grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        grid.CellContentClick += (_, args) => { if (args.RowIndex >= 0 && args.ColumnIndex == 4) Guard(() => ChangePackage(args.RowIndex)); };
    }

    private void ChooseTemplate(params string[] names)
    {
        manifestPath = names.Select(Template).FirstOrDefault(File.Exists);
        Reload();
    }
    private void OpenManifest()
    {
        using var picker = new OpenFileDialog { Filter = "VPM manifest (vpm-manifest.json)|vpm-manifest.json|JSON files (*.json)|*.json", FileName = "vpm-manifest.json" };
        if (picker.ShowDialog(this) == DialogResult.OK) { manifestPath = picker.FileName; Reload(); }
    }
    private void Reload()
    {
        catalog = PackageCatalog.Load();
        manifestLabel.Text = manifestPath ?? "No manifest selected. Choose a template or open a manifest.";
        undoButton.Enabled = File.Exists(ManifestStore.UndoPath);
        ShowPackages();
    }
    private void ShowPackages()
    {
        grid.Rows.Clear();
        var installed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try { if (manifestPath is not null && File.Exists(manifestPath)) installed = ManifestStore.Dependencies(manifestPath); }
        catch (Exception exception) { status.Text = $"Could not read manifest: {exception.Message}"; return; }
        var all = catalog.ToDictionary(entry => entry.Id, StringComparer.OrdinalIgnoreCase);
        foreach (var (id, version) in installed)
            if (!all.ContainsKey(id)) all[id] = new PackageInfo(id, id, version, new List<string> { version });
        foreach (var package in all.Values.OrderBy(entry => entry.Name, StringComparer.OrdinalIgnoreCase))
        {
            var isInstalled = installed.TryGetValue(package.Id, out var current);
            if (filter.SelectedItem?.ToString() == "Installed" && !isInstalled || filter.SelectedItem?.ToString() == "Available" && isInstalled) continue;
            if (!package.Name.Contains(search.Text, StringComparison.OrdinalIgnoreCase) && !package.Id.Contains(search.Text, StringComparison.OrdinalIgnoreCase)) continue;
            var index = grid.Rows.Add();
            var row = grid.Rows[index];
            row.Cells[0].Value = package.Name;
            row.Cells[1].Value = package.Id;
            var versionCell = (DataGridViewComboBoxCell)row.Cells[2];
            var choices = package.Versions.Concat(new[] { package.Version, current ?? "" }).Where(text => text.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            versionCell.Items.AddRange(choices);
            versionCell.Value = current ?? package.Version;
            row.Cells[3].Value = isInstalled ? "Installed" : "Available";
            row.Cells[4].Value = isInstalled ? "Remove" : "Add";
        }
    }
    private void ChangePackage(int index)
    {
        grid.EndEdit();
        var path = SelectedManifest();
        var row = grid.Rows[index];
        var id = row.Cells[1].Value?.ToString() ?? throw new InvalidDataException("Missing package ID");
        var version = row.Cells[2].Value?.ToString() ?? throw new InvalidDataException("Select a version");
        var installed = ManifestStore.Dependencies(path);
        var target = installed.ContainsKey(id) ? "remove" : "add";
        if (installed.TryGetValue(id, out var current) && !string.Equals(current, version, StringComparison.OrdinalIgnoreCase)) target = "update";
        if (!Confirm($"{target} {id} ({version}) in:\n{path}?\nA backup will be created first.")) return;
        ManifestStore.Backup(path);
        if (target == "remove") ManifestStore.Change(path, removals: new[] { id });
        else ManifestStore.Change(path, new Dictionary<string, string> { [id] = version });
        status.Text = $"{id}: {target} completed.";
        Reload();
    }
    private async Task RefreshRepos()
    {
        try
        {
            status.Text = "Refreshing repos...";
            var (updated, failed) = await PackageCatalog.RefreshAsync();
            Reload();
            status.Text = $"Refreshed {updated} repos; {failed} failed.";
        }
        catch (Exception exception) { MessageBox.Show(this, exception.Message, "Repo refresh error"); }
    }
    private void ApplyPlans(List<(string Path, Dictionary<string, string> Changes)> plans, string title)
    {
        if (plans.Count == 0) { status.Text = "Nothing to change."; return; }
        var count = plans.Sum(plan => plan.Changes.Count);
        if (!Confirm($"{title}: {count} package entries across {plans.Count} manifest(s)?\nExisting versions are kept where possible. Each changed file is backed up.")) return;
        foreach (var plan in plans) ManifestStore.Backup(plan.Path);
        foreach (var plan in plans) ManifestStore.Change(plan.Path, plan.Changes);
        Reload();
        status.Text = $"{title}: {count} entries applied.";
    }
    private void RestoreRepoPackages()
    {
        var path = SelectedManifest();
        var targets = LinkedTargets(path);
        var plans = new List<(string, Dictionary<string, string>)>();
        foreach (var target in targets)
        {
            var installed = ManifestStore.Dependencies(target);
            var missing = catalog.Where(entry => !entry.Id.StartsWith("com.vrchat.", StringComparison.OrdinalIgnoreCase) && !installed.ContainsKey(entry.Id))
                .ToDictionary(entry => entry.Id, entry => entry.Version, StringComparer.OrdinalIgnoreCase);
            if (missing.Count > 0) plans.Add((target, missing));
        }
        ApplyPlans(plans, "Restore repo packages");
    }
    private static IEnumerable<string> LinkedTargets(string path)
    {
        foreach (var names in new[] { new[] { "Avatar", "Avatar 2019" }, new[] { "World", "World 2019" } })
        {
            var pair = names.Select(Template).ToArray();
            if (pair.Any(candidate => string.Equals(candidate, path, StringComparison.OrdinalIgnoreCase)) && pair.All(File.Exists)) return pair;
        }
        return new[] { path };
    }
    private void UpdateAll()
    {
        var path = SelectedManifest();
        var plans = new List<(string, Dictionary<string, string>)>();
        foreach (var target in LinkedTargets(path))
        {
            var installed = ManifestStore.Dependencies(target);
            var newer = catalog.Where(entry => installed.TryGetValue(entry.Id, out var version) && PackageCatalog.ParseVersion(entry.Version) > PackageCatalog.ParseVersion(version))
                .ToDictionary(entry => entry.Id, entry => entry.Version, StringComparer.OrdinalIgnoreCase);
            if (newer.Count > 0) plans.Add((target, newer));
        }
        ApplyPlans(plans, "Update all");
    }
    private void CopyToProjects()
    {
        var path = SelectedManifest();
        var source = ManifestStore.Dependencies(path);
        var plans = new List<(string Path, Dictionary<string, string> Changes)>();
        foreach (var target in ManifestStore.ProjectManifests().Where(target => !string.Equals(target, path, StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                var existing = ManifestStore.Dependencies(target);
                var missing = source.Where(entry => !existing.ContainsKey(entry.Key))
                    .ToDictionary(entry => entry.Key, entry => entry.Value, StringComparer.OrdinalIgnoreCase);
                if (missing.Count > 0) plans.Add((target, missing));
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Text.Json.JsonException) { }
        }
        if (plans.Count == 0) { status.Text = "No projects need packages."; return; }
        if (!Confirm($"Copy {plans.Sum(plan => plan.Changes.Count)} missing entries to {plans.Count} projects?\nBackups will be created first. This replaces the previous Undo Last Copy record.")) return;
        var backups = plans.Select(plan => new ManifestBackup(plan.Path, ManifestStore.Backup(plan.Path))).ToList();
        ManifestStore.SaveUndo(path, backups);
        foreach (var plan in plans) ManifestStore.Change(plan.Path, plan.Changes);
        undoButton.Enabled = true;
        status.Text = $"Copied packages to {plans.Count} projects.";
    }
    private void UndoCopy()
    {
        var record = ManifestStore.LoadUndo();
        if (record is null || record.Backups.Count == 0) { undoButton.Enabled = false; return; }
        if (record.Backups.Any(entry => !File.Exists(entry.ManifestPath) || !File.Exists(entry.BackupPath)))
            throw new FileNotFoundException("A backup or project file is missing; nothing was restored.");
        if (!Confirm($"Restore {record.Backups.Count} project manifests to their state before the last copy?")) return;
        foreach (var entry in record.Backups) ManifestStore.Backup(entry.ManifestPath);
        foreach (var entry in record.Backups) File.Copy(entry.BackupPath, entry.ManifestPath, true);
        File.Delete(ManifestStore.UndoPath);
        undoButton.Enabled = false;
        Reload();
        status.Text = "Last copy undone.";
    }

    private void BuildCache()
    {
        var layout = Row();
        cacheTab.Controls.Add(layout);
        layout.Controls.Add(cachePath);
        layout.Controls.Add(Button("Browse", () => { using var picker = new FolderBrowserDialog(); if (picker.ShowDialog(this) == DialogResult.OK) cachePath.Text = picker.SelectedPath; }));
        layout.Controls.Add(Button("Open Folder", () => Guard(() => OpenFolder(cachePath.Text))));
        layout.Controls.Add(Button("Refresh Info", RefreshCacheInfo));
        layout.Controls.Add(Button("Clear Cache", () => Guard(ClearCache)));
        var info = Row(); info.Controls.Add(cacheInfo); cacheTab.Controls.Add(info); info.BringToFront();
        cachePath.TextChanged += (_, _) => RefreshCacheInfo();
    }
    private void RefreshCacheInfo()
    {
        try
        {
            if (!Directory.Exists(cachePath.Text)) { cacheInfo.Text = "Folder not found."; return; }
            cacheInfo.Text = $"{Directory.EnumerateFileSystemEntries(cachePath.Text).Count()} items in {cachePath.Text}";
        }
        catch (Exception exception) { cacheInfo.Text = exception.Message; }
    }
    private void ClearCache()
    {
        var path = Path.GetFullPath(cachePath.Text);
        if (!Directory.Exists(path) || Path.GetPathRoot(path) == path ||
            string.Equals(path.TrimEnd(Path.DirectorySeparatorChar), ManifestStore.VccRoot, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Select a cache folder, not the VCC data folder or a drive root.");
        if (!Confirm($"Delete everything INSIDE this folder?\n{path}\nThis cannot be undone.")) return;
        foreach (var entry in Directory.EnumerateFileSystemEntries(path))
        {
            if (Directory.Exists(entry)) Directory.Delete(entry, true);
            else File.Delete(entry);
        }
        RefreshCacheInfo();
    }

    private void BuildSettings()
    {
        var layout = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(12), AutoScroll = true };
        settingsTab.Controls.Add(layout);
        layout.Controls.Add(Button("Settings Health Check", CheckSettings));
        layout.Controls.Add(Button("Repair Settings JSON", () => Guard(RepairSettings)));
        layout.Controls.Add(Button("Search Packages", () => { tabs.SelectedTab = packagesTab; search.Focus(); }));
        layout.Controls.Add(Button("Find Projects", () => tabs.SelectedTab = projectsTab));
        layout.Controls.Add(settingsInfo);
        CheckSettings();
    }
    private void CheckSettings()
    {
        var path = PackageCatalog.SettingsPath;
        try
        {
            var json = ManifestStore.Read(path);
            settingsInfo.Text = $"Settings: {path}\nReadable JSON. Configured repos: {(json["userRepos"] as JsonArray)?.Count ?? 0}.";
        }
        catch (Exception exception) { settingsInfo.Text = $"Settings: {path}\nCould not read settings: {exception.Message}. No changes were made."; }
    }
    private void RepairSettings()
    {
        var path = PackageCatalog.SettingsPath;
        if (File.Exists(path))
        {
            var content = File.ReadAllBytes(path);
            if (content.Contains((byte)0) || System.Text.Encoding.UTF8.GetString(content).StartsWith("SQLite format 3", StringComparison.Ordinal))
                throw new InvalidDataException("Settings contains binary/database data; JSON repair is disabled.");
            try { ManifestStore.Read(path); throw new InvalidOperationException("Settings is already valid JSON; no repair needed."); }
            catch (System.Text.Json.JsonException) { }
        }
        if (!Confirm($"Rebuild missing or invalid settings.json at:\n{path}?\nThe original will be backed up first.")) return;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (File.Exists(path)) File.Copy(path, path + $".corrupt.{DateTime.Now:yyyyMMdd_HHmmss}.bak");
        var repos = new JsonArray();
        var repoPath = Path.Combine(ManifestStore.VccRoot, "Repos");
        if (Directory.Exists(repoPath))
            foreach (var file in Directory.EnumerateFiles(repoPath, "*.json")) repos.Add(new JsonObject { ["localPath"] = file });
        File.WriteAllText(path, new JsonObject { ["userRepos"] = repos }.ToJsonString());
        CheckSettings();
    }

    private void BuildProjects()
    {
        projectsTab.Controls.Add(projectResults);
        var row = Row();
        row.Controls.Add(scanButton);
        row.Controls.Add(cancelButton);
        row.Controls.Add(Button("Open Folder", () => { if (projectResults.SelectedItem is string path) Guard(() => OpenFolder(path)); }));
        row.Controls.Add(scanInfo);
        projectsTab.Controls.Add(row);
        scanButton.Click += async (_, _) => await ScanProjects();
        cancelButton.Click += (_, _) => scanCancellation?.Cancel();
        projectResults.DoubleClick += (_, _) => { if (projectResults.SelectedItem is string path) Guard(() => OpenFolder(path)); };
    }
    private async Task ScanProjects()
    {
        scanCancellation = new CancellationTokenSource();
        scanButton.Enabled = false;
        cancelButton.Enabled = true;
        projectResults.Items.Clear();
        var checkedFolders = 0;
        var skipped = 0;
        var progress = new Progress<string>(path => { projectResults.Items.Add(path); scanInfo.Text = $"Found {projectResults.Items.Count} projects; checked {checkedFolders} folders."; });
        try
        {
            await Task.Run(() =>
            {
                var queue = new Queue<string>(DriveInfo.GetDrives().Where(drive => drive.IsReady && drive.DriveType is DriveType.Fixed or DriveType.Removable or DriveType.Network).Select(drive => drive.RootDirectory.FullName));
                while (queue.Count > 0 && !scanCancellation.Token.IsCancellationRequested)
                {
                    var folder = queue.Dequeue();
                    checkedFolders++;
                    if (File.Exists(Path.Combine(folder, "Packages", "vpm-manifest.json")) || File.Exists(Path.Combine(folder, "ProjectSettings", "ProjectVersion.txt")))
                        ((IProgress<string>)progress).Report(folder);
                    try
                    {
                        foreach (var child in Directory.EnumerateDirectories(folder))
                        {
                            var name = Path.GetFileName(child);
                            if (name is ".git" or "node_modules" or "Library" or "Temp" or "obj" or "bin") continue;
                            try { if ((File.GetAttributes(child) & FileAttributes.ReparsePoint) == 0) queue.Enqueue(child); }
                            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException) { skipped++; }
                        }
                    }
                    catch (Exception exception) when (exception is IOException or UnauthorizedAccessException) { skipped++; }
                }
            });
            scanInfo.Text = $"{(scanCancellation.IsCancellationRequested ? "Cancelled" : "Finished")}: found {projectResults.Items.Count} projects; checked {checkedFolders} folders; skipped {skipped} inaccessible folders.";
        }
        catch (Exception exception) { scanInfo.Text = $"Search stopped: {exception.Message}"; }
        finally { scanButton.Enabled = true; cancelButton.Enabled = false; scanCancellation.Dispose(); scanCancellation = null; }
    }
}