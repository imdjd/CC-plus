            $version = "1.0.0"
                $pkgVersion = "1.0.0"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$UiColorBackground = [System.Drawing.Color]::FromArgb(245, 247, 250)
$UiColorPanel = [System.Drawing.Color]::FromArgb(255, 255, 255)
$UiColorText = [System.Drawing.Color]::FromArgb(38, 50, 56)
$UiColorPrimary = [System.Drawing.Color]::FromArgb(25, 118, 210)
$UiColorDanger = [System.Drawing.Color]::FromArgb(211, 47, 47)
$UiColorSecondary = [System.Drawing.Color]::FromArgb(96, 125, 139)

function Backup-ManifestFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    $ccPlusDataDir = Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\CCPlus"
    if (-not (Test-Path -LiteralPath $ccPlusDataDir)) {
        New-Item -Path $ccPlusDataDir -ItemType Directory -Force | Out-Null
    }

    $backupDir = Join-Path $ccPlusDataDir "Backups"
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }

    $safeName = ([System.IO.Path]::GetFileName($FilePath))
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $backupPath = Join-Path $backupDir ("{0}_{1}.json.bak" -f $safeName, $timestamp)
    Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force
    return $backupPath
}

function Get-LastProjectCopyUndoPath {
    $ccPlusDataDir = Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\CCPlus"
    if (-not (Test-Path -LiteralPath $ccPlusDataDir)) {
        New-Item -Path $ccPlusDataDir -ItemType Directory -Force | Out-Null
    }

    return Join-Path $ccPlusDataDir "last-project-copy-undo.json"
}

function Save-LastProjectCopyUndo {
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$Backups,
        [Parameter(Mandatory=$true)]
        [string]$SourceManifest
    )

    $undoPath = Get-LastProjectCopyUndoPath
    $undoRecord = [pscustomobject]@{
        CreatedAt = (Get-Date).ToString("o")
        SourceManifest = $SourceManifest
        Backups = @($Backups)
    }
    $undoRecord | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $undoPath -Encoding UTF8 -ErrorAction Stop
    return $undoPath
}

function Get-LastProjectCopyUndo {
    $undoPath = Get-LastProjectCopyUndoPath
    if (-not (Test-Path -LiteralPath $undoPath)) {
        return $null
    }

    return (Get-Content -LiteralPath $undoPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}

function Set-ButtonStyle {
    param(
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.Button]$Button,
        [Parameter(Mandatory=$true)]
        [ValidateSet("Primary", "Danger", "Secondary")]
        [string]$StyleKind
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.ForeColor = [System.Drawing.Color]::White
    $Button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand

    switch ($StyleKind) {
        "Primary" { $Button.BackColor = $UiColorPrimary }
        "Danger" { $Button.BackColor = $UiColorDanger }
        default { $Button.BackColor = $UiColorSecondary }
    }
}

function Get-DefaultRepoCachePath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\Repos"),
        (Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion")
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    return $candidates[0]
}

function Get-DefaultProjectManifestPath {
    $templateCandidates = @(
        (Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\VRCTemplates\Avatar\Packages\vpm-manifest.json"),
        (Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\VRCTemplates\Avatar 2019\Packages\vpm-manifest.json")
    )

    foreach ($path in $templateCandidates) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    $projectsRoot = Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\VRChatProjects"
    if (-not (Test-Path -LiteralPath $projectsRoot)) {
        return ""
    }

    $latest = Get-ChildItem -LiteralPath $projectsRoot -Recurse -Filter "vpm-manifest.json" -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        return $latest.FullName
    }

    return ""
}

function Get-AllProjectManifestPaths {
    $projectsRoot = Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\VRChatProjects"
    if (-not (Test-Path -LiteralPath $projectsRoot)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $projectsRoot -Recurse -Filter "vpm-manifest.json" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '[\\/]Packages[\\/]vpm-manifest\.json$' } |
            ForEach-Object { $_.FullName }
    )
}

function Find-ProjectLocations {
    param(
        [scriptblock]$OnProject,
        [scriptblock]$OnProgress,
        [scriptblock]$IsCancelled,
        [string[]]$Roots
    )

    $folders = New-Object 'System.Collections.Generic.Queue[string]'
    if (-not $PSBoundParameters.ContainsKey('Roots')) {
        $Roots = @([System.IO.DriveInfo]::GetDrives() | Where-Object {
            $_.IsReady -and $_.DriveType -in @('Fixed', 'Removable', 'Network')
        } | ForEach-Object { $_.RootDirectory.FullName })
    }
    foreach ($root in $Roots) {
        if ([System.IO.Directory]::Exists($root)) {
            $folders.Enqueue($root)
        }
    }

    $scanned = 0
    $skipped = 0
    while ($folders.Count -gt 0) {
        if (& $IsCancelled) { break }
        $folder = $folders.Dequeue()
        $scanned++

        $manifest = [System.IO.Path]::Combine($folder, 'Packages', 'vpm-manifest.json')
        $unityMarker = [System.IO.Path]::Combine($folder, 'ProjectSettings', 'ProjectVersion.txt')
        if ([System.IO.File]::Exists($manifest) -or [System.IO.File]::Exists($unityMarker)) {
            & $OnProject $folder
        }

        try {
            foreach ($child in [System.IO.Directory]::EnumerateDirectories($folder)) {
                try {
                    $name = [System.IO.Path]::GetFileName($child)
                    if ($name -in @('Library', 'Temp', 'obj', 'bin', 'node_modules', '.git') -and
                        ([System.IO.File]::Exists($manifest) -or [System.IO.File]::Exists($unityMarker) -or $name -in @('node_modules', '.git'))) {
                        continue
                    }
                    $attributes = [System.IO.File]::GetAttributes($child)
                    if (-not ($attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        $folders.Enqueue($child)
                    }
                } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
                    $skipped++
                    continue
                }
            }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            $skipped++
            continue
        }

        if ($scanned % 100 -eq 0) {
            & $OnProgress $scanned $folder
        }
    }

    return [pscustomobject]@{ Scanned = $scanned; Skipped = $skipped; Cancelled = (& $IsCancelled) }
}

function Get-TemplateManifestPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplateName
    )

    return Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\VRCTemplates\$TemplateName\Packages\vpm-manifest.json"
}

function Get-LinkedTemplateManifestTargets {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SelectedManifestPath
    )

    $targets = @($SelectedManifestPath)

    $pairs = @(
        @("Avatar", "Avatar 2019"),
        @("World", "World 2019")
    )

    foreach ($pair in $pairs) {
        $mainPath = Get-TemplateManifestPath -TemplateName $pair[0]
        $legacyPath = Get-TemplateManifestPath -TemplateName $pair[1]

        if (
            ($SelectedManifestPath -eq $mainPath -or $SelectedManifestPath -eq $legacyPath) -and
            (Test-Path -LiteralPath $mainPath) -and
            (Test-Path -LiteralPath $legacyPath)
        ) {
            $targets = @($mainPath, $legacyPath)
            break
        }
    }

    return $targets
}

function Get-VCCSettingsPath {
    $envOverride = $env:CCPLUS_SETTINGS_PATH
    if (-not [string]::IsNullOrWhiteSpace($envOverride)) {
        return $envOverride
    }

    $candidateDirectories = @()

    $workingDir = $env:CCPLUS_WORKING_DIR
    if (-not [string]::IsNullOrWhiteSpace($workingDir)) {
        $candidateDirectories += $workingDir
    }

    $currentDir = (Get-Location -ErrorAction SilentlyContinue).Path
    if (-not [string]::IsNullOrWhiteSpace($currentDir)) {
        $candidateDirectories += $currentDir
    }

    if ($candidateDirectories.Count -gt 0) {
        foreach ($dir in $candidateDirectories) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $candidate = Join-Path $dir "settings.json"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\settings.json"
}

function Get-UserReposFromSettings {
    $settingsPath = Get-VCCSettingsPath
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        throw "settings.json not found: $settingsPath"
    }

    $settings = (Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop
    if (-not $settings.userRepos) {
        return @()
    }

    return @($settings.userRepos)
}

function Save-UserReposToSettings {
    param(
        [Parameter(Mandatory=$true)]
        [object[]]$UserRepos
    )

    $settingsPath = Get-VCCSettingsPath
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        throw "settings.json not found: $settingsPath"
    }

    $settings = (Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop
    $settings.userRepos = @($UserRepos)
    $json = $settings | ConvertTo-Json -Depth 50
    Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8 -ErrorAction Stop
}

function Get-SettingsHealthReport {
    $settingsPath = Get-VCCSettingsPath

    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return [pscustomobject]@{
            Stage = "Missing"
            Summary = "settings.json is missing."
            Details = "Expected path: $settingsPath"
        }
    }

    $settings = $null
    $rawBytes = $null
    try {
        $rawBytes = [System.IO.File]::ReadAllBytes($settingsPath)
    } catch {
        return [pscustomobject]@{
            Stage = "Corrupted"
            Summary = "settings.json could not be read."
            Details = $_.Exception.Message
        }
    }

    # Detect known DB-like/binary content so we do not misclassify it as JSON corruption.
    $rawText = [System.Text.Encoding]::UTF8.GetString($rawBytes)
    if ($rawText.StartsWith("SQLite format 3") -or $rawText.Contains("LiteDB")) {
        return [pscustomobject]@{
            Stage = "Database"
            Summary = "settings.json appears to contain database-formatted data."
            Details = "Detected DB signature (SQLite/LiteDB style). JSON repair is disabled for safety."
        }
    }

    $nullByteCount = ($rawBytes | Where-Object { $_ -eq 0 }).Count
    if ($nullByteCount -gt 0) {
        return [pscustomobject]@{
            Stage = "Database"
            Summary = "settings.json appears to be binary data."
            Details = "Detected binary/null bytes. JSON repair is disabled for safety."
        }
    }

    try {
        $settings = (Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [pscustomobject]@{
            Stage = "Corrupted"
            Summary = "settings.json is invalid JSON."
            Details = $_.Exception.Message
        }
    }

    $issues = @()
    $repoCount = 0
    $missingPathCount = 0
    $missingFileCount = 0

    if ($null -eq $settings.userRepos) {
        $issues += "userRepos is missing."
    } else {
        $repos = @($settings.userRepos)
        $repoCount = $repos.Count

        if ($repoCount -eq 0) {
            $issues += "No user repos configured."
        }

        foreach ($repo in $repos) {
            if (-not $repo.localPath) {
                $missingPathCount++
                continue
            }

            $repoPath = [string]$repo.localPath
            if (-not (Test-Path -LiteralPath $repoPath)) {
                $missingFileCount++
            }
        }

        if ($missingPathCount -gt 0) {
            $issues += "$missingPathCount repo entries are missing localPath."
        }
        if ($missingFileCount -gt 0) {
            $issues += "$missingFileCount repo cache file path(s) do not exist."
        }
    }

    $stage = if ($issues.Count -gt 0) { "Warning" } else { "Healthy" }
    $summary = if ($stage -eq "Healthy") {
        "settings.json looks good."
    } else {
        "settings.json needs attention."
    }

    $detailParts = @("Repos: $repoCount")
    if ($issues.Count -gt 0) {
        $detailParts += $issues
    }

    return [pscustomobject]@{
        Stage = $stage
        Summary = $summary
        Details = ($detailParts -join "  |  ")
    }
}

function Repair-SettingsJson {
    $settingsPath = Get-VCCSettingsPath
    $settingsDir = Split-Path -Parent $settingsPath
    if (-not (Test-Path -LiteralPath $settingsDir)) {
        New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
    }

    $backupPath = ""
    if (Test-Path -LiteralPath $settingsPath) {
        $backupPath = "$settingsPath.corrupt.$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
        Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
    }

    $userRepos = @()
    $reposDir = Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\Repos"
    if (Test-Path -LiteralPath $reposDir) {
        $repoFiles = Get-ChildItem -LiteralPath $reposDir -Filter "*.json" -File -ErrorAction SilentlyContinue
        foreach ($repoFile in $repoFiles) {
            $userRepos += [pscustomobject]@{
                localPath = $repoFile.FullName
            }
        }
    }

    $safeSettings = [ordered]@{
        userRepos = @($userRepos)
    }

    $json = $safeSettings | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8 -ErrorAction Stop

    return [pscustomobject]@{
        SettingsPath = $settingsPath
        BackupPath = $backupPath
        RepoCount = $userRepos.Count
    }
}

function New-TestSettingsJson {
    $settingsPath = Get-VCCSettingsPath
    $settingsDir = Split-Path -Parent $settingsPath
    if (-not (Test-Path -LiteralPath $settingsDir)) {
        New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
    }

    $json = '{
  "userRepos": []
}'
    Set-Content -LiteralPath $settingsPath -Value $json -Encoding UTF8 -ErrorAction Stop
    return $settingsPath
}

function Get-FolderInfoText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return "Folder not found."
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
        $itemCount = $items.Count

        $totalBytes = 0
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                try {
                    $sum = (Get-ChildItem -LiteralPath $item.FullName -Force -Recurse -File -ErrorAction Stop |
                        Measure-Object -Property Length -Sum).Sum
                    if ($sum) {
                        $totalBytes += $sum
                    }
                } catch {
                    # Ignore unreadable subfolders and continue.
                }
            } else {
                $totalBytes += $item.Length
            }
        }

        $sizeMB = [math]::Round(($totalBytes / 1MB), 2)
        return "Items: $itemCount | Approx size: $sizeMB MB"
    } catch {
        return "Unable to read folder contents."
    }
}

function Get-DependencyMapFromManifest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }

    $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
    $manifest = $raw | ConvertFrom-Json -ErrorAction Stop

    $map = @{}
    if ($manifest -and $manifest.PSObject.Properties.Name -contains "dependencies" -and $manifest.dependencies) {
        foreach ($depProp in $manifest.dependencies.PSObject.Properties) {
            $version = ">=1.0.0"
            if ($depProp.Value -and $depProp.Value.PSObject.Properties.Name -contains "version" -and $depProp.Value.version) {
                $version = [string]$depProp.Value.version
            }
            $map[$depProp.Name] = $version
        }
    }

    return $map
}

function Merge-DependenciesIntoManifest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetManifestPath,
        [Parameter(Mandatory=$true)]
        [hashtable]$DependenciesToApply
    )

    if (-not (Test-Path -LiteralPath $TargetManifestPath)) {
        throw "Target manifest not found: $TargetManifestPath"
    }

    $raw = Get-Content -LiteralPath $TargetManifestPath -Raw -ErrorAction Stop
    $manifest = $raw | ConvertFrom-Json -ErrorAction Stop

    if (-not $manifest) {
        throw "Target manifest is empty or invalid JSON."
    }

    if ($manifest.PSObject.Properties.Name -notcontains "dependencies" -or -not $manifest.dependencies) {
        $manifest | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{})
    }

    $added = 0
    $updated = 0

    foreach ($depName in $DependenciesToApply.Keys) {
        $desiredVersion = [string]$DependenciesToApply[$depName]
        $existingDep = $manifest.dependencies.PSObject.Properties[$depName]

        if ($existingDep) {
            if (-not $existingDep.Value) {
                $manifest.dependencies.$depName = [pscustomobject]@{ version = $desiredVersion }
                $updated++
                continue
            }

            if ($existingDep.Value.PSObject.Properties.Name -contains "version") {
                if ([string]$existingDep.Value.version -ne $desiredVersion) {
                    $existingDep.Value.version = $desiredVersion
                    $updated++
                }
            } else {
                $existingDep.Value | Add-Member -NotePropertyName version -NotePropertyValue $desiredVersion
                $updated++
            }
        } else {
            $manifest.dependencies | Add-Member -NotePropertyName $depName -NotePropertyValue ([pscustomobject]@{ version = $desiredVersion })
            $added++
        }
    }

    $json = $manifest | ConvertTo-Json -Depth 50
    Set-Content -LiteralPath $TargetManifestPath -Value $json -Encoding UTF8 -ErrorAction Stop

    return [pscustomobject]@{
        Added = $added
        Updated = $updated
        TotalApplied = $DependenciesToApply.Count
    }
}

function Remove-DependenciesFromManifest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetManifestPath,
        [Parameter(Mandatory=$true)]
        [string[]]$DependencyNames
    )

    if (-not (Test-Path -LiteralPath $TargetManifestPath)) {
        throw "Target manifest not found: $TargetManifestPath"
    }

    $raw = Get-Content -LiteralPath $TargetManifestPath -Raw -ErrorAction Stop
    $manifest = $raw | ConvertFrom-Json -ErrorAction Stop

    if (-not $manifest -or -not $manifest.dependencies) {
        return 0
    }

    $removed = 0
    foreach ($depName in $DependencyNames) {
        if ($manifest.dependencies.PSObject.Properties[$depName]) {
            $manifest.dependencies.PSObject.Properties.Remove($depName)
            $removed++
        }
    }

    if ($removed -gt 0) {
        $json = $manifest | ConvertTo-Json -Depth 50
        Set-Content -LiteralPath $TargetManifestPath -Value $json -Encoding UTF8 -ErrorAction Stop
    }

    return $removed
}

function Get-LatestStablePackageVersion {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Package
    )

    if (-not $Package.versions) {
        return $null
    }

    $versionProperties = @($Package.versions.PSObject.Properties)
    $stableVersions = @($versionProperties | Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' })
    if ($stableVersions.Count -gt 0) {
        return ($stableVersions | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1)
    }

    return ($versionProperties | Select-Object -First 1)
}

function ConvertTo-PackageVersionChoice {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [string]$LatestVersion
    )

    $versionText = $Version.Trim()
    if ($versionText -match '^>=\s*(\d+(\.\d+){1,3})$') {
        $versionText = $matches[1]
    }

    $latestText = $LatestVersion.Trim()
    if ($latestText -match '^>=\s*(\d+(\.\d+){1,3})$') {
        $latestText = $matches[1]
    }

    if (
        $versionText -match '^\d+(\.\d+){1,3}$' -and
        $latestText -match '^\d+(\.\d+){1,3}$' -and
        ([version]$versionText -eq [version]$latestText)
    ) {
        return ">=$latestText"
    }

    return $versionText
}

function Test-IsNewerStablePackageVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Candidate,
        [string]$Current
    )

    if ($Candidate -notmatch '^\d+(\.\d+){1,3}$') {
        return $false
    }
    $currentVersion = $Current.Trim()
    if ($currentVersion -match '^>=\s*(\d+(\.\d+){1,3})$') {
        $currentVersion = $matches[1]
    }
    if ($currentVersion -notmatch '^\d+(\.\d+){1,3}$') {
        return $true
    }

    return ([version]$Candidate -gt [version]$currentVersion)
}

function Refresh-RepoCache {
    $updated = 0
    $failed = @()
    $repoEntries = Get-UserReposFromSettings
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    foreach ($repoEntry in $repoEntries) {
        if ([string]::IsNullOrWhiteSpace([string]$repoEntry.url) -or [string]::IsNullOrWhiteSpace([string]$repoEntry.localPath)) {
            continue
        }

        $temporaryPath = $null
        try {
            $localPath = [string]$repoEntry.localPath
            $localDirectory = Split-Path -Parent $localPath
            if (-not (Test-Path -LiteralPath $localDirectory)) {
                New-Item -Path $localDirectory -ItemType Directory -Force | Out-Null
            }

            $temporaryPath = "$localPath.refresh.tmp"
            $headers = @{}
            if ($repoEntry.headers -is [System.Collections.IDictionary]) {
                foreach ($key in $repoEntry.headers.Keys) {
                    $headers[[string]$key] = [string]$repoEntry.headers[$key]
                }
            } elseif ($repoEntry.headers) {
                foreach ($header in $repoEntry.headers.PSObject.Properties) {
                    $headers[[string]$header.Name] = [string]$header.Value
                }
            }

            Invoke-WebRequest -Uri ([string]$repoEntry.url) -Headers $headers -OutFile $temporaryPath -UseBasicParsing -TimeoutSec 12 -ErrorAction Stop
            $repoDoc = Get-Content -LiteralPath $temporaryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (-not $repoDoc.repo -or -not $repoDoc.repo.packages) {
                throw "Downloaded JSON does not contain repo packages."
            }

            Move-Item -LiteralPath $temporaryPath -Destination $localPath -Force -ErrorAction Stop
            $updated++
        } catch {
            $failed += "$(if ($repoEntry.name) { $repoEntry.name } else { $repoEntry.url }): $($_.Exception.Message)"
        } finally {
            if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return [pscustomobject]@{
        Updated = $updated
        Failed = @($failed)
    }
}

function Get-KnownPackageCatalog {
    $catalog = @{}
    $templates = @("Avatar", "Avatar 2019")

    foreach ($templateName in $templates) {
        $templatePath = Get-TemplateManifestPath -TemplateName $templateName
        if (Test-Path -LiteralPath $templatePath) {
            try {
                $deps = Get-DependencyMapFromManifest -ManifestPath $templatePath
                foreach ($depName in $deps.Keys) {
                    $normalized = $depName.ToLowerInvariant()
                    if (-not $catalog.ContainsKey($normalized)) {
                        $catalog[$normalized] = [pscustomobject]@{
                            PackageId = $depName
                            DisplayName = $depName
                            Version = [string]$deps[$depName]
                            Versions = @([string]$deps[$depName])
                        }
                    }
                }
            } catch {
                # Ignore template parse failures and keep building catalog.
            }
        }
    }

    try {
        $userRepos = Get-UserReposFromSettings
        $repoPaths = @($userRepos | Where-Object { $_.localPath } | ForEach-Object { [string]$_.localPath })
    } catch {
        $repoPaths = @()
    }

    $reposCachePath = Join-Path $env:LOCALAPPDATA "VRChatCreatorCompanion\Repos"
    if (Test-Path -LiteralPath $reposCachePath) {
        $repoPaths += @(Get-ChildItem -LiteralPath $reposCachePath -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }

    foreach ($repoPath in @($repoPaths | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            if (-not (Test-Path -LiteralPath $repoPath)) {
                continue
            }

            $repoDoc = (Get-Content -LiteralPath $repoPath -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop

            $packagesNode = $null
            if ($repoDoc.repo -and $repoDoc.repo.packages) {
                $packagesNode = $repoDoc.repo.packages
            } elseif ($repoDoc.packages) {
                $packagesNode = $repoDoc.packages
            }

            if (-not $packagesNode) {
                continue
            }

            foreach ($pkgProp in $packagesNode.PSObject.Properties) {
                $pkgName = [string]$pkgProp.Name
                $pkgVersion = ">=1.0.0"
                $pkgDisplayName = $pkgName
                $pkgVersions = @()

                if ($pkgProp.Value -and $pkgProp.Value.versions) {
                    $pkgVersions = @($pkgProp.Value.versions.PSObject.Properties | ForEach-Object { [string]$_.Name } | Select-Object -Unique)
                }

                $versionEntry = Get-LatestStablePackageVersion -Package $pkgProp.Value
                if ($versionEntry -and $versionEntry.Name) {
                    $pkgVersion = [string]$versionEntry.Name
                    if ($versionEntry.Value -and $versionEntry.Value.displayName) {
                        $pkgDisplayName = [string]$versionEntry.Value.displayName
                    }
                }

                $normalized = $pkgName.ToLowerInvariant()
                if (-not $catalog.ContainsKey($normalized)) {
                    $catalog[$normalized] = [pscustomobject]@{
                        PackageId = $pkgName
                        DisplayName = $pkgDisplayName
                        Version = $pkgVersion
                        Versions = @($pkgVersions)
                    }
                } else {
                    $catalog[$normalized].Versions = @($catalog[$normalized].Versions + $pkgVersions | Select-Object -Unique)
                    if (Test-IsNewerStablePackageVersion -Candidate $pkgVersion -Current ([string]$catalog[$normalized].Version)) {
                        $catalog[$normalized].Version = $pkgVersion
                    }

                    if (
                        $pkgDisplayName -and
                        $pkgDisplayName -ne $pkgName -and
                        $catalog[$normalized].DisplayName -eq $catalog[$normalized].PackageId
                    ) {
                        $catalog[$normalized].DisplayName = $pkgDisplayName
                    }
                }
            }
        } catch {
            # Ignore malformed repo cache files and continue.
        }
    }

    return $catalog
}

function Is-HiddenOfficialPackage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )

    $id = $PackageId.ToLowerInvariant()
    if ($id.StartsWith("com.vrchat.")) {
        return $true
    }

    $hiddenExact = @(
        "com.unity.modules.ui",
        "com.unity.textmeshpro"
    )

    return ($hiddenExact -contains $id)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "VRChat Creator Companion Utility"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1040, 760)
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $true
$form.MinimumSize = New-Object System.Drawing.Size(900, 650)
$form.AutoScroll = $false
$form.BackColor = $UiColorBackground
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.ForeColor = $UiColorText

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($tabControl)

$footer = New-Object System.Windows.Forms.StatusStrip
$footerLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$footerLabel.Text = "made by Imdjd"
$footer.Items.Add($footerLabel) | Out-Null
$form.Controls.Add($footer)

# Tab 1: Cache
$cacheTab = New-Object System.Windows.Forms.TabPage
$cacheTab.Text = "Cache"
$cacheTab.AutoScroll = $true
$cacheTab.BackColor = $UiColorPanel
$tabControl.TabPages.Add($cacheTab)

# Tab 2: Settings
$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = "Settings"
$settingsTab.AutoScroll = $true
$settingsTab.BackColor = $UiColorPanel
$tabControl.TabPages.Add($settingsTab)

# Read-only project locator
$projectsTab = New-Object System.Windows.Forms.TabPage
$projectsTab.Text = "Find Projects"
$projectsTab.BackColor = $UiColorPanel
$tabControl.TabPages.Add($projectsTab)

$projectsToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$projectsToolbar.Dock = [System.Windows.Forms.DockStyle]::Top
$projectsToolbar.Height = 54
$projectsToolbar.Padding = New-Object System.Windows.Forms.Padding(8)
$projectsTab.Controls.Add($projectsToolbar)

$scanProjectsButton = New-Object System.Windows.Forms.Button
$scanProjectsButton.Text = "Search Drives"
$scanProjectsButton.Size = New-Object System.Drawing.Size(120, 34)
Set-ButtonStyle -Button $scanProjectsButton -StyleKind Primary
$projectsToolbar.Controls.Add($scanProjectsButton)

$cancelProjectScanButton = New-Object System.Windows.Forms.Button
$cancelProjectScanButton.Text = "Cancel"
$cancelProjectScanButton.Size = New-Object System.Drawing.Size(90, 34)
$cancelProjectScanButton.Enabled = $false
Set-ButtonStyle -Button $cancelProjectScanButton -StyleKind Secondary
$projectsToolbar.Controls.Add($cancelProjectScanButton)

$openProjectFolderButton = New-Object System.Windows.Forms.Button
$openProjectFolderButton.Text = "Open Folder"
$openProjectFolderButton.Size = New-Object System.Drawing.Size(120, 34)
$openProjectFolderButton.Enabled = $false
Set-ButtonStyle -Button $openProjectFolderButton -StyleKind Secondary
$projectsToolbar.Controls.Add($openProjectFolderButton)

$projectScanStatus = New-Object System.Windows.Forms.Label
$projectScanStatus.Dock = [System.Windows.Forms.DockStyle]::Bottom
$projectScanStatus.Height = 42
$projectScanStatus.Padding = New-Object System.Windows.Forms.Padding(12, 8, 8, 8)
$projectScanStatus.Text = "Searches accessible drives for Unity and VCC projects. No files are changed."
$projectsTab.Controls.Add($projectScanStatus)

$projectResults = New-Object System.Windows.Forms.ListView
$projectResults.Dock = [System.Windows.Forms.DockStyle]::Fill
$projectResults.View = [System.Windows.Forms.View]::Details
$projectResults.FullRowSelect = $true
$projectResults.MultiSelect = $false
$projectResults.HideSelection = $false
$projectResults.Columns.Add("Project folder", 760) | Out-Null
$projectsTab.Controls.Add($projectResults)
$projectResults.BringToFront()

$script:projectScanCancelled = $false
$cancelProjectScanButton.Add_Click({ $script:projectScanCancelled = $true })
$projectResults.Add_SelectedIndexChanged({
    $openProjectFolderButton.Enabled = ($projectResults.SelectedItems.Count -gt 0)
})
$openProjectFolderButton.Add_Click({
    if ($projectResults.SelectedItems.Count -gt 0) {
        [System.Diagnostics.Process]::Start('explorer.exe', ('"{0}"' -f $projectResults.SelectedItems[0].Text)) | Out-Null
    }
})
$projectResults.Add_DoubleClick({ $openProjectFolderButton.PerformClick() })

$scanProjectsButton.Add_Click({
    $script:projectScanCancelled = $false
    $scanProjectsButton.Enabled = $false
    $cancelProjectScanButton.Enabled = $true
    $openProjectFolderButton.Enabled = $false
    $projectResults.Items.Clear()
    $projectScanStatus.Text = "Searching accessible drives..."
    try {
        $result = Find-ProjectLocations -OnProject {
            param($folder)
            $projectResults.Items.Add($folder) | Out-Null
            $projectScanStatus.Text = "Found $($projectResults.Items.Count) project(s). Searching..."
            [System.Windows.Forms.Application]::DoEvents()
        } -OnProgress {
            param($scanned, $folder)
            $projectScanStatus.Text = "Found $($projectResults.Items.Count) project(s); checked $scanned folders. $folder"
            [System.Windows.Forms.Application]::DoEvents()
        } -IsCancelled { $script:projectScanCancelled }
        $state = if ($result.Cancelled) { "Cancelled" } else { "Finished" }
        $projectScanStatus.Text = "$state. Found $($projectResults.Items.Count) project(s); checked $($result.Scanned) folders; $($result.Skipped) inaccessible folders skipped."
    } catch {
        $projectScanStatus.Text = "Search stopped: $($_.Exception.Message)"
    } finally {
        $scanProjectsButton.Enabled = $true
        $cancelProjectScanButton.Enabled = $false
    }
})

$cacheTitle = New-Object System.Windows.Forms.Label
$cacheTitle.Text = "Clear Creator Companion Repo Cache"
$cacheTitle.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$cacheTitle.Location = New-Object System.Drawing.Point(16, 16)
$cacheTitle.AutoSize = $true
$cacheTab.Controls.Add($cacheTitle)

$cachePathLabel = New-Object System.Windows.Forms.Label
$cachePathLabel.Text = "Target Repo Cache Folder:"
$cachePathLabel.Location = New-Object System.Drawing.Point(16, 54)
$cachePathLabel.AutoSize = $true
$cacheTab.Controls.Add($cachePathLabel)

$cachePathBox = New-Object System.Windows.Forms.TextBox
$cachePathBox.Location = New-Object System.Drawing.Point(16, 76)
$cachePathBox.Size = New-Object System.Drawing.Size(720, 24)
$cachePathBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$cachePathBox.Text = Get-DefaultRepoCachePath
$cacheTab.Controls.Add($cachePathBox)

$cacheBrowseButton = New-Object System.Windows.Forms.Button
$cacheBrowseButton.Text = "Browse"
$cacheBrowseButton.Location = New-Object System.Drawing.Point(746, 74)
$cacheBrowseButton.Size = New-Object System.Drawing.Size(120, 30)
$cacheBrowseButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$cacheTab.Controls.Add($cacheBrowseButton)

$cacheInfoLabel = New-Object System.Windows.Forms.Label
$cacheInfoLabel.Location = New-Object System.Drawing.Point(16, 114)
$cacheInfoLabel.Size = New-Object System.Drawing.Size(850, 24)
$cacheInfoLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$cacheInfoLabel.Text = Get-FolderInfoText -Path $cachePathBox.Text
$cacheTab.Controls.Add($cacheInfoLabel)

$cacheStatusLabel = New-Object System.Windows.Forms.Label
$cacheStatusLabel.Location = New-Object System.Drawing.Point(16, 144)
$cacheStatusLabel.Size = New-Object System.Drawing.Size(850, 30)
$cacheStatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$cacheStatusLabel.Text = "Ready."
$cacheTab.Controls.Add($cacheStatusLabel)

$cacheClearButton = New-Object System.Windows.Forms.Button
$cacheClearButton.Text = "Clear Repo Cache"
$cacheClearButton.Location = New-Object System.Drawing.Point(16, 185)
$cacheClearButton.Size = New-Object System.Drawing.Size(190, 40)
$cacheTab.Controls.Add($cacheClearButton)

$cacheOpenButton = New-Object System.Windows.Forms.Button
$cacheOpenButton.Text = "Open Folder"
$cacheOpenButton.Location = New-Object System.Drawing.Point(215, 185)
$cacheOpenButton.Size = New-Object System.Drawing.Size(130, 40)
$cacheTab.Controls.Add($cacheOpenButton)

$cacheRefreshButton = New-Object System.Windows.Forms.Button
$cacheRefreshButton.Text = "Refresh Info"
$cacheRefreshButton.Location = New-Object System.Drawing.Point(355, 185)
$cacheRefreshButton.Size = New-Object System.Drawing.Size(130, 40)
$cacheTab.Controls.Add($cacheRefreshButton)

$settingsHealthButton = New-Object System.Windows.Forms.Button
$settingsHealthButton.Text = "Settings Health Check"
$settingsHealthButton.Location = New-Object System.Drawing.Point(16, 48)
$settingsHealthButton.Size = New-Object System.Drawing.Size(190, 40)
$settingsTab.Controls.Add($settingsHealthButton)

$settingsRepairButton = New-Object System.Windows.Forms.Button
$settingsRepairButton.Text = "Repair Corrupted settings.json"
$settingsRepairButton.Location = New-Object System.Drawing.Point(216, 48)
$settingsRepairButton.Size = New-Object System.Drawing.Size(230, 40)
$settingsTab.Controls.Add($settingsRepairButton)

$settingsTestButton = New-Object System.Windows.Forms.Button
$settingsTestButton.Text = "Create Test settings.json"
$settingsTestButton.Location = New-Object System.Drawing.Point(466, 48)
$settingsTestButton.Size = New-Object System.Drawing.Size(220, 40)
$settingsTab.Controls.Add($settingsTestButton)

$settingsPackageSearchButton = New-Object System.Windows.Forms.Button
$settingsPackageSearchButton.Text = "Search Packages"
$settingsPackageSearchButton.Location = New-Object System.Drawing.Point(696, 48)
$settingsPackageSearchButton.Size = New-Object System.Drawing.Size(170, 40)
$settingsTab.Controls.Add($settingsPackageSearchButton)

$settingsFindProjectsButton = New-Object System.Windows.Forms.Button
$settingsFindProjectsButton.Text = "Find Projects"
$settingsFindProjectsButton.Location = New-Object System.Drawing.Point(16, 214)
$settingsFindProjectsButton.Size = New-Object System.Drawing.Size(170, 40)
$settingsFindProjectsButton.Tag = [pscustomobject]@{ Tabs = $tabControl; Projects = $projectsTab }
$settingsFindProjectsButton.Add_Click({
    $target = $this.Tag
    $target.Tabs.SelectedTab = $target.Projects
})
$settingsTab.Controls.Add($settingsFindProjectsButton)

$settingsHealthLabel = New-Object System.Windows.Forms.Label
$settingsHealthLabel.Location = New-Object System.Drawing.Point(16, 116)
$settingsHealthLabel.Size = New-Object System.Drawing.Size(960, 24)
$settingsHealthLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsHealthLabel.Text = "Settings health: Not checked."
$settingsHealthLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$settingsTab.Controls.Add($settingsHealthLabel)

$settingsHealthDetailsLabel = New-Object System.Windows.Forms.Label
$settingsHealthDetailsLabel.Location = New-Object System.Drawing.Point(16, 142)
$settingsHealthDetailsLabel.Size = New-Object System.Drawing.Size(960, 56)
$settingsHealthDetailsLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsHealthDetailsLabel.Text = ""
$settingsTab.Controls.Add($settingsHealthDetailsLabel)

$settingsTitle = New-Object System.Windows.Forms.Label
$settingsTitle.Text = "settings.json Health"
$settingsTitle.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$settingsTitle.Location = New-Object System.Drawing.Point(16, 16)
$settingsTitle.AutoSize = $true
$settingsTab.Controls.Add($settingsTitle)

$settingsPathLabel = New-Object System.Windows.Forms.Label
$settingsPathLabel.Text = "Path: $(Get-VCCSettingsPath)"
$settingsPathLabel.Location = New-Object System.Drawing.Point(16, 92)
$settingsPathLabel.Size = New-Object System.Drawing.Size(960, 20)
$settingsPathLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsTab.Controls.Add($settingsPathLabel)

Set-ButtonStyle -Button $cacheClearButton -StyleKind Danger
Set-ButtonStyle -Button $cacheOpenButton -StyleKind Secondary
Set-ButtonStyle -Button $cacheRefreshButton -StyleKind Primary
Set-ButtonStyle -Button $cacheBrowseButton -StyleKind Primary
Set-ButtonStyle -Button $settingsHealthButton -StyleKind Secondary
Set-ButtonStyle -Button $settingsRepairButton -StyleKind Danger
Set-ButtonStyle -Button $settingsTestButton -StyleKind Secondary
Set-ButtonStyle -Button $settingsPackageSearchButton -StyleKind Primary
Set-ButtonStyle -Button $settingsFindProjectsButton -StyleKind Primary

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog

$refreshCacheInfo = {
    $cacheInfoLabel.Text = Get-FolderInfoText -Path $cachePathBox.Text
}

$refreshSettingsHealth = {
    $report = Get-SettingsHealthReport
    $settingsHealthLabel.Text = "Settings health: $($report.Stage) - $($report.Summary)"
    $settingsHealthDetailsLabel.Text = $report.Details

    switch ($report.Stage) {
        "Healthy" {
            $settingsHealthLabel.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
        }
        "Warning" {
            $settingsHealthLabel.ForeColor = [System.Drawing.Color]::FromArgb(245, 124, 0)
        }
        "Database" {
            $settingsHealthLabel.ForeColor = [System.Drawing.Color]::FromArgb(25, 118, 210)
        }
        "Corrupted" {
            $settingsHealthLabel.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
        }
        "Missing" {
            $settingsHealthLabel.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
        }
        default {
            $settingsHealthLabel.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
        }
    }
}

$cacheBrowseButton.Add_Click({
    $folderDialog.SelectedPath = $cachePathBox.Text
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $cachePathBox.Text = $folderDialog.SelectedPath
        & $refreshCacheInfo
    }
})

$cacheRefreshButton.Add_Click({
    & $refreshCacheInfo
    $cacheStatusLabel.Text = "Folder info refreshed."
})

$settingsHealthButton.Add_Click({
    & $refreshSettingsHealth
})

$settingsRepairButton.Add_Click({
    $report = Get-SettingsHealthReport
    if ($report.Stage -eq "Database") {
        [System.Windows.Forms.MessageBox]::Show(
            "Repair is disabled because this file appears to be DB/binary data (LiteDB/SQLite style).`nUse the application's native migration/export path instead.",
            "Repair Blocked",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will back up and rebuild settings.json if it is corrupted or missing.`nContinue?",
        "Repair settings.json",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    try {
        $result = Repair-SettingsJson
        & $refreshSettingsHealth

        $backupInfo = if ($result.BackupPath) {
            "Backup: $($result.BackupPath)"
        } else {
            "Backup: not needed"
        }

        [System.Windows.Forms.MessageBox]::Show(
            "settings.json repaired.`nRepos added: $($result.RepoCount)`n$backupInfo",
            "Repair Complete",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Repair failed:`n$($_.Exception.Message)",
            "Repair Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$settingsTestButton.Add_Click({
    try {
        $path = New-TestSettingsJson
        & $refreshSettingsHealth
        [System.Windows.Forms.MessageBox]::Show(
            "Created a valid local test settings file:`n$path",
            "Test settings created",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to create test settings:`n$($_.Exception.Message)",
            "Test settings Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

if ((Split-Path -Leaf $cachePathBox.Text) -ieq "VRChatCreatorCompanion") {
    $repoCandidate = Join-Path $cachePathBox.Text "Repos"
    if (Test-Path -LiteralPath $repoCandidate) {
        $cachePathBox.Text = $repoCandidate
    }
}

$cacheOpenButton.Add_Click({
    if (Test-Path -LiteralPath $cachePathBox.Text) {
        Start-Process explorer.exe "`"$($cachePathBox.Text)`""
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Target folder does not exist.",
            "Open Folder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
})

$cacheClearButton.Add_Click({
    $target = $cachePathBox.Text

    if (-not (Test-Path -LiteralPath $target)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Target folder does not exist.",
            "Clear Cache",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will delete ALL files and folders inside:`n$target`n`nContinue?",
        "Confirm Clear Cache",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        $cacheStatusLabel.Text = "Cancelled by user."
        return
    }

    try {
        $children = Get-ChildItem -LiteralPath $target -Force -ErrorAction Stop
        $itemCount = $children.Count
        foreach ($child in $children) {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
        }
        $cacheStatusLabel.Text = "Repo cache cleared successfully."
    } catch {
        $cacheStatusLabel.Text = "Some items could not be removed. Close VCC/Unity and try again."
        [System.Windows.Forms.MessageBox]::Show(
            "Error while deleting cache items:`n$($_.Exception.Message)",
            "Clear Cache Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }

    & $refreshCacheInfo
})

$cachePathBox.Add_TextChanged({
    & $refreshCacheInfo
})

# Tab 2: Packages
$packagesTab = New-Object System.Windows.Forms.TabPage
$packagesTab.Text = "Packages"
$packagesTab.AutoScroll = $true
$packagesTab.BackColor = $UiColorPanel
$tabControl.TabPages.Add($packagesTab)

$pkgTitle = New-Object System.Windows.Forms.Label
$pkgTitle.Text = "Startup Packages"
$pkgTitle.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$pkgTitle.Location = New-Object System.Drawing.Point(16, 16)
$pkgTitle.AutoSize = $true
$packagesTab.Controls.Add($pkgTitle)

$selectedManifestPath = Get-DefaultProjectManifestPath

$manifestStatusLabel = New-Object System.Windows.Forms.Label
$manifestStatusLabel.Location = New-Object System.Drawing.Point(16, 44)
$manifestStatusLabel.Size = New-Object System.Drawing.Size(960, 22)
$manifestStatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$manifestStatusLabel.Text = "Add packages here to include them automatically in new projects."
$packagesTab.Controls.Add($manifestStatusLabel)

$manifestInfoLabel = New-Object System.Windows.Forms.Label
$manifestInfoLabel.Location = New-Object System.Drawing.Point(16, 68)
$manifestInfoLabel.Size = New-Object System.Drawing.Size(960, 22)
$manifestInfoLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$manifestInfoLabel.Text = ""
$packagesTab.Controls.Add($manifestInfoLabel)

$manifestOpenButton = New-Object System.Windows.Forms.Button
$manifestOpenButton.Text = "Open Manifest"
$manifestOpenButton.Location = New-Object System.Drawing.Point(486, 120)
$manifestOpenButton.Size = New-Object System.Drawing.Size(150, 40)
$packagesTab.Controls.Add($manifestOpenButton)

$manifestRefreshButton = New-Object System.Windows.Forms.Button
$manifestRefreshButton.Text = "Refresh"
$manifestRefreshButton.Location = New-Object System.Drawing.Point(676, 120)
$manifestRefreshButton.Size = New-Object System.Drawing.Size(150, 40)
$packagesTab.Controls.Add($manifestRefreshButton)

$restoreRepoPackagesButton = New-Object System.Windows.Forms.Button
$restoreRepoPackagesButton.Text = "Restore Repo Packages"
$restoreRepoPackagesButton.Size = New-Object System.Drawing.Size(170, 40)
$packagesTab.Controls.Add($restoreRepoPackagesButton)

$updateAllPackagesButton = New-Object System.Windows.Forms.Button
$updateAllPackagesButton.Text = "Update All"
$updateAllPackagesButton.Size = New-Object System.Drawing.Size(140, 40)
$packagesTab.Controls.Add($updateAllPackagesButton)

$addSelectedToAllProjectsButton = New-Object System.Windows.Forms.Button
$addSelectedToAllProjectsButton.Text = "Add All Installed to Projects"
$addSelectedToAllProjectsButton.Size = New-Object System.Drawing.Size(240, 40)
$packagesTab.Controls.Add($addSelectedToAllProjectsButton)

$undoLastProjectCopyButton = New-Object System.Windows.Forms.Button
$undoLastProjectCopyButton.Text = "Undo Last Copy"
$undoLastProjectCopyButton.Size = New-Object System.Drawing.Size(170, 40)
$undoLastProjectCopyButton.Enabled = $false
$packagesTab.Controls.Add($undoLastProjectCopyButton)

$useAvatarTemplatesButton = New-Object System.Windows.Forms.Button
$useAvatarTemplatesButton.Text = "Avatar"
$useAvatarTemplatesButton.Location = New-Object System.Drawing.Point(16, 120)
$useAvatarTemplatesButton.Size = New-Object System.Drawing.Size(150, 40)
$packagesTab.Controls.Add($useAvatarTemplatesButton)

$useAvatarTemplateButton = New-Object System.Windows.Forms.Button
$useAvatarTemplateButton.Text = "Worlds"
$useAvatarTemplateButton.Location = New-Object System.Drawing.Point(246, 120)
$useAvatarTemplateButton.Size = New-Object System.Drawing.Size(150, 40)
$packagesTab.Controls.Add($useAvatarTemplateButton)

$packageActionsPanel = New-Object System.Windows.Forms.TableLayoutPanel
$packageActionsPanel.Location = New-Object System.Drawing.Point(16, 108)
$packageActionsPanel.Size = New-Object System.Drawing.Size(960, 132)
$packageActionsPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$packageActionsPanel.ColumnCount = 3
$packageActionsPanel.RowCount = 3
$packageActionsPanel.GrowStyle = [System.Windows.Forms.TableLayoutPanelGrowStyle]::FixedSize
$packageActionsPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$packageActionsPanel.Padding = New-Object System.Windows.Forms.Padding(0)
for ($column = 0; $column -lt 3; $column++) {
    [void]$packageActionsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.333)))
}
for ($row = 0; $row -lt 3; $row++) {
    [void]$packageActionsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 33.333)))
}
$packagesTab.Controls.Add($packageActionsPanel)
$packageButtons = @(
    $useAvatarTemplatesButton,
    $useAvatarTemplateButton,
    $manifestOpenButton,
    $manifestRefreshButton,
    $restoreRepoPackagesButton,
    $updateAllPackagesButton,
    $addSelectedToAllProjectsButton,
    $undoLastProjectCopyButton
)
for ($index = 0; $index -lt $packageButtons.Count; $index++) {
    $button = $packageButtons[$index]
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill
    $button.Margin = New-Object System.Windows.Forms.Padding(4)
    [void]$packageActionsPanel.Controls.Add($button, ($index % 3), [Math]::Floor($index / 3))
}

$packageSearchLabel = New-Object System.Windows.Forms.Label
$packageSearchLabel.Text = "Search"
$packageSearchLabel.Location = New-Object System.Drawing.Point(16, 172)
$packageSearchLabel.Location = New-Object System.Drawing.Point(16, 254)
$packageSearchLabel.AutoSize = $true
$packageSearchLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$packagesTab.Controls.Add($packageSearchLabel)

$packageSearchBox = New-Object System.Windows.Forms.TextBox
$packageSearchBox.Location = New-Object System.Drawing.Point(72, 169)
$packageSearchBox.Size = New-Object System.Drawing.Size(320, 24)
$packagesTab.Controls.Add($packageSearchBox)

$settingsPackageSearchButton.Tag = [pscustomobject]@{
    Tabs = $tabControl
    Packages = $packagesTab
    SearchBox = $packageSearchBox
}
$settingsPackageSearchButton.Add_Click({
    $target = $this.Tag
    $target.Tabs.SelectedTab = $target.Packages
    $target.Packages.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    $target.SearchBox.Focus() | Out-Null
})

$packageFilterLabel = New-Object System.Windows.Forms.Label
$packageFilterLabel.Text = "Filter"
$packageFilterLabel.Location = New-Object System.Drawing.Point(410, 172)
$packageFilterLabel.AutoSize = $true
$packageFilterLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$packagesTab.Controls.Add($packageFilterLabel)

$packageFilterCombo = New-Object System.Windows.Forms.ComboBox
$packageFilterCombo.Location = New-Object System.Drawing.Point(458, 169)
$packageFilterCombo.Size = New-Object System.Drawing.Size(170, 24)
$packageFilterCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$packageFilterCombo.Items.Add("All")
[void]$packageFilterCombo.Items.Add("Installed")
[void]$packageFilterCombo.Items.Add("Available")
$packageFilterCombo.SelectedIndex = 0
$packagesTab.Controls.Add($packageFilterCombo)

$detectedLabel = New-Object System.Windows.Forms.Label
$detectedLabel.Text = "Package actions (one at a time):"
$detectedLabel.Location = New-Object System.Drawing.Point(16, 204)
$detectedLabel.AutoSize = $true
$detectedLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$packagesTab.Controls.Add($detectedLabel)

$packageGrid = New-Object System.Windows.Forms.DataGridView
$packageGrid.Location = New-Object System.Drawing.Point(16, 228)
$packageGrid.Size = New-Object System.Drawing.Size(960, 350)
$packageGrid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$packageGrid.AllowUserToAddRows = $false
$packageGrid.AllowUserToDeleteRows = $false
$packageGrid.ReadOnly = $false
$packageGrid.RowHeadersVisible = $false
$packageGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$packageGrid.MultiSelect = $false
$packageGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$packageGrid.BackgroundColor = [System.Drawing.Color]::White
$packageGrid.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$packageGrid.GridColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$packageGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(236, 239, 241)
$packageGrid.ColumnHeadersDefaultCellStyle.ForeColor = $UiColorText
$packageGrid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$packageGrid.EnableHeadersVisualStyles = $false
$packageGrid.ColumnHeadersHeight = 34
$packageGrid.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$packageGrid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(227, 242, 253)
$packageGrid.DefaultCellStyle.SelectionForeColor = $UiColorText
$packageGrid.RowTemplate.Height = 30
$packageGrid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::None

$colPackage = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPackage.HeaderText = "Package"
$colPackage.Name = "Package"
$colPackage.FillWeight = 23
$colPackage.MinimumWidth = 125
[void]$packageGrid.Columns.Add($colPackage)

$colPackageId = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPackageId.HeaderText = "Package Id"
$colPackageId.Name = "PackageId"
$colPackageId.FillWeight = 34
$colPackageId.MinimumWidth = 150
[void]$packageGrid.Columns.Add($colPackageId)

$colVersion = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
$colVersion.HeaderText = "Version"
$colVersion.Name = "Version"
$colVersion.FillWeight = 18
$colVersion.MinimumWidth = 130
$colVersion.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
[void]$packageGrid.Columns.Add($colVersion)

$colState = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colState.HeaderText = "State"
$colState.Name = "State"
$colState.FillWeight = 14
$colState.MinimumWidth = 105
[void]$packageGrid.Columns.Add($colState)

$colAction = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colAction.HeaderText = "Action"
$colAction.Name = "Action"
$colAction.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$colAction.FillWeight = 11
$colAction.MinimumWidth = 90
$colAction.UseColumnTextForButtonValue = $false
[void]$packageGrid.Columns.Add($colAction)
$packageGrid.Columns[4].DisplayIndex = 4
$packageGrid.Columns[0].ReadOnly = $true
$packageGrid.Columns[1].ReadOnly = $true
$packageGrid.Columns[3].ReadOnly = $true
$packageGrid.Columns[4].ReadOnly = $true
$packageGrid.Columns[2].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleLeft
$packageGrid.Columns[2].DisplayStyle = [System.Windows.Forms.DataGridViewComboBoxDisplayStyle]::ComboBox
$packageGrid.Columns[2].FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
$packageGrid.Columns[3].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter

$packagesTab.Controls.Add($packageGrid)

Set-ButtonStyle -Button $manifestOpenButton -StyleKind Secondary
Set-ButtonStyle -Button $manifestRefreshButton -StyleKind Primary
Set-ButtonStyle -Button $restoreRepoPackagesButton -StyleKind Primary
Set-ButtonStyle -Button $updateAllPackagesButton -StyleKind Primary
Set-ButtonStyle -Button $useAvatarTemplatesButton -StyleKind Secondary
Set-ButtonStyle -Button $useAvatarTemplateButton -StyleKind Secondary
Set-ButtonStyle -Button $undoLastProjectCopyButton -StyleKind Secondary

$refreshManifestInfo = {
    $path = $selectedManifestPath
    $packageGrid.Rows.Clear()

    if (-not $path) {
        $manifestInfoLabel.Text = "No file selected."
        return
    }

    if (-not (Test-Path -LiteralPath $path)) {
        $manifestInfoLabel.Text = "Manifest not found."
        return
    }

    try {
        $depMap = Get-DependencyMapFromManifest -ManifestPath $path
        $catalog = Get-KnownPackageCatalog

        # Build a normalized package table to avoid duplicates that differ only by case.
        $rowsByKey = @{}

        foreach ($normalized in $catalog.Keys) {
            $entry = $catalog[$normalized]
            if (-not $rowsByKey.ContainsKey($normalized)) {
                $rowsByKey[$normalized] = [pscustomobject]@{
                    Name = [string]$entry.PackageId
                    DisplayName = [string]$entry.DisplayName
                    AvailableVersion = [string]$entry.Version
                    Versions = @($entry.Versions)
                    InstalledVersion = ""
                    Installed = $false
                }
            }
        }

        foreach ($depName in $depMap.Keys) {
            $normalized = $depName.ToLowerInvariant()
            if ($rowsByKey.ContainsKey($normalized)) {
                $rowsByKey[$normalized].Name = $depName
                if (-not $rowsByKey[$normalized].DisplayName) {
                    $rowsByKey[$normalized].DisplayName = $depName
                }
                $rowsByKey[$normalized].InstalledVersion = [string]$depMap[$depName]
                $rowsByKey[$normalized].Installed = $true
                if ($rowsByKey[$normalized].Versions -notcontains [string]$depMap[$depName]) {
                    $rowsByKey[$normalized].Versions += [string]$depMap[$depName]
                }
            } else {
                $rowsByKey[$normalized] = [pscustomobject]@{
                    Name = $depName
                    DisplayName = $depName
                    AvailableVersion = [string]$depMap[$depName]
                    Versions = @([string]$depMap[$depName])
                    InstalledVersion = [string]$depMap[$depName]
                    Installed = $true
                }
            }
        }

        foreach ($row in ($rowsByKey.Values | Sort-Object @{ Expression = { $_.Installed }; Descending = $true }, @{ Expression = { $_.DisplayName }; Descending = $false })) {
            if (Is-HiddenOfficialPackage -PackageId $row.Name) {
                continue
            }

            $searchText = $packageSearchBox.Text.Trim().ToLowerInvariant()
            if ($searchText) {
                $haystack = (([string]$row.DisplayName) + " " + ([string]$row.Name)).ToLowerInvariant()
                if (-not $haystack.Contains($searchText)) {
                    continue
                }
            }

            $filterValue = [string]$packageFilterCombo.SelectedItem
            if ($filterValue -eq "Installed" -and -not $row.Installed) {
                continue
            }
            if ($filterValue -eq "Available" -and $row.Installed) {
                continue
            }

            $hasUpdate = $row.Installed -and (Test-IsNewerStablePackageVersion -Candidate ([string]$row.AvailableVersion) -Current ([string]$row.InstalledVersion))
            if ($row.Installed -and $hasUpdate) {
                $stateText = "Update Available"
                $actionText = "Update"
                $versionText = ConvertTo-PackageVersionChoice -Version ([string]$row.AvailableVersion) -LatestVersion ([string]$row.AvailableVersion)
            } elseif ($row.Installed) {
                $stateText = "Installed"
                $actionText = "Remove"
                $versionText = ConvertTo-PackageVersionChoice -Version ([string]$row.InstalledVersion) -LatestVersion ([string]$row.AvailableVersion)
            } else {
                $stateText = "Not Installed"
                $actionText = "Add"
                $versionText = ConvertTo-PackageVersionChoice -Version ([string]$row.AvailableVersion) -LatestVersion ([string]$row.AvailableVersion)
            }

            $displayText = if ($row.DisplayName) { $row.DisplayName } else { $row.Name }
            $versionCell = New-Object System.Windows.Forms.DataGridViewComboBoxCell
            $versionCell.DisplayStyle = [System.Windows.Forms.DataGridViewComboBoxDisplayStyle]::ComboBox
            $versionCell.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
            foreach ($versionChoice in @($row.Versions | Where-Object { $_ } | Select-Object -Unique)) {
                $choiceText = ConvertTo-PackageVersionChoice -Version ([string]$versionChoice) -LatestVersion ([string]$row.AvailableVersion)
                if (-not $versionCell.Items.Contains($choiceText)) {
                    [void]$versionCell.Items.Add($choiceText)
                }
            }
            if ($versionCell.Items.Count -eq 0) {
                [void]$versionCell.Items.Add($versionText)
            }
            if ($versionCell.Items.Contains($versionText)) {
                $versionCell.Value = $versionText
            } else {
                $versionCell.Items.Add($versionText)
                $versionCell.Value = $versionText
            }

            $gridRow = New-Object System.Windows.Forms.DataGridViewRow
            $gridRow.CreateCells($packageGrid)
            $gridRow.Cells[0].Value = $displayText
            $gridRow.Cells[1].Value = $row.Name
            $gridRow.Cells[2] = $versionCell
            $gridRow.Cells[3].Value = $stateText
            $gridRow.Cells[4].Value = $actionText
            $gridRow.Tag = $row
            [void]$packageGrid.Rows.Add($gridRow)
        }

        $manifestInfoLabel.Text = "Dependencies: $($depMap.Count)"
    } catch {
        $manifestInfoLabel.Text = "Could not read manifest JSON."
    }
}

$manifestOpenButton.Add_Click({
    $target = $selectedManifestPath
    if (-not $target -or -not (Test-Path -LiteralPath $target)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Manifest file does not exist.",
            "Open Manifest Folder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $parent = Split-Path -Parent $target
    Start-Process explorer.exe "`"$parent`""
})

$manifestRefreshButton.Add_Click({
    $manifestStatusLabel.Text = "Refreshing configured VCC repos..."
    $form.Refresh()

    try {
        $refreshResult = Refresh-RepoCache
        & $refreshManifestInfo
        $manifestStatusLabel.Text = "Repo catalog refreshed. Updated: $($refreshResult.Updated); failed: $(@($refreshResult.Failed).Count)."

        if (@($refreshResult.Failed).Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Some repos could not be refreshed. Existing cached data was kept for those repos.`n`n$($refreshResult.Failed -join "`n")",
                "Repo Refresh Results",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    } catch {
        $manifestStatusLabel.Text = "Repo refresh failed; cached catalog was kept."
        [System.Windows.Forms.MessageBox]::Show(
            "Could not refresh repos:`n$($_.Exception.Message)",
            "Repo Refresh Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        & $refreshManifestInfo
    }
})

$restoreRepoPackagesButton.Add_Click({
    $targetPath = $selectedManifestPath
    if (-not $targetPath -or -not (Test-Path -LiteralPath $targetPath)) {
        $manifestStatusLabel.Text = "Select a valid manifest before restoring packages."
        return
    }

    try {
        $catalog = Get-KnownPackageCatalog
        $targetPaths = Get-LinkedTemplateManifestTargets -SelectedManifestPath $targetPath
        $restorePlans = @()
        $totalMissing = 0

        foreach ($target in $targetPaths) {
            $installed = Get-DependencyMapFromManifest -ManifestPath $target
            $missing = @{}

            foreach ($entry in $catalog.Values) {
                $packageId = [string]$entry.PackageId
                if (-not $packageId -or (Is-HiddenOfficialPackage -PackageId $packageId)) {
                    continue
                }
                if ($installed.ContainsKey($packageId)) {
                    continue
                }

                $version = [string]$entry.Version
                if (-not $version) {
                    $version = "1.0.0"
                }
                $missing[$packageId] = ConvertTo-PackageVersionChoice -Version $version -LatestVersion $version
            }

            if ($missing.Count -gt 0) {
                $restorePlans += [pscustomobject]@{
                    Path = $target
                    Dependencies = $missing
                }
                $totalMissing += $missing.Count
            }
        }

        if ($totalMissing -eq 0) {
            $manifestStatusLabel.Text = "No missing packages found in the configured local repos."
            return
        }

        $targetListText = ($restorePlans | ForEach-Object {
            "- $($_.Path) ($($_.Dependencies.Count) packages)"
        }) -join "`n"
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Add $totalMissing missing packages from configured local repos?`n`nTargets:`n$targetListText`n`nEach changed manifest will be backed up first.",
            "Restore Repo Packages",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            $manifestStatusLabel.Text = "Package restore cancelled."
            return
        }

        $totalAdded = 0
        foreach ($plan in $restorePlans) {
            Backup-ManifestFile -FilePath $plan.Path | Out-Null
            $result = Merge-DependenciesIntoManifest -TargetManifestPath $plan.Path -DependenciesToApply $plan.Dependencies
            $totalAdded += $result.Added
        }

        $manifestStatusLabel.Text = "Restored $totalAdded packages from local repos."
        & $refreshManifestInfo
    } catch {
        $manifestStatusLabel.Text = "Package restore failed."
        [System.Windows.Forms.MessageBox]::Show(
            "Error while restoring packages:`n$($_.Exception.Message)",
            "Package Restore Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$updateAllPackagesButton.Add_Click({
    $targetPath = $selectedManifestPath
    if (-not $targetPath -or -not (Test-Path -LiteralPath $targetPath)) {
        $manifestStatusLabel.Text = "Select a valid manifest before updating packages."
        return
    }

    try {
        $manifestStatusLabel.Text = "Refreshing repos and checking for package updates..."
        $form.Refresh()
        $repoRefreshResult = Refresh-RepoCache
        $catalog = Get-KnownPackageCatalog
        $targetPaths = Get-LinkedTemplateManifestTargets -SelectedManifestPath $targetPath
        $updatePlans = @()
        $updateLines = @()

        foreach ($target in $targetPaths) {
            $installed = Get-DependencyMapFromManifest -ManifestPath $target
            $updates = @{}

            foreach ($packageId in $installed.Keys) {
                $normalized = ([string]$packageId).ToLowerInvariant()
                if (-not $catalog.ContainsKey($normalized)) {
                    continue
                }

                $currentVersion = [string]$installed[$packageId]
                $latestVersion = [string]$catalog[$normalized].Version
                if (Test-IsNewerStablePackageVersion -Candidate $latestVersion -Current $currentVersion) {
                    $latestChoice = ConvertTo-PackageVersionChoice -Version $latestVersion -LatestVersion $latestVersion
                    $updates[$packageId] = $latestChoice
                    $updateLines += "- ${packageId}: $currentVersion -> $latestChoice"
                }
            }

            if ($updates.Count -gt 0) {
                $updatePlans += [pscustomobject]@{
                    Path = $target
                    Dependencies = $updates
                }
            }
        }

        if ($updatePlans.Count -eq 0) {
            $manifestStatusLabel.Text = "All installed packages are already at the latest stable versions in the configured repos."
            return
        }

        $repoFailureNote = if (@($repoRefreshResult.Failed).Count -gt 0) {
            "`n`nSome repos could not refresh; their existing cache was used."
        } else {
            ""
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Update $($updateLines.Count) package entries to the latest stable repo versions?`n`n$($updateLines -join "`n")`n`nEach changed manifest will be backed up first.$repoFailureNote",
            "Update All Packages",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            $manifestStatusLabel.Text = "Package updates cancelled."
            return
        }

        $updatedCount = 0
        foreach ($plan in $updatePlans) {
            Backup-ManifestFile -FilePath $plan.Path | Out-Null
            $result = Merge-DependenciesIntoManifest -TargetManifestPath $plan.Path -DependenciesToApply $plan.Dependencies
            $updatedCount += $result.Updated
        }

        $manifestStatusLabel.Text = "Updated $updatedCount package entries to the latest stable versions."
        & $refreshManifestInfo
    } catch {
        $manifestStatusLabel.Text = "Bulk package update failed."
        [System.Windows.Forms.MessageBox]::Show(
            "Error while updating packages:`n$($_.Exception.Message)",
            "Update All Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$addSelectedToAllProjectsButton.Add_Click({
    $sourceManifest = $selectedManifestPath
    if (-not $sourceManifest -or -not (Test-Path -LiteralPath $sourceManifest)) {
        $manifestStatusLabel.Text = "Select a source manifest containing the packages to copy."
        return
    }

    try {
        $sourceDependencies = Get-DependencyMapFromManifest -ManifestPath $sourceManifest
    } catch {
        $manifestStatusLabel.Text = "Could not read the source manifest."
        return
    }

    if ($sourceDependencies.Count -eq 0) {
        $manifestStatusLabel.Text = "The source manifest has no packages to copy."
        return
    }

    $projectManifests = @(Get-AllProjectManifestPaths | Where-Object { $_ -ne $sourceManifest })
    if ($projectManifests.Count -eq 0) {
        $manifestStatusLabel.Text = "No other VCC project manifests were found."
        return
    }

    $addPlans = @()
    $totalMissingPackages = 0
    $projectsChanged = 0
    $projectsAlreadyComplete = 0
    $unreadable = 0
    foreach ($manifestPath in $projectManifests) {
        try {
            $installed = Get-DependencyMapFromManifest -ManifestPath $manifestPath
            $missing = @{}
            foreach ($packageId in $sourceDependencies.Keys) {
                if (-not $installed.ContainsKey($packageId)) {
                    $missing[$packageId] = $sourceDependencies[$packageId]
                }
            }

            if ($missing.Count -gt 0) {
                $addPlans += [pscustomobject]@{
                    Path = $manifestPath
                    Dependencies = $missing
                }
                $totalMissingPackages += $missing.Count
                $projectsChanged++
            } else {
                $projectsAlreadyComplete++
            }
        } catch {
            $unreadable++
        }
    }

    if ($totalMissingPackages -eq 0) {
        $manifestStatusLabel.Text = "All readable projects already have the source manifest packages."
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Copy $($sourceDependencies.Count) installed packages from:`n$sourceManifest`n`nMissing package entries: $totalMissingPackages across $projectsChanged projects.`nAlready-complete projects: $projectsAlreadyComplete`nUnreadable manifests skipped: $unreadable`n`nExisting package versions will be kept. Changed manifests will be backed up first.",
        "Add All Installed Packages to Projects",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        $manifestStatusLabel.Text = "Add all installed packages cancelled."
        return
    }

    try {
        $addedCount = 0
        $undoBackups = @()
        foreach ($plan in $addPlans) {
            $backupPath = Backup-ManifestFile -FilePath $plan.Path
            $undoBackups += [pscustomobject]@{
                ManifestPath = $plan.Path
                BackupPath = $backupPath
            }
        }

        Save-LastProjectCopyUndo -Backups $undoBackups -SourceManifest $sourceManifest | Out-Null

        foreach ($plan in $addPlans) {
            $result = Merge-DependenciesIntoManifest -TargetManifestPath $plan.Path -DependenciesToApply $plan.Dependencies
            $addedCount += $result.Added
        }

        $undoLastProjectCopyButton.Enabled = $true
        $manifestStatusLabel.Text = "Added $addedCount package entries across $projectsChanged projects."
        & $refreshManifestInfo
    } catch {
        $manifestStatusLabel.Text = "Could not copy all packages to projects."
        [System.Windows.Forms.MessageBox]::Show(
            "Error while copying packages to projects:`n$($_.Exception.Message)",
            "Add All Packages Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$undoLastProjectCopyButton.Add_Click({
    try {
        $undoRecord = Get-LastProjectCopyUndo
        if (-not $undoRecord -or @($undoRecord.Backups).Count -eq 0) {
            $manifestStatusLabel.Text = "There is no all-project copy to undo."
            $undoLastProjectCopyButton.Enabled = $false
            return
        }

        $invalidBackups = @($undoRecord.Backups | Where-Object {
            -not (Test-Path -LiteralPath $_.BackupPath) -or -not (Test-Path -LiteralPath $_.ManifestPath)
        })
        if ($invalidBackups.Count -gt 0) {
            $manifestStatusLabel.Text = "Undo is unavailable because one or more backup or project files are missing."
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Undo the last all-project package copy from:`n$($undoRecord.SourceManifest)`n`nRestore $(@($undoRecord.Backups).Count) project manifest(s) to their previous contents?",
            "Undo Last Copy",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            $manifestStatusLabel.Text = "Undo cancelled."
            return
        }

        foreach ($entry in $undoRecord.Backups) {
            Backup-ManifestFile -FilePath $entry.ManifestPath | Out-Null
        }
        foreach ($entry in $undoRecord.Backups) {
            Copy-Item -LiteralPath $entry.BackupPath -Destination $entry.ManifestPath -Force -ErrorAction Stop
        }

        Remove-Item -LiteralPath (Get-LastProjectCopyUndoPath) -Force -ErrorAction Stop
        $undoLastProjectCopyButton.Enabled = $false
        $manifestStatusLabel.Text = "Last all-project copy was undone."
        & $refreshManifestInfo
    } catch {
        $manifestStatusLabel.Text = "Undo failed; the undo record was kept."
        [System.Windows.Forms.MessageBox]::Show(
            "Could not undo the last copy:`n$($_.Exception.Message)",
            "Undo Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$useAvatarTemplateButton.Add_Click({
    $path = Get-TemplateManifestPath -TemplateName "World"
    if (Test-Path -LiteralPath $path) {
        $selectedManifestPath = $path
        & $refreshManifestInfo
        if (Test-Path -LiteralPath (Get-TemplateManifestPath -TemplateName "World 2019")) {
            $manifestStatusLabel.Text = "Using World templates. Package actions will apply to World and World 2019."
        } else {
            $manifestStatusLabel.Text = "Using World template manifest."
        }
    } else {
        $manifestStatusLabel.Text = "World template manifest not found."
    }
})

$useAvatarTemplatesButton.Add_Click({
    $path = Get-TemplateManifestPath -TemplateName "Avatar"
    if (Test-Path -LiteralPath $path) {
        $selectedManifestPath = $path
        & $refreshManifestInfo
        if (Test-Path -LiteralPath (Get-TemplateManifestPath -TemplateName "Avatar 2019")) {
            $manifestStatusLabel.Text = "Using Avatar templates. Package actions will apply to Avatar and Avatar 2019."
        } else {
            $manifestStatusLabel.Text = "Using Avatar template manifest."
        }
    } else {
        $manifestStatusLabel.Text = "Avatar template manifest not found."
    }
})

$packageGrid.Add_CellContentClick({
    param($sender, $e)

    if ($e.RowIndex -lt 0) {
        return
    }

    if ($e.ColumnIndex -ne 4) {
        return
    }

    $targetPath = $selectedManifestPath
    if (-not $targetPath -or -not (Test-Path -LiteralPath $targetPath)) {
        $manifestStatusLabel.Text = "No valid template manifest found."
        return
    }

    $targetPaths = Get-LinkedTemplateManifestTargets -SelectedManifestPath $targetPath

    $depId = [string]$packageGrid.Rows[$e.RowIndex].Cells[1].Value
    $depVersion = [string]$packageGrid.Rows[$e.RowIndex].Cells[2].Value
    $action = [string]$packageGrid.Rows[$e.RowIndex].Cells[4].Value

    if (-not $depId) {
        return
    }

    $targetListText = ($targetPaths | ForEach-Object { "- $_" }) -join "`n"
    if (-not $targetListText) {
        $targetListText = "- $targetPath"
    }

    $previewMessage = if ($action -eq "Remove") {
        "Remove package from manifest(s)?`n`nPackage: $depId`n`nTargets:`n$targetListText"
    } elseif ($action -eq "Update") {
        "Update package to version $depVersion in manifest(s)?`n`nPackage: $depId`n`nTargets:`n$targetListText"
    } else {
        "Add/Update package in manifest(s)?`n`nPackage: $depId`nVersion: $depVersion`n`nTargets:`n$targetListText"
    }

    $previewConfirm = [System.Windows.Forms.MessageBox]::Show(
        $previewMessage,
        "Confirm Package Action",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($previewConfirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        $manifestStatusLabel.Text = "Package action cancelled."
        return
    }

    try {
        if ($action -eq "Remove") {
            $totalRemoved = 0
            foreach ($tp in $targetPaths) {
                $backupPath = Backup-ManifestFile -FilePath $tp
                $totalRemoved += (Remove-DependenciesFromManifest -TargetManifestPath $tp -DependencyNames @($depId))
            }
            if ($totalRemoved -gt 0) {
                $manifestStatusLabel.Text = "Package removed: $depId (updated $($targetPaths.Count) manifest(s))"
            } else {
                $manifestStatusLabel.Text = "Package not found in manifest: $depId"
            }
        } else {
            if (-not $depVersion) {
                $depVersion = ">=1.0.0"
            }
            $oneDep = @{}
            $oneDep[$depId] = $depVersion
            $totalAdded = 0
            $totalUpdated = 0
            foreach ($tp in $targetPaths) {
                $backupPath = Backup-ManifestFile -FilePath $tp
                $result = Merge-DependenciesIntoManifest -TargetManifestPath $tp -DependenciesToApply $oneDep
                $totalAdded += $result.Added
                $totalUpdated += $result.Updated
            }
            $manifestStatusLabel.Text = "Package saved: $depId (Added: $totalAdded, Updated: $totalUpdated, manifests: $($targetPaths.Count))"
        }
    } catch {
        $manifestStatusLabel.Text = "Failed to run package action for $depId"
        [System.Windows.Forms.MessageBox]::Show(
            "Error while changing package:`n$($_.Exception.Message)",
            "Package Action Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }

    & $refreshManifestInfo
})

$packageGrid.Add_CurrentCellDirtyStateChanged({
    if ($packageGrid.IsCurrentCellDirty -and $packageGrid.CurrentCell -is [System.Windows.Forms.DataGridViewComboBoxCell]) {
        $packageGrid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

$packageGrid.Add_CellValueChanged({
    param($sender, $e)

    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 2) {
        return
    }

    $gridRow = $packageGrid.Rows[$e.RowIndex]
    $rowData = $gridRow.Tag
    if (-not $rowData) {
        return
    }

    $selectedVersion = [string]$gridRow.Cells[2].Value
    if (-not $rowData.Installed) {
        $gridRow.Cells[3].Value = "Not Installed"
        $gridRow.Cells[4].Value = "Add"
    } elseif ($selectedVersion -and $selectedVersion -ne [string]$rowData.InstalledVersion) {
        $gridRow.Cells[3].Value = "Version Selected"
        $gridRow.Cells[4].Value = "Update"
    } else {
        $gridRow.Cells[3].Value = "Installed"
        $gridRow.Cells[4].Value = "Remove"
    }
})

$packageSearchBox.Add_TextChanged({
    & $refreshManifestInfo
})

$packageFilterCombo.Add_SelectedIndexChanged({
    & $refreshManifestInfo
})

$updateCacheLayout = {
    [int]$left = 16
    [int]$top = 16
    [int]$gap = 10
    [int]$buttonWidth = 120
    [int]$rightPadding = 20
    [int]$contentWidth = [Math]::Max(500, $cacheTab.ClientSize.Width - $left - $rightPadding)

    $cacheTitle.Location = New-Object System.Drawing.Point($left, $top)
    $cachePathLabel.Location = New-Object System.Drawing.Point($left, 54)

    $cachePathBox.Location = New-Object System.Drawing.Point($left, 76)
    $cachePathBox.Width = [Math]::Max(250, $contentWidth - $buttonWidth - $gap)

    [int]$cacheBrowseX = [int]$cachePathBox.Location.X + [int]$cachePathBox.Width + $gap
    $cacheBrowseButton.Location = New-Object System.Drawing.Point($cacheBrowseX, 74)

    $cacheInfoLabel.Location = New-Object System.Drawing.Point($left, 114)
    $cacheInfoLabel.Width = $contentWidth
    $cacheStatusLabel.Location = New-Object System.Drawing.Point($left, 144)
    $cacheStatusLabel.Width = $contentWidth
}

$updateSettingsLayout = {
    [int]$left = 16
    [int]$rightPadding = 20
    [int]$contentWidth = [Math]::Max(500, $settingsTab.ClientSize.Width - $left - $rightPadding)

    $settingsHealthLabel.Width = $contentWidth
    $settingsHealthDetailsLabel.Width = $contentWidth
    $settingsPathLabel.Width = $contentWidth
}

$updatePackagesLayout = {
    [int]$left = 16
    [int]$rightPadding = 20
    [int]$gap = 10
    [int]$contentWidth = [Math]::Max(700, $packagesTab.ClientSize.Width - $left - $rightPadding)

    $manifestStatusLabel.Width = $contentWidth
    $manifestInfoLabel.Width = $contentWidth

    $packageSearchBox.Width = [Math]::Min(360, [Math]::Max(220, [int]($contentWidth * 0.35)))
    [int]$filterLabelX = [int]$packageSearchBox.Location.X + [int]$packageSearchBox.Width + 18
    $packageFilterLabel.Location = New-Object System.Drawing.Point($filterLabelX, 172)
    [int]$filterComboX = [int]$packageFilterLabel.Location.X + [int]$packageFilterLabel.Width + 8
    $packageFilterCombo.Location = New-Object System.Drawing.Point($filterComboX, 169)

    $packageActionsPanel.Location = New-Object System.Drawing.Point($left, 108)
    $packageActionsPanel.Width = $contentWidth

    $packageSearchLabel.Location = New-Object System.Drawing.Point($left, 254)
    $packageSearchBox.Location = New-Object System.Drawing.Point(72, 251)
    $packageFilterLabel.Location = New-Object System.Drawing.Point(410, 254)
    $packageFilterCombo.Location = New-Object System.Drawing.Point(458, 251)
    $detectedLabel.Location = New-Object System.Drawing.Point($left, 286)

    $packageGrid.Location = New-Object System.Drawing.Point($left, 310)
    $packageGrid.Width = $contentWidth
    $packageGrid.Height = [Math]::Max(220, $packagesTab.ClientSize.Height - $packageGrid.Top - 24)
}

$cacheTab.Add_Resize({ & $updateCacheLayout })
$settingsTab.Add_Resize({ & $updateSettingsLayout })
$packagesTab.Add_Resize({ & $updatePackagesLayout })
& $updateCacheLayout
& $updateSettingsLayout
& $updatePackagesLayout
& $refreshSettingsHealth
try {
    $undoLastProjectCopyButton.Enabled = [bool](Get-LastProjectCopyUndo)
} catch {
    $undoLastProjectCopyButton.Enabled = $false
}

# Force exact tab order to prevent missing/duplicate tab issues.
$tabControl.TabPages.Clear()
[void]$tabControl.TabPages.Add($packagesTab)
[void]$tabControl.TabPages.Add($cacheTab)
[void]$tabControl.TabPages.Add($settingsTab)
[void]$tabControl.TabPages.Add($projectsTab)
$tabControl.SelectedIndex = 0

& $refreshManifestInfo

[void]$form.ShowDialog()
