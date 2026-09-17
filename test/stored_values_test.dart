import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/scheduling/stored_values.dart';

// docs/TODO.md T-83: the same `Map<String, int?>` (AppState.pendingDayValues)
// was read in five places, three times UTC-tagged and twice with no tag.
// Both were correct - the domain layer requires UTC tagging (its arithmetic
// compares digit fields), while the display and ScheduledAlarm.title
// (formatDateTime) require local digits. That's exactly why it was
// dangerous: unifying it "for consistency" would have silently shifted the
// display and the alarm title by the device offset. Two named converters
// make the intent visible at every call site.

void main() {
  final instant = DateTime.utc(2026, 3, 11, 6, 30);
  final millis = instant.millisecondsSinceEpoch;

  group('instantFromStored (domain layer)', () {
    test('is UTC-tagged', () {
      final value = instantFromStored(millis)!;

      expect(value.isUtc, isTrue);
      expect(value, instant);
    });

    test('null stays null (gap day/safety valve)', () {
      expect(instantFromStored(null), isNull);
    });
  });

  group('localFromStored (platform and display)', () {
    test('is locally tagged', () {
      final value = localFromStored(millis)!;

      expect(value.isUtc, isFalse);
    });

    test('null stays null', () {
      expect(localFromStored(null), isNull);
    });
  });

  test('both denote the same real moment', () {
    // The difference is exclusively the tagging, never the instant - that's
    // the property both call sites rely on.
    expect(
      localFromStored(millis)!.isAtSameMomentAs(instantFromStored(millis)!),
      isTrue,
    );
  });

  test('toStored is the inverse, frame-independent', () {
    expect(toStored(instant), millis);
    expect(toStored(instant.toLocal()), millis);
    expect(toStored(null), isNull);
  });
}
