"""Build public distribution metadata without exposing private repository access."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


def public_url(value):
    parsed = urlparse(value)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.query or parsed.fragment):
        raise ValueError('Use a public HTTPS URL.')
    return value.rstrip('/')


def next_release(baseline, previous=None, force=False):
    version, build = baseline.split('+')
    parts = tuple(map(int, version.split('.')))
    build = int(build)
    minimum = 0
    if previous:
        old = tuple(map(int, previous['version'].split('.')))
        parts = max(parts, old)
        build = max(build, previous['build_number'])
        minimum = previous['minimum_build_number']
    major, minor, patch = parts
    build += 1
    return {'version': f'{major}.{minor}.{patch + 1}', 'build_number': build,
            'minimum_build_number': build if force else minimum}


def local_baseline(baseline, artifact):
    """Prevent reusing a build number already installed from a local release."""
    version, build = baseline.split('+')
    if not re.fullmatch(r'\d+\.\d+\.\d+', artifact['version']):
        raise ValueError('Invalid local release version')
    if type(artifact['build_number']) is not int or artifact['build_number'] < 1:
        raise ValueError('Invalid local release build')
    parts = max(tuple(map(int, version.split('.'))),
                tuple(map(int, artifact['version'].split('.'))))
    return '.'.join(map(str, parts)) + '+' + str(max(int(build), artifact['build_number']))


def prepare(args):
    base = public_url(args.site_url)
    previous = None
    try:
        request = Request(base + '/update.json', headers={'Cache-Control': 'no-cache'})
        with urlopen(request, timeout=20) as response:
            previous = json.load(response)
        # Refuse malformed metadata rather than risking a duplicate version.
        assert re.fullmatch(r'\d+\.\d+\.\d+', previous['version'])
        assert type(previous['build_number']) is int and previous['build_number'] > 0
        assert type(previous['minimum_build_number']) is int
        assert 0 <= previous['minimum_build_number'] <= previous['build_number']
    except HTTPError as error:
        if error.code != 404:
            raise
    baseline = re.search(r'^version:\s*(\d+\.\d+\.\d+\+\d+)',
                         (ROOT / 'pubspec.yaml').read_text(), re.M).group(1)
    local = ROOT / 'build/public-site/update.json'
    if not os.environ.get('GITHUB_ACTIONS') and local.exists():
        artifact = json.loads(local.read_text())
        if artifact.get('apk_url', '').startswith(base + '/'):
            baseline = local_baseline(baseline, artifact)
    manifest = next_release(baseline, previous, args.force)
    manifest['apk_url'] = base + '/downloads/Rail-Pro.apk'
    path = ROOT / 'build/release-plan.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f"version={manifest['version']}\nbuild={manifest['build_number']}\n")
    print(f"Release {manifest['version']}+{manifest['build_number']}; minimum build {manifest['minimum_build_number']}")


def bundle(args):
    manifest = json.loads((ROOT / 'build/release-plan.json').read_text())
    apk = ROOT / 'build/app/outputs/flutter-apk/app-release.apk'
    aapt = args.aapt or shutil.which('aapt')
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        properties = ROOT / 'android/local.properties'
        if properties.exists():
            match = re.search(r'^sdk.dir=(.+)$', properties.read_text(), re.M)
            if match:
                sdk = match.group(1).replace('\\\\', '\\').replace('\\:', ':')
    if not aapt and sdk:
        candidates = list((Path(sdk) / 'build-tools').glob('*/aapt.exe' if os.name == 'nt' else '*/aapt'))
        aapt = str(sorted(candidates)[-1]) if candidates else None
    if not aapt:
        raise RuntimeError('Android aapt is required to verify the built APK version.')
    badging = subprocess.run([aapt, 'dump', 'badging', str(apk)],
                             check=True, capture_output=True, text=True).stdout
    build = re.search(r"versionCode='(\d+)'", badging)
    version = re.search(r"versionName='([^']+)'", badging)
    if (not build or not version or int(build.group(1)) != manifest['build_number'] or
            version.group(1) != manifest['version']):
        raise RuntimeError('APK version differs from the release plan. Rebuild before publishing.')
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    manifest.update(sha256=digest, size_bytes=apk.stat().st_size)
    target = ROOT / 'build/public-site'
    # Copy only the website and signed binary, never the repository or secrets.
    target.mkdir(parents=True, exist_ok=True)
    for name in ('index.html', 'privacy.html', 'website.css', 'website.js'):
        shutil.copy2(ROOT / 'docs' / name, target / name)
    shutil.copytree(ROOT / 'docs/assets', target / 'assets', dirs_exist_ok=True)
    (target / 'downloads').mkdir(exist_ok=True)
    shutil.copy2(apk, target / 'downloads/Rail-Pro.apk')
    (target / 'update.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f"Public bundle ready: {target}; SHA-256 {digest}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(required=True)
    plan = commands.add_parser('prepare')
    plan.add_argument('--site-url', required=True)
    plan.add_argument('--force', action='store_true')
    plan.set_defaults(run=prepare)
    package = commands.add_parser('bundle')
    package.add_argument('--aapt', help='Optional path to Android build-tools aapt')
    package.set_defaults(run=bundle)
    options = parser.parse_args()
    options.run(options)
