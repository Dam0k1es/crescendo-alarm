List<List<DateTime>> testCases = [
  // Normal day time
  [
    DateTime(2020, 6, 29, 12, 0),   // Expected earliest time for week 0
    DateTime(2020, 6, 29, 12, 0),   // 12:00 AM
    DateTime(2020, 6, 30, 13, 0),   // 01:00 PM
    DateTime(2020, 7, 1, 14, 0),    // 02:00 PM
    DateTime(2020, 7, 2, 15, 0),    // 03:00 PM
    DateTime(2020, 7, 3, 12, 30),   // 12:30 AM
    DateTime(2020, 7, 4, 14, 30),   // 02:30 PM
  ],
  // Crosses day boundary
  [
    DateTime(2021, 6, 30, 23, 0),   // Expected earliest time for week 1
    DateTime(2021, 6, 29, 1, 0),    // 01:00 AM
    DateTime(2021, 6, 30, 23, 0),   // 11:00 PM
    DateTime(2021, 7, 1, 14, 0),    // 02:00 PM
    DateTime(2021, 7, 2, 15, 0),    // 03:00 PM
    DateTime(2021, 7, 3, 12, 30),   // 12:30 PM
    DateTime(2021, 7, 4, 14, 30),   // 02:30 PM
  ],
  // Near day boundary
  [
    DateTime(2022, 6, 30, 24, 0),   // Expected earliest time for week 2
    DateTime(2022, 6, 29, 1, 0),    // 01:00 AM
    DateTime(2022, 6, 30, 24, 0),   // 12:00 PM
    DateTime(2022, 7, 1, 2, 0),     // 02:00 AM
    DateTime(2022, 7, 2, 3, 0),     // 03:00 AM
    DateTime(2022, 7, 3, 12, 30),   // 12:30 AM
    DateTime(2022, 7, 4, 14, 30),   // 02:30 PM
  ],
  // Far before day boundary, one value out of sleep goal expected
  [
    DateTime(2023, 6, 30, 20, 0),   // Expected earliest time for week 3
    DateTime(2023, 6, 29, 1, 0),    // 01:00 AM
    DateTime(2023, 6, 30, 20, 0),   // 08:00 PM
    DateTime(2023, 7, 1, 21, 0),    // 09:00 PM
    DateTime(2023, 7, 2, 22, 0),    // 10:00 PM
    DateTime(2023, 7, 3, 23, 30),   // 11:30 PM
    DateTime(2023, 7, 4, 14, 30),   // 02:30 PM
  ],
  // Shortly after day boundary, rest expected to usual wake-up times
  [
    DateTime(2024, 6, 29, 1, 0),    // Expected earliest time for week 4
    DateTime(2024, 6, 29, 1, 0),    // 01:00 AM
    DateTime(2024, 6, 30, 6, 0),    // 06:00 AM
    DateTime(2024, 7, 1, 6, 30),    // 06:30 AM
    DateTime(2024, 7, 2, 7, 0),     // 07:00 AM
    DateTime(2024, 7, 3, 6, 15),    // 06:15 AM
    DateTime(2024, 7, 4, 8, 30),    // 08:30 AM
  ],
  // Late night alarms, early hours
  [
    DateTime(2025, 6, 29, 0, 0),    // Expected earliest time for week 5
    DateTime(2025, 6, 29, 0, 0),    // 12:00 AM
    DateTime(2025, 6, 30, 2, 0),    // 02:00 AM
    DateTime(2025, 7, 1, 4, 0),     // 04:00 AM
    DateTime(2025, 7, 2, 6, 0),     // 06:00 AM
    DateTime(2025, 7, 3, 8, 0),     // 08:00 AM
    DateTime(2025, 7, 4, 10, 0),    // 10:00 AM
  ],
  // Weekend alarms, varying sleep goals
  [
    DateTime(2026, 7, 1, 8, 0),   // Expected earliest time for week 6
    DateTime(2026, 6, 29, 12, 0),   // 12:00 AM
    DateTime(2026, 7, 1, 8, 0),     // 08:00 AM
    DateTime(2026, 7, 2, 9, 0),     // 09:00 AM
    DateTime(2026, 7, 3, 10, 0),    // 10:00 AM
    DateTime(2026, 7, 4, 11, 0),    // 11:00 AM
    DateTime(2026, 7, 5, 12, 0),    // 12:00 PM
  ],
  // Alarms during holidays
  [
    DateTime(2027, 12, 25, 8, 0),   // Expected earliest time for week 7
    DateTime(2027, 12, 24, 22, 0),  // 10:00 PM
    DateTime(2027, 12, 25, 8, 0),   // 08:00 AM
    DateTime(2027, 12, 26, 9, 0),   // 09:00 AM
    DateTime(2027, 12, 27, 10, 0),  // 10:00 AM
    DateTime(2027, 12, 28, 11, 0),  // 11:00 AM
    DateTime(2027, 12, 29, 12, 0),  // 12:00 PM
  ],
  // Alarms during special events
  [
    DateTime(2028, 2, 14, 7, 0),    // Expected earliest time for week 8
    DateTime(2028, 2, 13, 18, 0),   // 06:00 PM
    DateTime(2028, 2, 14, 7, 0),    // 07:00 AM
    DateTime(2028, 2, 15, 8, 0),    // 08:00 AM
    DateTime(2028, 2, 16, 9, 0),    // 09:00 AM
    DateTime(2028, 2, 17, 10, 0),   // 10:00 AM
    DateTime(2028, 2, 18, 11, 0),   // 11:00 AM
  ],
  // Alarms during vacation
  [
    DateTime(2029, 8, 1, 6, 0),     // Expected earliest time for week 9
    DateTime(2029, 7, 31, 22, 0),   // 10:00 PM
    DateTime(2029, 8, 1, 6, 0),     // 06:00 AM
    DateTime(2029, 8, 2, 7, 0),     // 07:00 AM
    DateTime(2029, 8, 3, 8, 0),     // 08:00 AM
    DateTime(2029, 8, 4, 9, 0),     // 09:00 AM
    DateTime(2029, 8, 5, 10, 0),    // 10:00 AM
  ],
    [
    DateTime(2030, 6, 29, 2, 0),    // Expected earliest time for week 10
    DateTime(2030, 6, 29, 2, 0),    // 02:00 AM
    DateTime(2030, 6, 30, 3, 0),    // 03:00 AM
    DateTime(2030, 7, 1, 4, 0),     // 04:00 AM
    DateTime(2030, 7, 2, 5, 0),     // 05:00 AM
    DateTime(2030, 7, 3, 6, 0),     // 06:00 AM
    DateTime(2030, 7, 4, 7, 0),     // 07:00 AM
  ],
  // Weekend alarms, various times
  [
    DateTime(2031, 6, 29, 8, 0),   // Expected earliest time for week 11
    DateTime(2031, 6, 29, 8, 0),    // 08:00 AM
    DateTime(2031, 7, 1, 12, 0),    // 12:00 PM
    DateTime(2031, 7, 2, 9, 0),     // 09:00 AM
    DateTime(2031, 7, 3, 10, 0),    // 10:00 AM
    DateTime(2031, 7, 4, 11, 0),    // 11:00 AM
    DateTime(2031, 7, 5, 8, 0),     // 08:00 AM
  ],
  // Early morning alarms, weekday
  [
    DateTime(2032, 6, 29, 4, 0),    // Expected earliest time for week 12
    DateTime(2032, 6, 29, 4, 0),    // 04:00 AM
    DateTime(2032, 6, 30, 5, 0),    // 05:00 AM
    DateTime(2032, 7, 1, 6, 0),     // 06:00 AM
    DateTime(2032, 7, 2, 7, 0),     // 07:00 AM
    DateTime(2032, 7, 3, 8, 0),     // 08:00 AM
    DateTime(2032, 7, 4, 9, 0),     // 09:00 AM
  ],
  // Alarms during a long weekend
  [
    DateTime(2033, 6, 29, 8, 0),    // Expected earliest time for week 13
    DateTime(2033, 6, 29, 8, 0),    // 08:00 AM
    DateTime(2033, 7, 1, 10, 0),    // 10:00 AM
    DateTime(2033, 7, 2, 9, 0),     // 09:00 AM
    DateTime(2033, 7, 3, 11, 0),    // 11:00 AM
    DateTime(2033, 7, 4, 12, 0),    // 12:00 PM
    DateTime(2033, 7, 5, 8, 0),     // 08:00 AM
  ],
  // Alarms during a short holiday
  [
    DateTime(2034, 12, 25, 9, 0),   // Expected earliest time for week 14
    DateTime(2034, 12, 25, 9, 0),   // 09:00 AM
    DateTime(2034, 12, 26, 10, 0),  // 10:00 AM
    DateTime(2034, 12, 27, 11, 0),  // 11:00 AM
    DateTime(2034, 12, 28, 12, 0),  // 12:00 PM
    DateTime(2034, 12, 29, 13, 0),  // 01:00 PM
    DateTime(2034, 12, 30, 14, 0),  // 02:00 PM
  ],
  // Alarms during a special event
  [
    DateTime(2035, 2, 14, 8, 0),    // Expected earliest time for week 15
    DateTime(2035, 2, 14, 8, 0),    // 08:00 AM
    DateTime(2035, 2, 15, 9, 0),    // 09:00 AM
    DateTime(2035, 2, 16, 10, 0),   // 10:00 AM
    DateTime(2035, 2, 17, 11, 0),   // 11:00 AM
    DateTime(2035, 2, 18, 12, 0),   // 12:00 PM
    DateTime(2035, 2, 19, 13, 0),   // 01:00 PM
  ],
  // Alarms during summer vacation
  [
    DateTime(2036, 8, 1, 7, 0),     // Expected earliest time for week 16
    DateTime(2036, 8, 1, 7, 0),     // 07:00 AM
    DateTime(2036, 8, 2, 8, 0),     // 08:00 AM
    DateTime(2036, 8, 3, 9, 0),     // 09:00 AM
    DateTime(2036, 8, 4, 10, 0),    // 10:00 AM
    DateTime(2036, 8, 5, 11, 0),    // 11:00 AM
    DateTime(2036, 8, 6, 12, 0),    // 12:00 PM
  ],
];
