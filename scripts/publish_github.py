"""Publish only the verified website bundle and signed APK to a public repository."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]


def github_token():
    token = os.environ.get('GH_TOKEN') or os.environ.get('PUBLIC_REPO_TOKEN')
    if token:
        return token
    result = subprocess.run(['git', 'credential', 'fill'],
                            input='protocol=https\nhost=github.com\n\n',
                            capture_output=True, text=True, check=True,
                            env={**os.environ, 'GIT_TERMINAL_PROMPT': '0', 'GCM_INTERACTIVE': 'Never'})
    values = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if not values.get('password'):
        raise RuntimeError('GitHub authentication with public repository write access is required.')
    return values['password']


def api(token, path, method='GET', data=None, content_type='application/json'):
    body = json.dumps(data).encode() if data is not None and not isinstance(data, bytes) else data
    request = Request(path if path.startswith('https://') else 'https://api.github.com/' + path,
                      data=body, method=method, headers={
                          'Authorization': 'Bearer ' + token,
                          'User-Agent': 'rail-pro-publisher',
                          'Accept': 'application/vnd.github+json', 'Content-Type': content_type})
    with urlopen(request, timeout=300) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def publish(repo):
    token = github_token()
    metadata = api(token, f'repos/{repo}')
    if metadata['private']:
        raise RuntimeError('The distribution repository must be public.')
    bundle = ROOT / 'build/public-site'
    manifest = json.loads((bundle / 'update.json').read_text())
    apk = ROOT / 'build/app/outputs/flutter-apk/app-release.apk'
    import hashlib
    if hashlib.sha256(apk.read_bytes()).hexdigest() != manifest['sha256']:
        raise RuntimeError('APK changed after bundle verification.')
    if manifest['apk_url'] != f'https://github.com/{repo}/releases/latest/download/Rail-Pro.apk':
        raise RuntimeError('Release manifest points at the wrong repository.')
    tag = 'v' + manifest['version']
    # Never replace a published version or silently clobber its assets.
    release = api(token, f'repos/{repo}/releases', 'POST', {
        'tag_name': tag, 'target_commitish': metadata['default_branch'],
        'name': f"Rail Pro {manifest['version']}", 'draft': True,
        'body': f"Android release {manifest['version']} (build {manifest['build_number']}).\n\n"
                'Download Rail-Pro.apk. update.json contains version and SHA-256 metadata.'})
    try:
        print(f'Uploading signed APK and metadata for {tag}...', flush=True)
        upload = release['upload_url'].split('{')[0]
        api(token, upload + '?name=Rail-Pro.apk', 'POST', apk.read_bytes(),
            'application/vnd.android.package-archive')
        api(token, upload + '?name=update.json', 'POST', (bundle / 'update.json').read_bytes())
        ipa = ROOT / 'build/ios/ipa/RailPro.ipa'
        if ipa.is_file():
            print(f'Uploading iOS IPA for {tag}...', flush=True)
            api(token, upload + '?name=RailPro.ipa', 'POST', ipa.read_bytes(),
                'application/octet-stream')
    except Exception:
        api(token, f"repos/{repo}/releases/{release['id']}", 'DELETE')
        raise
    api(token, f"repos/{repo}/releases/{release['id']}", 'PATCH', {'draft': False, 'make_latest': 'true'})
    print(f'Release {tag} published; deploying website files...', flush=True)
    checkout = Path(tempfile.mkdtemp(prefix='public-repo-', dir=ROOT / 'build'))
    subprocess.run(['git', 'clone', '--depth', '1', f'https://github.com/{repo}.git', str(checkout)], check=True)
    for name in ('index.html', 'privacy.html', 'website.css', 'website.js', 'update.json', '.nojekyll'):
        shutil.copy2(bundle / name, checkout / name)
    shutil.copytree(bundle / 'assets', checkout / 'assets', dirs_exist_ok=True)
    subprocess.run(['git', 'add', '--', 'index.html', 'privacy.html', 'website.css',
                    'website.js', 'update.json', '.nojekyll', 'assets'], cwd=checkout, check=True)
    subprocess.run(['git', '-c', 'user.name=Rail Pro Publisher',
                    '-c', 'user.email=rail-pro-publisher@users.noreply.github.com',
                    'commit', '-m', f"Publish Rail Pro {manifest['version']} (build {manifest['build_number']})"],
                   cwd=checkout, check=True)
    subprocess.run(['git', 'push', 'origin', f"HEAD:{metadata['default_branch']}"], cwd=checkout, check=True)
    try:
        pages = api(token, f'repos/{repo}/pages')
    except HTTPError as error:
        if error.code != 404:
            raise
        pages = api(token, f'repos/{repo}/pages', 'POST', {
            'build_type': 'legacy', 'source': {'branch': metadata['default_branch'], 'path': '/'}})
    else:
        api(token, f'repos/{repo}/pages', 'PUT', {
            'build_type': 'legacy', 'source': {'branch': metadata['default_branch'], 'path': '/'}})
    print(f"Published {tag} to https://github.com/{repo}/releases/tag/{tag}")
    print(f"Website: {pages['html_url']}")


def publish_ipa(repo):
    token = github_token()
    metadata = api(token, f'repos/{repo}')
    if metadata['private']:
        raise RuntimeError('The distribution repository must be public.')
    ipa = ROOT / 'build/ios/ipa/RailPro.ipa'
    if not ipa.is_file():
        raise FileNotFoundError(f'IPA not found at {ipa}')

    target_release = None
    try:
        latest = api(token, f'repos/{repo}/releases/latest')
        if latest and 'id' in latest:
            target_release = latest
    except HTTPError as error:
        if error.code != 404:
            raise

    if not target_release:
        releases = api(token, f'repos/{repo}/releases')
        if releases and len(releases) > 0:
            target_release = releases[0]

    if not target_release:
        pubspec_path = ROOT / 'pubspec.yaml'
        version_str = '1.0.0'
        if pubspec_path.is_file():
            import re
            m = re.search(r'^version:\s*([^\s+]+)', pubspec_path.read_text(), re.MULTILINE)
            if m:
                version_str = m.group(1)
        tag = f'v{version_str}'
        print(f'No existing release found; creating release {tag}...', flush=True)
        target_release = api(token, f'repos/{repo}/releases', 'POST', {
            'tag_name': tag,
            'target_commitish': metadata['default_branch'],
            'name': f'Rail Pro {version_str}',
            'draft': False,
            'make_latest': 'true',
            'body': f'Release {version_str}.\n\nDownload RailPro.ipa for iOS.',
        })

    upload_url = target_release['upload_url'].split('{')[0]
    assets = target_release.get('assets', [])

    for asset in assets:
        if asset.get('name') == 'RailPro.ipa':
            print(f"Deleting existing RailPro.ipa asset (ID: {asset['id']})...", flush=True)
            api(token, f"repos/{repo}/releases/assets/{asset['id']}", 'DELETE')
            break

    print(f"Uploading RailPro.ipa ({ipa.stat().st_size} bytes) to release {target_release.get('tag_name')}...", flush=True)
    api(token, upload_url + '?name=RailPro.ipa', 'POST', ipa.read_bytes(), 'application/octet-stream')
    print(f"Successfully published RailPro.ipa to https://github.com/{repo}/releases/tag/{target_release.get('tag_name')}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default='about-shihab/rail-pro')
    parser.add_argument('--upload-ipa-only', action='store_true',
                        help='Upload RailPro.ipa to the latest release on the distribution repo')
    args = parser.parse_args()
    if args.upload_ipa_only:
        publish_ipa(args.repo)
    else:
        publish(args.repo)
