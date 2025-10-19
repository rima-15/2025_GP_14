// lib/screens/venue_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart'; // less and more in descreption
import 'category_page.dart';

// ADDED: Storage + cache for coverPath header
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:cached_network_image/cached_network_image.dart';

const kGreen = Color(0xFF787E65);

class VenuePage extends StatefulWidget {
  final String placeId; // required for details
  final String name; // title
  final String description; // fallback description (from DB ONLY)
  final String? dbAddress; // from DB ONLY
  final String? coverPath; // Storage path

  // ADDED: if Home already resolved the URL, pass it to show image instantly
  final String? initialCoverUrl;

  const VenuePage({
    super.key,
    required this.placeId,
    required this.name,
    required this.description,
    this.dbAddress,
    this.coverPath,
    this.initialCoverUrl,
  });

  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage> {
  bool _loading = true;
  String? _error;

  // Details data (address seeded from DB; never overwritten by API)
  String? _address;

  // Hours-related
  bool? _openNow;
  List<String> _weekdayText = const [];
  List<dynamic> _periods = const [];
  int? _utcOffsetMinutes;
  String? _businessStatus;
  List<String> _types = const [];

  // ADDED: storage + tiny URL cache (static to persist across page instances)
  static final storage.FirebaseStorage _coversStorage =
      storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      );
  static final Map<String, String> _urlCache = {}; // coverPath -> url

  // ADDED: cache hours per placeId to avoid re-calls when revisiting
  static final Map<String, Map<String, dynamic>> _hoursCache = {};

  // ADDED: expand/collapse for description
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _address = widget.dbAddress; // seed from DB (do not override)
    _loadHours(); // API only for opening hours (+status/types)
  }

  Future<void> _loadHours() async {
    // if cached, use it instantly
    final cached = _hoursCache[widget.placeId];
    if (cached != null) {
      _applyHours(cached);
      setState(() => _loading = false);
      return;
    }

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
            'opening_hours',
            'current_opening_hours',
            'utc_offset',
            'types',
            'business_status',
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
      _hoursCache[widget.placeId] = res; // cache for next visits
      _applyHours(res);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _applyHours(Map<String, dynamic> res) {
    final currentOpening =
        (res['current_opening_hours'] as Map<String, dynamic>?) ?? {};
    final opening = currentOpening.isNotEmpty
        ? currentOpening
        : (res['opening_hours'] as Map<String, dynamic>?) ?? {};

    final weekdayText =
        (opening['weekday_text'] as List?)?.cast<String>() ?? const [];
    final periods = (opening['periods'] as List?) ?? const [];
    final openNow = opening['open_now'] as bool?;
    final utcOffset = res['utc_offset'] as int?;
    final types = (res['types'] as List?)?.cast<String>() ?? const [];
    final businessStatus = res['business_status'] as String?;

    setState(() {
      _openNow = openNow;
      _weekdayText = weekdayText;
      _periods = periods;
      _utcOffsetMinutes = utcOffset;
      _types = types;
      _businessStatus = businessStatus;
    });
  }

  // ---------- Helpers: image from Storage coverPath ----------
  Future<String?> _resolveCoverUrl() async {
    // prefer handed-in URL from Home for instant paint
    if ((widget.initialCoverUrl ?? '').isNotEmpty)
      return widget.initialCoverUrl;

    final p = widget.coverPath;
    if (p == null || p.isEmpty) return null;
    if (_urlCache.containsKey(p)) return _urlCache[p];
    try {
      final ref = _coversStorage.ref(p);
      final url = await ref.getDownloadURL().timeout(
        const Duration(seconds: 8),
      );
      _urlCache[p] = url;
      // Warm bytes
      // ignore: unused_result
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      return url;
    } catch (_) {
      return null;
    }
  }

  bool get _isAirport {
    if (_types.any((t) => t.toLowerCase() == 'airport')) return true;
    final n = widget.name.toLowerCase();
    return n.contains('airport');
  }

  bool get _isStadium {
    return _types.any((t) => t.toLowerCase() == 'stadium') ||
        widget.name.toLowerCase().contains('stadium') ||
        widget.name.toLowerCase().contains('arena') ||
        widget.name.toLowerCase().contains('park');
  }

  bool get _isTempClosed => _businessStatus == 'CLOSED_TEMPORARILY';
  bool get _isPermClosed => _businessStatus == 'CLOSED_PERMANENTLY';

  bool get _hasAnyHours =>
      (_weekdayText.isNotEmpty && _weekdayText.length >= 1) ||
      (_periods.isNotEmpty);

  int get _effectiveOffsetMinutes =>
      _utcOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes;

  DateTime _toLocalDateTime(int targetDay, String hhmm) {
    final offset = Duration(minutes: _effectiveOffsetMinutes);
    final nowLocal = DateTime.now().toUtc().add(offset);
    final todayIdx = (nowLocal.weekday % 7);
    int diff = (targetDay - todayIdx);
    if (diff < 0) diff += 7;
    final date = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    ).add(Duration(days: diff));
    final hh = int.parse(hhmm.substring(0, 2));
    final mm = int.parse(hhmm.substring(2, 4));
    return DateTime(date.year, date.month, date.day, hh, mm);
  }

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

  String _preciseStatusNow() {
    if (_isTempClosed) return 'Temporarily closed';
    if (_isPermClosed) return 'Permanently closed';
    if (_isAirport && !_hasAnyHours) return 'Open 24 hours';
    if (_isStadium && !_hasAnyHours) return 'Hours vary by event';

    if (_periods.isNotEmpty) {
      final offset = Duration(minutes: _effectiveOffsetMinutes);
      final nowLocal = DateTime.now().toUtc().add(offset);

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
        DateTime closeDT;
        if (close.containsKey('day') && close.containsKey('time')) {
          closeDT = _toLocalDateTime(
            (close['day'] as num).toInt(),
            (close['time'] as String),
          );
          if (!closeDT.isAfter(openDT))
            closeDT = closeDT.add(const Duration(days: 1));
        } else {
          closeDT = openDT.add(const Duration(days: 1));
        }
        for (int k = 0; k < 2; k++) {
          windows.add(
            _OpenWindow(
              openDT: openDT.add(Duration(days: 7 * k)),
              closeDT: closeDT.add(Duration(days: 7 * k)),
            ),
          );
        }
      }

      windows.sort((a, b) => a.openDT.compareTo(b.openDT));
      final firstToday = _firstOpenToday(windows, nowLocal);
      if (firstToday != null && nowLocal.isBefore(firstToday)) {
        return 'Closed · Opens ${_formatClock(firstToday)}';
      }
      for (final w in windows) {
        if (nowLocal.isBefore(w.openDT)) {
          return 'Closed · Opens ${_formatClock(w.openDT)}';
        }
        if (nowLocal.isAfter(w.openDT) && nowLocal.isBefore(w.closeDT)) {
          return 'Open · Closes ${_formatClock(w.closeDT)}';
        }
      }
      return 'Closed';
    }

    return _statusFromWeekdayTextFallback();
  }

  String _formatClock(DateTime dtLocal) {
    final hour = dtLocal.hour % 12 == 0 ? 12 : dtLocal.hour % 12;
    final min = dtLocal.minute.toString().padLeft(2, '0');
    final ampm = dtLocal.hour < 12 ? 'AM' : 'PM';
    return '$hour:$min $ampm';
  }

  List<String>? _splitRange(String s) {
    final m = RegExp(
      r'(\d{1,2}:\d{2}(?:\s?[AP]M)?)\s*[–-]\s*(\d{1,2}:\d{2}\s?[AP]M)',
    ).firstMatch(s);
    if (m == null) return null;
    var start = m.group(1)!.trim();
    var end = m.group(2)!.trim();
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
    final today = now.weekday % 7;
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

  @override
  Widget build(BuildContext context) {
    final summary = widget.description.trim(); // DB-only description

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
                if ((widget.coverPath ?? '').isNotEmpty ||
                    (widget.initialCoverUrl ?? '').isNotEmpty)
                  _buildHeaderCover(),

                // Summary (inline "More / Show less")
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ExpandableText(
                    text: summary,
                    maxLines: 3, // keep your intended collapsed height
                    style: const TextStyle(
                      color: Colors.black87,
                      height: 1.25,
                      fontSize: 16,
                    ),
                    linkStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          kGreen, // matches your palette; change if you prefer
                    ),
                  ),
                ),

                if ((_address ?? '').isNotEmpty)
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

                // Floor Map (keep your placeholder section)
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
                      _categoryCard(
                        context,
                        "Shops",
                        "120 places",
                        "images/Shops.png",
                      ),
                      const SizedBox(width: 12),
                      _categoryCard(
                        context,
                        "Cafes",
                        "25 places",
                        "images/Cafes.jpg",
                      ),
                      const SizedBox(width: 12),
                      _categoryCard(
                        context,
                        "Restaurants",
                        "40 places",
                        "images/restaurants.jpeg",
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // Header: steady loader -> image; if truly absent, show NA icon
  Widget _buildHeaderCover() {
    const h = 200.0;
    return FutureBuilder<String?>(
      future: _resolveCoverUrl(),
      builder: (context, snap) {
        final url = snap.data ?? widget.initialCoverUrl;
        if (url == null || url.isEmpty) {
          return SizedBox(
            height: h,
            width: double.infinity,
            child: Container(
              color: const Color(0xFFEDEFE3),
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.black45,
                size: 40,
              ),
            ),
          );
        }
        return SizedBox(
          height: h,
          width: double.infinity,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            placeholder: (_, __) => Container(
              color: const Color(0xFFEDEFE3),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: const Color(0xFFEDEFE3),
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image, color: Colors.black45),
            ),
            fadeInDuration: const Duration(milliseconds: 120),
          ),
        );
      },
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

    final noDropdown =
        _isTempClosed ||
        _isPermClosed ||
        statusText == 'Open 24 hours' ||
        statusText == 'Hours vary by event' ||
        sunFirst.isEmpty;

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
          title: statusTitle,
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

  Widget _statusTitleRich(String statusText) {
    String leading;
    String trailing = '';
    Color? color;

    if (statusText == 'Open 24 hours') {
      leading = statusText;
      color = Colors.green[800];
    } else if (statusText == 'Hours vary by event') {
      leading = statusText;
      color = const Color.fromARGB(255, 239, 139, 0);
    } else if (statusText.startsWith('Open')) {
      leading = 'Open';
      trailing = statusText.substring('Open'.length);
      color = Colors.green[800];
    } else if (statusText.startsWith('Closed')) {
      leading = 'Closed';
      trailing = statusText.substring('Closed'.length);
      color = Colors.red[700];
    } else if (statusText.startsWith('Temporarily closed')) {
      leading = 'Temporarily closed';
      trailing = statusText.substring('Temporarily closed'.length);
      color = Colors.red[700];
    } else if (statusText.startsWith('Permanently closed')) {
      leading = 'Permanently closed';
      trailing = statusText.substring('Permanently closed'.length);
      color = Colors.red[700];
    } else {
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
          if (trailing.isNotEmpty) const TextSpan(text: ''),
          if (trailing.isNotEmpty) const TextSpan(text: ''),
          if (trailing.isNotEmpty) const TextSpan(),
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

class _OpenWindow {
  final DateTime openDT;
  final DateTime closeDT;
  _OpenWindow({required this.openDT, required this.closeDT});
}

// ---- Inline expandable text ("… More" / "Show less") ----
class _ExpandableText extends StatefulWidget {
  final String text;
  final int maxLines; // collapsed
  final TextStyle? style;
  final TextStyle? linkStyle;

  const _ExpandableText({
    required this.text,
    this.maxLines = 3,
    this.style,
    this.linkStyle,
  });

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final base =
        widget.style ??
        const TextStyle(color: Colors.black87, height: 1.25, fontSize: 16);
    final link =
        widget.linkStyle ??
        const TextStyle(fontWeight: FontWeight.w600, color: kGreen);

    // If expanded -> simple full paragraph
    if (_expanded) {
      return RichText(
        text: TextSpan(
          style: base,
          children: [
            TextSpan(text: widget.text),
            const TextSpan(text: '  '),
            TextSpan(
              text: 'show less',
              style: link,
              recognizer: (TapGestureRecognizer()
                ..onTap = () {
                  setState(() => _expanded = false);
                }),
            ),
          ],
        ),
      );
    }

    // Collapsed: measure if it actually overflows
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: base),
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);

        final overflows = tp.didExceedMaxLines;

        if (!overflows) {
          // no overflow -> render normally
          return Text(widget.text, style: base);
        }

        // We need to find how much text fits, then append " … More"
        final more = ' more';
        final ellipsis = '…';
        final linkSpan = TextSpan(text: more, style: link);
        final testPainter = TextPainter(
          textDirection: TextDirection.ltr,
          maxLines: widget.maxLines,
          ellipsis: ellipsis,
        );

        // Binary search the cut point
        int low = 0, high = widget.text.length, cut = 0;
        while (low <= high) {
          final mid = (low + high) >> 1;
          final candidate = widget.text.substring(0, mid);
          testPainter.text = TextSpan(
            style: base,
            children: [
              TextSpan(text: candidate),
              TextSpan(text: ' $ellipsis'),
              linkSpan,
            ],
          );
          testPainter.layout(maxWidth: constraints.maxWidth);
          if (testPainter.didExceedMaxLines) {
            high = mid - 1;
          } else {
            cut = mid;
            low = mid + 1;
          }
        }

        final visibleText = widget.text.substring(0, cut).trimRight();

        return RichText(
          text: TextSpan(
            style: base,
            children: [
              TextSpan(text: visibleText),
              const TextSpan(text: ' … '),
              TextSpan(
                text: 'more',
                style: link,
                recognizer: (TapGestureRecognizer()
                  ..onTap = () {
                    setState(() => _expanded = true);
                  }),
              ),
            ],
          ),
        );
      },
    );
  }
}
