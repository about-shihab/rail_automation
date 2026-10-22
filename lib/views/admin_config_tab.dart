import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_config_service.dart';
import '../services/admin_service.dart';
import '../services/rail_api_config.dart';
import '../utils/app_theme.dart';

class AdminConfigTab extends StatefulWidget {
  const AdminConfigTab({super.key});

  @override
  State<AdminConfigTab> createState() => _AdminConfigTabState();
}

class _AdminConfigTabState extends State<AdminConfigTab>
    with AutomaticKeepAliveClientMixin {
  final _service = AdminConfigService();
  AdminConfigSnapshot? _snapshot;
  String? _error;
  bool _busy = false;
  int _revision = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object error) {
    if (error is AdminException) return error.message;
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Firestore denied access. Your account needs permission to edit app configuration.';
    }
    return 'Could not access configuration. Check your connection and try again.';
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await _service.load();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _revision++;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(Map<String, dynamic> changes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.save(_snapshot!, changes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('App configuration saved and applied on-the-fly'),
          backgroundColor: Color(0xFF009B78),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        if (_busy)
          const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            color: AppColors.primary,
          ),
        if (_error != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _snapshot == null
              ? Center(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reload configuration'),
                  ),
                )
              : AdminConfigEditor(
                  key: ValueKey(_revision),
                  values: _snapshot!.values,
                  busy: _busy,
                  onSave: _save,
                  onReload: _load,
                ),
        ),
      ],
    );
  }
}

/// Category metadata definition for meaningful on-the-fly admin customization.
class _ConfigFieldMeta {
  final String key;
  final String label;
  final String description;
  final String unit;
  final num min;
  final num max;
  final IconData icon;
  final List<num>? presets;

  const _ConfigFieldMeta({
    required this.key,
    required this.label,
    required this.description,
    required this.unit,
    required this.min,
    required this.max,
    required this.icon,
    this.presets,
  });
}

class AdminConfigEditor extends StatefulWidget {
  final Map<String, dynamic> values;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final VoidCallback onReload;

  const AdminConfigEditor({
    super.key,
    required this.values,
    required this.busy,
    required this.onSave,
    required this.onReload,
  });

  @override
  State<AdminConfigEditor> createState() => _AdminConfigEditorState();
}

class _AdminConfigEditorState extends State<AdminConfigEditor> {
  // All fields categorized into clear, meaningful operational domains
  static const _searchFrequencyGroup = [
    _ConfigFieldMeta(
      key: 'poll_interval_seconds',
      label: 'Search interval (seconds)',
      description: 'Frequency of checking Bangladesh Railway for open seats during normal hours.',
      unit: 'seconds',
      min: 10,
      max: 86400,
      icon: Icons.timer_outlined,
      presets: [15, 30, 60, 120],
    ),
    _ConfigFieldMeta(
      key: 'search_jitter_percent',
      label: 'Search jitter (%)',
      description: 'Adds random timing variation between requests to emulate human browsing and prevent bot blocks.',
      unit: '%',
      min: 0,
      max: 50,
      icon: Icons.shuffle_rounded,
      presets: [0, 10, 20, 30],
    ),
    _ConfigFieldMeta(
      key: 'search_backoff_multiplier',
      label: 'Search backoff multiplier',
      description: 'Multiplier applied to interval on network failures or Railway server rate limiting.',
      unit: 'multiplier',
      min: 1,
      max: 4,
      icon: Icons.trending_up_rounded,
      presets: [1.2, 1.5, 2.0],
    ),
    _ConfigFieldMeta(
      key: 'search_max_backoff_seconds',
      label: 'Maximum backoff (seconds)',
      description: 'Upper ceiling limit for the backoff interval when server errors occur.',
      unit: 'seconds',
      min: 10,
      max: 3600,
      icon: Icons.speed_rounded,
      presets: [120, 300, 600],
    ),
    _ConfigFieldMeta(
      key: 'via_search_interval_minutes',
      label: 'Via station search interval (minutes)',
      description: 'How frequently intermediate / via stations are searched during active background monitoring.',
      unit: 'minutes',
      min: 1,
      max: 60,
      icon: Icons.alt_route_rounded,
      presets: [1, 2, 3, 5, 10],
    ),
  ];

  static const _nearDepartureGroup = [
    _ConfigFieldMeta(
      key: 'search_near_departure_minutes',
      label: 'Near departure window (minutes)',
      description: 'When train leaves within this time, monitoring accelerates to high-speed checking.',
      unit: 'minutes',
      min: 0,
      max: 1440,
      icon: Icons.departure_board_rounded,
      presets: [30, 60, 120],
    ),
    _ConfigFieldMeta(
      key: 'search_near_departure_interval_seconds',
      label: 'Near departure interval (seconds)',
      description: 'Ultra-fast checking frequency used during the near departure window.',
      unit: 'seconds',
      min: 0,
      max: 3600,
      icon: Icons.bolt_rounded,
      presets: [5, 10, 15],
    ),
  ];

  static const _reservationGroup = [
    _ConfigFieldMeta(
      key: 'reservation_timeout_minutes',
      label: 'Reservation timeout (minutes)',
      description: 'How long held seats are kept for OTP input and payment before being released by Railway.',
      unit: 'minutes',
      min: 1,
      max: 15,
      icon: Icons.hourglass_top_rounded,
      presets: [3, 5, 10],
    ),
  ];

  static const _securityGroup = [
    _ConfigFieldMeta(
      key: 'otp_window_seconds',
      label: 'OTP wait window (seconds)',
      description: 'Maximum time allowed for Google OTP Verifier and SMS reception before fallback.',
      unit: 'seconds',
      min: 30,
      max: 600,
      icon: Icons.sms_outlined,
      presets: [120, 180, 240],
    ),
    _ConfigFieldMeta(
      key: 'login_retry_interval_seconds',
      label: 'Login retry interval (seconds)',
      description: 'Cooldown duration before attempting another silent background session refresh.',
      unit: 'seconds',
      min: 10,
      max: 3600,
      icon: Icons.lock_reset_rounded,
      presets: [30, 60, 120],
    ),
    _ConfigFieldMeta(
      key: 'request_timeout_seconds',
      label: 'Request timeout (seconds)',
      description: 'Network timeout limit for individual HTTP requests to Railway APIs.',
      unit: 'seconds',
      min: 5,
      max: 120,
      icon: Icons.wifi_tethering_error_rounded,
      presets: [10, 15, 30],
    ),
  ];

  static const _bookingLimitsGroup = [
    _ConfigFieldMeta(
      key: 'max_seats',
      label: 'Maximum seats',
      description: 'Maximum number of seats a single automated booking can reserve at once.',
      unit: 'seats',
      min: 1,
      max: 4,
      icon: Icons.airline_seat_recline_extra_rounded,
      presets: [1, 2, 4],
    ),
    _ConfigFieldMeta(
      key: 'low_availability_threshold',
      label: 'Low availability threshold',
      description: 'Seats remaining count that triggers urgent / high priority alerts to the user.',
      unit: 'seats',
      min: 1,
      max: 10,
      icon: Icons.notification_important_rounded,
      presets: [2, 4, 6],
    ),
  ];

  static const _creditsGroup = [
    _ConfigFieldMeta(
      key: 'default_credits',
      label: 'Default user credits',
      description: 'Initial free credit balance granted to new users upon registration.',
      unit: 'credits',
      min: 0,
      max: 100,
      icon: Icons.monetization_on_outlined,
      presets: [0, 2, 5, 10],
    ),
  ];

  static const _maps = {
    'api_headers': 'Request headers',
    'turnstile_site_keys': 'Turnstile site keys',
    'api_operations': 'API operations',
  };

  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  late bool _resume;
  late bool _pushAnnouncements;
  late bool _directRecharge;
  String? _error;
  bool _dirty = false;

  List<_ConfigFieldMeta> get _allFields => [
        ..._searchFrequencyGroup,
        ..._nearDepartureGroup,
        ..._reservationGroup,
        ..._securityGroup,
        ..._bookingLimitsGroup,
        ..._creditsGroup,
      ];

  @override
  void initState() {
    super.initState();
    for (final field in _allFields) {
      _controllers[field.key] =
          TextEditingController(text: '${widget.values[field.key]}');
    }
    for (final key in _maps.keys) {
      _controllers[key] = TextEditingController(
        text: const JsonEncoder.withIndent('  ').convert(widget.values[key]),
      );
    }
    _resume = widget.values['resume_search_after_expiry'] == true;
    _pushAnnouncements = widget.values['admin_push_enabled'] == true;
    _directRecharge = widget.values['direct_recharge_enabled'] == true;
    _controllers['recharge_contact_email'] = TextEditingController(
      text: widget.values['recharge_contact_email'] as String? ??
          'connect.abdulla@gmail.com',
    );
    _controllers['developer_name'] = TextEditingController(
      text: widget.values['developer_name'] as String? ?? 'Abdulla Al Mamun',
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed(String _) => setState(() => _dirty = true);

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    try {
      final edited = <String, dynamic>{
        for (final field in _allFields)
          field.key: field.key == 'search_backoff_multiplier'
              ? double.parse(_controllers[field.key]!.text.trim())
              : int.parse(_controllers[field.key]!.text.trim()),
        'resume_search_after_expiry': _resume,
        'admin_push_enabled': _pushAnnouncements,
        'direct_recharge_enabled': _directRecharge,
        'recharge_contact_email':
            _controllers['recharge_contact_email']!.text.trim(),
        'developer_name':
            _controllers['developer_name']!.text.trim(),
        for (final key in _maps.keys) key: jsonDecode(_controllers[key]!.text),
      };
      final patch = {
        for (final entry in edited.entries)
          if (!AdminConfigService.sameValue(
            entry.value,
            widget.values[entry.key],
          ))
            entry.key: entry.value,
      };
      AdminConfigService.validateChanges(patch);
      if (patch.isEmpty) {
        setState(() => _dirty = false);
        return;
      }
      await widget.onSave(patch);
    } on AdminException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException {
      if (mounted) {
        setState(() => _error = 'Enter valid numbers and JSON objects.');
      }
    }
  }

  Future<void> _reload() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Discard unsaved changes?'),
          content: const Text('Any unsaved modifications to operational parameters will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    widget.onReload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !widget.busy,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            // ── Executive Header Banner ────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withValues(alpha: 0.82),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Live Operational Controls',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'On The Fly',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Saved changes apply instantly across all active background searches and user sessions.',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Booking Schedule Info Banner ───────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2630) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF2D3748) : const Color(0xFFBBF7D0),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_available,
                    color: Color(0xFF16A34A),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monitor until train departure',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Journeys more than 10 days away are scheduled. Searching starts when the journey is within 10 days.',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── SECTION 1: Search & Frequency ──────────────────────────
            _buildSection(
              title: 'Search & Monitoring Frequency',
              icon: Icons.radar_rounded,
              badge: 'Engine',
              color: const Color(0xFF0284C7),
              isDark: isDark,
              fields: _searchFrequencyGroup,
            ),
            const SizedBox(height: 16),

            // ── SECTION 2: Near Departure Acceleration ─────────────────
            _buildSection(
              title: 'Near Departure Acceleration',
              icon: Icons.fast_forward_rounded,
              badge: 'Rush Mode',
              color: const Color(0xFFF59E0B),
              isDark: isDark,
              fields: _nearDepartureGroup,
            ),
            const SizedBox(height: 16),

            // ── SECTION 3: Reservation & Hold Window ───────────────────
            _buildSection(
              title: 'Reservation & Hold Window',
              icon: Icons.timer_outlined,
              badge: 'Railway Hold',
              color: const Color(0xFF8B5CF6),
              isDark: isDark,
              fields: _reservationGroup,
              extraWidget: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Resume searching after reservation expires',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Automatically restarts seat search if the user does not pay in time.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                    value: _resume,
                    activeThumbColor: AppColors.primary,
                    onChanged: widget.busy
                        ? null
                        : (value) => setState(() {
                              _resume = value;
                              _dirty = true;
                            }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── SECTION 4: Security, Login & OTP ───────────────────────
            _buildSection(
              title: 'Security & Verification Timers',
              icon: Icons.shield_outlined,
              badge: 'Security',
              color: const Color(0xFF10B981),
              isDark: isDark,
              fields: _securityGroup,
            ),
            const SizedBox(height: 16),

            // ── SECTION 5: Booking Limits & Availability ───────────────
            _buildSection(
              title: 'Booking Limits & Thresholds',
              icon: Icons.airline_seat_recline_extra_rounded,
              badge: 'Limits',
              color: const Color(0xFFEC4899),
              isDark: isDark,
              fields: _bookingLimitsGroup,
              extraWidget: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Push admin announcements',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Enable after the push delivery server is deployed. Announcements arrive while the app is closed.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                    value: _pushAnnouncements,
                    activeThumbColor: AppColors.primary,
                    onChanged: widget.busy
                        ? null
                        : (value) => setState(() {
                              _pushAnnouncements = value;
                              _dirty = true;
                            }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── SECTION 6: Credits & Recharge Policy ───────────────────
            _buildSection(
              title: 'Credits & Recharge Policy',
              icon: Icons.monetization_on_rounded,
              badge: 'Credits',
              color: const Color(0xFF059669),
              isDark: isDark,
              fields: _creditsGroup,
              extraWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Enable direct recharge window',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'When disabled, users see an email contact card to recharge credits. When enabled, users can submit TrxID directly.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                      value: _directRecharge,
                      activeThumbColor: AppColors.primary,
                      onChanged: widget.busy
                          ? null
                          : (value) => setState(() {
                                _directRecharge = value;
                                _dirty = true;
                              }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Support & Developer contact email',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Support and developer email address shown to users on their profile and for manual credit recharge requests.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('recharge_contact_email'),
                    controller: _controllers['recharge_contact_email'],
                    enabled: !widget.busy,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: _changed,
                    validator: (text) {
                      final email = text?.trim() ?? '';
                      if (!email.contains('@') || !email.contains('.')) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Developer name',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Developer name displayed on the profile drawer and app information screens.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('developer_name'),
                    controller: _controllers['developer_name'],
                    enabled: !widget.busy,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: _changed,
                    validator: (text) {
                      if (text == null || text.trim().isEmpty) {
                        return 'Developer name cannot be empty';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── SECTION 7: Advanced API & Cloudflare Maps ──────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2630) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? const Color(0xFF2D3748) : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.code_rounded,
                          size: 18,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Advanced API & Endpoint Overrides',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final entry in _maps.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.transparent,
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          maintainState: true,
                          children: [
                            if (entry.key == 'api_operations')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Supported operations: ${RailApiConfig.paths.keys.join(', ')}. Payload secrets must use {{placeholders}}.',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            TextFormField(
                              key: ValueKey(entry.key),
                              controller: _controllers[entry.key],
                              enabled: !widget.busy,
                              minLines: 4,
                              maxLines: 14,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'JSON object',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: _changed,
                              validator: (text) {
                                try {
                                  if (jsonDecode(text ?? '') is Map<String, dynamic>) {
                                    return null;
                                  }
                                } on FormatException {
                                  /* Show a field error below. */
                                }
                                return 'Enter a valid JSON object';
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // ── Primary Actions ────────────────────────────────────────
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: widget.busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text(
                'Save configuration',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.busy ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reload configuration'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required String badge,
    required Color color,
    required bool isDark,
    required List<_ConfigFieldMeta> fields,
    Widget? extraWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2630) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2D3748) : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final field in fields) ...[
            _buildFieldInput(field, isDark),
            const SizedBox(height: 14),
          ],
          ?extraWidget,
        ],
      ),
    );
  }

  Widget _buildFieldInput(_ConfigFieldMeta field, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                field.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${field.min}–${field.max}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          field.description,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey(field.key),
          controller: _controllers[field.key],
          enabled: !widget.busy,
          keyboardType: TextInputType.numberWithOptions(
            decimal: field.key == 'search_backoff_multiplier',
          ),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            suffixText: field.unit,
            suffixStyle: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
            helperText: '${field.min}–${field.max}',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: _changed,
          validator: (text) {
            final value = field.key == 'search_backoff_multiplier'
                ? double.tryParse(text?.trim() ?? '')
                : int.tryParse(text?.trim() ?? '');
            if (value == null ||
                !value.isFinite ||
                value < field.min ||
                value > field.max) {
              return 'Enter a value from ${field.min} to ${field.max}';
            }
            return null;
          },
        ),
        if (field.presets != null && field.presets!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: field.presets!.map((preset) {
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: widget.busy
                    ? null
                    : () {
                        _controllers[field.key]!.text = '$preset';
                        _changed('$preset');
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    '+$preset ${field.unit}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
