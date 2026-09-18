import 'dart:async';

import 'package:alarm/model/alarm_settings.dart';
import 'package:alarm/model/notification_settings.dart';
import 'package:alarm/model/volume_settings.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/alarms/ringing_watch.dart';

// Bug report: an alarm stopped by swiping its notification away (no app UI
// open) left the ring screen - opened for that same alarm before it was
// killed - stuck showing on reopen, with no ringing alarm behind it and no
// way out (`PopScope(canPop: false)`). `NotificationSettings
// .androidStopAlarmOnDismiss` defaults to true and stops the alarm entirely
// at the native level, so `Alarm.ringing` is the only place Dart ever learns
// about it. [RingingWatch] is the reusable half of the fix used by both
// ScreenAlarmActive and QrScanner: notice the alarm disappearing from the
// ringing set and let the screen react.

AlarmSettings _fakeAlarmSettings(int id) => AlarmSettings(
      id: id,
      dateTime: DateTime.now(),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(title: 't', body: 'b'),
    );

void main() {
  test('ignores the seed value even when the alarm is already absent',
      () async {
    final controller = StreamController<AlarmSet>();
    var goneCalled = false;
    final watch = RingingWatch(
      alarmId: 1,
      ringingStream: controller.stream,
      onGone: () => goneCalled = true,
    );

    // The stream's first delivery is its current snapshot, not a change -
    // reacting to it would auto-close a screen that just opened, before the
    // widget test harness (which never populates the real Alarm.ringing
    // subject) gets a chance to represent "still ringing" at all.
    controller.add(AlarmSet.empty());
    await Future<void>.delayed(Duration.zero);

    expect(goneCalled, isFalse);
    watch.cancel();
    await controller.close();
  });

  test('fires when the alarm disappears from a later event', () async {
    final controller = StreamController<AlarmSet>();
    var goneCalled = false;
    final watch = RingingWatch(
      alarmId: 1,
      ringingStream: controller.stream,
      onGone: () => goneCalled = true,
    );

    controller.add(AlarmSet([_fakeAlarmSettings(1)]));
    await Future<void>.delayed(Duration.zero);
    expect(goneCalled, isFalse);

    controller.add(AlarmSet.empty());
    await Future<void>.delayed(Duration.zero);
    expect(goneCalled, isTrue,
        reason: 'the alarm was stopped elsewhere - the screen must notice');

    watch.cancel();
    await controller.close();
  });

  test('does not fire while the watched alarm is still present', () async {
    final controller = StreamController<AlarmSet>();
    var goneCalled = false;
    final watch = RingingWatch(
      alarmId: 1,
      ringingStream: controller.stream,
      onGone: () => goneCalled = true,
    );

    controller.add(AlarmSet([_fakeAlarmSettings(1)]));
    await Future<void>.delayed(Duration.zero);

    // A second, unrelated alarm starting to ring must not be mistaken for
    // the watched one disappearing.
    controller.add(AlarmSet([_fakeAlarmSettings(1), _fakeAlarmSettings(2)]));
    await Future<void>.delayed(Duration.zero);

    expect(goneCalled, isFalse);
    watch.cancel();
    await controller.close();
  });

  test('only fires once on the present-to-absent edge, not again for every '
      'later event where the alarm is still absent', () async {
    // Bug found while diagnosing the Navigator "!_debugLocked" crash after
    // the Stop button: an unrelated alarm's OWN ring/stop can add further
    // events to the shared Alarm.ringing stream while ours has already
    // disappeared - each of those re-confirmed "still absent" and, before
    // this fix, called onGone again every time, multiplying however many
    // times the screen tries to pop itself.
    final controller = StreamController<AlarmSet>();
    var goneCallCount = 0;
    final watch = RingingWatch(
      alarmId: 1,
      ringingStream: controller.stream,
      onGone: () => goneCallCount++,
    );

    controller.add(AlarmSet([_fakeAlarmSettings(1)]));
    await Future<void>.delayed(Duration.zero);

    controller.add(AlarmSet.empty());
    await Future<void>.delayed(Duration.zero);
    // A second, unrelated alarm now starts ringing - alarm 1 is still gone.
    controller.add(AlarmSet([_fakeAlarmSettings(2)]));
    await Future<void>.delayed(Duration.zero);
    // ...and stops again - alarm 1 is still, still gone.
    controller.add(AlarmSet.empty());
    await Future<void>.delayed(Duration.zero);

    expect(goneCallCount, 1,
        reason: 'the disappearance is one event, not one per confirmation '
            'that it is still gone');

    watch.cancel();
    await controller.close();
  });

  test('cancel stops further notifications', () async {
    final controller = StreamController<AlarmSet>();
    var goneCalled = false;
    final watch = RingingWatch(
      alarmId: 1,
      ringingStream: controller.stream,
      onGone: () => goneCalled = true,
    );

    controller.add(AlarmSet([_fakeAlarmSettings(1)]));
    await Future<void>.delayed(Duration.zero);
    watch.cancel();

    controller.add(AlarmSet.empty());
    await Future<void>.delayed(Duration.zero);

    expect(goneCalled, isFalse);
    await controller.close();
  });
}
