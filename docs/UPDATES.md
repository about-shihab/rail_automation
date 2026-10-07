# Versions and public releases

Railway login recovery, API settings, and booking/OTP alerts:
[Railway API workflow configuration](RAIL_API_WORKFLOW.md).

Website: https://about-shihab.github.io/rail-pro/

APK: https://github.com/about-shihab/rail-pro/releases/latest/download/Rail-Pro.apk

The Flutter source stays in the private `about-shihab/rail_automation` repository.
Only website assets, release metadata, and the signed APK are published to the
public `about-shihab/rail-pro` repository. GitHub Pages serves its `main` branch
root. APKs and `update.json` are attached to versioned GitHub Releases.

## Release workflow

Push application changes to the private source repository's `main` branch, or run
**Actions → Android release and public website → Run workflow**. The workflow
runs Flutter/Python/JavaScript checks, restores production signing, builds the
APK, verifies its embedded version, and publishes to the public repository.
GitHub Pages deployment follows the public website commit.

Source-repository secrets required:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Existing production keystore |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Existing signing alias |
| `ANDROID_KEY_PASSWORD` | Signing key password |
| `PUBLIC_REPO_TOKEN` | GitHub credential with Contents write access to `about-shihab/rail-pro`; Pages/Administration write access is needed to configure hosting |

The publisher checks that the target repository is public, verifies the APK hash,
uploads the APK and metadata before publishing the release, and copies only the
website file allowlist. No source files or credentials are copied. Existing
public repository files are preserved. A published version is never overwritten.
Keep signing credentials and the publisher token in source-repository Actions
secrets; they do not belong in the public repository or APK.

## Version maintenance

Release preparation reads the public Pages manifest and the latest Release's
`update.json`, then increments the highest version/build and the local baseline.
The release asset prevents reusing a version when Pages deployment is delayed.
For the first migration, the previous Firebase manifest supplies the existing
version/build; subsequent GitHub releases do not depend on Firebase availability.
The initial migrated release follows `1.0.5+6` with `1.0.6+7`.

Concurrent source workflows are serialized. Metadata errors abort allocation;
only a 404 represents an initial deployment. The APK's embedded version and
SHA-256 must match the publication manifest. Stable latest-download links remain
usable by older cached update policies. Release tags preserve past versions.

Leave `force_update` disabled for ordinary releases. Enabling it sets the new
build as `minimum_build_number`. Later ordinary releases preserve that minimum.
The app checks the GitHub Pages manifest at startup, on resume, and periodically
while monitoring. A mandatory policy blocks new bookings until the user updates.
Android still asks the user to approve installation.

Previously installed APKs that point at Firebase continue checking that old URL
until upgraded. The migrated APK and later builds use GitHub Pages. Saved searches
remain on the device, and updates require the same production signing certificate.

## Local publication

```powershell
python scripts/release.py prepare --site-url https://about-shihab.github.io/rail-pro --release-repo about-shihab/rail-pro --previous-manifest-url https://railautomation-1993.web.app/update.json
$release = Get-Content build/release-plan.json | ConvertFrom-Json
flutter build apk --release --build-name $release.version --build-number $release.build_number --dart-define=UPDATE_MANIFEST_URL=https://about-shihab.github.io/rail-pro/update.json
python scripts/release.py bundle
python scripts/publish_github.py --repo about-shihab/rail-pro
```

Local publishing uses `GH_TOKEN`/`PUBLIC_REPO_TOKEN`, or your existing GitHub Git
credential. Git push must also be authenticated; CI configures it with
`gh auth setup-git`. Pages and APK links are public and need no user login.
