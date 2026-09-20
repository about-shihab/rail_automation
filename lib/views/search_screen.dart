import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../services/api_service.dart';
import '../services/pro_service.dart';
import '../services/theme_service.dart';
import '../utils/app_theme.dart';
import 'webview_login_screen.dart';
import 'train_selection_screen.dart';
import 'monitor_dashboard_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final List<String> _popularStations = [
    'Dhaka',
    'Chattogram',
    'Cox\'s Bazar',
    'Sylhet',
    'Rajshahi',
    'Khulna',
    'Bogura',
    'Dinajpur',
    'Cumilla',
    'Ishwardi',
    'Rangpur',
    'Brahmanbaria',
    'Mymensingh',
    'Jessore',
    'Santahar',
  ];

  final List<String> _seatClasses = [
    'ALL',
    'SNIGDHA',
    'S_CHAIR',
    'AC_S',
    'AC_B',
    'F_SEAT',
    'F_BERTH',
    'SHOVON',
  ];

  String _fromCity = 'Dhaka';
  String _toCity = 'Chattogram';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 3));
  String _selectedClass = 'SNIGDHA';

  AuthSession? _authSession;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await AuthSession.load();
    if (session == null || !session.isValid) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
        );
      }
      return;
    }
    setState(() => _authSession = session);
  }

  Future<void> _handleLogout() async {
    await AuthSession.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
      );
    }
  }

  Future<void> _searchTrips() async {
    if (_authSession == null || !_authSession!.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first.')),
      );
      _handleLogout();
      return;
    }

    setState(() => _isLoading = true);

    final dateFormatted = DateFormat('dd-MMM-yyyy').format(_selectedDate);

    try {
      final response = await ApiService.searchTrips(
        fromCity: _fromCity,
        toCity: _toCity,
        dateOfJourney: dateFormatted,
        seatClass: _selectedClass,
        authSession: _authSession!,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        _openTrips(response);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final err = e.toString();
        if (err.contains('401') || err.contains('expired') || err.contains('TOKEN_NOT_GIVEN')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 8),
              content: const Text('লগইন সেশনের মেয়াদ শেষ হয়েছে বা নতুন সেশন প্রয়োজন।'),
              action: SnackBarAction(
                label: 'পুনরায় লগইন',
                textColor: Colors.white,
                onPressed: _handleLogout,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('সার্ভার রেসপন্স: $err'),
              action: SnackBarAction(
                label: 'পুনরায় চেষ্টা',
                textColor: Colors.white,
                onPressed: _searchTrips,
              ),
            ),
          );
        }
      }
    }
  }

  void _openTrips(TripSearchResponse response) {
    final dateFormatted = DateFormat('dd-MMM-yyyy').format(_selectedDate);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrainSelectionScreen(
          searchResponse: response,
          fromCity: _fromCity,
          toCity: _toCity,
          dateOfJourney: dateFormatted,
          initialClass: _selectedClass,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormatted = DateFormat('dd-MMM-yyyy').format(_selectedDate);
    final proService = Provider.of<ProService>(context);
    final themeService = Provider.of<ThemeService>(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: AppBar(
        backgroundColor: AppColors.appBarGreen,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.train, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'টিকেট আছে',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                Text(
                  'বাংলাদেশ রেলওয়ে টিকিট এলার্ট',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: themeService.isDarkMode ? 'লাইট মোড চালু করুন' : 'ডার্ক মোড চালু করুন',
            icon: Icon(
              themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
            onPressed: () => themeService.toggleTheme(),
          ),
          IconButton(
            tooltip: 'টিকেট আসলে জানানোর ড্যাশবোর্ড',
            icon: const Icon(Icons.radar, color: Colors.tealAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'লগআউট',
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Profile & Pro status bar
            _buildProfileBanner(proService, isDark),
            const SizedBox(height: 16),

            // Search Form Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBg(isDark),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder(isDark)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.search, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'ট্রেন অনুসন্ধান',
                        style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // From City Dropdown
                  _buildStationDropdown(
                    label: 'কোথা থেকে (From Station)',
                    value: _fromCity,
                    icon: Icons.trip_origin,
                    isDark: isDark,
                    onChanged: (val) {
                      if (val != null) setState(() => _fromCity = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Swap stations button
                  Center(
                    child: IconButton(
                      icon: const Icon(Icons.swap_vert, color: AppColors.primary),
                      onPressed: () {
                        setState(() {
                          final temp = _fromCity;
                          _fromCity = _toCity;
                          _toCity = temp;
                        });
                      },
                    ),
                  ),

                  // To City Dropdown
                  _buildStationDropdown(
                    label: 'কোথায় যাবেন (To Station)',
                    value: _toCity,
                    icon: Icons.location_on,
                    isDark: isDark,
                    onChanged: (val) {
                      if (val != null) setState(() => _toCity = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Date of Journey
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: isDark
                                  ? const ColorScheme.dark(
                                      primary: Color(0xFF10B981),
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF1E293B),
                                      onSurface: Colors.white,
                                    )
                                  : const ColorScheme.light(
                                      primary: Color(0xFF059669),
                                      onPrimary: Colors.white,
                                      surface: Colors.white,
                                      onSurface: Color(0xFF0F172A),
                                    ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputFill(isDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.inputBorder(isDark)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month, color: AppColors.primary, size: 20),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'যাত্রার তারিখ (Date of Journey)',
                                style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11),
                              ),
                              Text(
                                dateFormatted,
                                style: TextStyle(
                                  color: AppColors.textPrimary(isDark),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Icon(Icons.arrow_drop_down, color: AppColors.textMuted(isDark)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Seat Class Selector
                  DropdownButtonFormField<String>(
                    initialValue: _selectedClass,
                    dropdownColor: AppColors.cardBg(isDark),
                    style: TextStyle(color: AppColors.textPrimary(isDark)),
                    decoration: InputDecoration(
                      labelText: 'আসন শ্রেণি (Seat Class)',
                      labelStyle: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13),
                      prefixIcon: const Icon(Icons.airline_seat_recline_extra, color: AppColors.primary),
                      filled: true,
                      fillColor: AppColors.inputFill(isDark),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.inputBorder(isDark)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.inputBorder(isDark)),
                      ),
                    ),
                    items: _seatClasses.map((cls) {
                      return DropdownMenuItem<String>(
                        value: cls,
                        child: Text(cls == 'ALL' ? 'ALL CLASSES (সকল আসন)' : cls),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedClass = val);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Search Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search, color: Colors.white),
                      label: Text(
                        _isLoading ? 'অনুসন্ধান করা হচ্ছে...' : 'টিকেট আছে কিনা দেখুন',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _isLoading ? null : _searchTrips,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBanner(ProService proService, bool isDark) {
    final phone = _authSession?.phoneNumber ?? 'User';
    final isPro = proService.isPro;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPro ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isPro ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
            radius: 18,
            child: Icon(
              isPro ? Icons.star : Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      phone,
                      style: TextStyle(
                        color: AppColors.textPrimary(isDark),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isPro ? Colors.amber : const Color(0xFF065F46),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isPro ? 'PRO 24/7' : 'FREE',
                        style: TextStyle(
                          color: isPro ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isPro
                      ? '২৪/৭ ক্লাউড সার্ভার নোটিফায়ার চালু রয়েছে'
                      : 'টিকেট ছাড়ার সাথে সাথে ফোনে নোটিফিকেশন পাবেন',
                  style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 11),
                ),
              ],
            ),
          ),
          if (!isPro)
            TextButton(
              onPressed: () {
                _showProUpgradeDialog(context, proService);
              },
              child: const Text(
                'Go Pro',
                style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  void _showProUpgradeDialog(BuildContext context, ProService proService) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium, color: Colors.amberAccent, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Upgrade to Pro',
                  style: TextStyle(color: AppColors.textPrimary(isDark), fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Pro ভার্সনে আপনার ফোন বন্ধ বা লক থাকলেও আমাদের ক্লাউড সার্ভার নিয়মিত চেক করে টিকেট পাওয়া মাত্রই আপনাকে উচ্চ-শব্দের অ্যালার্ম ও নোটিফিকেশন দিয়ে জানিয়ে দেবে!',
              style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            _buildPerkItem(Icons.cloud_done, '২৪/৭ ক্লাউড সার্ভার নোটিফায়ার (ফোন বন্ধ থাকলেও কাজ করে)', isDark),
            _buildPerkItem(Icons.all_inclusive, 'আনলিমিটেড সময় ধরে এলার্ট সুবিধা', isDark),
            _buildPerkItem(Icons.speed, 'অতি দ্রুত চেক (প্রতি ৫-১০ সেকেন্ড পরপর)', isDark),
            _buildPerkItem(Icons.notifications_active, 'তাৎক্ষণিক পুশ নোটিফিকেশন ও অডিবল অ্যালার্ম', isDark),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.bolt, color: Colors.white),
                label: const Text(
                  'Activate Pro (২৪/৭ ক্লাউড এলার্ট)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: () async {
                  await proService.setProStatus(true);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('🎉 Pro Activated! ২৪/৭ ক্লাউড নোটিফায়ার চালু হয়েছে।')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerkItem(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF059669), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationDropdown({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: AppColors.cardBg(isDark),
      style: TextStyle(color: AppColors.textPrimary(isDark)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.inputFill(isDark),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.inputBorder(isDark)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.inputBorder(isDark)),
        ),
      ),
      items: _popularStations.map((station) {
        return DropdownMenuItem<String>(
          value: station,
          child: Text(station),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
