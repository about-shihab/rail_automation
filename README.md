# Rail Pro

Flutter app for finding Railway journeys, selecting a class and seat quantity,
watching availability, attempting a reservation, and handing payment back to the user.

## User flow

1. Sign in to Railway and search a route and date.
2. Choose a train and class, then select Auto-book and the number of seats.
3. Optionally allow Railway SMS verification. Without permission, OTP is entered manually.
4. View a simple journey card; diagnostic logs are not displayed.
5. Review the held reservation and complete payment with Railway.

Search preferences survive restarts. Pause stops future reservation attempts; it
cannot undo a request already accepted by Railway. Pending or uncertain bookings
block further automatic attempts until reviewed. No payment is submitted automatically.

## Background operation

Android uses the existing foreground service and a persistent notification. The
configured polling interval defaults to 120 seconds. A saved active search starts
its service again when restored in the foreground. If service startup fails, the
app tells the user to keep it open. iOS uses scheduled background tasks rather than
continuous polling. Desktop and web require the app to remain open.

The current implementation bounds Android service sessions at five hours, and
free searches expire after the configured free duration (default one hour).
The operating system, connectivity, force-stop, and Railway authentication can
interrupt processing. Continuous unattended operation is not guaranteed.

Railway can require a fresh verification challenge (`cft_response`). The app does
not currently obtain that challenge automatically. In that case users must
continue on the official booking page. Live seat reservation and SMS verification
must be validated on a physical device before release.

## Validation

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

Mobile dashboard layout tests render previews under `build/design-preview`.
Tests cover seat availability parsing, cancellation before mutation, uncertain
booking outcomes, OTP acknowledgements, and fare-free automatic booking setup.

## Release configuration

Release builds require an upload keystore; debug signing is never used for release.
Copy `android/key.properties.example` to `android/key.properties` and supply your
own values. Keep the properties file and keystore private. The keystore path is
relative to the Android project directory, or can be absolute.

Before publishing, choose the final application ID (currently
`com.example.rail_automation`) and update the matching Firebase/platform
configuration. Verify production Firebase access rules and the existing credit
and account configuration in their deployed environment. Those external settings
are not validated by local tests.

Physical-device acceptance still required: notification and SMS permission granted
and denied, background/foreground transitions, service restart, force-stop recovery,
session expiry, Railway challenge, seats disappearing during booking, OTP timeout,
reservation expiry, and payment handoff. iOS signing and background behavior must
be validated using Xcode on macOS. The repository is not yet a certified production release.
