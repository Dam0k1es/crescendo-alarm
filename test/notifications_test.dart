import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/utils/notifications.dart';

// Phase 5 (docs/scheduling-v2-spec.md, "Implementation order", step
// 21): the bedtime notification must ALWAYS be scheduled, regardless
// of `reminderEnabled` - FR-16's checkpoint 2 (bedtime instant) needs
// a hook for that, even when the visible reminder is disabled.
// `sleepReminderContent` only decides WHETHER the notification is visible
// (title/body set) or created silently in the background (title/body
// both null - awesome_notifications' own "background notification").

void main() {
  group('sleepReminderContent (FR-16 prerequisite)', () {
    test('reminderEnabled=true -> visible title/text', () {
      final content = sleepReminderContent(reminderEnabled: true);
      expect(content.title, isNotNull);
      expect(content.body, isNotNull);
    });

    test('reminderEnabled=false -> neither title nor text (silent notification)', () {
      final content = sleepReminderContent(reminderEnabled: false);
      expect(content.title, isNull);
      expect(content.body, isNull);
    });
  });
}
