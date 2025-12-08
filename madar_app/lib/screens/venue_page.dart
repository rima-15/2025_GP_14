import 'dart:io' show Platform;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:madar_app/api/venue_cache_service.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'category_page.dart';

// ----------------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------------

const Color kPrimaryGreen = Color(0xFF777D63);

// ----------------------------------------------------------------------------
// Venue Page
// ----------------------------------------------------------------------------

class VenuePage extends StatefulWidget {
  final String placeId;
  final String name;
  final String description;
  final String? dbAddress;
  final double? lat;
  final double? lng;
  final List<String> imagePaths;
  final String? initialCoverUrl;
  final String? venueType;

  const VenuePage({
    super.key,
    required this.placeId,
    required this.name,
    required this.description,
    this.dbAddress,
    this.imagePaths = const [],
    this.initialCoverUrl,
    this.lat,
    this.lng,
    this.venueType,
  });

  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ---------- Constants ----------

  static const double _headerHeight = 180;
  static const double _topRadius = 35;

  // ---------- State ----------

  bool _loading = true;
  String? _error;
  String? _address;
  bool _aboutExpanded = false;
  bool _hoursExpanded = false;

  bool? _openNow;
  List<String> _weekdayText = const [];
  List<dynamic> _periods = const [];
  int? _utcOffsetMinutes;
  String? _businessStatus;
  List<String> _types = const [];

  String? _venueWebsite;
  String? _venuePhone;

  String _currentFloor = '';
  List<Map<String, String>> _venueMaps = [];
  bool _mapsLoading = false;

  // ---------- Caching ----------

  static final storage.FirebaseStorage _coversStorage =
      storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      );
  static final Map<String, String> _urlCache = {};
  static final Map<String, Map<String, dynamic>> _hoursCache = {};
  static final Map<String, Map<String, String>> _contactsCache = {};

  late final VenueCacheService _cache = VenueCacheService(
    FirebaseFirestore.instance,
  );

  @override
  void initState() {
    super.initState();
    _address = widget.dbAddress;

    // Check for cached data
    final cachedHours = _hoursCache[widget.placeId];
    final cachedContacts = _contactsCache[widget.placeId];

    if (cachedHours != null) {
      _applyHours(cachedHours);
      setState(() => _loading = false);
    } else {
      _loadHours();
    }

    if (cachedContacts != null) {
      _venueWebsite = cachedContacts['website'];
      _venuePhone = cachedContacts['phone'];
    } else {
      _loadVenueContacts();
    }

    _prefetchAllVenueImages();
    _loadVenueMaps();
  }

  // ---------- Data Loading ----------

  /// Load opening hours from API with fallback to DB
  Future<void> _loadHours() async {
    // Try Google Place Details API first
    try {
      final key = dotenv.env['GOOGLE_API_KEY'];
      if (key != null && widget.placeId.isNotEmpty) {
        final uri = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=${Uri.encodeComponent(widget.placeId)}'
          '&fields=business_status,current_opening_hours,opening_hours,utc_offset,types'
          '&key=$key',
        );

        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          if (data['status'] == 'OK' &&
              data['result'] is Map<String, dynamic>) {
            final result = Map<String, dynamic>.from(data['result'] as Map);

            final normalized = <String, dynamic>{
              'current_opening_hours': result['current_opening_hours'],
              'opening_hours': result['opening_hours'],
              'utc_offset': result['utc_offset'],
              'types': (result['types'] as List?)?.cast<String>(),
              'business_status': result['business_status'],
              '_source': 'api',
              '_ts': DateTime.now().millisecondsSinceEpoch,
            };

            _hoursCache[widget.placeId] = normalized;
            _applyHours(normalized);
            setState(() => _loading = false);
            return;
          }
        }
      }
    } catch (_) {}

    // Fallback to cached API data
    final cached = _hoursCache[widget.placeId];
    if (cached != null && cached['_source'] == 'api') {
      _applyHours(cached);
      setState(() => _loading = false);
      return;
    }

    // Final fallback: monthly meta from DB
    try {
      final meta = await _cache
          .getMonthlyMeta(widget.placeId)
          .timeout(const Duration(seconds: 10));

      final resultLike = <String, dynamic>{};
      if (meta.openingHours != null) {
        resultLike['current_opening_hours'] = meta.openingHours;
      }
      if (meta.rating != null) {
        resultLike['rating'] = meta.rating;
      }
      if (meta.businessStatus != null) {
        resultLike['business_status'] = meta.businessStatus;
      }
      if (meta.types != null) {
        resultLike['types'] = meta.types;
      }
      resultLike['_source'] = 'db';
      resultLike['_ts'] = DateTime.now().millisecondsSinceEpoch;

      _hoursCache[widget.placeId] = resultLike;
      _applyHours(resultLike);
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
        provider.resolve(const ImageConfiguration());
      } catch (_) {}
    }
  }

  Future<void> _loadVenueContacts() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(widget.placeId)
          .get(const GetOptions(source: Source.serverAndCache));
      final data = doc.data();
      if (data != null) {
        final site = (data['venueWebsite'] ?? '').toString().trim();
        final phone = (data['venuePhone'] ?? '').toString().trim();

        _contactsCache[widget.placeId] = {
          'website': site.isNotEmpty ? site : '',
          'phone': phone.isNotEmpty ? phone : '',
        };

        setState(() {
          _venueWebsite = site.isNotEmpty ? site : null;
          _venuePhone = phone.isNotEmpty ? phone : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadVenueMaps() async {
    setState(() => _mapsLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(widget.placeId)
          .get(const GetOptions(source: Source.serverAndCache));

      final data = doc.data();

      if (data != null && data['map'] is List) {
        final maps = (data['map'] as List).cast<Map<String, dynamic>>();

        final convertedMaps = maps.map((map) {
          final floorNumber = (map['floorNumber'] ?? '').toString();
          final mapURL = (map['mapURL'] ?? '').toString();
          return {'floorNumber': floorNumber, 'mapURL': mapURL};
        }).toList();

        setState(() => _venueMaps = convertedMaps);

        if (convertedMaps.isNotEmpty) {
          final firstMap = convertedMaps.first;
          final firstMapURL = firstMap['mapURL'];
          if (firstMapURL != null && firstMapURL.isNotEmpty) {
            setState(() => _currentFloor = firstMapURL);
          }
        }
      } else {
        setState(() => _venueMaps = []);
      }
    } catch (e) {
      setState(() => _venueMaps = []);
    } finally {
      setState(() => _mapsLoading = false);
    }
  }

  // ---------- Apply Hours Data ----------

  void _applyHours(Map<String, dynamic> res) {
    final currentOpening =
        (res['current_opening_hours'] as Map<String, dynamic>?) ?? {};
    final opening = currentOpening.isNotEmpty
        ? currentOpening
        : (res['opening_hours'] as Map<String, dynamic>?) ?? {};

    List<String> weekdayText =
        (opening['weekday_text'] as List?)?.cast<String>() ?? const [];
    final periods = (opening['periods'] as List?) ?? const [];
    final utcOffset = res['utc_offset'] as int?;
    final types = (res['types'] as List?)?.cast<String>() ?? const [];
    final businessStatus = res['business_status'] as String?;

    // Assume 24h for airports without hours
    if (weekdayText.isEmpty && types.contains('airport')) {
      weekdayText = const [
        'Sunday: Open 24 hours',
        'Monday: Open 24 hours',
        'Tuesday: Open 24 hours',
        'Wednesday: Open 24 hours',
        'Thursday: Open 24 hours',
        'Friday: Open 24 hours',
        'Saturday: Open 24 hours',
      ];
    }

    // Ensure Sunday-first order
    if (weekdayText.isNotEmpty &&
        weekdayText.first.toLowerCase().startsWith('monday')) {
      final idxSun = weekdayText.indexWhere(
        (l) => l.toLowerCase().startsWith('sunday'),
      );
      if (idxSun > 0) {
        weekdayText = [
          ...weekdayText.sublist(idxSun),
          ...weekdayText.sublist(0, idxSun),
        ];
      }
    }

    // Store periods and UTC offset first
    _periods = periods;
    _utcOffsetMinutes = utcOffset;
    _types = types;
    _businessStatus = businessStatus;
    _weekdayText = weekdayText;

    // Compute open/closed status locally from stored data
    final computedOpenNow = _computeLocalOpenNow();

    setState(() {
      _openNow = computedOpenNow;
      _weekdayText = weekdayText;
      _periods = periods;
      _utcOffsetMinutes = utcOffset;
      _types = types;
      _businessStatus = businessStatus;
    });
  }

  // ---------- Local Open/Closed Computation ----------

  /// Computes whether the venue is currently open based on stored periods
  /// and UTC offset, instead of relying on API's open_now boolean.
  bool? _computeLocalOpenNow() {
    // If no periods data, cannot determine
    if (_periods.isEmpty) {
      // Check if 24 hours from weekday text
      if (_isOpen24Hours()) return true;
      return null;
    }

    // Check for 24/7 open (single period with no close)
    if (_periods.length == 1) {
      final period = _periods.first as Map<String, dynamic>?;
      if (period != null && !period.containsKey('close')) {
        // Open 24/7
        return true;
      }
    }

    // Get current time in venue's timezone
    final now = DateTime.now().toUtc();
    final venueOffset = _utcOffsetMinutes ?? 180; // Default to UTC+3 (Riyadh)
    final venueNow = now.add(Duration(minutes: venueOffset));

    // Google API uses 0=Sunday, 1=Monday, ..., 6=Saturday
    // Dart's DateTime.weekday: 1=Monday, ..., 7=Sunday
    // Convert Dart weekday to Google format
    final dartWeekday = venueNow.weekday; // 1-7 (Mon-Sun)
    final googleDay = dartWeekday == 7 ? 0 : dartWeekday; // 0-6 (Sun-Sat)

    final currentTimeMinutes = venueNow.hour * 60 + venueNow.minute;

    // Check each period to see if we're within opening hours
    for (final period in _periods) {
      if (period is! Map<String, dynamic>) continue;

      final openData = period['open'] as Map<String, dynamic>?;
      final closeData = period['close'] as Map<String, dynamic>?;

      if (openData == null) continue;

      final openDay = openData['day'] as int?;
      final openTime = openData['time'] as String?;

      if (openDay == null || openTime == null) continue;

      // Parse open time (format: "HHMM")
      final openMinutes = _parseTimeToMinutes(openTime);
      if (openMinutes == null) continue;

      // Handle case where there's no close (24 hours for that day)
      if (closeData == null) {
        if (openDay == googleDay) return true;
        continue;
      }

      final closeDay = closeData['day'] as int?;
      final closeTime = closeData['time'] as String?;

      if (closeDay == null || closeTime == null) continue;

      final closeMinutes = _parseTimeToMinutes(closeTime);
      if (closeMinutes == null) continue;

      // Check if current time falls within this period
      final isOpen = _isWithinPeriod(
        currentDay: googleDay,
        currentMinutes: currentTimeMinutes,
        openDay: openDay,
        openMinutes: openMinutes,
        closeDay: closeDay,
        closeMinutes: closeMinutes,
      );

      if (isOpen) return true;
    }

    return false;
  }

  /// Parse time string "HHMM" to minutes since midnight
  int? _parseTimeToMinutes(String time) {
    if (time.length != 4) return null;
    final hour = int.tryParse(time.substring(0, 2));
    final minute = int.tryParse(time.substring(2, 4));
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Check if current time is within an opening period
  /// Handles overnight periods (e.g., 10PM - 2AM)
  bool _isWithinPeriod({
    required int currentDay,
    required int currentMinutes,
    required int openDay,
    required int openMinutes,
    required int closeDay,
    required int closeMinutes,
  }) {
    // Same day period
    if (openDay == closeDay) {
      if (currentDay == openDay &&
          currentMinutes >= openMinutes &&
          currentMinutes < closeMinutes) {
        return true;
      }
      return false;
    }

    // Overnight period (closes next day)
    // Check if we're in the opening part (after open time on open day)
    if (currentDay == openDay && currentMinutes >= openMinutes) {
      return true;
    }

    // Check if we're in the closing part (before close time on close day)
    if (currentDay == closeDay && currentMinutes < closeMinutes) {
      return true;
    }

    // Handle multi-day spans (rare, but possible)
    // Calculate days between open and close
    int daySpan = closeDay - openDay;
    if (daySpan < 0) daySpan += 7;

    if (daySpan > 1) {
      // Check if current day is between open and close days
      int currentOffset = currentDay - openDay;
      if (currentOffset < 0) currentOffset += 7;
      if (currentOffset > 0 && currentOffset < daySpan) {
        return true;
      }
    }

    return false;
  }

  // ---------- URL & Navigation Helpers ----------

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
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openInMaps() async {
    final id = widget.placeId;
    final hasLL = widget.lat != null && widget.lng != null;
    final nameEnc = Uri.encodeComponent(widget.name);
    final ll = hasLL
        ? '${widget.lat!.toStringAsFixed(6)},${widget.lng!.toStringAsFixed(6)}'
        : null;

    final Uri primary = hasLL
        ? Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$nameEnc&query_place_id=$id',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query_place_id=$id',
          );

    final Uri alt = Uri.parse(
      'https://www.google.com/maps/place/?q=place_id:$id',
    );

    final Uri geo = hasLL
        ? Uri.parse('geo:$ll?q=$ll($nameEnc)')
        : Uri.parse('geo:0,0?q=$nameEnc');

    if (Platform.isIOS) {
      if (await canLaunchUrl(primary)) {
        final ok = await launchUrl(
          primary,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      }
      final Uri iosGmm = hasLL
          ? Uri.parse(
              'comgooglemaps://?q=$nameEnc&center=$ll&zoom=17&query_place_id=$id',
            )
          : Uri.parse('comgooglemaps://?q=$nameEnc&query_place_id=$id');
      if (await canLaunchUrl(iosGmm)) {
        final ok = await launchUrl(
          iosGmm,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      }
      await launchUrl(alt, mode: LaunchMode.externalApplication);
      return;
    }

    for (final uri in [primary, alt, geo]) {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      }
    }
  }

  Future<void> _openWebsite() async {
    final raw = _venueWebsite?.trim();
    if (raw == null || raw.isEmpty) return;
    final normalized = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    final uri = Uri.parse(normalized);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callVenue() async {
    final raw = _venuePhone?.trim();
    if (raw == null || raw.isEmpty) return;
    final cleaned = raw.replaceAll(RegExp(r'[()\s-]'), '');
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ---------- Display Helpers ----------

  String _getVenueTypeDisplay() {
    if (widget.venueType == null || widget.venueType!.isEmpty) {
      return 'Venue';
    }

    final type = widget.venueType!.toLowerCase();
    if (type == 'malls' || type == 'mall') {
      return 'Shopping mall';
    } else if (type == 'stadiums' || type == 'stadium') {
      return 'Stadium';
    } else if (type == 'airports' || type == 'airport') {
      return 'Airport';
    }

    return widget.venueType![0].toUpperCase() + widget.venueType!.substring(1);
  }

  bool _isOpen24Hours() {
    if (_weekdayText.isEmpty) return false;
    return _weekdayText.every(
      (line) =>
          line.toLowerCase().contains('24') ||
          line.toLowerCase().contains('open 24'),
    );
  }

  bool _isTemporarilyClosed() {
    return _businessStatus?.toLowerCase() == 'closed_temporarily';
  }

  bool _hasVaryingHours() {
    if (_weekdayText.isEmpty) return false;
    return _weekdayText.any(
      (line) =>
          line.toLowerCase().contains('vary') ||
          line.toLowerCase().contains('event'),
    );
  }

  String _getOpeningStatus() {
    if (_isTemporarilyClosed()) return 'Temporarily Closed';
    if (_isOpen24Hours()) return 'Open 24 Hours';
    if (_hasVaryingHours()) return 'Hours Vary';
    if (_openNow == true) return 'Open';
    if (_openNow == false) return 'Closed';
    return 'Not Available';
  }

  String _normalizeHoursLine(String s) {
    return s
        .replaceAll(RegExp(r'[\u2012\u2013\u2014\u2212\-]+'), '-')
        .replaceAll(RegExp(r'[\u202F\u00A0]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _getOpeningTime() {
    if (_isTemporarilyClosed() || _isOpen24Hours() || _hasVaryingHours()) {
      return '';
    }

    if (_weekdayText.isEmpty) return '';
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

    if (line.isEmpty) return '';

    String timePart = line.contains(':')
        ? line.split(':').sublist(1).join(':').trim()
        : '';

    if (timePart.isEmpty || timePart.toLowerCase() == 'closed') {
      return '';
    }

    timePart = _normalizeHoursLine(timePart);

    final m = RegExp(
      r'^\s*(\d{1,2}:\d{2})\s*(?:([AP]M))?\s*-\s*(\d{1,2}:\d{2})\s*([AP]M)\s*$',
      caseSensitive: false,
    ).firstMatch(timePart);

    if (m != null) {
      final startTime = m.group(1)!;
      final startMer = (m.group(2) ?? m.group(4))!;
      final endTime = m.group(3)!;
      final endMer = m.group(4)!;

      if (_openNow == true) {
        return 'Closes at $endTime $endMer';
      } else {
        return 'Opens at $startTime $startMer';
      }
    }

    // Fallbacks
    if (_openNow == true) {
      final matchClose = RegExp(
        r'[-–]\s*(\d{1,2}:\d{2}\s?[AP]M)',
        caseSensitive: false,
      ).firstMatch(timePart);
      if (matchClose != null) return 'Closes at ${matchClose.group(1)}';
    } else {
      final matchOpenLoose = RegExp(
        r'(\d{1,2}:\d{2})(?:\s?([AP]M))?',
        caseSensitive: false,
      ).firstMatch(timePart);
      if (matchOpenLoose != null) {
        final t = matchOpenLoose.group(1)!;
        final mer = matchOpenLoose.group(2);
        return 'Opens at ${mer == null ? t : '$t $mer'}';
      }
    }

    return '';
  }

  Color _getStatusColor() {
    if (_isTemporarilyClosed()) return Colors.red;
    if (_isOpen24Hours()) return Colors.green;
    if (_hasVaryingHours()) return Colors.orange;
    if (_openNow == true) return Colors.green;
    if (_openNow == false) return const Color.fromRGBO(244, 67, 54, 1);
    return Colors.orange;
  }

  void _showImageOverlay(int startIndex) {
    final imagesToShow = widget.imagePaths.skip(1).toList();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => _ImageOverlay(
        imagePaths: imagesToShow,
        startIndex: startIndex,
        getUrlFor: _imageUrlForPath,
      ),
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final horizontalPadding = isSmallScreen ? 12.0 : 16.0;

    final hasWebsite = (_venueWebsite != null && _venueWebsite!.isNotEmpty);
    final hasPhone = (_venuePhone != null && _venuePhone!.isNotEmpty);
    final bool isMall =
        widget.venueType?.toLowerCase() == 'malls' ||
        widget.venueType?.toLowerCase() == 'mall';
    final bool isSolitaire = widget.name.toLowerCase().contains('solitaire');

    final String effectiveVenueId = (isMall && !isSolitaire)
        ? 'ChIJcYTQDwDjLj4RZEiboV6gZzM'
        : widget.placeId;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color.fromARGB(145, 255, 255, 255),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: kPrimaryGreen, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: kPrimaryGreen,
                backgroundColor: kPrimaryGreen.withOpacity(0.2),
              ),
            )
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                // Hero image
                if (widget.imagePaths.isNotEmpty)
                  _buildHeroImage()
                else
                  SizedBox(
                    height: _headerHeight,
                    child: Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.image_not_supported, size: 48),
                      ),
                    ),
                  ),

                // White content section
                Transform.translate(
                  offset: const Offset(0, -_topRadius),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(_topRadius),
                        topRight: Radius.circular(_topRadius),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // Venue name and type
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.name,
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 20 : 22,
                                  fontWeight: FontWeight.w700,
                                  color: kPrimaryGreen,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getVenueTypeDisplay(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Action buttons
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _actionButton(
                                  icon: Icons.location_on_outlined,
                                  label: 'Location',
                                  onTap: _openInMaps,
                                ),
                              ),
                              if (hasWebsite) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _actionButton(
                                    icon: Icons.language,
                                    label: 'Website',
                                    onTap: _openWebsite,
                                  ),
                                ),
                              ],
                              if (hasPhone) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _actionButton(
                                    icon: Icons.phone_outlined,
                                    label: 'Call',
                                    onTap: _callVenue,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Photo strip
                        if (widget.imagePaths.length > 1)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            child: _buildPhotoStrip(),
                          ),
                        const SizedBox(height: 24),

                        // About section
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildExpandableText(
                                widget.description,
                                _aboutExpanded,
                                () => setState(
                                  () => _aboutExpanded = !_aboutExpanded,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Opening hours section
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Opening Hours',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildOpeningHours(),
                            ],
                          ),
                        ),

                        // Divider
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: 20,
                          ),
                          child: Divider(
                            color: Colors.grey.shade200,
                            height: 1,
                          ),
                        ),

                        // Floor Map section
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Map',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildFloorMapViewer(),
                            ],
                          ),
                        ),

                        // Divider
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: 20,
                          ),
                          child: Divider(
                            color: Colors.grey.shade200,
                            height: 1,
                          ),
                        ),

                        // Discover More section
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: Text(
                            'Discover More',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        SizedBox(
                          height: 180,
                          child: _DiscoverMoreSection(
                            venueId: effectiveVenueId,
                            getUrlFor: _imageUrlForCategory,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ---------- UI Builders ----------

  Widget _buildHeroImage() {
    final path = widget.imagePaths.isNotEmpty ? widget.imagePaths.first : '';

    // Use initial cover URL if provided (passed from home page)
    if (widget.initialCoverUrl != null && widget.initialCoverUrl!.isNotEmpty) {
      // Cache the URL for future use
      if (path.isNotEmpty) {
        _urlCache[path] = widget.initialCoverUrl!;
      }
      return SizedBox(
        height: _headerHeight,
        width: double.infinity,
        child: CachedNetworkImage(
          imageUrl: widget.initialCoverUrl!,
          cacheKey: path.isNotEmpty ? path : widget.initialCoverUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey.shade200),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: Icon(Icons.image_not_supported, size: 48),
            ),
          ),
        ),
      );
    }

    if (path.isEmpty) {
      return SizedBox(
        height: _headerHeight,
        child: Container(
          color: Colors.grey.shade200,
          child: const Center(child: Icon(Icons.image_not_supported, size: 48)),
        ),
      );
    }

    // Check static cache first for instant display
    if (_urlCache.containsKey(path)) {
      return SizedBox(
        height: _headerHeight,
        width: double.infinity,
        child: CachedNetworkImage(
          imageUrl: _urlCache[path]!,
          cacheKey: path,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey.shade200),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: Icon(Icons.image_not_supported, size: 48),
            ),
          ),
        ),
      );
    }

    // Not cached - load with FutureBuilder
    return FutureBuilder<String?>(
      future: _imageUrlForPath(path),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: _headerHeight,
            child: Container(
              color: Colors.grey.shade200,
              child: Center(
                child: FutureBuilder(
                  future: Future.delayed(const Duration(milliseconds: 500)),
                  builder: (context, delaySnap) {
                    if (delaySnap.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }
                    return CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimaryGreen,
                      backgroundColor: kPrimaryGreen.withOpacity(0.2),
                    );
                  },
                ),
              ),
            ),
          );
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return SizedBox(
            height: _headerHeight,
            child: Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: Icon(Icons.image_not_supported, size: 48),
              ),
            ),
          );
        }
        return SizedBox(
          height: _headerHeight,
          width: double.infinity,
          child: CachedNetworkImage(
            imageUrl: snap.data!,
            cacheKey: path,
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                Container(color: Colors.grey.shade200),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: Icon(Icons.image_not_supported, size: 48),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: kPrimaryGreen, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: kPrimaryGreen,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoStrip() {
    final images = widget.imagePaths.length > 1
        ? widget.imagePaths.sublist(1)
        : const <String>[];

    if (images.isEmpty) return const SizedBox.shrink();

    return _PhotoStripWidget(
      images: images,
      onImageTap: _showImageOverlay,
      getUrlFor: _imageUrlForPath,
    );
  }

  Widget _buildExpandableText(
    String text,
    bool isExpanded,
    VoidCallback onTap,
  ) {
    final style = const TextStyle(
      fontSize: 15,
      color: Colors.black87,
      height: 1.5,
    );

    const double arrowSlotWidth = 32;
    const EdgeInsets arrowPad = EdgeInsets.symmetric(horizontal: 6);

    return LayoutBuilder(
      builder: (context, constraints) {
        final probe = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 2,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth - arrowSlotWidth);
        final exceeded = probe.didExceedMaxLines;

        if (!exceeded) {
          return Text(text, style: style);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: isExpanded ? null : 2,
                overflow: isExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: style,
              ),
            ),
            SizedBox(
              width: arrowSlotWidth,
              child: Align(
                alignment: Alignment.topCenter,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: arrowPad,
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 22,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOpeningHours() {
    final status = _getOpeningStatus();
    final time = _getOpeningTime();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (_weekdayText.isNotEmpty &&
                !_isOpen24Hours() &&
                !_isTemporarilyClosed() &&
                !_hasVaryingHours()) {
              setState(() => _hoursExpanded = !_hoursExpanded);
            }
          },
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (status.isNotEmpty)
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 15,
                          color: _getStatusColor(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (status.isNotEmpty && time.isNotEmpty)
                      Text(
                        ' • ',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    if (time.isNotEmpty)
                      Flexible(
                        child: Text(
                          time,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (_weekdayText.isNotEmpty &&
                  !_isOpen24Hours() &&
                  !_isTemporarilyClosed() &&
                  !_hasVaryingHours())
                InkWell(
                  onTap: () => setState(() => _hoursExpanded = !_hoursExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 6),
                    child: Icon(
                      _hoursExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 22,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_hoursExpanded && _weekdayText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _weekdayText.map((line) {
                final parts = line.split(':');
                if (parts.length < 2) return const SizedBox.shrink();

                final day = parts[0].trim();
                final hours = parts.sublist(1).join(':').trim();

                final now = DateTime.now();
                final today = now.weekday % 7;
                const days = [
                  'Sunday',
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                ];
                final isToday = day.toLowerCase() == days[today].toLowerCase();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isToday
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isToday ? Colors.black : Colors.grey.shade700,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          hours,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

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

  Widget _buildFloorMapViewer() {
    if (_mapsLoading) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: kPrimaryGreen,
                backgroundColor: kPrimaryGreen.withOpacity(0.2),
              ),
              const SizedBox(height: 8),
              const Text('Loading maps...'),
            ],
          ),
        ),
      );
    }

    final hasMaps = _venueMaps.isNotEmpty;

    if (!hasMaps) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              const Text('No floor maps available'),
            ],
          ),
        ),
      );
    }

    return _FloorMapSection(venueMaps: _venueMaps, initialFloor: _currentFloor);
  }
}

// ----------------------------------------------------------------------------
// Image Overlay
// ----------------------------------------------------------------------------

class _ImageOverlay extends StatefulWidget {
  final List<String> imagePaths;
  final int startIndex;
  final Future<String?> Function(String) getUrlFor;

  const _ImageOverlay({
    required this.imagePaths,
    required this.startIndex,
    required this.getUrlFor,
  });

  @override
  State<_ImageOverlay> createState() => _ImageOverlayState();
}

class _ImageOverlayState extends State<_ImageOverlay> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemCount: widget.imagePaths.length,
            itemBuilder: (context, index) {
              return Center(
                child: FutureBuilder<String?>(
                  future: widget.getUrlFor(widget.imagePaths[index]),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return FutureBuilder(
                        future: Future.delayed(
                          const Duration(milliseconds: 500),
                        ),
                        builder: (context, delaySnap) {
                          if (delaySnap.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox.shrink();
                          }
                          return CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.3),
                          );
                        },
                      );
                    }
                    if (snap.hasError ||
                        snap.data == null ||
                        snap.data!.isEmpty) {
                      return const Icon(
                        Icons.error,
                        color: Colors.white,
                        size: 48,
                      );
                    }
                    return InteractiveViewer(
                      child: CachedNetworkImage(
                        imageUrl: snap.data!,
                        fit: BoxFit.contain,
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${widget.imagePaths.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Floor Map Widgets
// ----------------------------------------------------------------------------

class _FloorMapViewer extends StatelessWidget {
  final String currentFloor;

  const _FloorMapViewer({required this.currentFloor});

  @override
  Widget build(BuildContext context) {
    if (currentFloor.isEmpty) {
      return _buildError('No map selected');
    }

    try {
      return ModelViewer(
        key: ValueKey(currentFloor),
        src: currentFloor,
        alt: "3D Floor Map",
        ar: false,
        autoRotate: false,
        cameraControls: true,
        backgroundColor: Colors.white,
        cameraOrbit: "0deg 65deg 2.5m",
        minCameraOrbit: "auto 0deg auto",
        maxCameraOrbit: "auto 90deg auto",
        cameraTarget: "0m 0m 0m",
      );
    } catch (e) {
      return _buildError('Failed to load 3D map');
    }
  }

  Widget _buildError(String message) {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _FloorMapSection extends StatefulWidget {
  final List<Map<String, String>> venueMaps;
  final String initialFloor;

  const _FloorMapSection({required this.venueMaps, required this.initialFloor});

  @override
  State<_FloorMapSection> createState() => _FloorMapSectionState();
}

class _FloorMapSectionState extends State<_FloorMapSection> {
  late String _currentFloor;

  @override
  void initState() {
    super.initState();
    _currentFloor = widget.initialFloor;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Container(
            height: 250,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Stack(
              children: [
                _FloorMapViewer(currentFloor: _currentFloor),
                if (widget.venueMaps.length > 1)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: widget.venueMaps.map((map) {
                          final floorNumber = map['floorNumber'] ?? '';
                          final mapURL = map['mapURL'] ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildFloorButton(floorNumber, mapURL),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloorButton(String label, String mapURL) {
    bool isSelected = _currentFloor == mapURL;

    return SizedBox(
      width: 42,
      height: 36,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? kPrimaryGreen : Colors.white,
          foregroundColor: isSelected ? Colors.white : kPrimaryGreen,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected ? kPrimaryGreen : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          elevation: isSelected ? 2 : 0,
        ),
        onPressed: () => setState(() => _currentFloor = mapURL),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Discover More Section
// ----------------------------------------------------------------------------

class _DiscoverMoreSection extends StatefulWidget {
  final String venueId;
  final Future<String?> Function(String) getUrlFor;

  const _DiscoverMoreSection({required this.venueId, required this.getUrlFor});

  @override
  State<_DiscoverMoreSection> createState() => _DiscoverMoreSectionState();
}

class _DiscoverMoreSectionState extends State<_DiscoverMoreSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Map<String, String> _cachedUrls = {};
  final Map<String, CategoryData> _categoryData = {};
  bool _urlsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('venues')
          .doc(widget.venueId)
          .collection('categories')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final imagePath = data['categoryImage'] ?? 'images/default.jpg';

        if (imagePath.isNotEmpty) {
          try {
            final url = await widget.getUrlFor(imagePath);
            if (url != null && mounted) {
              _cachedUrls[imagePath] = url;
              _categoryData[doc.id] = CategoryData(
                id: doc.id,
                name: data['categoryName'] ?? 'Unnamed',
                image: imagePath,
              );
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() => _urlsLoaded = true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_urlsLoaded || _categoryData.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: kPrimaryGreen,
          backgroundColor: kPrimaryGreen.withOpacity(0.2),
        ),
      );
    }

    final categories = _categoryData.values.toList();

    // Sort categories
    int priorityFor(String name) {
      final n = name.trim().toLowerCase();
      switch (n) {
        case 'shops':
          return 0;
        case 'cafes':
          return 1;
        case 'restaurants':
        case 'resturants':
          return 2;
        case 'services':
          return 9999;
        default:
          return 100;
      }
    }

    categories.sort((a, b) {
      final aPri = priorityFor(a.name);
      final bPri = priorityFor(b.name);

      if (aPri != bPri) return aPri.compareTo(bPri);

      if (aPri == 100) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return 0;
    });

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: categories.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final cat = categories[i];
        final cachedUrl = _cachedUrls[cat.image];

        return GestureDetector(
          key: ValueKey(cat.id),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CategoryPage(
                  categoryName: cat.name,
                  venueId: widget.venueId,
                  categoryId: cat.id,
                ),
              ),
            );
          },
          child: Container(
            width: 130,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: cachedUrl != null
                      ? CachedNetworkImage(
                          imageUrl: cachedUrl,
                          cacheKey: cat.image,
                          height: 130,
                          width: 130,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey.shade200),
                          errorWidget: (context, url, error) => Container(
                            height: 130,
                            width: 130,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported),
                          ),
                        )
                      : Container(
                          height: 130,
                          width: 130,
                          color: Colors.grey.shade200,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    cat.name,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color.fromARGB(255, 44, 44, 44),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Category Data Model
// ----------------------------------------------------------------------------

class CategoryData {
  final String id;
  final String name;
  final String image;

  CategoryData({required this.id, required this.name, required this.image});
}

// ----------------------------------------------------------------------------
// Photo Strip Widget
// ----------------------------------------------------------------------------

class _PhotoStripWidget extends StatefulWidget {
  final List<String> images;
  final void Function(int) onImageTap;
  final Future<String?> Function(String) getUrlFor;

  const _PhotoStripWidget({
    required this.images,
    required this.onImageTap,
    required this.getUrlFor,
  });

  @override
  State<_PhotoStripWidget> createState() => _PhotoStripWidgetState();
}

class _PhotoStripWidgetState extends State<_PhotoStripWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Map<String, String> _cachedUrls = {};
  bool _urlsLoaded = false;

  @override
  void initState() {
    super.initState();
    _preloadUrls();
  }

  Future<void> _preloadUrls() async {
    for (final path in widget.images) {
      if (path.isEmpty) continue;
      try {
        final url = await widget.getUrlFor(path);
        if (url != null && mounted) {
          _cachedUrls[path] = url;
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _urlsLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final width = MediaQuery.of(context).size.width - 32;
    final pageCount = (widget.images.length / 3).ceil();

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: pageCount,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, page) {
          final start = page * 3;

          String? img0 = (start < widget.images.length)
              ? widget.images[start]
              : null;
          String? img1 = (start + 1 < widget.images.length)
              ? widget.images[start + 1]
              : null;
          String? img2 = (start + 2 < widget.images.length)
              ? widget.images[start + 2]
              : null;

          return Container(
            width: width,
            margin: EdgeInsets.only(right: page == pageCount - 1 ? 0 : 12),
            child: Row(
              children: [
                Expanded(flex: 2, child: _gridImageOrBlank(img0, true, start)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _gridImageOrBlank(img1, false, start + 1),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _gridImageOrBlank(img2, false, start + 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _gridImageOrBlank(String? path, bool large, int index) {
    if (path == null || path.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }
    return _gridImage(path, large, index);
  }

  Widget _gridImage(String path, bool large, int index) {
    final cachedUrl = _cachedUrls[path];

    return GestureDetector(
      onTap: () => widget.onImageTap(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: cachedUrl != null
            ? CachedNetworkImage(
                imageUrl: cachedUrl,
                cacheKey: path,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (context, url) =>
                    Container(color: Colors.grey.shade200),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.error, size: 24),
                ),
              )
            : Container(
                color: Colors.grey.shade200,
                child: Center(
                  child: !_urlsLoaded
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kPrimaryGreen,
                          backgroundColor: kPrimaryGreen.withOpacity(0.2),
                        )
                      : const Icon(Icons.image_not_supported, size: 24),
                ),
              ),
      ),
    );
  }
}
