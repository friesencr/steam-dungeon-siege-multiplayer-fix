@echo off
setlocal
rem Dungeon Siege 1 fix for Windows 10/11. No extra downloads required.
rem Launch the game once, close it, then right-click this file: Run as administrator.
rem Default: multiplayer fixes plus 1920x1080 widescreen.
rem Options: --no-widescreen, --dry-run, --help (one option per run).
rem Based on https://github.com/GenesisFR/DS1TroubleshootingGuide
set "DSFIX_SELF=%~f0"
set "DSFIX_OPTION=%~1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$text = [IO.File]::ReadAllText($env:DSFIX_SELF); $marker = '#' + ' DSFIX_POWERSHELL'; $i = $text.IndexOf($marker); if ($i -lt 0) { throw 'Missing script payload.' }; & ([scriptblock]::Create($text.Substring($i + $marker.Length)))"
set "DSFIX_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %DSFIX_EXIT%
# DSFIX_POWERSHELL
# Compatible with Windows PowerShell 5.1, included in Windows 10/11.
$ErrorActionPreference = 'Stop'

function Read-ConfigFile {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $encoding = [Text.Encoding]::Default
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $encoding = New-Object Text.UTF8Encoding($true)
        $offset = 3
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        $encoding = [Text.Encoding]::Unicode
        $offset = 2
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
        $encoding = [Text.Encoding]::BigEndianUnicode
        $offset = 2
    }
    $preamble = [byte[]]@()
    if ($offset -gt 0) { $preamble = [byte[]]$bytes[0..($offset - 1)] }
    [pscustomobject]@{
        Path = $Path
        Original = $bytes
        Encoding = $encoding
        Preamble = $preamble
        Text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
}

function Set-TopLevelSettings {
    param([string]$Text, [System.Collections.IDictionary]$Settings)
    $newline = "`n"
    if ($Text.Contains("`r`n")) { $newline = "`r`n" }
    $section = [regex]::Match($Text, '(?m)^[\t ]*\[')
    $split = $Text.Length
    if ($section.Success) { $split = $section.Index }
    $top = $Text.Substring(0, $split)
    $rest = $Text.Substring($split)
    $keys = ($Settings.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $top = [regex]::Replace($top, ('(?im)^[\t ]*(?:' + $keys + ')[\t ]*=[^\r\n]*(?:\r?\n|$)'), '')
    $prefix = ($Settings.Keys | ForEach-Object { $_ + ' = ' + $Settings[$_] + $newline }) -join ''
    return $prefix + $top + $rest
}

function Add-Resolution {
    param([string]$Text, [string]$Resolution)
    if ($Text.Contains('[' + $Resolution + ']')) { return $Text }
    $pattern = '(?m)^([^\r\n]*\[1024x768\][^\r\n]*)(\r?\n)'
    if (-not [regex]::IsMatch($Text, $pattern)) { throw 'Unrecognized system_detail.gas resolution profiles. No configuration changes made.' }
    return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $match.Value + $match.Groups[1].Value.Replace('[1024x768]', '[' + $Resolution + ']') + $match.Groups[2].Value
    })
}

function Get-UpdatedBytes {
    param($Config, [string]$Text)
    return ,([byte[]]($Config.Preamble + $Config.Encoding.GetBytes($Text)))
}

function Get-GameFolders {
    param([string]$ScriptDirectory)
    $roots = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $games = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath (Join-Path $ScriptDirectory 'DungeonSiege.exe')) { [void]$games.Add($ScriptDirectory) }
    foreach ($entry in @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam', 'InstallPath')
    )) {
        $registry = Get-ItemProperty -LiteralPath $entry[0] -ErrorAction SilentlyContinue
        if ($registry -and $registry.($entry[1])) { [void]$roots.Add([string]$registry.($entry[1])) }
    }
    foreach ($programFiles in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($programFiles) { [void]$roots.Add((Join-Path $programFiles 'Steam')) }
    }
    $libraries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $roots) {
        [void]$libraries.Add($root)
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = [IO.File]::ReadAllText($vdf)
            foreach ($match in [regex]::Matches($text, '"(?:path|\d+)"\s*"((?:\\.|[^"\\])*)"')) {
                $library = $match.Groups[1].Value.Replace('\\', '\').Replace('\"', '"')
                if ([IO.Path]::IsPathRooted($library)) { [void]$libraries.Add($library) }
            }
        }
    }
    foreach ($library in $libraries) {
        $manifest = Join-Path $library 'steamapps\appmanifest_39190.acf'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $match = [regex]::Match([IO.File]::ReadAllText($manifest), '"installdir"\s*"((?:\\.|[^"\\])*)"')
        $folder = 'Dungeon Siege 1'
        if ($match.Success) { $folder = $match.Groups[1].Value.Replace('\\', '\').Replace('\"', '"') }
        $game = Join-Path (Join-Path $library 'steamapps\common') $folder
        if (Test-Path -LiteralPath (Join-Path $game 'DungeonSiege.exe')) { [void]$games.Add($game) }
    }
    return @($games | Sort-Object)
}

# DSFIX_MAIN
$backup = $null
try {
    $option = $env:DSFIX_OPTION
    if ($option -and $option -notin @('--no-widescreen', '--dry-run', '--help')) { throw 'Unknown option. Use --help for instructions.' }
    if ($option -eq '--help') {
        Write-Host 'Dungeon Siege 1 Windows 10/11 fix'
        Write-Host 'Launch the game once and close it. Then right-click this .bat: Run as administrator.'
        Write-Host 'Default: enable multiplayer, enable Windows DirectPlay, and set 1920x1080 widescreen.'
        Write-Host 'fix-dungeon-siege.bat --no-widescreen   Multiplayer only'
        Write-Host 'fix-dungeon-siege.bat --dry-run         Preview without changes (no admin needed)'
        Write-Host 'Backups are saved under Documents\Dungeon Siege\dsfix-backups.'
        Write-Host 'ZoneMatch remains offline; use Network or direct IP.'
        exit 0
    }
    $dryRun = $option -eq '--dry-run'
    $widescreen = $option -ne '--no-widescreen'
    if (-not $dryRun) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Right-click this .bat and choose Run as administrator. Windows requires this to enable DirectPlay and update files under Program Files.'
        }
    }
    if (Get-Process -Name DungeonSiege, DSLOA, dpnsvr -ErrorAction SilentlyContinue) { throw 'Close Dungeon Siege and its multiplayer server first.' }
    $games = @(Get-GameFolders ([IO.Path]::GetDirectoryName($env:DSFIX_SELF)))
    if ($games.Count -eq 1) {
        $game = $games[0]
    } elseif ($games.Count -gt 1) {
        Write-Host 'Multiple installations found:'
        for ($i = 0; $i -lt $games.Count; $i++) { Write-Host ($i.ToString() + ': ' + $games[$i]) }
        $choice = Read-Host 'Enter the installation number'
        if ($choice -notmatch '^\d+$' -or [int]$choice -ge $games.Count) { throw 'Invalid installation number.' }
        $game = $games[[int]$choice]
    } else {
        $game = (Read-Host 'Paste the game folder containing DungeonSiege.exe').Trim().Trim('"')
    }
    if (-not (Test-Path -LiteralPath (Join-Path $game 'DungeonSiege.exe'))) { throw 'DungeonSiege.exe was not found in that folder.' }
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $configPath = Join-Path $documents 'Dungeon Siege\DungeonSiege.ini'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Host 'The user configuration was not found. Launch the game once first, or specify its configuration.'
        $configPath = (Read-Host 'Paste the full path to your user DungeonSiege.ini').Trim().Trim('"')
    }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'User configuration not found. No changes made.' }
    $userConfig = Read-ConfigFile $configPath
    $settings = [ordered]@{ zonematch = 'true'; dpnsvr = 'false' }
    if ($widescreen) { $settings['width'] = '1920'; $settings['height'] = '1080' }
    $changes = @([pscustomobject]@{ Config = $userConfig; Updated = (Get-UpdatedBytes $userConfig (Set-TopLevelSettings $userConfig.Text $settings)) })
    if ($widescreen) {
        $systemConfig = Read-ConfigFile (Join-Path $game 'system_detail.gas')
        $changes += [pscustomobject]@{ Config = $systemConfig; Updated = (Get-UpdatedBytes $systemConfig (Add-Resolution $systemConfig.Text '1920x1080')) }
    }
    Write-Host ('Game: ' + $game)
    Write-Host ('User configuration: ' + $configPath)
    Write-Host 'Multiplayer: zonematch = true, dpnsvr = false; enable Windows DirectPlay if needed.'
    if ($widescreen) { Write-Host 'Resolution: 1920x1080' } else { Write-Host 'Resolution: keep current setting' }
    if ($dryRun) { Write-Host 'Dry run complete. No files or Windows features changed.'; exit 0 }
    $feature = Get-WindowsOptionalFeature -Online -FeatureName DirectPlay
    $name = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $backup = Join-Path (Split-Path -Parent $configPath) ('dsfix-backups\' + $name)
    [void](New-Item -ItemType Directory -Path $backup -Force)
    $locations = @('DirectPlay state before fix: ' + [string]$feature.State)
    for ($i = 0; $i -lt $changes.Count; $i++) {
        $file = 'config-' + $i + '-' + [IO.Path]::GetFileName($changes[$i].Config.Path)
        Copy-Item -LiteralPath $changes[$i].Config.Path -Destination (Join-Path $backup $file)
        $locations += $file + ' -> ' + $changes[$i].Config.Path
    }
    $locations | Set-Content -LiteralPath (Join-Path $backup 'restore-locations.txt') -Encoding UTF8
    Write-Host ('Backups: ' + $backup)
    $restart = $feature.State -eq 'EnablePending'
    if ($feature.State -ne 'Enabled' -and $feature.State -ne 'EnablePending') {
        Write-Host 'Enabling Windows DirectPlay. Windows may need to download feature files.'
        $result = Enable-WindowsOptionalFeature -Online -FeatureName DirectPlay -All -NoRestart
        $restart = [bool]$result.RestartNeeded
    }
    $state = (Get-WindowsOptionalFeature -Online -FeatureName DirectPlay).State
    if ($state -notin @('Enabled', 'EnablePending')) { throw ('DirectPlay was not enabled. Current state: ' + $state) }
    # Verify every source still matches the backup before changing any configuration.
    foreach ($change in $changes) {
        $current = [IO.File]::ReadAllBytes($change.Config.Path)
        if ([Convert]::ToBase64String($current) -ne [Convert]::ToBase64String($change.Config.Original)) { throw 'A configuration changed during setup. Close the game and rerun.' }
    }
    foreach ($change in $changes) {
        [IO.File]::WriteAllBytes($change.Config.Path, $change.Updated)
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($change.Config.Path)) -ne [Convert]::ToBase64String($change.Updated)) { throw ('Could not verify ' + $change.Config.Path) }
    }
    Write-Host ''
    Write-Host 'Done. Launch Dungeon Siege from Steam, then choose Network to host or join.'
    if ($restart -or $state -eq 'EnablePending') { Write-Host 'Restart Windows before playing to finish enabling DirectPlay.' }
    if ($widescreen) { Write-Host 'The interface stays at its original size. Avoid changing resolution in the game menu; it lists the original sizes.' }
    Write-Host 'To undo file changes: close the game and copy the backup files to the paths in restore-locations.txt.'
    exit 0
} catch {
    Write-Host ('Error: ' + $_.Exception.Message) -ForegroundColor Red
    if ($backup) { Write-Host ('Original configuration backups: ' + $backup) }
    exit 1
}
