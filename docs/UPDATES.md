# Versions and mandatory updates

বাংলায় ধাপে ধাপে প্রকাশের নির্দেশনা: [Firebase-এ Rail Pro প্রকাশ করুন](FIREBASE_PUBLISH_BN.md)।

The source repository can remain private. APK downloads and update metadata must be on public HTTPS hosting. The app never contains GitHub access tokens. The configured Firebase project is `railautomation-1993`; deployment requires your Firebase Hosting access and CI configuration.

## One-time GitHub setup

Create repository variables:

| Variable | Value |
| --- | --- |
| `FIREBASE_PROJECT_ID` | `railautomation-1993` (or your hosting project) |
| `PUBLIC_SITE_URL` | `https://railautomation-1993.web.app` (or your public custom domain) |

Create repository/environment secrets:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the **existing production keystore** |
| `ANDROID_STORE_PASSWORD` | Existing keystore password |
| `ANDROID_KEY_ALIAS` | Existing signing alias |
| `ANDROID_KEY_PASSWORD` | Existing signing-key password |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase deployment service-account JSON |

Use the same signing certificate for every release. A different certificate cannot update an installed APK. Keep secrets out of git, issues, logs, website files, and app configuration. Set up Firebase Hosting and the deployment service account using [Firebase's GitHub integration](https://firebase.google.com/docs/hosting/github-integration). No credentials are needed by users.

## Publish a release

Run **Actions → Android release and public website → Run workflow**. The workflow checks the current public `update.json`, increments the patch version and Android build number, runs checks, signs the APK, and publishes the website, APK, and metadata together. Concurrent releases are serialized. Failed metadata requests abort version allocation; only a 404 allows the initial release. The checked-in `pubspec.yaml` supplies the initial baseline. Raise its major/minor baseline for a larger version change; ordinary patch releases need no edits.

Leave `force_update` off for ordinary releases. Turn it on when all older builds must update: the new build becomes `minimum_build_number`. Future ordinary releases preserve this minimum. A subsequent larger-build policy can lower the minimum to recover from an accidental requirement. Stale older manifests cannot lower it.

Only `build/public-site` is published: website files, images, the signed APK and public metadata. Private source, signing files and service accounts are excluded. Stable `/downloads/Rail-Pro.apk` always points to the newest release so cached policies do not rely on deleted version-specific assets.

Example generated metadata (do not publish this example):

```json
{
  "version": "1.0.2",
  "build_number": 3,
  "minimum_build_number": 3,
  "apk_url": "https://your-public-domain.example/downloads/Rail-Pro.apk",
  "sha256": "computed-from-the-signed-apk",
  "size_bytes": 64000000
}
```

## App behavior

Installed version/build come from Android's package manager. The app checks metadata on startup, resume and at most every five minutes during service monitoring. New seat-layout/reservation operations consult cached policy, including in worker isolates. An in-progress startup check is awaited before starting a booking.

A mandatory update replaces navigation, blocks Back dismissal and prevents new bookings. Saved searches remain on the device. Android asks the user to approve APK installation; the app cannot silently replace itself. A cached mandatory policy remains effective offline. Without a valid cached policy, a failed initial check leaves the app usable. Invalid metadata is rejected to avoid locking users behind an unusable download. This is client-side enforcement; APKs predating this feature require backend version enforcement if they must be blocked.

The website reads the same manifest for its download URL, version and size. Before publication, it clearly shows download is unavailable. There is no private GitHub release fallback.

## Local build and alternative hosting

```powershell
python scripts/release.py prepare --site-url https://your-public-domain.example
# Add --force above to require this release.
$release = Get-Content build/release-plan.json | ConvertFrom-Json
flutter build apk --release --build-name $release.version --build-number $release.build_number --dart-define=UPDATE_MANIFEST_URL=https://your-public-domain.example/update.json
python scripts/release.py bundle
```

Deploy `build/public-site` together to Firebase or another public HTTPS host. For Firebase, authenticate locally then run `firebase deploy --only hosting --project YOUR_PROJECT`. Serve `update.json` and `/downloads/Rail-Pro.apk` without login and with caching disabled. Check both URLs from a signed-out browser before enabling mandatory updates. Keep the existing app installed while updating.

The previously published v1.0.1 GitHub APK does not contain this mechanism. Users must first install a release containing it. Repository configuration does not imply GitHub secrets or Firebase deployment are already set up.
