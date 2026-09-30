import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  bn,
  en,
}

class LanguageService extends ChangeNotifier {
  static const String _prefKey = 'app_language_code';
  static final LanguageService instance = LanguageService._internal();

  AppLanguage _currentLanguage = AppLanguage.bn;

  AppLanguage get currentLanguage => _currentLanguage;
  bool get isBangla => _currentLanguage == AppLanguage.bn;

  factory LanguageService() => instance;

  LanguageService._internal() {
    _loadLanguage();
  }

  static LanguageService of(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<LanguageService>(context, listen: listen);
    } catch (_) {
      return instance;
    }
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefKey);
      if (code == 'en') {
        _currentLanguage = AppLanguage.en;
      } else {
        _currentLanguage = AppLanguage.bn;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_currentLanguage == language) return;
    _currentLanguage = language;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, language == AppLanguage.en ? 'en' : 'bn');
    } catch (_) {}
  }

  Future<void> toggleLanguage() async {
    await setLanguage(isBangla ? AppLanguage.en : AppLanguage.bn);
  }

  String t(String key) {
    final map = _translations[key];
    if (map == null) return key;
    return isBangla ? (map['bn'] ?? key) : (map['en'] ?? key);
  }

  static const Map<String, Map<String, String>> _translations = {
    // ── App Info ──────────────────────────────────────────────────────────────
    'app_name': {'bn': 'Rail Pro', 'en': 'Rail Pro'},
    'app_subtitle': {'bn': 'বাংলাদেশ রেলওয়ে টিকেট অটোমেশন ও এলার্ট', 'en': 'Bangladesh Railway Ticket Automation & Alerts'},

    // ── Navigation & Actions ──────────────────────────────────────────────────
    'login': {'bn': 'লগইন', 'en': 'Login'},
    'relogin': {'bn': 'পুনরায় লগইন করুন', 'en': 'Re-Login'},
    'logout': {'bn': 'লগআউট', 'en': 'Logout'},
    'cancel': {'bn': 'বাতিল', 'en': 'Cancel'},

    // ── Search Screen ─────────────────────────────────────────────────────────
    'search': {'bn': 'অনুসন্ধান', 'en': 'Search'},
    'search_tickets': {'bn': 'টিকেট খুঁজুন', 'en': 'Search Tickets'},
    'searching': {'bn': 'টিকেট খোঁজা হচ্ছে...', 'en': 'Searching tickets...'},
    'train_search': {'bn': 'ট্রেন অনুসন্ধান', 'en': 'Train Search'},
    'from_station': {'bn': 'কোথা থেকে', 'en': 'From Station'},
    'to_station': {'bn': 'কোথায় যাবেন', 'en': 'To Station'},
    'journey_date': {'bn': 'যাত্রার তারিখ', 'en': 'Date of Journey'},
    'seat_class': {'bn': 'আসন শ্রেণি', 'en': 'Seat Class'},
    'swap_stations': {'bn': 'স্টেশন বদলান', 'en': 'Swap Stations'},
    'logged_in_as': {'bn': 'লগইন করা আছেন', 'en': 'Logged in as'},
    'session_active': {'bn': 'সেশন সক্রিয়', 'en': 'Session Active'},

    // ── Train Selection ───────────────────────────────────────────────────────
    'trains_found': {'bn': 'টি ট্রেন পাওয়া গেছে', 'en': 'trains found'},
    'no_trains_found': {'bn': 'নির্বাচিত রুটে কোনো ট্রেন পাওয়া যায়নি।', 'en': 'No trains found for this route.'},
    'notify_all_trains': {'bn': 'সব ট্রেনের এলার্ট চালু করুন', 'en': 'Alert for All Trains'},
    'notify_hint': {'bn': 'আসন খালি হওয়ামাত্র ফোনে এলার্ট পাবেন', 'en': 'Get an alert the moment any seat opens up'},
    'seats_available': {'bn': 'টি আসন আছে', 'en': 'seats available'},
    'no_seats': {'bn': 'আসন নেই', 'en': 'No seats'},
    'notify_this_train': {'bn': 'এই ট্রেনের এলার্ট চালু করুন', 'en': 'Alert for this train'},
    'monitor_sheet_title': {'bn': 'এলার্ট চালু করুন', 'en': 'Set Ticket Alert'},
    'monitor_sheet_desc': {
      'bn': 'আসন খালি হলে সাথে সাথে ফোনে অডিবল এলার্ম ও নোটিফিকেশন আসবে।',
      'en': 'You will get an audible alarm and notification the moment a seat becomes available.',
    },
    'start_alert_for': {'bn': 'এলার্ট শুরু করুন', 'en': 'Start Alert'},
    'train_label': {'bn': 'ট্রেন', 'en': 'Train'},
    'class_label': {'bn': 'শ্রেণি', 'en': 'Class'},
    'fare_label': {'bn': 'ভাড়া', 'en': 'Fare'},
    'current_seats': {'bn': 'বর্তমান আসন', 'en': 'Current Seats'},
    'login_required': {'bn': 'এই সুবিধা পেতে প্রথমে লগইন করুন।', 'en': 'Please log in first to use this feature.'},
    'radar_dashboard': {'bn': 'টিকেট রাডার', 'en': 'Ticket Radar'},

    // ── Monitor Dashboard ─────────────────────────────────────────────────────
    'ticket_notifier': {'bn': 'টিকেট নজরদারি', 'en': 'Ticket Notifier'},
    'ticket_radar': {'bn': 'টিকেট নজরদারি', 'en': 'Ticket Notifier'},
    'searching_active': {'bn': 'রাডার সক্রিয়', 'en': 'Radar Active'},
    'radar_paused': {'bn': 'রাডার বিরতিতে', 'en': 'Radar Paused'},
    'auth_expired': {'bn': 'লগইন সেশনের মেয়াদ শেষ। পুনরায় লগইন করুন।', 'en': 'Login session expired. Please re-login.'},
    'active_route': {'bn': 'সক্রিয় রুট', 'en': 'Active Route'},
    'target_train': {'bn': 'নির্দিষ্ট ট্রেন', 'en': 'Target Train'},
    'all_trains': {'bn': 'সকল ট্রেন', 'en': 'All Trains'},
    'any_class': {'bn': 'যেকোনো শ্রেণি', 'en': 'Any Class'},
    'available_seats': {'bn': 'পাওয়া যাচ্ছে', 'en': 'Available Now'},
    'no_seats_yet': {'bn': 'এখনও কোনো আসন খালি পাওয়া যায়নি', 'en': 'No seats found yet'},
    'book_now': {'bn': 'এখনই বুকিং করুন', 'en': 'Book Now'},
    'stop_monitoring': {'bn': 'এলার্ট বন্ধ করুন', 'en': 'Stop Alert'},
    'resume_monitoring': {'bn': 'এলার্ট পুনরায় চালু করুন', 'en': 'Resume Alert'},
    'sound_alert': {'bn': 'শব্দ এলার্ট', 'en': 'Sound Alert'},
    'check_interval': {'bn': 'চেক ব্যবধান', 'en': 'Scan Interval'},
    'total_checks': {'bn': 'মোট চেক', 'en': 'Total Checks'},
    'next_check': {'bn': 'পরবর্তী চেক', 'en': 'Next Check'},
    'seats_found': {'bn': 'আসন পাওয়া', 'en': 'Seats Found'},
    'paused': {'bn': 'বিরতি', 'en': 'Paused'},
    'new_search_warning': {'bn': 'নতুন রুট খুঁজলে এই এলার্ট বন্ধ হয়ে যাবে।', 'en': 'Starting a new search will stop the current alert.'},
    'notifier_will_stop_title': {'bn': 'এলার্ট বন্ধ হবে', 'en': 'Alert Will Stop'},
    'notifier_will_stop_body': {
      'bn': 'আপনার সক্রিয় টিকেট এলার্ট বন্ধ হয়ে যাবে এবং নতুন রুট খোঁজা শুরু হবে। একটিমাত্র এলার্ট চালু থাকতে পারবে। চালিয়ে যেতে চান?',
      'en': 'Your active ticket alert will be stopped and a new search will begin. Only one alert can be active at a time. Continue?',
    },
    'keep_active': {'bn': 'না, চলতে দিন', 'en': 'Keep Active'},
    'yes_new_search': {'bn': 'হ্যাঁ, নতুন খুঁজুন', 'en': 'Yes, New Search'},
    'search_another_route': {'bn': 'নতুন রুট অনুসন্ধান করুন', 'en': 'Search Another Route'},

    // ── Credentials & Autofill ────────────────────────────────────────────────
    'save_credentials': {'bn': 'লগইন তথ্য সংরক্ষণ করুন', 'en': 'Save Login Credentials'},
    'saved_credentials_msg': {
      'bn': 'ভবিষ্যতে এক ক্লিকে স্বয়ংক্রিয় লগইনের জন্য তথ্য সেভ থাকবে।',
      'en': 'Credentials saved for one-click auto-fill next time.',
    },
    'autofill_btn': {'bn': 'স্বয়ংক্রিয়ভাবে পূরণ করুন', 'en': 'Auto-fill Credentials'},
    'autofill_done': {'bn': 'তথ্য স্বয়ংক্রিয়ভাবে পূরণ হয়েছে', 'en': 'Credentials auto-filled'},
    'mobile_number': {'bn': 'মোবাইল নম্বর', 'en': 'Mobile Number'},
    'password': {'bn': 'পাসওয়ার্ড', 'en': 'Password'},
    'save_and_fill': {'bn': 'সেভ করুন ও পূরণ করুন', 'en': 'Save & Fill'},

    // ── Loading & Status ──────────────────────────────────────────────────────
    'loading_tickets': {
      'bn': 'রেলওয়ে সার্ভার থেকে টিকেট স্ক্যান করা হচ্ছে...',
      'en': 'Scanning Railway servers for tickets...',
    },
    'please_wait': {'bn': 'অনুগ্রহ করে অপেক্ষা করুন', 'en': 'Please wait'},
  };
}
