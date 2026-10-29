VRChat CC Cache Cleaner (No Install)

What this does:
- Opens a small Windows app.
- Tab 1 (Packages): browse and add/remove packages one at a time.
- Restore Repo Packages: add missing third-party packages from the local VCC repo cache to the selected template manifest.
- Tab 2 (Cache): clear repo cache folder contents.
- Find Projects tab: search accessible fixed, removable, and network drives for Unity/VCC project folders, then select a result and open its folder. Search is read-only and can be cancelled; inaccessible folders are skipped.
- Defaults to VRCTemplates manifests, but you can browse to any vpm-manifest.json.
- "Clear Cache" deletes everything INSIDE the selected cache folder.
- Package Refresh downloads updated metadata from configured VCC repos and reloads the package list.
- Update All checks installed packages against refreshed repos and applies all newer stable versions in one confirmed batch.
- Add All Installed to Projects copies every dependency in the selected source manifest to every readable VCC project manifest where each package is missing.
- Undo Last Copy restores the project manifests from before the most recent Add All Installed to Projects operation.
- Settings has a Search Packages button that opens the search field on the Packages tab, and a Find Projects button that opens the project search tab.
- Select a package version from its Version dropdown; only the newest stable option uses an open-ended >= constraint, while older options remain exact versions.

How to run:
1) From a source checkout, use Start CC+.bat to run the script directly, or build the executable with: dotnet publish CCPlusLauncher.csproj -c Release
	The built executable is in bin\Release\net10.0-windows\win-x64\publish\Start CC+.exe.
2) Use Cache tab to clear repo cache if needed
3) Use Packages tab, choose a target template or project vpm-manifest.json
4) Choose a source manifest (Avatar or Worlds), then use Add All Installed to Projects to copy all its packages to existing projects; use Restore Repo Packages to add all repo packages to the selected template
5) Use quick buttons: Avatar / Worlds / Open Manifest / Refresh
6) Open Find Projects and click Search Drives to locate existing projects elsewhere on accessible drives. Select a result and click Open Folder to inspect it. Cancel stops the scan without changing any files.

Default paths it tries first:
- %LOCALAPPDATA%\VRChatCreatorCompanion\Repos
- %LOCALAPPDATA%\VRChatCreatorCompanion
- %LOCALAPPDATA%\VRChat\VRChat\Cache-WindowsPlayer
- %APPDATA%\VRChat
- %LOCALAPPDATA%\VRChat

VRChat CC note:
- For Creator Companion, the repo cache is usually in %LOCALAPPDATA%\VRChatCreatorCompanion\Repos.

Package note:
- The package tab updates dependencies inside the selected vpm-manifest.json file.
- Package add/remove asks for confirmation with a target preview.
- Package version dropdowns show plain version numbers for older releases and >= only on the newest stable release.
- Installed packages show their installed and available versions; use Update to change an outdated package to the available version.
- Use Update All to update every outdated installed package in the selected manifest(s) together.
- Use Update All to set installed packages to a >= constraint for their newest stable release; this tool does not install packages while closed.
- Manifest files are automatically backed up before package changes.
- The last all-project copy can be undone from the Undo Last Copy button, including after restarting the app.

Where things are stored:
- Installed packages per project: project Packages\vpm-manifest.json dependencies

Notes:
- Close VRChat before clearing cache, otherwise some files can be locked.
- Use the correct folder. This action is destructive for everything inside the selected folder.
- Main script file name: CCPlusTool.ps1
- The repository contains source only; build outputs and executables are excluded from Git. To distribute the self-contained Windows x64 executable, use a GitHub Release rather than committing it (the executable exceeds GitHub's 100 MB file limit).
- The app uses Windows PowerShell included with Windows. Package restore also requires VRChat Creator Companion and its local repo cache on that PC.
