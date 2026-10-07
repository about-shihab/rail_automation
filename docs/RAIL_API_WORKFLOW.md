# Railway API configuration and session recovery

Store the fields from [RAIL_API_CONFIG.json](RAIL_API_CONFIG.json) in Firestore
`app_config/workflow`. The app listens for changes and caches validated settings
for background workers. `app_config/settings` overrides duplicate top-level
fields, including the entire `api_operations` map. Keep API settings in one of
these documents. Removing a setting restores its built-in default.

The example covers sign-in, trip search, seat layout, handshake, seat reservation,
passenger details, OTP verification/resend, purchase history, and ticket download.
It is configuration data, not a Firebase CLI deployment file. This source change
does not write configuration to the live database. Restrict configuration writes
to administrators in your Firestore rules.

Each `api_operations` entry supports:

| Field | Meaning |
| --- | --- |
| `url` | Full HTTPS Shohoz API URL. Only `railspaapi.shohoz.com` on port 443 is accepted because requests contain authentication headers. Ticket downloads support `{order_id}`. |
| `payload` | Complete JSON payload template. For GET requests, rendered values become query parameters. Omit this field to use the operation's normal runtime payload. |
| `min_interval_seconds` | Minimum interval between starts of that operation's calls within an app isolate, 0–300 seconds. Concurrent calls allocate their slots in order. This does not schedule an operation or automatically repeat a booking. |

Use `{{field_name}}` for runtime values. An entire placeholder preserves its type,
including arrays and objects; for example `"ticket_ids": "{{ticket_ids}}"` and
`"extras": "{{extras}}"`. Missing fields fail locally before sending. Payload
templates replace the entire payload, so include every field required by the API.
Seat layout normally omits `cft_response` unless verification is required. Its
template is omitted in the example to preserve that behavior; if you configure a
template containing `{{cft_response}}`, every call must provide that field.

`poll_interval_seconds` controls recurring seat checks (10–86400 seconds).
`request_timeout_seconds` controls HTTP timeout (5–120 seconds).
`login_retry_interval_seconds` limits login recovery attempts (10–3600 seconds,
default 60), including across app restarts and workers through encrypted storage.
`otp_window_seconds` controls SMS waiting (30–600 seconds). Keep mutation intervals
at zero unless the API requires otherwise: delaying reservation or OTP calls uses
up the Railway seat-hold window. Background scheduling on iOS remains subject to
the operating system's minimum interval and execution limits.

## Login recovery

Users save their own phone and password through the app's existing Login screen.
Those values, device keys, action tokens, cookies, and session tokens stay in
encrypted device storage. Never put credentials or captured verification tokens
in Firestore or this JSON file. Sensitive payload fields accept placeholders,
not literal secrets.

Before an API call, the app recovers a locally expired token. A server 401, or a
403 explicitly identifying an expired/invalid session or token, triggers one
sign-in request and one retry with the replacement token. Concurrent recoveries
for the same account/device share a login in each isolate. A successful login
updates the saved session and removes the previous session's action token.
Generic Cloudflare failures, timeouts, and server errors do not replay mutations.
Only an explicit incorrect username/password response from sign-in causes an
automatic redirect to the Login WebView. Other recovery failures show an error
and keep the current screen available.

Login uses a fresh, single-use `cft_response` from the existing verification flow.
The token captured in curl cannot be used for recurring logins. When credentials
are unavailable, verification cannot be shown, or login fails, the app posts a
login-required notification. Tapping it opens the Railway Login screen. A login
performed in another browser can invalidate the token even before its JWT expiry;
the server-rejection path handles that case.

## Alerts and OTP

Seat availability triggers the existing maximum-priority seat alert with sound
and vibration. Once reservation and passenger details are acknowledged, a new
high-priority alert says `আপনার টিকেট বুকিং কনফার্ম হয়েছে` and explains that OTP
and payment are still required. This is a seat hold, not a paid ticket.

Automatic OTP mode still posts an actionable reservation alert. If SMS permission
is missing, the listener errors, the SMS waiting window expires, or verification
fails, the app persists manual mode and asks the user to verify OTP. Automatic
verification uses the existing sender and OTP filters. Once Railway acknowledges
the OTP, the alert asks the user to purchase the ticket before the hold expires.
Successful payment retains the final ticket-confirmation alert. Android/iOS
notification permissions and channel settings control actual sound delivery.

Local validation uses mocked HTTP and SMS responses. No live login, seat hold,
OTP submission, payment, or database write is performed by those tests.
