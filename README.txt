CC+ for VRChat Creator Companion (Windows x64)

Download Start CC+.exe from the latest GitHub Release and run it. The self-contained app needs no installation, .NET runtime, or PowerShell.

- Packages: choose a template or project Packages\vpm-manifest.json to add, remove, or update packages. Restore Repo Packages uses VCC's local repo cache.
- Add All Installed to Projects copies missing dependencies into projects in VCC's default project folder. Undo Last Copy restores their backed-up manifests.
- Find Projects: search accessible drives for Unity/VCC projects, select a result, and open its folder. The search is read-only and cancellable.
- Settings: health checks and shortcuts to package search and Find Projects.
- Cache: inspect or clear the selected repo cache folder.

Build from source: run dotnet publish CCPlusLauncher.csproj -c Release and use bin\Release\net10.0-windows\win-x64\publish\Start CC+.exe. Executables are distributed through Releases, not Git (they exceed GitHub's 100 MB file limit).

Safety: package changes back up manifests and ask for confirmation. Clear Cache deletes everything inside the selected folder; check its path and close VRChat first. Project dependencies live in Packages\vpm-manifest.json.

Antivirus: no software can guarantee a 0-detection result. Check the release checksum and report false positives to the scanner vendor; do not disable antivirus.
