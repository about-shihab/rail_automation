# iOS behavior and release checks

The iOS app uses WKWebView's native user agent for visible login and session
recovery. Cloudflare verification frames remain enabled. Android retains its
existing login user agent.

Native method channels are registered when the implicit Flutter engine is
initialized, as required by the UIScene lifecycle. This includes reading the
installed app version and opening ticket PDFs. PDFs are saved under the app's
Documents/Tickets directory and displayed with Quick Look, which offers sharing
and printing. The browser is used only if native viewing fails.

Notification permission requests and status checks use the iOS notification
plugin. Android Google SMS consent is unavailable on iOS; automatic SMS controls
are disabled and the OTP field retains its one-time-code keyboard suggestion.
An existing automatic OTP reservation falls back to manual entry on iOS.

The periodic refresh handler is registered before application launch finishes,
including the first launch. iOS decides when background refresh runs; it cannot
provide Android's continuous foreground-service polling or guarantee a 15-minute
interval. Keep the app open for time-sensitive monitoring.

## Automated validation

Run `flutter analyze --no-pub` and `flutter test --no-pub`. The iOS regression
tests use fake native channels and WebViews; they do not execute Swift, contact
Cloudflare, or prove delivery while the app is suspended.

## Required checks on a Mac and iPhone

- Build the iOS target in Xcode and confirm native channel and Quick Look code
  compiles. Windows cannot perform this check.
- Complete Cloudflare verification and login, then expire the session and test
  recovery and manual login.
- Deny notifications, check the reported status, then enable notifications in
  Settings and check again. Test a local seat alert and its destination.
- Reserve a seat, fill an SMS code using the keyboard suggestion, and complete
  the OTP/payment flow.
- Download a purchased ticket, preview it, share it, and print it. Confirm a
  second download works after dismissing the preview.
- Restart offline after caching an update policy and confirm its link remains
  the IPA link. Verify the installed version is read from the app bundle.
- Schedule a search and test background refresh on a physical device. Delivery
  timing remains controlled by iOS.

Remote administrator announcements remain Android-only in `AdminPushService`.
Enabling iOS remote push also requires a valid Firebase iOS app registration,
APNs credentials, and push entitlements for the signing profile. These cannot be
confirmed from the Windows workspace and are separate from local seat alerts.

References: [Flutter UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate),
[Cloudflare mobile integration](https://developers.cloudflare.com/turnstile/get-started/mobile-implementation/),
[Apple Quick Look](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller).
