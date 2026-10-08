import 'package:intl/intl.dart';

/// Railway dates and times use Bangladesh time, regardless of device timezone.
class JourneySchedule {
  static const advanceDays = 10;
  static const bangladeshOffset = Duration(hours: 6);

  static DateTime? parseDate(String value) {
    for (final pattern in ['dd-MMM-yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy']) {
      try {
        return DateFormat(pattern, 'en_US').parseStrict(value.trim(), true);
      } on FormatException {
        // Try the next supported railway format.
      }
    }
    return null;
  }

  /// Convert railway wall-clock components into an absolute instant.
  static DateTime railwayTime(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  ).subtract(bangladeshOffset);

  static DateTime? salesOpenAt(String journeyDate) {
    final date = parseDate(journeyDate);
    return date == null
        ? null
        : railwayTime(date.subtract(const Duration(days: advanceDays)));
  }

  static bool isOutsideWindow(String journeyDate, {DateTime? now}) {
    final start = salesOpenAt(journeyDate);
    return start != null && (now ?? DateTime.now()).isBefore(start);
  }

  static String formatStart(DateTime value) => DateFormat(
    'dd MMM yyyy, hh:mm a',
    'en_US',
  ).format(value.toUtc().add(bangladeshOffset));
}
