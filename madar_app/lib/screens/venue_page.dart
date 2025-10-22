import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'category_page.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart'; // less and more in description

// Imports for venue url generation
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';

// Storage + cache
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:cached_network_image/cached_network_image.dart';

const kGreen = Color(0xFF787E65);

class VenuePage extends StatefulWidget {
  final String placeId; // required for details
  final String name;
  final String description;
  final String? dbAddress;
  final double? lat;
  final double? lng;

  // NEW: all storage image paths (first = cover)
  final List<String> imagePaths;

  // if Home already resolved the first URL, use it for instant paint
  final String? initialCoverUrl;

  const VenuePage({
    super.key,
    required this.placeId,
    required this.name,
    required this.description,
    this.dbAddress,
    this.imagePaths = const [],
    this.initialCoverUrl,
    this.lat, // NEW
    this.lng,
  });

  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage> {
  bool _loading = true;
  String? _error;

  // address seeded from DB; never overwritten by API
  String? _address;

  // Hours-related
  bool? _openNow;
  List<String> _weekdayText = const [];
  List<dynamic> _periods = const [];
  int? _utcOffsetMinutes;
  String? _businessStatus;
  List<String> _types = const [];

  // storage + tiny URL cache (static across instances)
  static final storage.FirebaseStorage _coversStorage =
      storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      );
  static final Map<String, String> _urlCache = {}; // path -> url

  // hours cache
  static final Map<String, Map<String, dynamic>> _hoursCache = {};

  // description expand
  bool _descExpanded = false;

  // carousel
  late final PageController _pageCtrl = PageController();
  int _pageIndex = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _address = widget.dbAddress;
    _loadHours();
    _prefetchAllVenueImages();
  }

  Future<void> _loadHours() async {
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
      _hoursCache[widget.placeId] = res;
      _applyHours(res);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _prefetchAllVenueImages() async {
    for (final p in widget.imagePaths) {
      if (p.isEmpty) continue;
      try {
        final url =
            _urlCache[p] ??
            await _coversStorage
                .ref(p)
                .getDownloadURL()
                .timeout(const Duration(seconds: 8));
        _urlCache[p] = url;

        final provider = CachedNetworkImageProvider(url, cacheKey: p);
        provider.resolve(const ImageConfiguration()); // warms memory
      } catch (_) {}
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

  // ---------- Helpers for Storage paths ----------
  Future<String?> _imageUrlForPath(
    String path, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (path.isEmpty) return null;
    if (_urlCache.containsKey(path)) return _urlCache[path];
    try {
      final ref = _coversStorage.ref(path);
      final url = await ref.getDownloadURL().timeout(timeout);
      _urlCache[path] = url;
      // warm bytes
      // ignore: unused_result
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      return url;
    } catch (_) {
      return null;
    }
  }

  Widget _noImageHeader(double h) {
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
  // ---------- Helpers for address as link ----------

  // open address as link in google map
  Future<void> _openInMaps() async {
    final id = widget.placeId;
    final hasLL = widget.lat != null && widget.lng != null;
    final lat = widget.lat?.toStringAsFixed(6);
    final lng = widget.lng?.toStringAsFixed(6);

    // ANDROID — place sheet (no directions)
    final Uri androidGeo = hasLL
        ? Uri.parse('geo:$lat,$lng?q=place_id:$id&z=17')
        : Uri.parse('geo:0,0?q=place_id:$id');

    // iOS — Google Maps app if present
    final Uri iosGmm = hasLL
        ? Uri.parse('comgooglemaps://?q=place_id:$id&center=$lat,$lng&zoom=17')
        : Uri.parse('comgooglemaps://?q=place_id:$id');

    // Web fallback (place page; centered & zoom-hinted)
    final Uri web = hasLL
        ? Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query_place_id': id,
            'query': '$lat,$lng',
            'll': '$lat,$lng',
            'z': '17',
          })
        : Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query_place_id': id,
          });

    if (Platform.isAndroid && await canLaunchUrl(androidGeo)) {
      await launchUrl(androidGeo, mode: LaunchMode.externalApplication);
      return;
    }
    if (Platform.isIOS && await canLaunchUrl(iosGmm)) {
      await launchUrl(iosGmm, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  Uri _mapsPlaceUri(String placeId) => Uri.parse(
    'https://www.google.com/maps/search/?api=1&query_place_id=$placeId',
  );

  Widget _addressRow() {
    final addr = (_address ?? '').trim();
    if (addr.isEmpty) return const SizedBox.shrink();

    // We’ll render text that wraps to multiple lines,
    // and put the icon at the end using a WidgetSpan.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            height: 1.35,
          ),
          children: [
            TextSpan(text: addr),
            const WidgetSpan(child: SizedBox(width: 8)), // nice breathing room
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: InkWell(
                onTap: _openInMaps,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2), // optically align
                  // The diamond arrow = Material icon "assistant_direction"
                  child: Icon(
                    Icons.assistant_direction,
                    color: kGreen, // green INSIDE the diamond
                    size: 20, // no colored circle behind it
                  ),
                ),
              ),
            ),
          ],
        ),
        softWrap: true, // <— wrap to new lines as needed
        maxLines: null, // <— no truncation
      ),
    );
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
                // Header (carousel with dots inside image)
                if (widget.imagePaths.isNotEmpty)
                  _buildHeaderCarousel()
                else
                  _noImageHeader(200),

                // Summary
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ExpandableText(
                    text: summary,
                    maxLines: 3,
                    style: const TextStyle(
                      color: Colors.black87,
                      height: 1.25,
                      fontSize: 16,
                    ),
                    linkStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: kGreen,
                    ),
                  ),
                ),

                _addressRow(),
                const SizedBox(height: 12),

                // Opening hours card
                _hoursCard(),

                const SizedBox(height: 16),

                // Floor Map (placeholder)
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

                // 🔹 Explore Categories (dynamic from Firestore)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "Explore Categories",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('venues')
                        .doc(widget.placeId)
                        .collection('categories')
                        .snapshots(),

                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No categories found.'),
                        );
                      }

                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final categoryId = docs[i]
                              .id; // 👈 هذا هو الـ ID الحقيقي (مثل solitaireshops)
                          final data = docs[i].data();
                          final name = data['categoryName'] ?? 'Unnamed';
                          final count = data['placesCount'] ?? 0;
                          final image =
                              data['categoryImage'] ?? 'images/default.jpg';

                          return _categoryCard(
                            context,
                            name,
                            '$count places',
                            image,
                            widget.placeId,
                            categoryId,
                            _imageUrlForCategory, // 🔹 أرسل الدالة هنا
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  // ----- Header carousel with dots overlay -----
  Widget _buildHeaderCarousel() {
    const double h = 200.0;

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.imagePaths.length,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            itemBuilder: (context, index) {
              final path = widget.imagePaths[index];

              // first image: use handed-in URL if available
              if (index == 0 && (widget.initialCoverUrl ?? '').isNotEmpty) {
                return CachedNetworkImage(
                  imageUrl: widget.initialCoverUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: const Color(0xFFEDEFE3),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => _noImageHeader(h),
                  fadeInDuration: const Duration(milliseconds: 120),
                );
              }

              return FutureBuilder<String?>(
                future: _imageUrlForPath(path),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Container(
                      color: const Color(0xFFEDEFE3),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final url = snap.data;
                  if (snap.hasError || url == null || url.isEmpty) {
                    return _noImageHeader(h);
                  }
                  return CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFFEDEFE3),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _noImageHeader(h),
                    fadeInDuration: const Duration(milliseconds: 120),
                  );
                },
              );
            },
          ),

          // Dots overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(widget.imagePaths.length, (i) {
                    final bool active = i == _pageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 8 : 6,
                      height: active ? 8 : 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hoursCard() {
    // Sunday-first order
    List<String> sunFirst = _weekdayText;
    if (_weekdayText.length == 7 &&
        _weekdayText.first.toLowerCase().startsWith('monday')) {
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

  // 🔹 تحميل صورة الكاتيقوري من Firebase Storage بنفس طريقة HomePage
  Future<String?> _imageUrlForCategory(String path) async {
    if (path.isEmpty) return null;
    if (_urlCache.containsKey(path)) return _urlCache[path];
    try {
      final ref = _coversStorage.ref(path);
      final url = await ref.getDownloadURL().timeout(
        const Duration(seconds: 8),
      );
      _urlCache[path] = url;
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      return url;
    } catch (_) {
      return null;
    }
  }

  static Widget _categoryCard(
    BuildContext context,
    String title,
    String subtitle,
    String imagePath, // 🔹 Storage path
    String venueId,
    String categoryId,
    Future<String?> Function(String) getUrlFor, // 🔹 دالة تحميل الصورة
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryPage(
              categoryName: title,
              venueId: venueId,
              categoryId: categoryId,
            ),
          ),
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
              child: FutureBuilder<String?>(
                future: getUrlFor(imagePath),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Container(
                      height: 100,
                      width: 140,
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (snap.hasError ||
                      snap.data == null ||
                      snap.data!.isEmpty) {
                    return Container(
                      height: 100,
                      width: 140,
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported,
                        color: Colors.grey,
                      ),
                    );
                  }
                  return CachedNetworkImage(
                    imageUrl: snap.data!,
                    height: 100,
                    width: 140,
                    fit: BoxFit.cover,
                  );
                },
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

    // expanded -> full paragraph
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

    // collapsed: measure overflow
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
          return Text(widget.text, style: base);
        }

        final more = ' more';
        final ellipsis = '…';
        final linkSpan = TextSpan(text: more, style: link);
        final testPainter = TextPainter(
          textDirection: TextDirection.ltr,
          maxLines: widget.maxLines,
          ellipsis: ellipsis,
        );

        // binary search cut point
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
