# Hooking up TurnstileOverlay

1. Copy `TurnstileOverlay.kt` into
   `android/app/src/main/kotlin/com/example/rail_automation/`
   (same folder as `MainActivity.kt`). If your package name differs, change the
   `package` line.

2. In `MainActivity.kt`, find the handler for the channel
   `com.example.rail_automation/overlay` (it already handles `canDrawOverlays`
   and `requestOverlayPermission`) and add two cases:

```kotlin
"showVerification" -> {
    val siteKey = call.argument<String>("siteKey")
    if (siteKey.isNullOrEmpty()) {
        result.success(null)
    } else {
        TurnstileOverlay.show(
            applicationContext,
            siteKey,
            call.argument<String>("title") ?: "",
            call.argument<String>("message") ?: "",
            result,
        )
    }
}
"hideVerification" -> {
    TurnstileOverlay.hide()
    result.success(null)
}
```

3. `AndroidManifest.xml` must already contain (you request it today):

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
```

4. Test checklist (real Android device):
   - Grant "Display over other apps" for Rail Pro.
   - Start an auto-book search, minimize the app, make the cached token expire
     (wait 5+ minutes or clear it), then trigger a seat.
   - Expected: silent try (about 20s) -> small card over other apps -> tap the
     check -> booking continues without opening the app.
   - Close the card with the X, or ignore it for 90s -> the existing
     "open app" notification appears once.
   - Open the app while the card is showing -> the card disappears.
