# Privacy Policy for Rail Pro

**Last Updated**: October 5, 2026

Welcome to **Rail Pro** ("we", "our", or "us"). We respect your privacy and are committed to protecting any personal information you share with us. This Privacy Policy explains our practices regarding the collection, use, and disclosure of information through the Rail Pro mobile application.

---

### 1. Information We Collect
- **Railway Credentials & Account Data**: Your Bangladesh Railway login credentials (phone number and session tokens) are stored locally and encrypted securely on your device using Android Secure Storage / Keystore. We do not transmit or store your Railway passwords on any external private servers.
- **Trip & Monitoring Preferences**: Search criteria (such as origin station, destination station, journey date, and preferred train classes) are stored locally to facilitate automated ticket availability monitoring.
- **SMS OTP Consent**: If you enable OTP auto-fill, Google Play services asks permission to share one incoming OTP message. The app checks Railway branding and extracts the verification code for your pending reservation. It does not request READ_SMS or RECEIVE_SMS, access your inbox, or send the SMS body to Firebase. You may decline and enter the OTP manually.

---

### 2. How We Use Information
- To check Bangladesh Railway ticket availability across scheduled trains.
- To notify you immediately when seats become available.
- To hold and reserve seats at your explicit request using official railway API channels.
- To manage your user credits and transaction history.

---

### 3. Third-Party Services
- **Official Bangladesh Railway Portal**: All seat checks, passenger registrations, and booking transactions are processed directly with the official Bangladesh Railway ticketing system (eticket.railway.gov.bd).
- **Google Firebase / Cloud Firestore**: Stores your profile identifier (including phone number when available), profile details, credit balance, recharge transaction submissions, login/activity timestamps, and administrator messages. Railway login does not itself authenticate you to Firebase; deployment must configure separate authentication and access rules.

---

### 4. Data Security
We implement strict security practices:
- Credentials and action tokens are stored using platform secure storage. Hardware backing depends on the device.
- All communications with the Railway portal and Firebase use encrypted HTTPS / TLS protocols.
- We do not sell, rent, or trade your personal data to any third party.

---

### 5. Disclaimer
Rail Pro is an independent automation and monitoring utility tool created to assist users with personal train ticket reservations on the official Bangladesh Railway portal. This application is not affiliated with, endorsed by, or operated by Bangladesh Railway (BR) or Shohoz-Synesis-Vincen JV.

---

### 6. Contact Us
If you have any questions, feedback, or concerns regarding this Privacy Policy:
- **Developer**: Abdulla Al Mamun
- **Email**: connect.abdulla@gmail.com
