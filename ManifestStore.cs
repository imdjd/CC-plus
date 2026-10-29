using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

internal sealed record ManifestBackup(string ManifestPath, string BackupPath);
internal sealed record CopyUndo(DateTime CreatedAt, string SourceManifest, List<ManifestBackup> Backups);

internal static class ManifestStore
{
    internal static readonly string VccRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VRChatCreatorCompanion");
    internal static readonly string DataRoot = Path.Combine(VccRoot, "CCPlus");
    internal static readonly string UndoPath = Path.Combine(DataRoot, "last-project-copy-undo.json");
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };

    internal static JsonObject Read(string path) => JsonNode.Parse(File.ReadAllText(path)) as JsonObject
        ?? throw new InvalidDataException($"Invalid JSON object: {path}");

    internal static Dictionary<string, string> Dependencies(string path)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (Read(path)["dependencies"] is JsonObject dependencies)
            foreach (var entry in dependencies)
                result[entry.Key] = entry.Value?["version"]?.ToString() ?? ">=1.0.0";
        return result;
    }

    internal static string Backup(string path, string? backupDirectory = null)
    {
        var directory = backupDirectory ?? Path.Combine(DataRoot, "Backups");
        Directory.CreateDirectory(directory);
        var target = Path.Combine(directory, $"{Path.GetFileName(path)}_{DateTime.Now:yyyyMMdd_HHmmss_fff}_{Guid.NewGuid():N}.json.bak");
        File.Copy(path, target);
        return target;
    }

    internal static void Change(string path, IReadOnlyDictionary<string, string>? updates = null, IEnumerable<string>? removals = null)
    {
        var document = Read(path);
        var dependencies = document["dependencies"] as JsonObject;
        if (dependencies is null)
        {
            dependencies = new JsonObject();
            document["dependencies"] = dependencies;
        }
        if (removals is not null)
            foreach (var name in removals) dependencies.Remove(name);
        if (updates is not null)
            foreach (var (name, version) in updates)
            {
                if (dependencies[name] is not JsonObject package)
                {
                    package = new JsonObject();
                    dependencies[name] = package;
                }
                package["version"] = version;
            }
        var temporary = path + ".ccplus.tmp";
        try
        {
            File.WriteAllText(temporary, document.ToJsonString(JsonOptions));
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    internal static IEnumerable<string> ProjectManifests()
    {
        var root = Path.Combine(VccRoot, "VRChatProjects");
        if (!Directory.Exists(root)) yield break;
        foreach (var project in Directory.EnumerateDirectories(root))
        {
            var manifest = Path.Combine(project, "Packages", "vpm-manifest.json");
            if (File.Exists(manifest)) yield return manifest;
        }
    }

    internal static CopyUndo? LoadUndo()
    {
        if (!File.Exists(UndoPath)) return null;
        return JsonSerializer.Deserialize<CopyUndo>(File.ReadAllText(UndoPath), JsonOptions);
    }

    internal static void SaveUndo(string source, List<ManifestBackup> backups)
    {
        Directory.CreateDirectory(DataRoot);
        File.WriteAllText(UndoPath, JsonSerializer.Serialize(new CopyUndo(DateTime.Now, source, backups), JsonOptions));
    }
}