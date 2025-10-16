// lib/screens/venue_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'category_page.dart'; // keep your existing page

const kGreen = Color(0xFF787E65);

class VenuePage extends StatefulWidget {
  final String placeId; // required for details
  final String name; // title
  final String? image; // can be asset path or http url
  final String description; // fallback description

  const VenuePage({
    super.key,
    required this.placeId,
    required this.name,
    this.image,
    required this.description,
  });

  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage> {
  bool _loading = true;
  String? _error;

  // Details data
  String? _address;
  String? _editorial;

  // Hours-related
  bool? _openNow;
  List<String> _weekdayText =
      const []; // Google’s weekday_text (Mon..Sun usually)
  List<dynamic> _periods = const []; // structured hours for precise calc
  int? _utcOffsetMinutes; // minutes from Google

  // Business & types
  String?
  _businessStatus; // OPERATIONAL, CLOSED_TEMPORARILY, CLOSED_PERMANENTLY
  List<String> _types = const [];

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final key = dotenv.maybeGet('GOOGLE_API_KEY') ?? '';
      if (key.isEmpty) {
        throw Exception('Missing GOOGLE_API_KEY in .env');
      }
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': widget.placeId,
          'fields': [
            'formatted_address',
            'editorial_summary',
            'name',
            'types',
            'business_status',
            'utc_offset', // ✅ correct field
            'opening_hours',
            'current_opening_hours', // preferred
          ].join(','),
          'key': key,
        },
      );

      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['status'] != 'OK') {
        throw Exception(
          'Details error: ${j['status']} ${j['error_message'] ?? ''}',
        );
      }

      final res = (j['result'] as Map<String, dynamic>?) ?? {};

      // Prefer current_opening_hours when available
      final currentOpening =
          (res['current_opening_hours'] as Map<String, dynamic>?) ?? {};
      final opening = currentOpening.isNotEmpty
          ? currentOpening
          : (res['opening_hours'] as Map<String, dynamic>?) ?? {};

      final editorial =
          (res['editorial_summary'] as Map<String, dynamic>?)?['overview']
              as String?;
      final weekdayText =
          (opening['weekday_text'] as List?)?.cast<String>() ?? const [];
      final periods = (opening['periods'] as List?) ?? const [];
      final openNow = opening['open_now'] as bool?;
      final utcOffset = res['utc_offset'] as int?;
      final types = (res['types'] as List?)?.cast<String>() ?? const [];
      final businessStatus = res['business_status'] as String?;

      setState(() {
        _address = res['formatted_address'] as String?;
        _editorial = editorial;
        _openNow = openNow;
        _weekdayText = weekdayText;
        _periods = periods;
        _utcOffsetMinutes = utcOffset;
        _types = types;
        _businessStatus = businessStatus;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ---------- Helpers: type detection & special cases ----------

  bool get _isAirport {
    if (_types.any((t) => t.toLowerCase() == 'airport')) return true;
    final n = widget.name.toLowerCase();
    return n.contains('airport');
  }

  bool get _isStadium {
    return _types.any((t) => t.toLowerCase() == 'stadium') ||
        widget.name.toLowerCase().contains('stadium') ||
        widget.name.toLowerCase().contains('arena') ||
        widget.name.toLowerCase().contains('park'); // e.g., Al-Awwal Park
  }

  bool get _isTempClosed => _businessStatus == 'CLOSED_TEMPORARILY';
  bool get _isPermClosed => _businessStatus == 'CLOSED_PERMANENTLY';

  bool get _hasAnyHours =>
      (_weekdayText.isNotEmpty && _weekdayText.length >= 1) ||
      (_periods.isNotEmpty);

  bool get _looks24h =>
      _weekdayText.any((l) => l.toLowerCase().contains('open 24 hours'));

  // Use Google offset when present; otherwise device zone offset (minutes)
  int get _effectiveOffsetMinutes =>
      _utcOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes;

  // ---------- Time math using periods + UTC offset ----------

  /// Converts Google "day" (0=Sunday..6=Saturday) + "HHMM" to local DateTime.
  DateTime _toLocalDateTime(int targetDay, String hhmm) {
    final offset = Duration(minutes: _effectiveOffsetMinutes);
    final nowLocal = DateTime.now().toUtc().add(offset);

    // Find date of the next targetDay relative to local today (0=Sun..6=Sat)
    final todayIdx = (nowLocal.weekday % 7); // Sun=0 .. Sat=6
    int diff = (targetDay - todayIdx);
    if (diff < 0) diff += 7;
    final date = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    ).add(Duration(days: diff));

    // Parse HHMM (24h)
    final hh = int.parse(hhmm.substring(0, 2));
    final mm = int.parse(hhmm.substring(2, 4));

    return DateTime(date.year, date.month, date.day, hh, mm);
  }

  // earliest opening window that starts "today" (local)
  DateTime? _firstOpenToday(List<_OpenWindow> windows, DateTime nowLocal) {
    DateTime? first;
    for (final w in windows) {
      final isSameDay =
          w.openDT.year == nowLocal.year &&
          w.openDT.month == nowLocal.month &&
          w.openDT.day == nowLocal.day;
      if (isSameDay) {
        if (first == null || w.openDT.isBefore(first)) first = w.openDT;
      }
    }
    return first;
  }

  /// Returns precise status text like:
  /// - "Open · Closes 2:00 AM"
  /// - "Closed · Opens 9:00 AM"
  /// Falls back to weekday_text when periods not available.
  String _preciseStatusNow() {
    // Handle business_status quickly
    if (_isTempClosed) return 'Temporarily closed';
    if (_isPermClosed) return 'Permanently closed';

    // Airports: if no hours at all, treat as open 24h (no dropdown)
    if (_isAirport && !_hasAnyHours) {
      return 'Open 24 hours';
    }
    // Stadiums: if no hours, event-based (no dropdown)
    if (_isStadium && !_hasAnyHours) {
      return 'Hours vary by event';
    }

    // If periods exist, use them for accurate next open/close
    if (_periods.isNotEmpty) {
      final offset = Duration(minutes: _effectiveOffsetMinutes);
      final nowLocal = DateTime.now().toUtc().add(offset);

      // Build windows (open, close)
      final windows = <_OpenWindow>[];
      for (final p in _periods) {
        final m = p as Map<String, dynamic>;

        final open = (m['open'] ?? {}) as Map<String, dynamic>;
        final close = (m['close'] ?? {}) as Map<String, dynamic>;

        if (!open.containsKey('day') || !open.containsKey('time')) continue;

        final openDT = _toLocalDateTime(
          (open['day'] as num).toInt(),
          (open['time'] as String),
        );
        DateTime? closeDT;
        if (close.containsKey('day') && close.containsKey('time')) {
          closeDT = _toLocalDateTime(
            (close['day'] as num).toInt(),
            (close['time'] as String),
          );
          // overnight close rolls to the next day
          if (!closeDT.isAfter(openDT)) {
            closeDT = closeDT.add(const Duration(days: 1));
          }
        } else {
          // No close → treat as 24h window from open to next day
          closeDT = openDT.add(const Duration(days: 1));
        }

        // duplicate 1 extra week forward to cover wrap-around
        for (int k = 0; k < 2; k++) {
          windows.add(
            _OpenWindow(
              openDT: openDT.add(Duration(days: 7 * k)),
              closeDT: closeDT!.add(Duration(days: 7 * k)),
            ),
          );
        }
      }

      windows.sort((a, b) => a.openDT.compareTo(b.openDT));

      // ---- pre-check: before today's first opening? → Closed · Opens HH:MM
      final firstToday = _firstOpenToday(windows, nowLocal);
      if (firstToday != null && nowLocal.isBefore(firstToday)) {
        return 'Closed · Opens ${_formatClock(firstToday)}';
      }

      // Determine if currently open and what closes next
      for (final w in windows) {
        if (nowLocal.isBefore(w.openDT)) {
          // Not yet open → next open is w.openDT
          return 'Closed · Opens ${_formatClock(w.openDT)}';
        }
        if (nowLocal.isAfter(w.openDT) && nowLocal.isBefore(w.closeDT)) {
          // Currently open → show close time
          return 'Open · Closes ${_formatClock(w.closeDT)}';
        }
      }

      // No future window matched: consider closed without known next open
      return 'Closed';
    }

    // Fallback to weekday_text + open_now heuristic
    return _statusFromWeekdayTextFallback();
  }

  String _formatClock(DateTime dtLocal) {
    final hour = dtLocal.hour % 12 == 0 ? 12 : dtLocal.hour % 12;
    final min = dtLocal.minute.toString().padLeft(2, '0');
    final ampm = dtLocal.hour < 12 ? 'AM' : 'PM';
    return '$hour:$min $ampm';
  }

  // ---------- Fallback when periods/offset not available ----------

  /// "9:00 AM – 11:00 PM" → ["9:00 AM","11:00 PM"]
  List<String>? _splitRange(String s) {
    final m = RegExp(
      r'(\d{1,2}:\d{2}(?:\s?[AP]M)?)\s*[–-]\s*(\d{1,2}:\d{2}\s?[AP]M)',
    ).firstMatch(s);
    if (m == null) return null;
    var start = m.group(1)!.trim();
    var end = m.group(2)!.trim();

    // If start misses AM/PM but end has it, copy it.
    final meridiem = RegExp(r'([AP]M)').firstMatch(end)?.group(1);
    if (meridiem != null && !RegExp(r'[AP]M').hasMatch(start)) {
      start = '$start $meridiem';
    }
    return [start, end];
  }

  String _normalizeRangeText(String range) {
    final parts = _splitRange(range);
    if (parts == null) return range;
    return '${parts[0]} – ${parts[1]}';
  }

  String _statusFromWeekdayTextFallback() {
    if (_isTempClosed) return 'Temporarily closed';
    if (_isPermClosed) return 'Permanently closed';
    if (_isAirport && !_hasAnyHours) return 'Open 24 hours';
    if (_isStadium && !_hasAnyHours) return 'Hours vary by event';
    if (_weekdayText.isEmpty) return 'Hours unavailable';

    final now = DateTime.now();
    final today = now.weekday % 7; // 0 Sun..6 Sat
    const labelsSunFirst = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    final line = _weekdayText.firstWhere(
      (l) => l.toLowerCase().startsWith(labelsSunFirst[today].toLowerCase()),
      orElse: () => '',
    );
    final timePart = line.contains(':')
        ? line.split(':').sublist(1).join(':').trim()
        : '';
    if (timePart.isEmpty || timePart.toLowerCase() == 'closed') {
      final nextOpen = _nextOpenFromWeekdayText(today);
      return nextOpen == null ? 'Closed' : 'Closed · Opens $nextOpen';
    }

    final range = _normalizeRangeText(timePart);
    final parts = _splitRange(range);

    if (_openNow == false) {
      final nextOpen = _nextOpenFromWeekdayText(today);
      return nextOpen == null ? 'Closed' : 'Closed · Opens $nextOpen';
    }

    if (parts == null) return 'Open';
    return 'Open · Closes ${parts[1]}';
  }

  String? _nextOpenFromWeekdayText(int todayIndex) {
    const labels = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    for (int i = 0; i < 7; i++) {
      final idx = (todayIndex + i) % 7;
      final day = labels[idx];
      final line = _weekdayText.firstWhere(
        (l) => l.toLowerCase().startsWith(day.toLowerCase()),
        orElse: () => '',
      );
      if (line.isEmpty) continue;
      final timePart = line.contains(':')
          ? line.split(':').sublist(1).join(':').trim()
          : '';
      if (timePart.isEmpty || timePart.toLowerCase() == 'closed') continue;
      final parts = _splitRange(timePart);
      if (parts == null) continue;
      return parts[0];
    }
    return null;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final summary = (_editorial?.trim().isNotEmpty == true)
        ? _editorial!.trim()
        : widget.description.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.name,
          style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (widget.image != null && widget.image!.isNotEmpty)
                  _buildHeaderImage(widget.image!),

                // Summary (≈2.5 lines → 3 with tight line height)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    summary,
                    style: const TextStyle(
                      color: Colors.black87,
                      height: 1.25,
                      fontSize: 16,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                if (_address?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _address!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Opening hours card
                _hoursCard(),

                const SizedBox(height: 16),

                // Floor map (your placeholder section)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "Floor Map",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEFE3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.map_outlined,
                        size: 48,
                        color: Colors.black45,
                      ),
                    ),
                  ),
                ),

                // Explore categories (your exact UI)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "Explore Categories",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _categoryCard(context, "Shops", "—", "images/Shops.png"),
                      const SizedBox(width: 12),
                      _categoryCard(context, "Cafes", "—", "images/Cafes.jpg"),
                      const SizedBox(width: 12),
                      _categoryCard(
                        context,
                        "Restaurants",
                        "—",
                        "images/restaurants.jpeg",
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderImage(String src) {
    final isHttp = src.startsWith('http');
    const h = 200.0;
    return isHttp
        ? Image.network(
            src,
            height: h,
            width: double.infinity,
            fit: BoxFit.cover,
          )
        : Image.asset(
            src,
            height: h,
            width: double.infinity,
            fit: BoxFit.cover,
          );
  }

  Widget _hoursCard() {
    // Build Sunday-first order from Google’s weekday_text (usually Mon..Sun)
    List<String> sunFirst = _weekdayText;
    if (_weekdayText.length == 7 &&
        _weekdayText.first.toLowerCase().startsWith('monday')) {
      // rotate to Sunday-first
      sunFirst = [_weekdayText[6], ..._weekdayText.take(6)];
    }

    final statusText = _preciseStatusNow();

    // No dropdown for: Temporarily/Permanently Closed, 24h, event-based, or if no lines exist.
    final noDropdown =
        _isTempClosed ||
        _isPermClosed ||
        statusText == 'Open 24 hours' ||
        statusText == 'Hours vary by event' ||
        sunFirst.isEmpty;

    // Build a title where only "Open"/"Closed"/"Temporarily closed"/"Permanently closed" is colored
    final statusTitle = _statusTitleRich(statusText);

    if (noDropdown) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.05),
        elevation: 3,
        child: ListTile(
          leading: const Icon(Icons.schedule, color: kGreen),
          title: statusTitle,
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      shadowColor: Colors.black.withOpacity(0.05),
      elevation: 3,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          leading: const Icon(Icons.schedule, color: kGreen),
          title: statusTitle, // colored keyword only
          iconColor: kGreen,
          collapsedIconColor: kGreen,
          childrenPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          children: sunFirst.map((line) {
            final parts = line.split(':');
            final day = parts.first;
            final timePart = parts.length > 1
                ? parts.sublist(1).join(':').trim()
                : 'Closed';
            final fixed = (timePart.toLowerCase() == 'closed')
                ? 'Closed'
                : _normalizeRangeText(timePart);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(day, style: const TextStyle(fontSize: 15)),
                  Text(
                    fixed,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Renders "Open · Closes 2:00 AM" with only "Open" green (or "Closed" red)
  Widget _statusTitleRich(String statusText) {
    // By default we split a colored "keyword" from a neutral "rest".
    // For special phrases we color the whole thing.
    String leading;
    String trailing = '';
    Color? color;

    // ---- special full-phrase coloring ----
    if (statusText == 'Open 24 hours') {
      leading = statusText;
      color = Colors.green[800]; // all green ✅
    } else if (statusText == 'Hours vary by event') {
      leading = statusText;
      color = const Color.fromARGB(255, 239, 139, 0); // orange / dark yellow ✅
    } else if (statusText.startsWith('Open')) {
      leading = 'Open';
      trailing = statusText.substring('Open'.length);
      color = Colors.green[800]; // only "Open" green
    } else if (statusText.startsWith('Closed')) {
      leading = 'Closed';
      trailing = statusText.substring('Closed'.length);
      color = Colors.red[700]; // only "Closed" red
    } else if (statusText.startsWith('Temporarily closed')) {
      leading = 'Temporarily closed';
      trailing = statusText.substring('Temporarily closed'.length);
      color = Colors.red[700];
    } else if (statusText.startsWith('Permanently closed')) {
      leading = 'Permanently closed';
      trailing = statusText.substring('Permanently closed'.length);
      color = Colors.red[700];
    } else {
      // neutral fallbacks ("Hours unavailable", etc.)
      leading = statusText;
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: leading,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? Colors.black87,
            ),
          ),
          if (trailing.isNotEmpty)
            const TextSpan(
              text: '', // spacer handled by the dot in the string itself
            ),
          if (trailing.isNotEmpty)
            const TextSpan(text: ''), // keep structure identical
          if (trailing.isNotEmpty)
            const TextSpan(), // (no visible effect; preserves your design)
          if (trailing.isNotEmpty)
            TextSpan(
              text: trailing,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
        ],
      ),
    );
  }

  // same card widget you had
  static Widget _categoryCard(
    BuildContext context,
    String title,
    String subtitle,
    String image,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CategoryPage(categoryName: title)),
        );
      },
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: Image.asset(
                image,
                height: 100,
                width: 140,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple window model for precise time calc
class _OpenWindow {
  final DateTime openDT;
  final DateTime closeDT;
  _OpenWindow({required this.openDT, required this.closeDT});
}
