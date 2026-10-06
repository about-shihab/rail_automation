# Firebase-এ Rail Pro প্রকাশ করুন

Firebase Hosting-এ ওয়েবসাইট, Android APK ও `update.json` প্রকাশ হবে। ব্যবহারকারী ওয়েবসাইট থেকে APK ডাউনলোড করে ইনস্টল করবেন। GitHub-এর source repository private রাখা যায়।

## ১. Firebase-এ লগইন করুন

PowerShell-এ repository খুলুন:

```powershell
Set-Location E:\rail_automation
firebase login --reauth
firebase projects:list
```

ব্রাউজারে যে Google account দিয়ে `railautomation-1993` প্রজেক্ট পরিচালনা করেন, সেটি দিয়ে লগইন করুন। আগের authentication যাচাইয়ে `401` এসেছিল; `--reauth` নতুন করে লগইন করাবে। তালিকায় প্রজেক্টটি দেখা যেতে হবে। Firebase CLI না থাকলে আগে `npm install -g firebase-tools` চালান।

## ২. Hosting ও প্রকাশযোগ্য ফাইল যাচাই করুন

[Firebase Console](https://console.firebase.google.com/project/railautomation-1993/hosting)-এ আপনার প্রজেক্টের Hosting খুলুন। প্রথমবার হলে Get started দিয়ে setup করুন। এরপর:

```powershell
firebase hosting:sites:list --project railautomation-1993
Get-Content build/public-site/update.json
Test-Path build/public-site/downloads/Rail-Pro.apk
```

এই repository-র `firebase.json` public directory হিসেবে `build/public-site` ব্যবহার করে। APK, ওয়েবসাইট ও metadata একই build-এর হতে হবে। একটি পুরোনো APK-এর পাশে নতুন version number লিখে প্রকাশ করবেন না; release script APK-এর আসল version যাচাই করে bundle বানায়।

## ৩. প্রকাশ করুন

প্রস্তুত bundle থাকলে:

```powershell
firebase deploy --only hosting --project railautomation-1993
```

প্রকাশের পরে signed-out/incognito browser-এ যাচাই করুন:

- ওয়েবসাইট: https://railautomation-1993.web.app/
- APK: https://railautomation-1993.web.app/downloads/Rail-Pro.apk
- আপডেটের তথ্য: https://railautomation-1993.web.app/update.json

APK ডাউনলোড করে আগের অ্যাপের ওপর ইনস্টল করুন; আনইনস্টল করার প্রয়োজন নেই। প্রতিবার একই production keystore ব্যবহার করতে হবে। Android ইনস্টল করার অনুমতি চাইতে পারে।

## পরের সংস্করণ তৈরি ও প্রকাশ

```powershell
Set-Location E:\rail_automation
python scripts/release.py prepare --site-url https://railautomation-1993.web.app
if ($LASTEXITCODE -ne 0) { throw 'Version preparation failed' }
$railRelease = Get-Content build/release-plan.json | ConvertFrom-Json
flutter build apk --release --build-name $railRelease.version --build-number $railRelease.build_number --dart-define=UPDATE_MANIFEST_URL=https://railautomation-1993.web.app/update.json
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
python scripts/release.py bundle
if ($LASTEXITCODE -ne 0) { throw 'Bundle validation failed' }
firebase deploy --only hosting --project railautomation-1993
```

Version ও build number স্বয়ংক্রিয়ভাবে বাড়বে। Local release-এ আগের তৈরি APK-এর নম্বরও বিবেচনা করা হয়, যাতে প্রথম Firebase প্রকাশের আগেই একই build number আবার ব্যবহার না হয়। পুরোনো build-এ আপডেট বাধ্যতামূলক করতে `prepare` command-এ `--force` যোগ করুন।

Private GitHub থেকে automated release চাইলে [UPDATES.md](UPDATES.md)-এর repository variables ও signing/deployment secrets সেট করুন, তারপর Actions-এর **Android release and public website** workflow চালান।

## নোটিফিকেশন না এলে

এই সংশোধনে automatic OTP চালু থাকলেও একটি **আসন সংরক্ষিত · বুকিং চলছে** notification থাকে। আলাদা “OTP লিখুন” notification আসে না; payment ready হলে পেমেন্টের notification আসে। এটি পেতে সংশোধিত নতুন APK ইনস্টল করতে হবে।

Android Settings → Apps → Rail Pro → Notifications-এ **Allow notifications**, **Seats found**, এবং **Reserved tickets** চালু আছে কি না দেখুন। Sound/alert settings-ও পরীক্ষা করুন। Android-এর Do Not Disturb বা বন্ধ করা notification channel অ্যাপের alert নীরব করতে পারে।

সূত্র: [Firebase Hosting quickstart](https://firebase.google.com/docs/hosting/quickstart), [Firebase CLI](https://firebase.google.com/docs/cli)।
