using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

internal sealed record PackageInfo(string Id, string Name, string Version, List<string> Versions);

internal static class PackageCatalog
{
    internal static string SettingsPath => Environment.GetEnvironmentVariable("CCPLUS_SETTINGS_PATH") is { Length: > 0 } path
        ? path : Path.Combine(ManifestStore.VccRoot, "settings.json");

    internal static List<PackageInfo> Load(IEnumerable<string>? sourcePaths = null)
    {
        var catalog = new Dictionary<string, PackageInfo>(StringComparer.OrdinalIgnoreCase);
        var repoPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (sourcePaths is not null)
            foreach (var path in sourcePaths) repoPaths.Add(path);
        else
        {
            foreach (var repo in ConfiguredRepos())
            {
                var path = repo["localPath"]?.ToString();
                if (!string.IsNullOrWhiteSpace(path)) repoPaths.Add(path);
            }
            var repoFolder = Path.Combine(ManifestStore.VccRoot, "Repos");
            if (Directory.Exists(repoFolder))
                foreach (var path in Directory.EnumerateFiles(repoFolder, "*.json")) repoPaths.Add(path);
        }

        foreach (var path in repoPaths.Where(File.Exists))
        {
            try
            {
                var doc = ManifestStore.Read(path);
                var packages = doc["repo"]?["packages"] as JsonObject ?? doc["packages"] as JsonObject;
                if (packages is null) continue;
                foreach (var (id, value) in packages)
                {
                    if (value is not JsonObject node) continue;
                    var versions = node["versions"] as JsonObject;
                    if (versions is null || versions.Count == 0) continue;
                    var names = versions.Select(version => version.Key).OrderByDescending(key => ParseVersion(key)).ToList();
                    var latest = names.FirstOrDefault(name => !name.Contains('-', StringComparison.Ordinal)) ?? names[0];
                    var display = versions[latest]?["displayName"]?.ToString() ?? node["displayName"]?.ToString() ?? id;
                    if (!catalog.TryGetValue(id, out var existing))
                        catalog[id] = new PackageInfo(id, display, latest, names);
                    else
                    {
                        var combined = existing.Versions.Concat(names).Distinct(StringComparer.OrdinalIgnoreCase)
                            .OrderByDescending(key => ParseVersion(key)).ToList();
                        var newest = ParseVersion(latest) > ParseVersion(existing.Version) ? latest : existing.Version;
                        catalog[id] = new PackageInfo(id, display, newest, combined);
                    }
                }
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidOperationException)
            {
            }
        }
        return catalog.Values.OrderBy(package => package.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    internal static Version ParseVersion(string text)
    {
        var clean = text.TrimStart('>', '=', '<', ' ', '^', '~').Split('-', '+')[0];
        return Version.TryParse(clean, out var parsed) ? parsed : new Version(0, 0);
    }

    internal static IEnumerable<JsonObject> ConfiguredRepos()
    {
        if (!File.Exists(SettingsPath)) yield break;
        JsonArray? repos;
        try { repos = ManifestStore.Read(SettingsPath)["userRepos"] as JsonArray; }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidOperationException) { yield break; }
        if (repos is null) yield break;
        foreach (var repo in repos)
            if (repo is JsonObject entry) yield return entry;
    }

    internal static async Task<(int Updated, int Failed)> RefreshAsync()
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        var updated = 0;
        var failed = 0;
        foreach (var repo in ConfiguredRepos())
        {
            var url = repo["url"]?.ToString();
            var path = repo["localPath"]?.ToString();
            if (string.IsNullOrWhiteSpace(url) || string.IsNullOrWhiteSpace(path)) continue;
            var temporary = path + ".refresh.tmp";
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                if (repo["headers"] is JsonObject headers)
                    foreach (var (name, value) in headers) request.Headers.TryAddWithoutValidation(name, value?.ToString());
                using var response = await client.SendAsync(request);
                response.EnsureSuccessStatusCode();
                var text = await response.Content.ReadAsStringAsync();
                var parsed = JsonNode.Parse(text);
                if (parsed?["repo"]?["packages"] is not JsonObject) throw new InvalidDataException("Invalid repo package data");
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                await File.WriteAllTextAsync(temporary, text);
                File.Move(temporary, path, true);
                updated++;
            }
            catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException or IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidDataException)
            { failed++; }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        return (updated, failed);
    }
}