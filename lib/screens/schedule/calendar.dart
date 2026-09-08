part of 'screen_schedule.dart';

List<Calendar> calendars = [];
final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

Future initCalendars(AppState appState) async {
  debugPrint("=====initCalendars");

  Result result = Result();

  try {
    result = await _deviceCalendarPlugin.retrieveCalendars();
  } catch (e) {
    debugPrint("=====initCalendars: Error retrieving calendars: $e");
  }

  for (ResultError error in result.errors) {
    debugPrint(
        '======initCalendars: Error init calendars: ${error.errorCode} ${error.errorMessage}');
  }

  if (result.isSuccess) {
    calendars = result.data;
    for (Calendar calendar in calendars) {
      debugPrint("======initCalendars: Found calendar ${calendar.name}");
    }
    if (calendars.isNotEmpty) {
      appState.calendarsInitialized = true;
    }
  } else {
    debugPrint("=====initCalendars: Error initializing calendars");
  }
}

Future<List<Meeting>> getCalendarEntries(
    AppState appState, DateTime startTime, DateTime endTime) async {
  String timeZone = appState.currentTimeZone;
  Color selectedColor;
  List<Meeting> meetingCollection = [];

  // To really retrieve one week one day has to be subtracted, else on other places 6 days or 13 days would be specified
  debugPrint(
      "=====getCalendarEntries: Retrieving calendar entries from $startTime to ${endTime.subtract(const Duration(days: 1))}");
  final params = RetrieveEventsParams(
    startDate: startTime,
    endDate: endTime.subtract(const Duration(days: 1)),
  );

  debugPrint(
      '======getCalendarEntries: Calendars list has size ${calendars.length}.');

  for (Calendar calendar in calendars) {
    final result =
        await _deviceCalendarPlugin.retrieveEvents(calendar.id, params);

    for (ResultError error in result.errors) {
      debugPrint(
          '======getCalendarEntries: Error check event exist: ${error.errorCode} ${error.errorMessage}');
    }

    selectedColor = Color(calendar.color!);

    if (result.isSuccess) {
      for (Event event in result.data ?? []) {
        Meeting meeting =
            eventToMeeting(event, selectedColor, timeZone, timeZone);
        try {
          if (!appState.meetings.contains(meeting)) {
            meetingCollection.add(meeting);
          } else {
            debugPrint(
                "=====getCalendarEntries: Meeting ${meeting.eventName} already exists in list, skipping");
          }
        } catch (e) {
          debugPrint("=====getCalendarEntries: Error add meeting to list: $e");
        }
      }
    }
  }

  debugPrint(
      "=====getCalendarEntries: Read ${meetingCollection.length} meetings from OS");

  return meetingCollection;
}

// For future development
// Future<bool> addToCalendar(Meeting meeting) async {
//   var event = meetingToEvent(meeting);
//   Result<String>? result =
//       await _deviceCalendarPlugin.createOrUpdateEvent(event);
//
//   for (ResultError error in result?.errors ?? []) {
//     debugPrint(
//         '======getCalendarEntries: Error add event to calendar: ${error.errorCode} ${error.errorMessage}');
//   }
//
//   if (result?.isSuccess ?? false) {
//     debugPrint(
//         '======getCalendarEntries: Add event to calendar result: ${result?.data}');
//     return true;
//   }
//
//   return false;
// }

bool isSameDate(DateTime date1, DateTime date2) {
  final bool status = date1.year == date2.year &&
      date1.month == date2.month &&
      date1.day == date2.day;

  debugPrint(
      "=====isSameDate: ${date1.year}.${date1.month}.${date1.day} == ${date2.year}.${date2.month}.${date2.day} : $status");

  return status;
}

tz.Location getLocationFromAbbreviation(String abbreviation) {
  // Map Posix to Olson Format
  final Map<String, String> timeZoneMapping = {
    'ACDT': 'Australia/Adelaide',
    'ACST': 'Australia/Darwin',
    'ACT': 'America/Rio_Branco',
    'ADT': 'America/Halifax',
    'AEDT': 'Australia/Sydney',
    'AEST': 'Australia/Brisbane',
    'AFT': 'Asia/Kabul',
    'AKDT': 'America/Juneau',
    'AKST': 'America/Anchorage',
    'AMST': 'America/Campo_Grande',
    'AMT': 'America/Boa_Vista',
    'ART': 'America/Argentina/Buenos_Aires',
    'AST': 'Asia/Riyadh',
    'AWST': 'Australia/Perth',
    'AZOST': 'Atlantic/Azores',
    'AZT': 'Asia/Baku',
    'BDT': 'Asia/Dhaka',
    'BIOT': 'Indian/Chagos',
    'BIT': 'Pacific/Pago_Pago',
    'BOT': 'America/La_Paz',
    'BRST': 'America/Sao_Paulo',
    'BRT': 'America/Sao_Paulo',
    'BST': 'Europe/London',
    'BTT': 'Asia/Thimphu',
    'CAT': 'Africa/Harare',
    'CCT': 'Indian/Cocos',
    'CDT': 'America/Chicago',
    'CEST': 'Europe/Berlin',
    'CET': 'Europe/Berlin',
    'CHADT': 'Pacific/Chatham',
    'CHAST': 'Pacific/Chatham',
    'CHOT': 'Asia/Choibalsan',
    'CHST': 'Pacific/Guam',
    'CHUT': 'Pacific/Chuuk',
    'CIST': 'America/Curacao',
    'CKT': 'Pacific/Rarotonga',
    'CLST': 'America/Santiago',
    'CLT': 'America/Santiago',
    'COST': 'America/Bogota',
    'COT': 'America/Bogota',
    'CST': 'America/Chicago',
    'CT': 'Asia/Shanghai',
    'CVT': 'Atlantic/Cape_Verde',
    'CWST': 'Australia/Eucla',
    'CXT': 'Indian/Christmas',
    'DAVT': 'Antarctica/Davis',
    'DDUT': 'Antarctica/DumontDUrville',
    'DFT': 'Europe/Paris',
    'EASST': 'Pacific/Easter',
    'EAST': 'Pacific/Easter',
    'EAT': 'Africa/Nairobi',
    'ECT': 'Europe/Amsterdam',
    'EDT': 'America/New_York',
    'EEST': 'Europe/Istanbul',
    'EET': 'Europe/Istanbul',
    'EGST': 'America/Danmarkshavn',
    'EGT': 'America/Scoresbysund',
    'EST': 'America/New_York',
    'ET': 'America/New_York',
    'FET': 'Europe/Minsk',
    'FJT': 'Pacific/Fiji',
    'FKST': 'Atlantic/Stanley',
    'FKT': 'Atlantic/Stanley',
    'FNT': 'America/Noronha',
    'GALT': 'Pacific/Galapagos',
    'GAMT': 'Pacific/Gambier',
    'GET': 'Asia/Tbilisi',
    'GFT': 'America/Cayenne',
    'GILT': 'Pacific/Tarawa',
    'GIT': 'Pacific/Guadalcanal',
    'GMT': 'Europe/London',
    'GST': 'Asia/Dubai',
    'GYT': 'America/Guyana',
    'HDT': 'Pacific/Honolulu',
    'HAEC': 'Europe/Paris',
    'HST': 'Pacific/Honolulu',
    'ICT': 'Asia/Bangkok',
    'IDT': 'Asia/Jerusalem',
    'IOT': 'Indian/Chagos',
    'IRDT': 'Asia/Tehran',
    'IRKT': 'Asia/Irkutsk',
    'IRST': 'Asia/Tehran',
    'IST': 'Asia/Kolkata',
    'JST': 'Asia/Tokyo',
    'KGT': 'Asia/Bishkek',
    'KOST': 'Pacific/Kosrae',
    'KRAT': 'Asia/Krasnoyarsk',
    'KST': 'Asia/Seoul',
    'LHST': 'Australia/Lord_Howe',
    'LINT': 'Pacific/Kiritimati',
    'MAGT': 'Asia/Magadan',
    'MART': 'Pacific/Marquesas',
    'MAWT': 'Antarctica/Mawson',
    'MDT': 'America/Denver',
    'MET': 'Europe/Paris',
    'MEST': 'Europe/Paris',
    'MHT': 'Pacific/Majuro',
    'MIST': 'Antarctica/Macquarie',
    'MIT': 'Pacific/Apia',
    'MMT': 'Asia/Rangoon',
    'MSK': 'Europe/Moscow',
    'MST': 'America/Denver',
    'MUT': 'Indian/Mauritius',
    'MVT': 'Indian/Maldives',
    'MYT': 'Asia/Kuala_Lumpur',
    'NCT': 'Pacific/Noumea',
    'NDT': 'America/St_Johns',
    'NFT': 'Pacific/Norfolk',
    'NPT': 'Asia/Kathmandu',
    'NST': 'America/St_Johns',
    'NT': 'Pacific/Midway',
    'NUT': 'Pacific/Niue',
    'NZDT': 'Pacific/Auckland',
    'NZST': 'Pacific/Auckland',
    'OMST': 'Asia/Omsk',
    'ORAT': 'Asia/Oral',
    'PDT': 'America/Los_Angeles',
    'PET': 'America/Lima',
    'PETT': 'Asia/Kamchatka',
    'PGT': 'Pacific/Port_Moresby',
    'PHOT': 'Pacific/Enderbury',
    'PHT': 'Asia/Manila',
    'PKT': 'Asia/Karachi',
    'PMDT': 'America/Miquelon',
    'PMST': 'America/Miquelon',
    'PONT': 'Pacific/Pohnpei',
    'PST': 'America/Los_Angeles',
    'PWT': 'Pacific/Palau',
    'PYST': 'America/Asuncion',
    'PYT': 'America/Asuncion',
    'RET': 'Indian/Reunion',
    'ROTT': 'Antarctica/Rothera',
    'SAKT': 'Asia/Sakhalin',
    'SAMT': 'Europe/Samara',
    'SAST': 'Africa/Johannesburg',
    'SBT': 'Pacific/Guadalcanal',
    'SCT': 'Indian/Mahe',
    'SGT': 'Asia/Singapore',
    'SLST': 'Asia/Colombo',
    'SRET': 'Asia/Srednekolymsk',
    'SRT': 'America/Paramaribo',
    'SST': 'Pacific/Pago_Pago',
    'SYOT': 'Antarctica/Syowa',
    'TAHT': 'Pacific/Tahiti',
    'THA': 'Asia/Bangkok',
    'TFT': 'Indian/Kerguelen',
    'TJT': 'Asia/Dushanbe',
    'TKT': 'Pacific/Fakaofo',
    'TLT': 'Asia/Dili',
    'TMT': 'Asia/Ashgabat',
    'TRT': 'Europe/Istanbul',
    'TOT': 'Pacific/Tongatapu',
    'TVT': 'Pacific/Funafuti',
    'ULAST': 'Asia/Ulaanbaatar',
    'ULAT': 'Asia/Ulaanbaatar',
    'UTC': 'Etc/UTC',
    'UYST': 'America/Montevideo',
    'UYT': 'America/Montevideo',
    'UZT': 'Asia/Tashkent',
    'VET': 'America/Caracas',
    'VLAT': 'Asia/Vladivostok',
    'VOLT': 'Europe/Volgograd',
    'VOST': 'Antarctica/Vostok',
    'VUT': 'Pacific/Efate',
    'WAKT': 'Pacific/Wake',
    'WAST': 'Africa/Windhoek',
    'WAT': 'Africa/Lagos',
    'WEST': 'Europe/Lisbon',
    'WET': 'Europe/Lisbon',
    'WIT': 'Asia/Jakarta',
    'WGST': 'America/Godthab',
    'WGT': 'America/Godthab',
    'WST': 'Australia/Perth',
    'YAKT': 'Asia/Yakutsk',
    'YEKT': 'Asia/Yekaterinburg',
  };

  final String? timeZoneName = timeZoneMapping[abbreviation];
  if (timeZoneName != null) {
    return tz.getLocation(timeZoneName);
  } else {
    return tz.getLocation('Etc/UTC');
  }
}
