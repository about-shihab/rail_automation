import '../services/login_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../models/purchased_ticket.dart';
import '../models/trip_record.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/ticket_download_service.dart';
import '../services/trip_history_service.dart';
import '../utils/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/scenic_rail_header.dart';
import '../services/booking_service.dart';
import '../services/notification_service.dart';
import 'reservation_screen.dart';
import 'webview_login_screen.dart';

enum _TripFilter { all, successful, failed }
enum _MainTab { purchased, autoBook }

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  _MainTab _activeTab = _MainTab.purchased;
  _TripFilter _autoBookFilter = _TripFilter.all;

  // Purchased tickets state
  List<PurchasedTicket>? _purchasedTickets;
  bool _loadingPurchased = false;
  String? _purchasedError;
  final Set<int> _downloadingOrderIds = {};

  @override
  void initState() {
    super.initState();
    _fetchPurchasedTickets();
  }

  Future<void> _fetchPurchasedTickets() async {
    setState(() {
      _loadingPurchased = true;
      _purchasedError = null;
    });

    try {
      final session = await AuthSession.load();
      if (session == null) {
        if (mounted) {
          setState(() {
            _loadingPurchased = false;
            _purchasedError = 'not_logged_in';
          });
        }
        return;
      }

      final tickets = await ApiService.getPurchaseHistory(
        authSession: session,
        silent: true,
      );

      // Check if any pending reservation was paid and confirmed by ticket
      final pending = await BookingService.pending();
      if (pending != null && pending['status'] == 'readyForPayment') {
        final tripId = int.tryParse('${pending['seatClass']?['trip_id']}');
        final trainName = pending['train']?['trip_number']?.toString() ??
            pending['train']?['train_name']?.toString() ?? '';
        final doj = pending['date']?.toString() ?? '';

        final confirmed = tickets.where((t) => t.isConfirmed && !t.isRefunded && t.pnr.isNotEmpty).firstWhere(
          (t) =>
              (tripId != null && t.tripId == tripId) ||
              (trainName.isNotEmpty &&
                  t.trainName.toLowerCase().contains(trainName.toLowerCase())) ||
              (doj.isNotEmpty && t.journeyDate.contains(doj)),
          orElse: () => tickets.firstWhere(
            (t) => t.isConfirmed && !t.isRefunded && t.pnr.isNotEmpty && tripId != null && t.tripId == tripId,
            orElse: () => tickets.first,
          ),
        );

        if (confirmed.isConfirmed && !confirmed.isRefunded && confirmed.pnr.isNotEmpty) {
          final done = await BookingService.completeSuccessfulBooking(reservation: pending);
          if (done) {
            await NotificationService().showPurchaseSuccessAlert(
              trainName: trainName.isNotEmpty ? trainName : confirmed.trainName,
              pnr: confirmed.pnr,
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          _purchasedTickets = tickets;
          _loadingPurchased = false;
          _purchasedError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        if (LoginFlow.needsLogin(e)) {
          await AuthSession.clear();
          if (mounted) {
            setState(() {
              _loadingPurchased = false;
              _purchasedError = 'not_logged_in';
            });
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)),
            ).then((_) => _fetchPurchasedTickets());
          }
          return;
        }
        setState(() {
          _loadingPurchased = false;
          _purchasedError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _downloadTicket(PurchasedTicket ticket) async {
    if (_downloadingOrderIds.contains(ticket.orderId)) return;

    setState(() => _downloadingOrderIds.add(ticket.orderId));

    try {
      final session = await AuthSession.load();
      if (session == null) {
        // If no active app session, open the official purchase history portal in browser
        await TicketDownloadService.openInBrowser(
          TicketDownloadService.purchaseHistoryUrl,
        );
        return;
      }

      final bytes = await ApiService.downloadTicketPdf(
        orderId: ticket.orderId,
        authSession: session,
      );

      final fileName = 'rail_ticket_${ticket.orderId}.pdf';

      // Save locally to device Downloads/RailPro as well
      TicketDownloadService.saveAndOpenTicketPdf(
        bytes: bytes,
        fileName: fileName,
      );

      // Open in browser so Chrome/system browser natively downloads & opens the PDF
      final openedInBrowser = await TicketDownloadService.downloadPdfViaBrowser(
        bytes: bytes,
        fileName: fileName,
      );

      if (!openedInBrowser) {
        await TicketDownloadService.openInBrowser(
          TicketDownloadService.purchaseHistoryUrl,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Ticket PDF opened in browser for download!'),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      // If direct API download fails, open the official railway portal in the browser
      await TicketDownloadService.openInBrowser(
        TicketDownloadService.purchaseHistoryUrl,
      );

      if (mounted) {
        if (LoginFlow.needsLogin(e)) {
          await AuthSession.clear();
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Opened Railway Purchase History in browser to download ticket.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Direct Link',
              textColor: Colors.white,
              onPressed: () {
                TicketDownloadService.openInBrowser(
                  TicketDownloadService.directDownloadUrl(ticket.orderId),
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingOrderIds.remove(ticket.orderId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = TripHistoryService();
    final lang = context.watch<LanguageService>();

    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final allTrips = history.trips;
        final successfulTrips = allTrips
            .where((t) =>
                t.status == TripBookingStatus.successful ||
                t.status == TripBookingStatus.awaitingOtp)
            .toList();
        final failedTrips = allTrips
            .where((t) =>
                t.status == TripBookingStatus.failed ||
                t.status == TripBookingStatus.expired)
            .toList();

        List<TripRecord> filteredAutoBook;
        switch (_autoBookFilter) {
          case _TripFilter.all:
            filteredAutoBook = allTrips;
            break;
          case _TripFilter.successful:
            filteredAutoBook = successfulTrips;
            break;
          case _TripFilter.failed:
            filteredAutoBook = failedTrips;
            break;
        }

        return Scaffold(
          backgroundColor: AppColors.scaffoldBg(isDark),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(66),
            child: ScenicRailHeader(
              compact: true,
              sceneOpacity: 0.70,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.confirmation_number_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.tr('Trips & Tickets', 'ট্রিপস ও টিকেট'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 6,
                                    offset: Offset(0, 1.2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              lang.tr(
                                'Official railway purchases & booking history',
                                'অফিসিয়াল টিকেট ও বুকিং ইতিহাস',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_activeTab == _MainTab.purchased)
                        IconButton(
                          tooltip: lang.tr('Refresh tickets', 'টিকেট রিফ্রেশ করুন'),
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: _loadingPurchased ? null : _fetchPurchasedTickets,
                        )
                      else if (allTrips.isNotEmpty)
                        IconButton(
                          tooltip: lang.tr('Clear history', 'ইতিহাস মুছুন'),
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            color: Colors.white70,
                            size: 22,
                          ),
                          onPressed: () => _confirmClearHistory(context, history, isDark, lang),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              // ── Top Navigation Tabs: Purchased Tickets vs Auto-Book History ──
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _tabButton(
                        title: lang.tr('Official Tickets', 'অফিসিয়াল টিকেট'),
                        count: _purchasedTickets?.length,
                        icon: Icons.confirmation_number_outlined,
                        isActive: _activeTab == _MainTab.purchased,
                        onTap: () {
                          if (_activeTab != _MainTab.purchased) {
                            setState(() => _activeTab = _MainTab.purchased);
                            if (_purchasedTickets == null && !_loadingPurchased) {
                              _fetchPurchasedTickets();
                            }
                          }
                        },
                        isDark: isDark,
                      ),
                    ),
                    Expanded(
                      child: _tabButton(
                        title: lang.tr('Auto-Book Logs', 'অটো-বুক লগ'),
                        count: allTrips.length,
                        icon: Icons.bolt_rounded,
                        isActive: _activeTab == _MainTab.autoBook,
                        onTap: () {
                          if (_activeTab != _MainTab.autoBook) {
                            setState(() => _activeTab = _MainTab.autoBook);
                          }
                        },
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tab Contents ──
              Expanded(
                child: _activeTab == _MainTab.purchased
                    ? _buildPurchasedTicketsView(isDark, lang)
                    : _buildAutoBookHistoryView(
                        allTrips: allTrips,
                        successfulTrips: successfulTrips,
                        failedTrips: failedTrips,
                        filtered: filteredAutoBook,
                        isDark: isDark,
                        lang: lang,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tabButton({
    required String title,
    int? count,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? AppColors.primary : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive
                  ? (isDark ? Colors.white : AppColors.primary)
                  : (isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.12))
                      : (isDark ? Colors.white12 : Colors.black12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? (isDark ? Colors.white : AppColors.primary)
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // ── Purchased Tickets Tab ──────────────────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildPurchasedTicketsView(bool isDark, LanguageService lang) {
    if (_loadingPurchased) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              lang.tr(
                'Fetching official tickets from Bangladesh Railway...',
                'রেলওয়ে সার্ভার থেকে টিকেট লোড হচ্ছে...',
              ),
              style: TextStyle(
                color: AppColors.textSecondary(isDark),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
    }

    if (_purchasedError == 'not_logged_in') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_person_rounded,
                  size: 36,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                lang.tr('Railway Login Required', 'রেলওয়ে লগইন প্রয়োজন'),
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                lang.tr(
                  'Log in with your official Bangladesh Railway account to view and download your purchased tickets.',
                  'ক্রয়কৃত টিকিট দেখতে এবং ডাউনলোড করতে আপনার বাংলাদেশ রেলওয়ে অ্যাকাউন্টে লগইন করুন।',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary(isDark),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(lang.tr('Log in with Railway Account', 'রেলওয়ে অ্যাকাউন্টে লগইন করুন')),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
                  );
                  _fetchPurchasedTickets();
                },
              ),
            ],
          ),
        ),
      );
    }

    if (_purchasedError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                lang.tr('Could not load purchase history', 'ক্রয় ইতিহাস লোড করা যায়নি'),
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _purchasedError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary(isDark),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(lang.tr('Retry', 'পুনরায় চেষ্টা করুন')),
                onPressed: _fetchPurchasedTickets,
              ),
            ],
          ),
        ),
      );
    }

    final tickets = _purchasedTickets ?? [];
    if (tickets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchPurchasedTickets,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.airplane_ticket_outlined,
                      size: 34,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    lang.tr('No Purchased Tickets Found', 'কোনো ক্রয়কৃত টিকেট পাওয়া যায়নি'),
                    style: TextStyle(
                      color: AppColors.textPrimary(isDark),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lang.tr(
                      'Your official Bangladesh Railway purchased tickets will show up here.\nPull down to refresh.',
                      'আপনার বাংলাদেশ রেলওয়ে থেকে কেনা টিকেট এখানে প্রদর্শিত হবে।\nরিফ্রেশ করতে নিচে টানুন।',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary(isDark),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPurchasedTickets,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: tickets.length,
        itemBuilder: (context, index) {
          final ticket = tickets[index];
          return _PurchasedTicketCard(
            ticket: ticket,
            isDark: isDark,
            isDownloading: _downloadingOrderIds.contains(ticket.orderId),
            onDownload: () => _downloadTicket(ticket),
          );
        },
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // ── Auto-Book History Tab ──────────────────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildAutoBookHistoryView({
    required List<TripRecord> allTrips,
    required List<TripRecord> successfulTrips,
    required List<TripRecord> failedTrips,
    required List<TripRecord> filtered,
    required bool isDark,
    required LanguageService lang,
  }) {
    return Column(
      children: [
        // Filter Chips Row
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(
            children: [
              _filterChip(
                label: '${lang.tr("All", "সকল")} (${allTrips.length})',
                selected: _autoBookFilter == _TripFilter.all,
                onTap: () => setState(() => _autoBookFilter = _TripFilter.all),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _filterChip(
                label: '${lang.tr("Successful", "সফল")} (${successfulTrips.length})',
                selected: _autoBookFilter == _TripFilter.successful,
                onTap: () => setState(() => _autoBookFilter = _TripFilter.successful),
                color: AppColors.primary,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _filterChip(
                label: '${lang.tr("Failed", "ব্যর্থ")} (${failedTrips.length})',
                selected: _autoBookFilter == _TripFilter.failed,
                onTap: () => setState(() => _autoBookFilter = _TripFilter.failed),
                color: AppColors.error,
                isDark: isDark,
              ),
            ],
          ),
        ),

        // Trip Cards List
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(isDark, lang)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _TripCard(record: item, isDark: isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
    required bool isDark,
  }) {
    final activeColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.18)
              : AppColors.cardBg(isDark),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? activeColor
                : AppColors.cardBorder(isDark),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected
                ? (isDark ? Colors.white : activeColor)
                : AppColors.textSecondary(isDark),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool isDark, LanguageService lang) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.train_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _autoBookFilter == _TripFilter.all
                  ? lang.tr('No Automation History Yet', 'কোনো অটো-বুকিং ইতিহাস নেই')
                  : _autoBookFilter == _TripFilter.successful
                      ? lang.tr('No Successful Auto-Bookings', 'কোনো সফল অটো-বুকিং নেই')
                      : lang.tr('No Failed Auto-Bookings', 'কোনো ব্যর্থ অটো-বুকিং নেই'),
              style: TextStyle(
                color: AppColors.textPrimary(isDark),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              lang.tr(
                'Successful reservations and failed auto-book attempts will automatically be recorded here.',
                'সফল বুকিং এবং ব্যর্থ অনুসন্ধানের তথ্য স্বয়ংক্রিয়ভাবে এখানে সংরক্ষিত থাকবে।',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary(isDark),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    TripHistoryService history,
    bool isDark,
    LanguageService lang,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          lang.tr('Clear Trip History?', 'ট্রিপ ইতিহাস মুছে ফেলতে চান?'),
          style: TextStyle(color: AppColors.textPrimary(isDark)),
        ),
        content: Text(
          lang.tr(
            'This will clear all saved successful and failed booking records on this device.',
            'এটি এই ডিভাইস থেকে সমস্ত সংরক্ষিত সফল এবং ব্যর্থ বুকিং রেকর্ড মুছে ফেলবে।',
          ),
          style: TextStyle(color: AppColors.textSecondary(isDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.tr('Cancel', 'বাতিল')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.tr('Clear All', 'সব মুছুন')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await history.clearHistory();
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ── Official Purchased Ticket Card ──────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

class _PurchasedTicketCard extends StatelessWidget {
  final PurchasedTicket ticket;
  final bool isDark;
  final bool isDownloading;
  final VoidCallback onDownload;

  const _PurchasedTicketCard({
    required this.ticket,
    required this.isDark,
    required this.isDownloading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageService>();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: Train name, Class & Status badge ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.train_rounded,
                    color: AppColors.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.trainName,
                        style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ticket.seatClass.isNotEmpty)
                        Text(
                          '${lang.tr("Class", "শ্রেণি")}: ${ticket.seatClass}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ticket.isRefunded
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: ticket.isRefunded
                          ? AppColors.warning.withValues(alpha: 0.35)
                          : AppColors.success.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ticket.isRefunded ? Icons.undo_rounded : Icons.check_circle_rounded,
                        size: 11,
                        color: ticket.isRefunded ? AppColors.warning : AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ticket.isRefunded
                            ? lang.tr('REFUNDED', 'রিফান্ডকৃত')
                            : lang.tr('CONFIRMED', 'নিশ্চিত'),
                        style: TextStyle(
                          color: ticket.isRefunded ? AppColors.warning : AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Journey Details Grid ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: _infoCell(
                    icon: Icons.calendar_month_rounded,
                    label: lang.tr('Journey Date', 'যাত্রার তারিখ'),
                    value: ticket.journeyDate,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _infoCell(
                    icon: Icons.access_time_rounded,
                    label: lang.tr('Booked At', 'বুকিংয়ের সময়'),
                    value: ticket.bookingDate,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom Download in Browser Button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: isDownloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: Text(
                        isDownloading
                            ? lang.tr('Opening Browser Download...', 'ব্রাউজারে খোলা হচ্ছে...')
                            : lang.tr('Download', 'ডাউনলোড'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: isDownloading ? null : onDownload,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: lang.tr('Options', 'অপশন'),
                  icon: Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppColors.textPrimary(isDark),
                    ),
                  ),
                  onSelected: (val) {
                    if (val == 'portal') {
                      TicketDownloadService.openInBrowser(
                        TicketDownloadService.purchaseHistoryUrl,
                      );
                    } else if (val == 'direct') {
                      TicketDownloadService.openInBrowser(
                        TicketDownloadService.directDownloadUrl(ticket.orderId),
                      );
                    } else if (val == 'copy') {
                      Clipboard.setData(ClipboardData(
                        text: TicketDownloadService.directDownloadUrl(ticket.orderId),
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            lang.tr('Ticket PDF link copied to clipboard!', 'টিকেট লিংক ক্লিপবোর্ডে কপি করা হয়েছে!'),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'portal',
                      child: Row(
                        children: [
                          const Icon(Icons.language_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            lang.tr('Open Railway Website Portal', 'রেলওয়ে ওয়েবসাইট পোর্টালে যান'),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'direct',
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            lang.tr('Open Direct Ticket URL', 'সরাসরি টিকিটের লিংক খুলুন'),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          const Icon(Icons.copy_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            lang.tr('Copy Ticket Link', 'টিকিটের লিংক কপি করুন'),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCell({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary(isDark)),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textSecondary(isDark),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value.isNotEmpty ? value : '—',
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ── Auto-Book Local Trip Record Card ────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

class _TripCard extends StatelessWidget {
  final TripRecord record;
  final bool isDark;

  const _TripCard({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageService>();
    final isSuccess = record.status == TripBookingStatus.successful;
    final isReserved = record.status == TripBookingStatus.awaitingOtp;
    final isExpired = record.status == TripBookingStatus.expired;
    final isFailed = record.status == TripBookingStatus.failed;

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    if (isSuccess) {
      badgeColor = AppColors.success;
      badgeIcon = Icons.check_circle_rounded;
      badgeText = lang.tr('SUCCESSFUL', 'সফল');
    } else if (isReserved) {
      badgeColor = AppColors.primary;
      badgeIcon = Icons.hourglass_top_rounded;
      badgeText = lang.tr('RESERVED (OTP)', 'সংরক্ষিত (ওটিপি)');
    } else if (isExpired) {
      badgeColor = AppColors.warning;
      badgeIcon = Icons.timer_off_outlined;
      badgeText = lang.tr('EXPIRED (5m Limit)', 'মেয়াদোত্তীর্ণ (৫ মি.)');
    } else {
      badgeColor = AppColors.error;
      badgeIcon = Icons.cancel_outlined;
      badgeText = lang.tr('FAILED', 'ব্যর্থ');
    }

    final formattedTime = DateFormat('dd MMM, hh:mm a').format(record.createdAt);
    final friendlyReason = friendlyErrorMessage(record.failureReason);
    final rawReason = (record.failureReason ?? '').toLowerCase();
    final isTurnstileOrRaw = rawReason.contains('422') ||
        rawReason.contains('turnstile') ||
        rawReason.contains('cft_response') ||
        rawReason.contains('verification') ||
        rawReason.contains('{code:') ||
        friendlyReason.toLowerCase().contains('human check');
    final shouldShowFailure = isExpired ||
        (record.failureReason != null &&
            record.failureReason!.isNotEmpty &&
            !isTurnstileOrRaw &&
            friendlyReason.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReserved
              ? AppColors.primary.withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isReserved ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row: Status badge & timestamp ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 11, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                formattedTime,
                style: TextStyle(
                  color: AppColors.textSecondary(isDark),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Train Name & Class ──
          Row(
            children: [
              Expanded(
                child: Text(
                  record.trainName,
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  record.seatClass,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Journey Route & Date ──
          Row(
            children: [
              Text(
                '${record.fromCity} → ${record.toCity}',
                style: TextStyle(
                  color: AppColors.textSecondary(isDark),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '•  ${record.dateOfJourney}',
                style: TextStyle(
                  color: AppColors.textSecondary(isDark),
                  fontSize: 12,
                ),
              ),
            ],
          ),

          // ── Seat details & Fare ──
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_seat_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    record.seatNumbers.isNotEmpty
                        ? '${lang.tr("Seats", "আসন")}: ${record.seatNumbers.join(", ")} (${record.coachName})'
                        : (record.coachName.isNotEmpty
                            ? '${lang.tr("Coach", "বগি")}: ${record.coachName}'
                            : (isFailed ? lang.tr('No seats held', 'কোনো আসন ধরা যায়নি') : lang.tr('Seats pending', 'আসন প্রক্রিয়াধীন'))),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary(isDark),
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (record.totalFare > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '৳${record.totalFare.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: AppColors.textPrimary(isDark),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Failure reason / Expiry note (if any) ──
          if (shouldShowFailure) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (isExpired ? AppColors.warning : AppColors.error)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isExpired ? AppColors.warning : AppColors.error)
                      .withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpired
                        ? Icons.timer_off_outlined
                        : Icons.error_outline_rounded,
                    size: 13,
                    color: isExpired ? AppColors.warning : AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      friendlyReason,
                      style: TextStyle(
                        color: isExpired ? AppColors.warning : AppColors.error,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Live Action Button (if currently awaiting OTP) ──
          if (isReserved) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(
                  lang.tr('Continue Reservation & OTP', 'বুকিং ও ওটিপি যাচাই চালিয়ে যান'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReservationScreen()),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
