import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/admin_config_service.dart';
import '../services/admin_service.dart';
import '../services/rail_api_config.dart';

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('App configuration saved')));
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
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _snapshot == null
              ? Center(
                  child: TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Reload configuration'),
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

/// Forms use friendly labels; advanced API maps remain available as JSON.
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
  static const _fields = <String, (String, num, num)>{
    'poll_interval_seconds': ('Search interval (seconds)', 10, 86400),
    'request_timeout_seconds': ('Request timeout (seconds)', 5, 120),
    'search_jitter_percent': ('Search jitter (%)', 0, 50),
    'search_backoff_multiplier': ('Search backoff multiplier', 1, 4),
    'search_max_backoff_seconds': ('Maximum backoff (seconds)', 10, 3600),
    'search_near_departure_minutes': (
      'Near departure window (minutes)',
      0,
      1440,
    ),
    'search_near_departure_interval_seconds': (
      'Near departure interval (seconds)',
      0,
      3600,
    ),
    'reservation_timeout_minutes': ('Reservation timeout (minutes)', 1, 15),
    'login_retry_interval_seconds': (
      'Login retry interval (seconds)',
      10,
      3600,
    ),
    'otp_window_seconds': ('OTP wait window (seconds)', 30, 600),
    'low_availability_threshold': ('Low availability threshold', 1, 10),
    'max_seats': ('Maximum seats', 1, 4),
  };
  static const _maps = {
    'api_headers': 'Request headers',
    'turnstile_site_keys': 'Turnstile site keys',
    'api_operations': 'API operations',
  };
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  late bool _resume;
  late bool _pushAnnouncements;
  String? _error;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    for (final key in _fields.keys) {
      _controllers[key] = TextEditingController(text: '${widget.values[key]}');
    }
    for (final key in _maps.keys) {
      _controllers[key] = TextEditingController(
        text: const JsonEncoder.withIndent('  ').convert(widget.values[key]),
      );
    }
    _resume = widget.values['resume_search_after_expiry'] == true;
    _pushAnnouncements = widget.values['admin_push_enabled'] == true;
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
        for (final key in _fields.keys)
          key: key == 'search_backoff_multiplier'
              ? double.parse(_controllers[key]!.text.trim())
              : int.parse(_controllers[key]!.text.trim()),
        'resume_search_after_expiry': _resume,
        'admin_push_enabled': _pushAnnouncements,
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
          title: const Text('Discard unsaved changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
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
    return PopScope(
      canPop: !widget.busy,
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'App configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved changes apply to all users. Existing monitoring sessions pick up updated settings automatically.',
            ),
            const SizedBox(height: 20),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_available),
              title: Text('Monitor until train departure'),
              subtitle: Text(
                'Journeys more than 10 days away are scheduled. Searching starts when the journey is within 10 days.',
              ),
            ),
            const SizedBox(height: 16),
            for (final entry in _fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  key: ValueKey(entry.key),
                  controller: _controllers[entry.key],
                  enabled: !widget.busy,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: entry.key == 'search_backoff_multiplier',
                  ),
                  decoration: InputDecoration(
                    labelText: entry.value.$1,
                    helperText: '${entry.value.$2}–${entry.value.$3}',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _changed,
                  validator: (text) {
                    final value = entry.key == 'search_backoff_multiplier'
                        ? double.tryParse(text?.trim() ?? '')
                        : int.tryParse(text?.trim() ?? '');
                    if (value == null ||
                        !value.isFinite ||
                        value < entry.value.$2 ||
                        value > entry.value.$3) {
                      return 'Enter a value from ${entry.value.$2} to ${entry.value.$3}';
                    }
                    return null;
                  },
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resume searching after reservation expires'),
              value: _resume,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() {
                      _resume = value;
                      _dirty = true;
                    }),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Push admin announcements'),
              subtitle: const Text(
                'Enable after the push delivery server is deployed. Announcements will arrive while the app is minimized or closed.',
              ),
              value: _pushAnnouncements,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() {
                      _pushAnnouncements = value;
                      _dirty = true;
                    }),
            ),
            for (final entry in _maps.entries)
              ExpansionTile(
                title: Text(entry.value),
                maintainState: true,
                children: [
                  if (entry.key == 'api_operations')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Configure enabled, method, url, poll_interval_seconds, min_interval_seconds, timeout_seconds, retries, retry_delay_seconds, headers and payload. Supported operations: ${RailApiConfig.paths.keys.join(', ')}. Payload secrets must use {{placeholders}}.',
                      ),
                    ),
                  TextFormField(
                    key: ValueKey(entry.key),
                    controller: _controllers[entry.key],
                    enabled: !widget.busy,
                    minLines: 4,
                    maxLines: 16,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
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
                  const SizedBox(height: 16),
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: widget.busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save configuration'),
            ),
            TextButton.icon(
              onPressed: widget.busy ? null : _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload configuration'),
            ),
          ],
        ),
      ),
    );
  }
}
