import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/utils/notifications.dart';

// Phase 5 (docs/scheduling-v2-spec.md, "Implementierungsreihenfolge", Schritt
// 21): die Schlafengehen-Notification muss IMMER geplant werden, unabhängig
// von `reminderEnabled` - FR-16s Checkpoint 2 (Schlafengehen-Zeitpunkt) braucht
// dafür einen Aufhänger, auch wenn die sichtbare Erinnerung deaktiviert ist.
// `sleepReminderContent` entscheidet nur, OB die Notification sichtbar ist
// (title/body gesetzt) oder still im Hintergrund erzeugt wird (title/body
// beide null - awesome_notifications' eigene "background notification").

void main() {
  group('sleepReminderContent (FR-16 Voraussetzung)', () {
    test('reminderEnabled=true -> sichtbarer Titel/Text', () {
      final content = sleepReminderContent(reminderEnabled: true);
      expect(content.title, isNotNull);
      expect(content.body, isNotNull);
    });

    test('reminderEnabled=false -> weder Titel noch Text (stille Notification)', () {
      final content = sleepReminderContent(reminderEnabled: false);
      expect(content.title, isNull);
      expect(content.body, isNull);
    });
  });
}
