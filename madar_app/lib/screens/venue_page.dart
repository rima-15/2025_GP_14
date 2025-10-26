import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart'
    as storage;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:madar_app/api/venue_cache_service.dart';
import 'category_page.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

// Madar color
const Color kPrimaryGreen = Color(
  0xFF777D63,
);

class VenuePage extends StatefulWidget {
  final String placeId;
  final String name;
  final String description;
  final String? dbAddress;
  final double? lat;
  final double? lng;
  final List<String> imagePaths;
  final String? initialCoverUrl;
  final String?
  venueType; // Add this to get venue type

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
  State<VenuePage> createState() =>
      _VenuePageState();
}

class _VenuePageState
    extends State<VenuePage> {
  // --- NEW: keep header sizing and overlap consistent ---
  static const double _headerHeight =
      180; // hero image height
  static const double _topRadius =
      35; // rounded top radius & overlap

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

  // NEW: website/phone from DB
  String? _venueWebsite;
  String? _venuePhone;

  // 3D map
  String _currentFloor =
      'assets/maps/F1_map.glb';

  static final storage.FirebaseStorage
  _coversStorage =
      storage
          .FirebaseStorage.instanceFor(
        bucket:
            'gs://madar-database.firebasestorage.app',
      );
  static final Map<String, String>
  _urlCache = {};
  static final Map<
    String,
    Map<String, dynamic>
  >
  _hoursCache = {};

  late final VenueCacheService _cache =
      VenueCacheService(
        FirebaseFirestore.instance,
      );

  @override
  void initState() {
    super.initState();
    _address = widget.dbAddress;
    _loadHours();
    _prefetchAllVenueImages();
    _loadVenueContacts(); // NEW
  }

  Future<void> _loadHours() async {
    final cached =
        _hoursCache[widget.placeId];
    if (cached != null) {
      _applyHours(cached);
      setState(() => _loading = false);
      return;
    }

    try {
      final meta = await _cache
          .getMonthlyMeta(
            widget.placeId,
          )
          .timeout(
            const Duration(seconds: 10),
          );

      final resultLike =
          <String, dynamic>{};
      if (meta.openingHours != null) {
        resultLike['current_opening_hours'] =
            meta.openingHours;
      }
      if (meta.rating != null) {
        resultLike['rating'] =
            meta.rating;
      }

      _hoursCache[widget.placeId] =
          resultLike;
      _applyHours(resultLike);
    } catch (e) {
      setState(
        () => _error = e.toString(),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void>
  _prefetchAllVenueImages() async {
    for (final p in widget.imagePaths) {
      if (p.isEmpty) continue;
      try {
        final url =
            _urlCache[p] ??
            await _coversStorage
                .ref(p)
                .getDownloadURL()
                .timeout(
                  const Duration(
                    seconds: 8,
                  ),
                );
        _urlCache[p] = url;
        final provider =
            CachedNetworkImageProvider(
              url,
              cacheKey: p,
            );
        provider.resolve(
          const ImageConfiguration(),
        );
      } catch (_) {}
    }
  }

  // NEW: load website/phone from venues/{placeId}
  Future<void>
  _loadVenueContacts() async {
    try {
      final doc =
          await FirebaseFirestore
              .instance
              .collection('venues')
              .doc(widget.placeId)
              .get(
                const GetOptions(
                  source: Source
                      .serverAndCache,
                ),
              );
      final data = doc.data();
      if (data != null) {
        final site =
            (data['venueWebsite'] ?? '')
                .toString()
                .trim();
        final phone =
            (data['venuePhone'] ?? '')
                .toString()
                .trim();
        setState(() {
          _venueWebsite =
              site.isNotEmpty
              ? site
              : null;
          _venuePhone = phone.isNotEmpty
              ? phone
              : null;
        });
      }
    } catch (_) {
      // Keep silently; buttons will just stay hidden
    }
  }

  void _applyHours(
    Map<String, dynamic> res,
  ) {
    final currentOpening =
        (res['current_opening_hours']
            as Map<String, dynamic>?) ??
        {};
    final opening =
        currentOpening.isNotEmpty
        ? currentOpening
        : (res['opening_hours']
                  as Map<
                    String,
                    dynamic
                  >?) ??
              {};

    final weekdayText =
        (opening['weekday_text']
                as List?)
            ?.cast<String>() ??
        const [];
    final periods =
        (opening['periods'] as List?) ??
        const [];
    final openNow =
        opening['open_now'] as bool?;
    final utcOffset =
        res['utc_offset'] as int?;
    final types =
        (res['types'] as List?)
            ?.cast<String>() ??
        const [];
    final businessStatus =
        res['business_status']
            as String?;

    setState(() {
      _openNow = openNow;
      _weekdayText = weekdayText;
      _periods = periods;
      _utcOffsetMinutes = utcOffset;
      _types = types;
      _businessStatus = businessStatus;
    });
  }

  Future<String?> _imageUrlForPath(
    String path, {
    Duration timeout = const Duration(
      seconds: 8,
    ),
  }) async {
    if (path.isEmpty) return null;
    if (_urlCache.containsKey(path))
      return _urlCache[path];
    try {
      final ref = _coversStorage.ref(
        path,
      );
      final url = await ref
          .getDownloadURL()
          .timeout(timeout);
      _urlCache[path] = url;
      CachedNetworkImageProvider(
        url,
      ).resolve(
        const ImageConfiguration(),
      );
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openInMaps() async {
    final id = widget.placeId;
    final hasLL =
        widget.lat != null &&
        widget.lng != null;
    final nameEnc = Uri.encodeComponent(
      widget.name,
    );
    final ll = hasLL
        ? '${widget.lat!.toStringAsFixed(6)},${widget.lng!.toStringAsFixed(6)}'
        : null;

    // ✅ 1) Preferred: universal links that open the place details page
    // This reliably opens the place card on old and new Android builds.
    final Uri primary = hasLL
        ? Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$nameEnc&query_place_id=$id',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query_place_id=$id',
          );

    // ✅ 2) Alternate universal link that also targets the place page
    final Uri alt = Uri.parse(
      'https://www.google.com/maps/place/?q=place_id:$id',
    );

    // ✅ 3) Fallback: plain geo (last resort; may not open the card)
    final Uri geo = hasLL
        ? Uri.parse(
            'geo:$ll?q=$ll($nameEnc)',
          )
        : Uri.parse(
            'geo:0,0?q=$nameEnc',
          );

    // iOS branch (keep your existing handling if you want, but universal links work too)
    if (Platform.isIOS) {
      // Try universal link first (opens Google Maps app if installed, else Safari)
      if (await canLaunchUrl(primary)) {
        final ok = await launchUrl(
          primary,
          mode: LaunchMode
              .externalApplication,
        );
        if (ok) return;
      }
      // Your previous iOS scheme fallback (Google Maps app)
      final Uri iosGmm = hasLL
          ? Uri.parse(
              'comgooglemaps://?q=$nameEnc&center=$ll&zoom=17&query_place_id=$id',
            )
          : Uri.parse(
              'comgooglemaps://?q=$nameEnc&query_place_id=$id',
            );
      if (await canLaunchUrl(iosGmm)) {
        final ok = await launchUrl(
          iosGmm,
          mode: LaunchMode
              .externalApplication,
        );
        if (ok) return;
      }
      // Final fallback: alt link
      await launchUrl(
        alt,
        mode: LaunchMode
            .externalApplication,
      );
      return;
    }

    // ✅ Android: try universal links first (best compatibility), then geo
    for (final uri in [
      primary,
      alt,
      geo,
    ]) {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode
              .externalApplication,
        );
        if (ok) return;
      }
    }
  }

  // NEW: open website safely
  Future<void> _openWebsite() async {
    final raw = _venueWebsite?.trim();
    if (raw == null || raw.isEmpty)
      return;
    final normalized =
        raw.startsWith('http://') ||
            raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    final uri = Uri.parse(normalized);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode
            .externalApplication,
      );
    }
  }

  // NEW: start phone call (OS will show dialer UI)
  Future<void> _callVenue() async {
    final raw = _venuePhone?.trim();
    if (raw == null || raw.isEmpty)
      return;
    // Keep '+' if present; remove spaces and dashes
    final cleaned = raw.replaceAll(
      RegExp(r'[()\s-]'),
      '',
    );
    final uri = Uri.parse(
      'tel:$cleaned',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // Helper to get venue type display name
  String _getVenueTypeDisplay() {
    if (widget.venueType == null ||
        widget.venueType!.isEmpty) {
      return 'Venue';
    }

    final type = widget.venueType!
        .toLowerCase();
    if (type == 'malls' ||
        type == 'mall') {
      return 'Shopping mall';
    } else if (type == 'stadiums' ||
        type == 'stadium') {
      return 'Stadium';
    } else if (type == 'airports' ||
        type == 'airport') {
      return 'Airport';
    }

    // Capitalize first letter as fallback
    return widget.venueType![0]
            .toUpperCase() +
        widget.venueType!.substring(1);
  }

  // Helper to determine if open 24 hours
  bool _isOpen24Hours() {
    if (_weekdayText.isEmpty)
      return false;
    return _weekdayText.every(
      (line) =>
          line.toLowerCase().contains(
            '24',
          ) ||
          line.toLowerCase().contains(
            'open 24',
          ),
    );
  }

  // Helper to check if temporarily closed
  bool _isTemporarilyClosed() {
    return _businessStatus
            ?.toLowerCase() ==
        'closed_temporarily';
  }

  // Helper to check if hours vary
  bool _hasVaryingHours() {
    if (_weekdayText.isEmpty)
      return false;
    return _weekdayText.any(
      (line) =>
          line.toLowerCase().contains(
            'vary',
          ) ||
          line.toLowerCase().contains(
            'event',
          ),
    );
  }

  String _getOpeningStatus() {
    if (_isTemporarilyClosed()) {
      return 'Temporarily Closed';
    }
    if (_isOpen24Hours()) {
      return 'Open 24 Hours';
    }
    if (_hasVaryingHours()) {
      return 'Hours Vary';
    }
    if (_openNow == true) {
      return 'Open';
    } else if (_openNow == false) {
      return 'Closed';
    }
    return '';
  }

  String _getOpeningTime() {
    if (_isTemporarilyClosed() ||
        _isOpen24Hours() ||
        _hasVaryingHours()) {
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

    final line = _weekdayText
        .firstWhere(
          (l) => l
              .toLowerCase()
              .startsWith(
                labelsSunFirst[today]
                    .toLowerCase(),
              ),
          orElse: () => '',
        );

    if (line.isEmpty) return '';

    final timePart = line.contains(':')
        ? line
              .split(':')
              .sublist(1)
              .join(':')
              .trim()
        : '';

    if (timePart.isEmpty ||
        timePart.toLowerCase() ==
            'closed') {
      return '';
    }

    // If currently open, show closing time
    if (_openNow == true) {
      final match = RegExp(
        r'–\s*(\d{1,2}:\d{2}\s?[AP]M)',
        caseSensitive: false,
      ).firstMatch(timePart);
      if (match != null) {
        return 'Closes at ${match.group(1)}';
      }
    } else {
      // If closed, show opening time
      final match = RegExp(
        r'(\d{1,2}:\d{2}\s?[AP]M)',
        caseSensitive: false,
      ).firstMatch(timePart);
      if (match != null) {
        return 'Opens at ${match.group(1)}';
      }
    }

    return '';
  }

  Color _getStatusColor() {
    if (_isTemporarilyClosed()) {
      return Colors.red;
    }
    if (_isOpen24Hours()) {
      return Colors.green;
    }
    if (_hasVaryingHours()) {
      return Colors.orange;
    }
    if (_openNow == true) {
      return Colors.green;
    } else if (_openNow == false) {
      return Colors.red;
    }
    return Colors.grey;
  }

  void _showImageOverlay(
    int startIndex,
  ) {
    final imagesToShow = widget
        .imagePaths
        .skip(1)
        .toList();

    showDialog(
      context: context,
      barrierColor: Colors.black
          .withOpacity(0.9),
      builder: (context) =>
          _ImageOverlay(
            imagePaths: imagesToShow,
            startIndex: startIndex,
            getUrlFor: _imageUrlForPath,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasWebsite =
        (_venueWebsite != null &&
        _venueWebsite!.isNotEmpty);
    final hasPhone =
        (_venuePhone != null &&
        _venuePhone!.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors
          .grey
          .shade100, // ✅ Light gray background to show rounded white container
      extendBodyBehindAppBar:
          true, // ✅ Make body extend behind app bar
      appBar: AppBar(
        backgroundColor: Colors
            .transparent, // ✅ Transparent app bar
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(
            8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(
                  0,
                  2,
                ),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.black,
              size: 20,
            ),
            onPressed: () =>
                Navigator.pop(context),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                // ✅ Hero image - SLIM height (150px from reference image)
                if (widget
                    .imagePaths
                    .isNotEmpty)
                  _buildHeroImage()
                else
                  SizedBox(
                    height:
                        _headerHeight,
                    child: Container(
                      color: Colors
                          .grey
                          .shade200,
                      child: const Center(
                        child: Icon(
                          Icons
                              .image_not_supported,
                          size: 48,
                        ),
                      ),
                    ),
                  ),

                // ✅ White content section with rounded top corners
                // NOTE: shift up by the same radius amount so the image and the rounded
                // corners overlap perfectly (no white sliver).
                Transform.translate(
                  offset: const Offset(
                    0,
                    -_topRadius,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color:
                          Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft:
                            Radius.circular(
                              _topRadius,
                            ),
                        topRight:
                            Radius.circular(
                              _topRadius,
                            ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const SizedBox(
                          height: 20,
                        ),

                        // ✅ Venue name and type
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                horizontal:
                                    16,
                              ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                widget
                                    .name,
                                style: const TextStyle(
                                  fontSize:
                                      22,
                                  fontWeight:
                                      FontWeight.w700,
                                  color:
                                      kPrimaryGreen,
                                ),
                              ),
                              const SizedBox(
                                height:
                                    4,
                              ),
                              Text(
                                _getVenueTypeDisplay(), // ✅ Dynamic venue type
                                style: TextStyle(
                                  fontSize:
                                      14,
                                  color: Colors
                                      .grey
                                      .shade600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        // ✅ Three action buttons - with GREEN accent color
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                horizontal:
                                    16,
                              ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _actionButton(
                                  icon:
                                      Icons.location_on_outlined,
                                  label:
                                      'Location',
                                  onTap:
                                      _openInMaps,
                                ),
                              ),
                              if (hasWebsite) ...[
                                const SizedBox(
                                  width:
                                      12,
                                ),
                                Expanded(
                                  child: _actionButton(
                                    icon:
                                        Icons.language,
                                    label:
                                        'Website',
                                    onTap:
                                        _openWebsite, // NEW
                                  ),
                                ),
                              ],
                              if (hasPhone) ...[
                                const SizedBox(
                                  width:
                                      12,
                                ),
                                Expanded(
                                  child: _actionButton(
                                    icon:
                                        Icons.phone_outlined,
                                    label:
                                        'Call',
                                    onTap:
                                        _callVenue, // NEW
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(
                          height: 24,
                        ),

                        // ✅ Photo grid - ORIGINAL layout: large left, 2 small squares stacked right
                        if (widget
                                .imagePaths
                                .length >
                            1)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal:
                                  16,
                            ),
                            child:
                                _buildPhotoStrip(), // NEW: horizontal repeating pattern
                          ),

                        const SizedBox(
                          height: 24,
                        ),

                        // ✅ About section - with inline expand arrow
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                horizontal:
                                    16,
                              ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                'About',
                                style: TextStyle(
                                  fontSize:
                                      14,
                                  fontWeight:
                                      FontWeight.w600,
                                  color: Colors
                                      .grey
                                      .shade500,
                                  letterSpacing:
                                      0.5,
                                ),
                              ),
                              const SizedBox(
                                height:
                                    8,
                              ),
                              _buildExpandableText(
                                widget
                                    .description,
                                _aboutExpanded,
                                () => setState(
                                  () => _aboutExpanded =
                                      !_aboutExpanded,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        // ✅ Opening hours - with ALL cases + expand arrow
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                horizontal:
                                    16,
                              ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                'Opening Hours',
                                style: TextStyle(
                                  fontSize:
                                      14,
                                  fontWeight:
                                      FontWeight.w600,
                                  color: Colors
                                      .grey
                                      .shade500,
                                  letterSpacing:
                                      0.5,
                                ),
                              ),
                              const SizedBox(
                                height:
                                    8,
                              ),
                              _buildOpeningHours(),
                            ],
                          ),
                        ),

                        // ✅ Light divider line after opening hours
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                horizontal:
                                    16,
                                vertical:
                                    20,
                              ),
                          child: Divider(
                            color: Colors
                                .grey
                                .shade200,
                            height: 1,
                          ),
                        ),

                        // ✅ Floor Map section - REGULAR heading
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                horizontal:
                                    16,
                              ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const Text(
                                'Floor Map',
                                style: TextStyle(
                                  fontSize:
                                      16,
                                  fontWeight:
                                      FontWeight.w600,
                                  color:
                                      Colors.black,
                                ),
                              ),
                              const SizedBox(
                                height:
                                    12,
                              ),
                              _buildFloorMapViewer(),
                            ],
                          ),
                        ),

                        // ✅ Light divider line after floor map
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                horizontal:
                                    16,
                                vertical:
                                    20,
                              ),
                          child: Divider(
                            color: Colors
                                .grey
                                .shade200,
                            height: 1,
                          ),
                        ),

                        // ✅ Discover More section - REGULAR heading
                        Padding(
                          padding:
                              EdgeInsets.symmetric(
                                horizontal:
                                    16,
                              ),
                          child: Text(
                            'Discover More',
                            style: TextStyle(
                              fontSize:
                                  14,
                              fontWeight:
                                  FontWeight
                                      .w600,
                              color: Colors
                                  .grey
                                  .shade500,
                              letterSpacing:
                                  0.5,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 12,
                        ),

                        SizedBox(
                          height: 180,
                          child:
                              StreamBuilder<
                                QuerySnapshot<
                                  Map<
                                    String,
                                    dynamic
                                  >
                                >
                              >(
                                stream: FirebaseFirestore
                                    .instance
                                    .collection(
                                      'venues',
                                    )
                                    .doc(
                                      widget.placeId,
                                    )
                                    .collection(
                                      'categories',
                                    )
                                    .snapshots(),
                                builder:
                                    (
                                      context,
                                      snapshot,
                                    ) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return Center(
                                          child: Text(
                                            'Error: ${snapshot.error}',
                                          ),
                                        );
                                      }

                                      final docs =
                                          snapshot.data?.docs ??
                                          [];
                                      if (docs.isEmpty) {
                                        return const Center(
                                          child: Text(
                                            'No categories found.',
                                          ),
                                        );
                                      }

                                      return ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        itemCount: docs.length,
                                        separatorBuilder:
                                            (
                                              _,
                                              __,
                                            ) => const SizedBox(
                                              width: 12,
                                            ),
                                        itemBuilder:
                                            (
                                              context,
                                              i,
                                            ) {
                                              final categoryId = docs[i].id;
                                              final data = docs[i].data();
                                              final name =
                                                  data['categoryName'] ??
                                                  'Unnamed';
                                              final image =
                                                  data['categoryImage'] ??
                                                  'images/default.jpg';

                                              return _categoryCard(
                                                context,
                                                name,
                                                image,
                                                widget.placeId,
                                                categoryId,
                                                _imageUrlForCategory,
                                              );
                                            },
                                      );
                                    },
                              ),
                        ),

                        const SizedBox(
                          height: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ✅ Hero image - SLIM height (150px)
  Widget _buildHeroImage() {
    final path =
        widget.imagePaths.first;

    if (widget.initialCoverUrl !=
            null &&
        widget
            .initialCoverUrl!
            .isNotEmpty) {
      return SizedBox(
        height: _headerHeight,
        width: double.infinity,
        child: Image.network(
          widget.initialCoverUrl!,
          fit: BoxFit.cover,
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _imageUrlForPath(path),
      builder: (context, snap) {
        if (snap.connectionState ==
            ConnectionState.waiting) {
          return SizedBox(
            height: _headerHeight,
            child: Container(
              color:
                  Colors.grey.shade200,
              child: const Center(
                child:
                    CircularProgressIndicator(),
              ),
            ),
          );
        }
        if (snap.hasError ||
            snap.data == null ||
            snap.data!.isEmpty) {
          return SizedBox(
            height: _headerHeight,
            child: Container(
              color:
                  Colors.grey.shade200,
              child: const Center(
                child: Icon(
                  Icons
                      .image_not_supported,
                  size: 48,
                ),
              ),
            ),
          );
        }
        return SizedBox(
          height: _headerHeight,
          width: double.infinity,
          child: Image.network(
            snap.data!,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  // ✅ Action button - with GREEN accent color
  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius:
              BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: kPrimaryGreen,
              size: 20,
            ), // ✅ GREEN color
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color:
                    kPrimaryGreen, // ✅ GREEN color
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === NEW: HORIZONTAL STRIP repeating your 3-tile pattern ===
  Widget _buildPhotoStrip() {
    final images =
        widget.imagePaths.length > 1
        ? widget.imagePaths.sublist(1)
        : const <String>[];

    if (images.isEmpty)
      return const SizedBox.shrink();

    final width =
        MediaQuery.of(
          context,
        ).size.width -
        32;

    final pageCount =
        (images.length / 3).ceil();

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection:
            Axis.horizontal,
        itemCount: pageCount,
        physics:
            const BouncingScrollPhysics(),
        itemBuilder: (context, page) {
          final start = page * 3;

          String? img0 =
              (start < images.length)
              ? images[start]
              : null;
          String? img1 =
              (start + 1 <
                  images.length)
              ? images[start + 1]
              : null;
          String? img2 =
              (start + 2 <
                  images.length)
              ? images[start + 2]
              : null;

          return Container(
            width: width,
            margin: EdgeInsets.only(
              right:
                  page == pageCount - 1
                  ? 0
                  : 12,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child:
                      _gridImageOrBlank(
                        img0,
                        true,
                        start,
                      ),
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child:
                            _gridImageOrBlank(
                              img1,
                              false,
                              start + 1,
                            ),
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      Expanded(
                        child:
                            _gridImageOrBlank(
                              img2,
                              false,
                              start + 2,
                            ),
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

  Widget _gridImageOrBlank(
    String? path,
    bool large,
    int index,
  ) {
    if (path == null || path.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(8),
        ),
      );
    }
    return _gridImage(
      path,
      large,
      index,
    );
  }

  Widget _gridImage(
    String path,
    bool large,
    int index,
  ) {
    return GestureDetector(
      onTap: () =>
          _showImageOverlay(index),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(8),
        child: FutureBuilder<String?>(
          future: _imageUrlForPath(
            path,
          ),
          builder: (context, snap) {
            if (snap.connectionState ==
                ConnectionState
                    .waiting) {
              return Container(
                color: Colors
                    .grey
                    .shade200,
                child: const Center(
                  child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                ),
              );
            }
            if (snap.hasError ||
                snap.data == null ||
                snap.data!.isEmpty) {
              return Container(
                color: Colors
                    .grey
                    .shade200,
                child: const Center(
                  child: Icon(
                    Icons
                        .image_not_supported,
                    size: 24,
                  ),
                ),
              );
            }
            return CachedNetworkImage(
              imageUrl: snap.data!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholder:
                  (context, url) =>
                      Container(
                        color: Colors
                            .grey
                            .shade200,
                      ),
              errorWidget:
                  (
                    context,
                    url,
                    error,
                  ) => Container(
                    color: Colors
                        .grey
                        .shade200,
                    child: const Icon(
                      Icons.error,
                    ),
                  ),
            );
          },
        ),
      ),
    );
  }

  // ✅ Expandable text with INLINE arrow at end of line 2
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final probe =
            TextPainter(
              text: TextSpan(
                text: text,
                style: style,
              ),
              maxLines: 2,
              textDirection:
                  TextDirection.ltr,
            )..layout(
              maxWidth:
                  constraints.maxWidth,
            );
        final exceeded =
            probe.didExceedMaxLines;

        if (!exceeded) {
          return Text(
            text,
            style: style,
          );
        }

        if (isExpanded) {
          return Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Text(text, style: style),
              InkWell(
                onTap: onTap,
                borderRadius:
                    BorderRadius.circular(
                      8,
                    ),
                child: Padding(
                  padding:
                      const EdgeInsets.only(
                        top: 6,
                        right: 8,
                      ),
                  child: Icon(
                    Icons
                        .keyboard_arrow_up,
                    size: 22,
                    color: Colors
                        .grey
                        .shade600,
                  ),
                ),
              ),
            ],
          );
        }

        // Collapsed: text ellipsizes to 2 lines; arrow sits in a narrow trailing slot
        return Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow
                    .ellipsis,
                style: style,
              ),
            ),
            InkWell(
              onTap: onTap,
              borderRadius:
                  BorderRadius.circular(
                    8,
                  ),
              child: Padding(
                padding:
                    const EdgeInsets.only(
                      left: 6,
                      right: 6,
                    ),
                child: Icon(
                  Icons
                      .keyboard_arrow_down,
                  size: 20,
                  color: Colors
                      .grey
                      .shade600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ✅ Opening hours with ALL cases + expand arrow
  Widget _buildOpeningHours() {
    final status = _getOpeningStatus();
    final time = _getOpeningTime();

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (_weekdayText
                    .isNotEmpty &&
                !_isOpen24Hours() &&
                !_isTemporarilyClosed() &&
                !_hasVaryingHours()) {
              setState(
                () => _hoursExpanded =
                    !_hoursExpanded,
              );
            }
          },
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (status
                        .isNotEmpty)
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 15,
                          color:
                              _getStatusColor(),
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                      ),
                    if (status
                            .isNotEmpty &&
                        time.isNotEmpty)
                      Text(
                        ' • ',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors
                              .grey
                              .shade600,
                        ),
                      ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors
                              .black87,
                        ),
                      ),
                  ],
                ),
              ),
              if (_weekdayText
                      .isNotEmpty &&
                  !_isOpen24Hours() &&
                  !_isTemporarilyClosed() &&
                  !_hasVaryingHours())
                InkWell(
                  onTap: () => setState(
                    () => _hoursExpanded =
                        !_hoursExpanded,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                        8,
                      ),
                  child: Padding(
                    padding:
                        const EdgeInsets.only(
                          left: 8,
                          right: 6,
                        ),
                    child: Icon(
                      _hoursExpanded
                          ? Icons
                                .keyboard_arrow_up
                          : Icons
                                .keyboard_arrow_down,
                      size: 22,
                      color: Colors
                          .grey
                          .shade600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_hoursExpanded &&
            _weekdayText.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.only(
                  top: 12,
                ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: _weekdayText.map((
                line,
              ) {
                final parts = line
                    .split(':');
                if (parts.length < 2)
                  return const SizedBox.shrink();

                final day = parts[0]
                    .trim();
                final hours = parts
                    .sublist(1)
                    .join(':')
                    .trim();

                final now =
                    DateTime.now();
                final today =
                    now.weekday % 7;
                const days = [
                  'Sunday',
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                ];
                final isToday =
                    day.toLowerCase() ==
                    days[today]
                        .toLowerCase();

                return Padding(
                  padding:
                      const EdgeInsets.only(
                        bottom: 8,
                      ),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .spaceBetween,
                    children: [
                      Text(
                        day,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isToday
                              ? FontWeight
                                    .w600
                              : FontWeight
                                    .normal,
                          color: isToday
                              ? Colors
                                    .black
                              : Colors
                                    .grey
                                    .shade700,
                        ),
                      ),
                      Text(
                        hours,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors
                              .grey
                              .shade600,
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

  Future<String?> _imageUrlForCategory(
    String path,
  ) async {
    if (path.isEmpty) return null;
    if (_urlCache.containsKey(path))
      return _urlCache[path];
    try {
      final ref = _coversStorage.ref(
        path,
      );
      final url = await ref
          .getDownloadURL()
          .timeout(
            const Duration(seconds: 8),
          );
      _urlCache[path] = url;
      CachedNetworkImageProvider(
        url,
      ).resolve(
        const ImageConfiguration(),
      );
      return url;
    } catch (_) {
      return null;
    }
  }

  static Widget _categoryCard(
    BuildContext context,
    String title,
    String imagePath,
    String venueId,
    String categoryId,
    Future<String?> Function(String)
    getUrlFor,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CategoryPage(
                  categoryName: title,
                  venueId: venueId,
                  categoryId:
                      categoryId,
                ),
          ),
        );
      },
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                    8,
                  ),
              child: FutureBuilder<String?>(
                future: getUrlFor(
                  imagePath,
                ),
                builder: (context, snap) {
                  if (snap.connectionState ==
                      ConnectionState
                          .waiting) {
                    return Container(
                      height: 130,
                      width: 130,
                      color: Colors
                          .grey
                          .shade200,
                      child: const Center(
                        child:
                            CircularProgressIndicator(
                              strokeWidth:
                                  2,
                            ),
                      ),
                    );
                  }
                  if (snap.hasError ||
                      snap.data ==
                          null ||
                      snap
                          .data!
                          .isEmpty) {
                    return Container(
                      height: 130,
                      width: 130,
                      color: Colors
                          .grey
                          .shade200,
                      child: const Center(
                        child: Icon(
                          Icons
                              .image_not_supported,
                        ),
                      ),
                    );
                  }
                  return CachedNetworkImage(
                    imageUrl:
                        snap.data!,
                    height: 130,
                    width: 130,
                    fit: BoxFit.cover,
                  );
                },
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.all(
                    8,
                  ),
              child: Text(
                title,
                textAlign:
                    TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow
                    .ellipsis,
                style: const TextStyle(
                  fontWeight:
                      FontWeight.w600,
                  fontSize: 13,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // Floor map state

  Widget _buildFloorMapViewer() {
    // Check if the venue is Solitaire
    bool isSolitaire = widget.name
        .toLowerCase()
        .contains('solitaire');

    if (!isSolitaire) {
      // Return the old placeholder design for non-Solitaire venues
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius:
              BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            Icons.map_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
        ),
      );
    }

    // Return the interactive 3D map for Solitaire venue
    return _FloorMapSection(
      currentFloor: _currentFloor,
      onFloorChanged: (String newFloor) {
        // This will only update the state without rebuilding the entire page
        _currentFloor = newFloor;
      },
    );
  }
}

// Separate widget for the 3D viewer - only rebuilds when floor changes
class _FloorMapViewer
    extends StatelessWidget {
  final String currentFloor;

  const _FloorMapViewer({
    required this.currentFloor,
  });

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      key: ValueKey(
        currentFloor,
      ), // Forces rebuild only when floor changes
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
      fieldOfView: "45deg",
    );
  }
}

// Complete floor map section as a separate widget
class _FloorMapSection
    extends StatefulWidget {
  final String currentFloor;
  final Function(String) onFloorChanged;

  const _FloorMapSection({
    required this.currentFloor,
    required this.onFloorChanged,
  });

  @override
  State<_FloorMapSection>
  createState() =>
      _FloorMapSectionState();
}

class _FloorMapSectionState
    extends State<_FloorMapSection> {
  late String _currentFloor;

  @override
  void initState() {
    super.initState();
    _currentFloor = widget.currentFloor;
  }

  @override
  void didUpdateWidget(
    _FloorMapSection oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentFloor !=
        widget.currentFloor) {
      _currentFloor =
          widget.currentFloor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 250,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.only(
                    topLeft:
                        Radius.circular(
                          12,
                        ),
                    topRight:
                        Radius.circular(
                          12,
                        ),
                  ),
            ),
            child: Stack(
              children: [
                _FloorMapViewer(
                  currentFloor:
                      _currentFloor,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.all(
                          8,
                        ),
                    decoration: BoxDecoration(
                      color: Colors
                          .white
                          .withOpacity(
                            0.9,
                          ),
                      borderRadius:
                          BorderRadius.circular(
                            8,
                          ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors
                              .black
                              .withOpacity(
                                0.1,
                              ),
                          blurRadius: 4,
                          offset:
                              const Offset(
                                0,
                                2,
                              ),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildFloorButton(
                          '1',
                          'assets/maps/F2_map.glb',
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        _buildFloorButton(
                          'G',
                          'assets/maps/F1_map.glb',
                        ),
                      ],
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

  Widget _buildFloorButton(
    String label,
    String floorAsset,
  ) {
    bool isSelected =
        _currentFloor == floorAsset;

    return Container(
      width: 42,
      height: 36,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected
              ? kPrimaryGreen
              : Colors.white,
          foregroundColor: isSelected
              ? Colors.white
              : kPrimaryGreen,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
                  8,
                ),
            side: BorderSide(
              color: isSelected
                  ? kPrimaryGreen
                  : Colors
                        .grey
                        .shade300,
              width: 1.5,
            ),
          ),
          elevation: isSelected ? 2 : 0,
          shadowColor: Colors.black
              .withOpacity(0.1),
        ),
        onPressed: () {
          setState(() {
            _currentFloor = floorAsset;
          });
          widget.onFloorChanged(
            floorAsset,
          );
        },
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ImageOverlay
    extends StatefulWidget {
  final List<String> imagePaths;
  final int startIndex;
  final Future<String?> Function(String)
  getUrlFor;

  const _ImageOverlay({
    required this.imagePaths,
    required this.startIndex,
    required this.getUrlFor,
  });

  @override
  State<_ImageOverlay> createState() =>
      _ImageOverlayState();
}

class _ImageOverlayState
    extends State<_ImageOverlay> {
  late final PageController
  _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _pageController = PageController(
      initialPage: widget.startIndex,
    );
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
            onPageChanged: (index) =>
                setState(
                  () => _currentIndex =
                      index,
                ),
            itemCount: widget
                .imagePaths
                .length,
            itemBuilder: (context, index) {
              return Center(
                child: FutureBuilder<String?>(
                  future: widget.getUrlFor(
                    widget
                        .imagePaths[index],
                  ),
                  builder: (context, snap) {
                    if (snap.connectionState ==
                        ConnectionState
                            .waiting) {
                      return const CircularProgressIndicator();
                    }
                    if (snap.hasError ||
                        snap.data ==
                            null ||
                        snap
                            .data!
                            .isEmpty) {
                      return const Icon(
                        Icons.error,
                        color: Colors
                            .white,
                        size: 48,
                      );
                    }
                    return InteractiveViewer(
                      child: CachedNetworkImage(
                        imageUrl:
                            snap.data!,
                        fit: BoxFit
                            .contain,
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Positioned(
            top:
                MediaQuery.of(
                  context,
                ).padding.top +
                8,
            right: 16,
            child: IconButton(
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () =>
                  Navigator.pop(
                    context,
                  ),
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
                  fontWeight:
                      FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
