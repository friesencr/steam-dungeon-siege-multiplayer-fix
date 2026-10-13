#!/usr/bin/env bash
# Dungeon Siege 1 Steam/Proton multiplayer and widescreen fix.
# Run: bash fix-dungeon-siege.sh
# Requires Python 3 and Protontricks (native or Flatpak). No sudo needed.
# Launch the game once with Proton, then close it before running this script.
# Based on the fixes verified on this installation and:
# https://github.com/GenesisFR/DS1TroubleshootingGuide
set -euo pipefail
command -v python3 >/dev/null || { echo "Install Python 3 first." >&2; exit 1; }
exec python3 - "$@" <<'PY'
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description="Fix Dungeon Siege 1 on Linux/Steam Deck: multiplayer, native DirectPlay, and optional widescreen.", epilog="Backups contain the original Proton prefix and configuration files. Keep Steam open, but close the game. This does not restore the original ZoneMatch service.")
parser.add_argument('--resolution', default='1920x1080', metavar='WIDTHxHEIGHT', help='widescreen size (default: 1920x1080; up to 1080p)')
parser.add_argument('--no-widescreen', action='store_true', help='apply only multiplayer fixes')
parser.add_argument('--steam-dir', type=Path, help='Steam root containing steamapps/libraryfolders.vdf')
parser.add_argument('--game-dir', type=Path, help='explicit Dungeon Siege 1 game directory')
parser.add_argument('--dry-run', action='store_true', help='show the plan without changing files or installing anything')
args = parser.parse_args()

def fail(message):
    raise RuntimeError(message)

def unique(paths):
    return list(dict.fromkeys(p.expanduser().resolve() for p in paths))

def vdf_value(raw):
    return re.sub(r'\\([\\"])', r'\1', raw)

def set_top_level(data, values):
    # Preserve unrelated settings, including settings with the same name in sections.
    newline = b'\r\n' if b'\r\n' in data else b'\n'
    lines = data.splitlines(keepends=True)
    header = next((i for i, line in enumerate(lines) if line.lstrip().startswith(b'[')), len(lines))
    top, rest = lines[:header], lines[header:]
    for key, value in values.items():
        pattern = re.compile(rb'^\s*' + key.encode() + rb'\s*=', re.I)
        matches = [i for i, line in enumerate(top) if pattern.match(line)]
        replacement = f'{key} = {value}'.encode() + newline
        if matches:
            top[matches[0]] = replacement
            for i in reversed(matches[1:]):
                del top[i]
        else:
            top.insert(0, replacement)
    return b''.join(top + rest)

def atomic_write(path, data):
    path = path.resolve()
    mode = path.stat().st_mode & 0o777
    fd, temp = tempfile.mkstemp(prefix='.dsfix-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

backup = None
try:
    size = re.fullmatch(r'(\d+)x(\d+)', args.resolution)
    if not args.no_widescreen and (not size or not (640 <= int(size[1]) <= 1920 and 480 <= int(size[2]) <= 1080)):
        fail('Use a resolution from 640x480 through 1920x1080. Higher resolutions need additional fixes.')
    home = Path.home()
    roots = unique([args.steam_dir] if args.steam_dir else [
        Path(os.environ['STEAM_DIR']) if os.environ.get('STEAM_DIR') else home / '.local/share/Steam',
        home / '.steam/steam', home / '.steam/root',
        home / '.var/app/com.valvesoftware.Steam/.local/share/Steam',
    ])
    found = []
    for root in roots:
        libraries = [root]
        vdf = root / 'steamapps/libraryfolders.vdf'
        if vdf.is_file():
            text = vdf.read_text(errors='replace')
            libraries += [Path(vdf_value(p)) for p in re.findall(r'"path"\s*"((?:\\.|[^"\\])*)"', text)]
            libraries += [Path(vdf_value(p)) for p in re.findall(r'"\d+"\s*"((?:\\.|[^"\\])*)"', text)]
        libraries = unique(libraries)
        for library in libraries:
            manifest = library / 'steamapps/appmanifest_39190.acf'
            if not manifest.is_file():
                continue
            match = re.search(r'"installdir"\s*"((?:\\.|[^"\\])*)"', manifest.read_text(errors='replace'))
            game = args.game_dir.expanduser().resolve() if args.game_dir else library / 'steamapps/common' / (vdf_value(match[1]) if match else 'Dungeon Siege 1')
            if not (game / 'DungeonSiege.exe').is_file():
                continue
            prefixes = unique([library / 'steamapps/compatdata/39190/pfx', root / 'steamapps/compatdata/39190/pfx'])
            prefix = next((p for p in prefixes if (p / 'user.reg').is_file()), None)
            if prefix:
                found.append((root, game, prefix))
    found = list(dict.fromkeys(found))
    if not found:
        fail('Cannot find Dungeon Siege 1 and its Proton prefix. Install it and launch it once using Proton. For a custom Steam location, pass --steam-dir PATH.')
    if len(found) != 1:
        fail('Multiple installations found. Select one with --steam-dir PATH and, if necessary, --game-dir PATH.')
    steam, game, prefix = found[0]
    configs = list((prefix / 'drive_c/users').glob('*/Documents/Dungeon Siege/DungeonSiege.ini'))
    if len(configs) != 1:
        fail('Cannot uniquely locate the user configuration. Launch the game once and close it first.')
    config = configs[0]
    system = game / 'system_detail.gas'
    before = config.read_bytes()
    settings = {'zonematch': 'true', 'dpnsvr': 'false'}
    if not args.no_widescreen:
        settings.update(width=size[1], height=size[2])
    changes = {config: (before, set_top_level(before, settings))}
    if not args.no_widescreen:
        original = system.read_bytes()
        updated = original
        if ('[' + args.resolution + ']').encode() not in original:
            updated, count = re.subn(rb'(?m)^([^\r\n]*\[1024x768\][^\r\n]*)(\r?\n)', lambda m: m[0] + m[1].replace(b'[1024x768]', ('[' + args.resolution + ']').encode()) + m[2], original)
            if not count:
                fail('Cannot recognize system_detail.gas resolution profiles; no changes made.')
        changes[system] = (original, updated)
    log = prefix / 'winetricks.log'
    registry = (prefix / 'user.reg').read_text(errors='replace')
    native = (log.exists() and 'directplay' in log.read_text().splitlines()
              and re.search(r'"\*?dpnet"="native(?:,builtin)?"', registry)
              and (prefix / 'drive_c/windows/syswow64/dpnet.dll').is_file()
              and not (prefix / 'drive_c/windows/syswow64/dpnet.dll').is_symlink())
    command = None
    if not native:
        if shutil.which('protontricks'):
            command = ['protontricks', '39190', '-q', 'directplay']
        elif shutil.which('flatpak') and subprocess.run(['flatpak', 'info', 'com.github.Matoking.protontricks'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            command = ['flatpak', 'run', '--env=STEAM_DIR=' + str(steam), 'com.github.Matoking.protontricks', '39190', '-q', 'directplay']
        elif not args.dry_run:
            fail('Install Protontricks first using your package manager, or run: flatpak install flathub com.github.Matoking.protontricks\nThen rerun this script. No files have been changed.')
    print('Game:', game)
    print('Proton prefix:', prefix)
    print('Multiplayer: zonematch = true, dpnsvr = false')
    print('DirectPlay:', 'native version already installed' if native else 'install native Microsoft components through Protontricks')
    print('Resolution:', 'keep current setting' if args.no_widescreen else args.resolution)
    if args.dry_run:
        print('Dry run complete. No files changed.')
        sys.exit(0)
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            name = (process / 'comm').read_text().strip().lower()
        except OSError:
            continue
        if name.startswith('dungeonsiege') or name in ('dsloa.exe', 'dpnsvr.exe'):
            fail('Close Dungeon Siege and its multiplayer server before running this script.')
    if native and all(old == new for old, new in changes.values()):
        print('All fixes are already applied.')
        sys.exit(0)
    if not shutil.which('cp'):
        fail('The cp utility is required to back up the Proton prefix.')
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = prefix.parent / 'dsfix-backups' / (stamp + '-' + str(os.getpid()))
    backup.mkdir(parents=True)
    print('Creating backup:', backup, flush=True)
    subprocess.run(['cp', '-a', '--reflink=auto', '--', str(prefix), str(backup / 'pfx')], check=True)
    for i, (path, (old, new)) in enumerate(changes.items()):
        shutil.copy2(path, backup / ('config-' + str(i) + '-' + path.name))
    (backup / 'locations.json').write_text(json.dumps({str(i): str(path.resolve()) for i, path in enumerate(changes)}, indent=2) + '\n')
    if command:
        print('Installing DirectPlay. Downloads may take a few minutes.', flush=True)
        environment = os.environ.copy()
        environment['STEAM_DIR'] = str(steam)
        subprocess.run(command, env=environment, check=True)
        if not log.exists() or 'directplay' not in log.read_text().splitlines():
            fail('Protontricks did not record a successful DirectPlay installation.')
    for path, (old, new) in changes.items():
        if path.read_bytes() != old:
            fail('A configuration changed during installation. Close the game and rerun the script.')
    for path, (old, new) in changes.items():
        if old != new:
            atomic_write(path, new)
        if path.read_bytes() != new:
            fail('Could not verify the configuration: ' + str(path))
    print('\nDone. Launch Dungeon Siege from Steam, then choose Network to host or join.')
    print('Backup:', backup)
    if not args.no_widescreen:
        print('The interface stays at its original size. Avoid changing resolution in the game menu; it lists the original sizes.')
except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
    print('\nError:', error, file=sys.stderr)
    if backup:
        print('Backup location:', backup, file=sys.stderr)
        print('Before restoring, close the game. The pfx folder is the original prefix; config-* files are the originals at the paths in locations.json.', file=sys.stderr)
    sys.exit(1)
PY
