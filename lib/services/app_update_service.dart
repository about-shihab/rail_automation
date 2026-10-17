import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class UpdatePolicy {
  const UpdatePolicy(
    this.version,
    this.build,
    this.minimumBuild,
    this.download,
  );
  final String version;
  final int build;
  final int minimumBuild;
  final Uri download;

  static UpdatePolicy? parse(dynamic value) {
    if (value is! Map) return null;
    final build = value['build_number'];
    final minimum = value['minimum_build_number'];
    final version = value['version'];
    final uri = Uri.tryParse('${value['apk_url'] ?? ''}');
    if (build is! int ||
        minimum is! int ||
        build < 1 ||
        minimum < 0 ||
        minimum > build ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return UpdatePolicy(version, build, minimum, uri);
  }

  bool requiresUpdate(int installedBuild) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      installedBuild > 0 &&
      installedBuild < minimumBuild;
  Map<String, dynamic> toJson() => {
    'version': version,
    'build_number': build,
    'minimum_build_number': minimumBuild,
    'apk_url': download.toString(),
  };
}

/// Public HTTPS metadata; repository credentials never enter the app.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService({this.client});
  final http.Client? client;
  static final instance = AppUpdateService();
  static const endpoint = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://about-shihab.github.io/rail-pro/update.json',
  );
  static const cacheKey = 'rail_update_policy_v1';
  static const installedKey = 'rail_installed_build';
  static const versionKey = 'rail_installed_version';
  static const _channel = MethodChannel('com.example.rail_automation/overlay');
  UpdatePolicy? policy;
  int installedBuild = 0;
  String installedVersion = '';
  bool checking = false;
  String? error;
  Future<void>? _refreshing;
  DateTime? _lastChecked;
  bool get required => policy?.requiresUpdate(installedBuild) ?? false;

  Future<void> initialize() async {
    Map<String, dynamic>? info;
    try {
      info = await _channel.invokeMapMethod<String, dynamic>('appVersion');
    } catch (_) {}
    installedBuild = (info?['build'] as num?)?.toInt() ?? 0;
    installedVersion = info?['version'] as String? ?? '';
    final prefs = await SharedPreferences.getInstance();
    if (installedBuild > 0) {
      await prefs.setInt(installedKey, installedBuild);
    } else {
      installedBuild = prefs.getInt(installedKey) ?? 1;
    }
    if (installedVersion.isNotEmpty) {
      await prefs.setString(versionKey, installedVersion);
    } else {
      installedVersion = prefs.getString(versionKey) ?? '1.0.1';
    }
    await reloadCache();
  }

  Future<void> reloadCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    installedBuild = prefs.getInt(installedKey) ?? installedBuild;
    installedVersion = prefs.getString(versionKey) ?? installedVersion;
    try {
      policy = UpdatePolicy.parse(
        jsonDecode(prefs.getString(cacheKey) ?? 'null'),
      );
    } catch (_) {
      /* Preserve the last valid policy on a damaged cache. */
    }
  }

  Future<void> refresh({bool force = false}) {
    if (_refreshing != null) return _refreshing!;
    if (!force &&
        _lastChecked != null &&
        DateTime.now().difference(_lastChecked!) < const Duration(minutes: 5)) {
      return Future.value();
    }
    return _refreshing = _fetch().whenComplete(() => _refreshing = null);
  }

  Future<void> _fetch() async {
    checking = true;
    notifyListeners();
    try {
      await reloadCache();
      final uri = Uri.parse(endpoint);
      if (uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('An HTTPS update endpoint is required.');
      }
      final response =
          await (client?.get(uri, headers: {'Cache-Control': 'no-cache'}) ??
                  http.get(uri, headers: {'Cache-Control': 'no-cache'}))
              .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.length > 16384) {
        throw const FormatException('Update information is unavailable.');
      }
      final next = UpdatePolicy.parse(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      if (next == null) {
        throw const FormatException('Invalid update information.');
      }
      // Ignore stale CDN responses. An explicit newer release can lower the
      // minimum if a mandatory release needs to be rolled back.
      if (policy == null || next.build >= policy!.build) {
        policy = next;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, jsonEncode(next.toJson()));
      }
      error = null;
    } catch (_) {
      error = 'Could not check for updates. Please try again.';
      // Keep a cached mandatory update effective while offline.
    } finally {
      _lastChecked = DateTime.now();
      checking = false;
      notifyListeners();
    }
  }

  /// Also called in worker isolates before starting a new reservation.
  Future<void> ensureBookingAllowed() async {
    // A booking must not outrun the startup/resume policy check.
    if (_refreshing != null) await _refreshing;
    await reloadCache();
    if (required) {
      throw StateError('Update Rail Pro before starting a new booking.');
    }
  }
}
