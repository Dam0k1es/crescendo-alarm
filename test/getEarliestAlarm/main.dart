import 'cases.dart';
import 'scheduling.dart'; 

void main() {
  for (int i = 0; i < testCases.length; i++) {
    List<DateTime> week = testCases[i].sublist(1);
    DateTime expected = testCases[i][0];

    int sleepGoal = 8;

    DateTime result = getEarliestEvent(week, sleepGoal);
    if (result == expected) {
      print('Test $i erfolgreich! Erwartetes Ergebnis: $expected, erhaltenes Ergebnis: $result');
    } else {
      print('Test $i fehlgeschlagen! Erwartetes Ergebnis: $expected, erhaltenes Ergebnis: $result');
    }
  }
}

