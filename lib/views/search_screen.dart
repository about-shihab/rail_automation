import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../services/language_service.dart';
import '../widgets/fancy_train_loader.dart';
import '../utils/app_theme.dart';
import '../services/firebase_user_service.dart';
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
          MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)),
        );
      }
      return;
    }
    setState(() => _authSession = session);
  }

  Future<void> _handleLogout() async {
    await FirebaseUserService().clearSession();
    await AuthSession.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)),
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
    final themeService = Provider.of<ThemeService>(context);
    final langService = LanguageService.of(context);
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
              children: [
                Text(
                  langService.t('app_name'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                Text(
                  langService.t('app_subtitle'),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Language toggle
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: langService.toggleLanguage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                langService.isBangla ? 'EN' : 'বাং',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          IconButton(
            tooltip: themeService.isDarkMode ? 'লাইট মোড' : 'ডার্ক মোড',
            icon: Icon(
              themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
            onPressed: () => themeService.toggleTheme(),
          ),
          IconButton(
            tooltip: langService.t('radar_dashboard'),
            icon: const Icon(Icons.radar, color: Colors.tealAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()),
              );
            },
          ),
          IconButton(
            tooltip: langService.t('logout'),
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User session banner
                _buildSessionBanner(isDark, langService),
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
                            langService.t('train_search'),
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
                        label: langService.t('from_station'),
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
                        label: langService.t('to_station'),
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
                                    langService.t('journey_date'),
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
                          labelText: langService.t('seat_class'),
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
                            child: Text(cls == 'ALL' ? (langService.isBangla ? 'সকল শ্রেণি' : 'ALL CLASSES') : cls),
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
                          icon: const Icon(Icons.search, color: Colors.white),
                          label: Text(
                            langService.t('search_tickets'),
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
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.88),
                child: FancyTrainLoader(
                  message: langService.t('searching'),
                  showCard: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionBanner(bool isDark, LanguageService langService) {
    final phone = _authSession?.phoneNumber ?? (_authSession?.displayName ?? '—');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFECFDF5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: Color(0xFF059669), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phone,
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  langService.t('session_active'),
                  style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.redAccent),
            label: Text(
              langService.t('logout'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
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
