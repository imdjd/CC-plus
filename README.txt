CC+ is a lightweight Windows companion tool for managing VRChat project packages and maintaining the local package cache.

Download the complete CC+ folder from the latest GitHub Release and run Start CC+.exe. The self-contained app needs no installation, .NET runtime, or PowerShell. The multi-file publish includes portable debugging symbols for inspection and troubleshooting.

- Packages: choose a template or project Packages\vpm-manifest.json to add, remove, or update packages. Restore Repo Packages uses VCC's local repo cache.
- Add All Installed to Projects copies missing dependencies into projects in VCC's default project folder. Undo Last Copy restores their backed-up manifests.
- Settings: inspect or clear the selected repo cache folder, with a shortcut to package search.

Build from source: run dotnet publish CCPlusLauncher.csproj -c Release and use the complete output in bin\Release\net10.0-windows\win-x64\publish. Executables are distributed through Releases, not Git (they exceed GitHub's 100 MB file limit).

Safety: package changes back up manifests and ask for confirmation. Clear Cache deletes everything inside the selected folder; check its path and close VRChat first. Project dependencies live in Packages\vpm-manifest.json.

