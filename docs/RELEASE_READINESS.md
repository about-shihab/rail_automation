# Release readiness — October 5, 2026

This is an engineering readiness record, not a claim of Play approval. The exact Google Play / Play Protect rejection has not been supplied.

## Changes in this update

- Restore session and reservation storage before Railway's checkout router executes.
- Keep payment-provider pages visible; offer retry when Railway returns to search.
- Never confirm from a manual button or success URL alone. Require a new confirmed Railway purchase, PNR, and matching trip ID.
- Use Google SMS User Consent without inbox permissions or an invented sender identity. Decline, timeout, and unavailable Google services retain manual entry.
- Show pending human verification in-app, with heads-up notifications while minimized. No forced full-screen takeover or display-over-app permission requests.
- Require production signing keys for release builds.

## Requirements still needing external configuration or device validation

1. Supply the exact rejection notice. Code changes cannot remove a Play Protect warning or overturn a Play decision by themselves.
2. Resolve monetization for the intended distribution channel. The existing bKash recharge sells credits that unlock app functionality. For Play distribution, integrate Play Billing with server-side receipt verification unless an applicable exception/program permits the current flow. Train fares are transportation payments and remain on Railway checkout. Do not submit the current recharge flow as Play-compliant without resolving this.
3. Add authenticated backend identity and deployed Firestore access rules. The repository uses Railway session identity and client Firestore writes, without a Firebase Auth dependency or deployed rules in this workspace. A client-side admin flag is not an authorization boundary. Balance and administrator mutations require server enforcement; no production security claim can be made from the client alone.
4. Configure signing with the existing application identity and upload key. Do not change the package ID of an already published app. Increase the version code for submission. Keep keystore files and credentials out of source control.
5. Complete accurate Play Data safety, privacy policy, account deletion (where applicable), foreground-service declarations, and review access instructions. Verify data retention and actual cloud rules rather than relying on local documentation.
6. Validate on a physical Android device: real Railway SMS consent/decline/resend; manual and automatic OTP; checkout amount/passenger details; each payment provider and return path; payment cancellation; expired reservations; app minimize/resume; notification permission denied; Do Not Disturb; process recreation; human-verification cancellation and retry.

No Android device is connected in this workspace. Fake WebView tests verify ordering and state preservation, but do not prove the live website accepts reconstructed session storage. Live payment must be performed and confirmed by the account holder.

## Policy references

- [Google API choice: User Consent for third-party SMS formats](https://developers.google.com/identity/sms-retriever/choose-an-api)
- [Android HTTPS base origins for local WebView content](https://developer.android.com/develop/ui/views/layout/webapps/load-local-content)
- [Play foreground-service and full-screen intent requirements](https://support.google.com/googleplay/android-developer/answer/13392821)
- [Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738)

## Local verification

Run `flutter analyze`, `flutter test`, and `flutter build apk --debug`. Build a production-signed app bundle only after the requirements above are satisfied. Inspect the newly merged manifest to ensure SMS inbox, display-over-app, and full-screen permissions are absent.


Validation for the current update: `flutter analyze` reports no issues; all 90 tests pass; the signed release APK builds (59.9 MB) using the existing signing configuration. The regenerated release manifest omits READ_SMS, RECEIVE_SMS, SYSTEM_ALERT_WINDOW, and USE_FULL_SCREEN_INTENT. Native/live-device acceptance and Google Play approval remain unverified. The current build is `build/app/outputs/flutter-apk/app-release.apk`. The earlier debug APK and release App Bundle predate the latest UI changes; rebuild the bundle after resolving the release requirements above.


The current UI update hands a valid WebView login session directly to native Search, uses ranked station autocomplete, shortens booking/security copy, and listens for worker updates while the app is active. Pending verification opens when the user returns to the app; the notification tap is optional. Human-required Turnstile challenges still require interaction. Screenshot previews are in `build/design-preview/stations-light.png`, `stations-dark.png`, and `processing-light.png`.


The booking illustration shows a passenger with a bag following a ticket direction sign to a staffed counter. The passenger walks toward the counter while searching and stays at the desk for reservation, OTP, and payment. Counter icons and the passenger’s phone/card reflect the actual booking state, without simulated queue progress. Reserved seats show a payment prompt instead of a waiting queue. Search and tab headers use the launcher icon, and the search action uses a gradient button with press feedback and a disabled loading state. The new animation and button respect reduced-motion settings. Narrow-screen previews with enlarged text are in `build/design-preview/booking-stages-light.png` and `booking-stages-dark.png`; the updated dashboard is in `journey-light.png` and `journey-dark.png`.


The auto-booking sheet now uses the selected app language for its controls, seat counts, seat-class names, credit disclosure, and action. Language changes while the sheet is open preserve its selections. The shorter layout groups the chosen trains and booking controls into two cards and retains only the OTP credit cost and payment requirement. Bangla previews with enlarged text are in `build/design-preview/watch-options-bn-light.png` and `watch-options-bn-dark.png`.


Notifications now use a dedicated transparent train status icon, a compact Rail Pro logo, stage accents, grouped expanded text, localized actions, and private lock-screen visibility. Reservation alerts keep their real expiry countdown and destination; no full-screen intent was added. Background notifications reload the saved language preference. Native visual acceptance still needs a physical Android device, since Android/OEM templates determine the final layout. The promotional video and editable source are in `marketing/`; it uses demo app previews, not a real purchase, and includes no availability or Play approval guarantee.
