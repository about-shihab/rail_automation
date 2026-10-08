import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rail_automation/services/admin_config_service.dart';
import 'package:rail_automation/services/admin_service.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/views/admin_config_tab.dart';

void main() {
  test('rejects out-of-range settings, secret headers and literal secrets', () {
    for (final patch in <Map<String, dynamic>>[
      {'poll_interval_seconds': 1},
      {'search_backoff_multiplier': double.nan},
      {
        'api_headers': {'Authorization': 'secret'},
      },
      {
        'turnstile_site_keys': {'sign_in': 'invalid'},
      },
      {
        'api_operations': {
          'sign_in': {
            'payload': {'password': 'secret'},
          },
        },
      },
      {
        'api_operations': {
          'search_trips': {'url': 'https://example.com/search'},
        },
      },
      {
        'api_operations': {
          'search_trips': {'timeout_seconds': 999},
        },
      },
    ]) {
      expect(
        () => AdminConfigService.validateChanges(patch),
        throwsA(isA<AdminException>()),
      );
    }
  });

  test('accepts operational settings and placeholder templates', () {
    final patch = <String, dynamic>{
      'poll_interval_seconds': 60,
      'resume_search_after_expiry': true,
      'api_headers': {'Accept-Language': 'en-US,en;q=0.9'},
      'api_operations': {
        'sign_in': {
          'enabled': true,
          'timeout_seconds': 20,
          'payload': {'password': '{{password}}'},
        },
        'search_trips': {
          'method': 'GET',
          'poll_interval_seconds': 60,
          'retries': 1,
        },
      },
    };
    expect(AdminConfigService.validateChanges(patch), patch);
  });

  test('settings overrides are loaded and stale edits are rejected', () {
    final before = AdminConfigSnapshot(
      {'poll_interval_seconds': 60},
      {'poll_interval_seconds': 90},
    );
    expect(before.values['poll_interval_seconds'], 90);
    expect(
      () => AdminConfigService.checkConflicts(
        before,
        AdminConfigSnapshot(
          {'poll_interval_seconds': 60},
          {'poll_interval_seconds': 120},
        ),
        ['poll_interval_seconds'],
      ),
      throwsA(isA<AdminException>()),
    );
    // Changes to an unrelated setting do not block this edit.
    expect(
      () => AdminConfigService.checkConflicts(
        before,
        AdminConfigSnapshot(
          {'poll_interval_seconds': 60, 'otp_window_seconds': 200},
          {'poll_interval_seconds': 90},
        ),
        ['poll_interval_seconds'],
      ),
      returnsNormally,
    );
  });

  test('non-admins cannot load or save configuration', () async {
    final service = AdminConfigService();
    await expectLater(service.load(), throwsA(isA<AdminException>()));
    await expectLater(
      service.save(AdminConfigSnapshot({}, {}), {'poll_interval_seconds': 60}),
      throwsA(isA<AdminException>()),
    );
  });

  testWidgets('editor sends only changed settings and preserves API maps', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminConfigEditor(
            values: AppConfig.validate({
              'api_operations': {
                'search_trips': {
                  'method': 'GET',
                  'payload': {'seat_class': '{{seat_class}}'},
                },
              },
            }),
            busy: false,
            onSave: (patch) async {
              saved = patch;
            },
            onReload: () {},
          ),
        ),
      ),
    );
    expect(find.text('Monitor until train departure'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('service_max_session_hours')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll_interval_seconds')),
      '60',
    );
    final save = find.text('Save configuration');
    await tester.scrollUntilVisible(
      save,
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pump();
    expect(saved, {'poll_interval_seconds': 60});
  });

  testWidgets('invalid numeric input is shown without saving', (tester) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminConfigEditor(
            values: AppConfig.validate({}),
            busy: false,
            onSave: (_) async {
              saved = true;
            },
            onReload: () {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll_interval_seconds')),
      '1',
    );
    final save = find.text('Save configuration');
    await tester.scrollUntilVisible(
      save,
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pump();
    expect(saved, isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('poll_interval_seconds')),
      -450,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enter a value from 10 to 86400'), findsOneWidget);
  });
}
