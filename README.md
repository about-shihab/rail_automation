# rail_automation

A new Flutter project.

## Ticket notifications

The latest route/train watch is saved locally and becomes the home screen on
relaunch. Whole-route and whole-train requests send `seat_class=SNIGDHA`, then
evaluate every returned seat class. A specific class watch filters the result.
Unchanged availability does not repeatedly notify; new or changed availability
does. Alerts include Bangla and English and open the official booking search in
an in-app webview, including after a cold launch. Booking may require login.

Foreground searches run immediately and periodically. Android WorkManager and
iOS BGTaskScheduler perform network checks after the app is backgrounded or
normally closed. Background work is requested every 15 minutes, but delivery is
controlled by the OS and can be delayed by battery/network restrictions. Force
stop, iOS force quit, or powering off the phone prevents reliable delivery.
This is not continuous server monitoring. See the
[Workmanager setup and platform limitations](https://github.com/fluttercommunity/flutter_workmanager/blob/main/docs/quickstart.mdx).
Free watches expire one hour after creation, including time spent closed; Pro
watches retain the existing unlimited-duration policy. Starting a new watch
replaces the previous watch. Desktop/web monitoring requires the app to stay open.

Validation: `flutter analyze`, `flutter test`, `flutter build apk --debug`.
On physical Android and iOS devices, verify notification permission granted and
denied, background delivery after normal close, tap from both a running and
terminated app, pause cancellation, expired login, and the complete official
booking flow. iOS builds require macOS/Xcode. Live seat availability is not
guaranteed until booking completes.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
