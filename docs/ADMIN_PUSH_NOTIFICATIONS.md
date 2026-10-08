# Admin announcement push delivery

This feature uses Firebase Cloud Messaging for admin announcements only. Seat,
reservation, OTP, and ticket notifications retain their existing local/background
delivery. Android is the configured Firebase platform in this repository.

The app registers its FCM token in `push_devices/{installationId}`, updates it
when the token rotates or the Railway account changes, and disassociates the
account on logout. Broadcast announcements include registered devices without
a Railway login. Targeted announcements select an exact normalized phone number.
Do not use phone-number FCM topics for private announcements.

The `deliverAdminAnnouncement` function runs when an administrator creates a
`notifications/{id}` document with `delivery: "push"` and
`kind: "admin_announcement"`. It checks the sender's admin role, sends an OS
notification payload on the announcements channel, paginates device fanout,
removes invalid tokens, and retries transient failures. Successful recipients
have server-owned receipts so ordinary retries do not resend them. A crash
between FCM send and receipt storage can still cause a repeat; the notification
tag is stable so Android replaces the same announcement. Receipts have an
`expireAt` field; enable a Firestore TTL policy on that field to clean them up.

Foreground messages use the existing local notification renderer. Background
messages with a notification payload are displayed by Android; the background
handler does not display another copy. Tapping an announcement opens its details.
Push-tagged documents are excluded from the older Firestore alert listener.

## Enable delivery

1. Install/build the app. Notification permission and Google Play services are
   required. Device registration stays disabled until push delivery is enabled.
2. Review production Firestore rules before deployment. Restrict announcement
   creation to verified administrators, permit each installation to register its
   own token and verified account, deny client listing of `push_devices`, and deny
   all client access to `push_delivery_receipts`. The sender-role check in the
   function is defense in depth, not authentication: clients must not be able to
   forge `sentBy`, another account's registration, or their own `is_admin` field.
   The existing Railway session is not a Firebase Auth identity; a rules policy
   that expects Firebase Auth phone claims needs a verified identity bridge.
   Do not make these collections public to get around permission errors.
3. Deploy the reviewed function (requires a Firebase project with Cloud Functions
   billing enabled):

   ```powershell
   firebase deploy --only functions:admin-announcements --project railautomation-1993
   ```

4. Enable **More → Admin → Configuration → Push admin announcements**, or set
   `admin_push_enabled: true` in the owning `app_config` document. It defaults to
   false so announcements continue using the existing listener before deployment.
   Open the updated app on each recipient device once after enabling the setting
   so it registers its token. Running clients also react to this config change.
5. Send a new admin announcement to a test device with the app minimized, then
   removed from recent apps. Confirm one system notification and its tap route.
   Check the document's `pushStatus`: `sent`, `no_devices`, or `failed`.
   `pushRecipientCount` records eligible unique registrations, not a read receipt.

Android Settings → Force stop blocks FCM until the app is reopened. Delivery is
also subject to notification permission, network access, and device restrictions.
Closing the app does not start or extend seat monitoring. iOS push additionally
needs an iOS Firebase app, signing entitlements, and an APNs key; these are not
configured in this Android-focused project.

## Production readiness checked on October 8, 2026

The refreshed Firebase CLI account can access the project. Billing is disabled,
and the Cloud Functions API is disabled. The deployed Firestore rules permit
public reads and writes until October 25, 2026. With that policy, a client can
forge `sentBy` or edit an admin role, so the sender-role lookup alone cannot prove
that an announcement came from an administrator. It would also expose a device
registration collection if registration were enabled.

No cloud rules, billing, APIs, functions, or app config were changed during this
check. Push delivery and device registration remain off by default. Activating
delivery requires billing approval and verified Firebase identities with tested
rules for sender roles and device ownership. Changing all rules to require
Firebase Auth immediately would break the app's existing Railway-only identity
flow; prepare and verify that migration before deploying the restrictive policy.

## Validation

```powershell
flutter test test/admin_push_test.dart test/notification_design_test.dart test/admin_config_test.dart
cd functions
npm test
```

Tests mock notifications and FCM; they do not send announcements to live users.
The function uses Application Default Credentials on Firebase. Never put an
Admin SDK private key, Railway password, or session token in the app or config.
