# iOS behavior and release checks

The iOS app uses WKWebView's native user agent for visible login and session
recovery. Cloudflare verification frames remain enabled. Android retains its
existing login user agent.

Requests carrying `cft_response` on iOS now use the user agent reported by the
retained verification WKWebView, with desktop Chromium client hints removed.
Seat-layout and sign-in challenges use their own configured site keys and do
not share pending tokens. The first execution after a site-key change is marked
used, so the next attempt resets the widget properly.

Token warming completes its cache handoff before booking consumes the result.
A submitted token cannot be cached again by a late callback. Cache entries
carry their site key and are discarded with less than 30 seconds of lifetime
remaining. Seat-layout payload templates cannot drop the runtime token. If
Railway rejects authentication after submission, session recovery does not
replay that token; the layout guard obtains a fresh challenge for its single
automatic retry. Explicit CFT rejection also gets one fresh-token retry while
the app is open. A second rejection stops for a deliberate user retry.

Leaving the app during native seat loading saves the exact leg and boarding
date and posts a local notification. Resume or notification tap restores that
layout, obtains fresh verification if needed, and clears the pending alert on
success. The saved context is account-bound, expires after 30 minutes, excludes
credentials and tokens, and never authorizes reservation or payment. This also
preserves an intermediate leg departing after midnight.

Native method channels are registered when the implicit Flutter engine is
initialized, as required by the UIScene lifecycle. This includes reading the
installed app version and opening ticket PDFs. PDFs are saved under the app's
Documents/Tickets directory and displayed with Quick Look, which offers sharing
and printing. The browser is used only if native viewing fails.

Notification permission requests and status checks use the iOS notification
plugin. Android Google SMS consent is unavailable on iOS; automatic SMS controls
are disabled and the OTP field retains its one-time-code keyboard suggestion.
An existing automatic OTP reservation falls back to manual entry on iOS.

iOS now posts a quiet, separate search-status notification when monitoring is
enabled or scheduled, and removes it when monitoring stops. This is a normal
iOS notification, not a pinned Android foreground-service indicator. Seat-found
alerts use banners, Notification Center entries and sound. Permission denial or
native delivery failure is reported rather than silently accepted; failed seat
notifications remain eligible on the next refresh.

Background refresh reads a separate encrypted, device-bound Keychain session
that is accessible after the first unlock since reboot. Existing sessions are
copied while scheduling from the open app, and updated/removed on login/logout.
Saved passwords retain their original unlocked-device access. The worker asks
the user to reopen the app when its session expires instead of attempting to
read a locked password or solve Cloudflare in the background.

The periodic refresh handler is registered before application launch finishes,
including the first launch. iOS decides when background refresh runs; it cannot
provide Android's continuous foreground-service polling or guarantee a 15-minute
interval. Keep the app open for time-sensitive monitoring.

## Automated validation

Railway API requests now share a single queue across searches, route loading,
seat layouts and booking steps, with at least 1.5 seconds between starts and
one active request at a time. Existing operation-specific intervals still
apply. A 429 response pauses every Railway API operation using `Retry-After`
(seconds or HTTP date), or a 30–300 second fallback backoff. The pause is saved
for background workers and app restarts. Queued work fails with the same
cooldown instead of sending another request. Seat-layout verification tokens
are never reused. Only explicit token/session rejection starts the single
fresh-token retry; rate limits, timeouts and server errors do not. Booking
mutations are never automatically replayed after an unknown outcome.

Auto-booking makes one attempt per monitoring cycle and backs off on failure.
A partially held or uncertain reservation is saved for review and prevents
another automatic booking. Intermediate scans start only after opening the
search for a particular train. Listing sold-out trains and normal monitoring
no longer start scans for every intermediate stop.

The intermediate search has independent **Two-ticket options** and **Station
seats** tabs. Route loads share a cached, bounded request; failures show a retry
instead of an endless spinner. Progress and stop controls are available during
split searches. Opening Station seats cancels the split scan. Station selection
allows forward journeys only, and segment queries and booking use the boarding
date adjusted for midnight relative to the original boarding station. Network
errors are not presented as sold-out trains or replaced with another train.

The mock-server test fixture removes wall-clock request spacing; dedicated
request-pacer tests verify production spacing, response serialization and
cooldown behavior with an injected clock.

Run `flutter analyze --no-pub` and `flutter test --no-pub`. The iOS regression
tests use fake native channels and WebViews; they do not execute Swift, contact
Cloudflare, or prove delivery while the app is suspended.
`ios_seat_layout_token_test.dart` exercises the browser-callback-to-request flow
against a mock server. It does not prove that a production token is accepted.
`smooth_seat_layout_test.dart` verifies bounded token refresh and session recovery.
`seat_layout_continuation_test.dart` verifies notification routing, account
binding, saved-leg expiry and pause/resume recovery. The intermediate booking
test follows an overnight second leg through a rejected-token refresh into the
native seat picker, using a simulated Turnstile callback.
`node test/turnstile_bootstrap_test.cjs` checks the embedded JavaScript's widget
reset behavior, including after a site-key change.

## Required checks on a Mac and iPhone

- Build the iOS target in Xcode and confirm native channel and Quick Look code
  compiles. Windows cannot perform this check.
- Complete Cloudflare verification and login, then expire the session and test
  recovery and manual login.
- Complete a real Turnstile challenge and load real seats. Repeat for another
  train, including while a token is being prepared, and verify that each layout
  receives a different unused token. Verify a session-refresh retry obtains a
  fresh token. Avoid recording raw tokens or authentication headers in logs.
- Open an intermediate leg, leave during seat loading, and verify one local
  notification returns to the same stations and correct boarding date. Repeat
  after terminating and reopening the app, then with notification permission
  denied. Verify an invalid token gets at most one automatic fresh-token retry.
- Deny notifications, check the reported status, then enable notifications in
  Settings and check again. Test a local seat alert and its destination, verify
  the separate search-status notification, and stop searching to remove it.
- Reserve a seat, fill an SMS code using the keyboard suggestion, and complete
  the OTP/payment flow.
- Verify sequential auto-booking, rate-limit countdowns and recovery after a
  server pause. Confirm an uncertain reservation stays available for review.
- Open a sold-out train's intermediate search, switch tabs during a scan, retry
  a failed route load, and book an overnight segment using its displayed date.
- Download a purchased ticket, preview it, share it, and print it. Confirm a
  second download works after dismissing the preview.
- Restart offline after caching an update policy and confirm its link remains
  the IPA link. Verify the installed version is read from the app bundle.
- Schedule a search and test background refresh on a physical device. Delivery
  timing remains controlled by iOS. Unlock once after reboot, lock the screen,
  and test seat detection and alert delivery during a background refresh.

Remote administrator announcements remain Android-only in `AdminPushService`.
Enabling iOS remote push also requires a valid Firebase iOS app registration,
APNs credentials, and push entitlements for the signing profile. These cannot be
confirmed from the Windows workspace and are separate from local seat alerts.

References: [Flutter UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate),
[Cloudflare mobile integration](https://developers.cloudflare.com/turnstile/get-started/mobile-implementation/),
[Apple Quick Look](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller).
