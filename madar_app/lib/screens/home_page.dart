// ✅ NEW HOME PAGE - Following EXACTLY the reference image
// Large cards with image, name overlay, stars, and distance

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:madar_app/screens/venue_page.dart';
import 'package:madar_app/api/data_fetcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:madar_app/api/venue_cache_service.dart';
import 'package:madar_app/widgets/app_widgets.dart';

const double _riyadhLat = 24.7136;
const double _riyadhLng = 46.6753;

const Color kPrimaryGreen = Color(0xFF777D63);

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  @override
  void dispose() {
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true; // ✅ Keep state alive when navigating away

  final storage.FirebaseStorage _coversStorage =
      storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      );

  final List<String> filters = const ['All', 'Malls', 'Stadiums', 'Airports'];

  int selectedFilterIndex = 0;
  String _query = '';
  bool _loading = true;
  String? _error;

  // ✅ Static variables persist across widget rebuilds (survive navigation)
  static List<VenueData> _staticAllVenues = []; // Master list loaded once
  static final Map<String, String> _staticImageCache = {};
  static final Map<String, double> _staticRatingCache = {};
  static bool _hasLoadedOnce = false; // Track if we've loaded data before

  // ✅ Instance variables for UI state
  List<VenueData> _venues = []; // Filtered/displayed list
  double baseLat = _riyadhLat, baseLng = _riyadhLng;

  late final VenueCacheService _cache = VenueCacheService(
    FirebaseFirestore.instance,
  );

  // ✅ Use static cache references in instance
  Map<String, String> get _imageCache => _staticImageCache;
  Map<String, double> get _ratingCache => _staticRatingCache;
  List<VenueData> get _allVenues => _staticAllVenues;
  set _allVenues(List<VenueData> value) => _staticAllVenues = value;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    // ✅ Check static flag - if already loaded, just display cached data
    if (_hasLoadedOnce && _allVenues.isNotEmpty) {
      // Already loaded - just refresh the display instantly
      setState(() {
        _loading = false;
      });
      _applyLocalFilterAndSort();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (enabled &&
            perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final p = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          baseLat = p.latitude;
          baseLng = p.longitude;
        }
      } catch (_) {}

      await _loadAllVenues();
      _applyLocalFilterAndSort();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _venues = [];
      });
    }
  }

  // ✅ Load ALL venues once from Firestore
  Future<void> _loadAllVenues() async {
    try {
      final col = FirebaseFirestore.instance.collection('venues');
      final snap = await col.get();
      debugPrint('🟢 All venues fetched: ${snap.docs.length}');

      final items = <VenueData>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final String? name = (d['venueName'] as String?)?.trim();
        final String? address = (d['venueAddress'] as String?)?.trim();
        final String? description = (d['venueDescription'] as String?)?.trim();
        final String? categoryStr = (d['venueType'] as String?)?.trim();
        final String placeId = doc.id;

        final double? lat = (d['latitude'] as num?)?.toDouble();
        final double? lng = (d['longitude'] as num?)?.toDouble();

        List<String> imagePaths = [];
        final images = d['venueImages'];
        if (images is String && images.isNotEmpty) {
          imagePaths = [images];
        } else if (images is List) {
          imagePaths = images
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .toList();
        }

        double? dist;
        if (lat != null && lng != null) {
          dist = Geolocator.distanceBetween(baseLat, baseLng, lat, lng);
        } else {
          dist = 1e12;
        }

        final double? rating = _ratingCache[placeId];
        items.add(
          VenueData(
            placeId: placeId,
            name: name,
            address: address,
            description: description,
            lat: lat,
            lng: lng,
            rating: rating ?? 0,
            imagePaths: imagePaths,
            thumbPath: null,
            category: categoryStr,
            distanceMeters: dist,
          ),
        );
      }

      items.sort(
        (a, b) =>
            (a.distanceMeters ?? 1e12).compareTo(b.distanceMeters ?? 1e12),
      );

      if (mounted) {
        _allVenues = items;
        _hasLoadedOnce = true; // ✅ Mark as loaded
        setState(() => _loading = false);
      }

      _kickOffRatings(items);
      _prefetchCoverUrls(items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _kickOffRatings(List<VenueData> items) async {
    for (final v in items) {
      final pid = v.placeId;
      if (pid == null || pid.isEmpty) continue;
      if (_ratingCache.containsKey(pid)) continue;
      _fetchRating(v);
    }
  }

  Future<void> _prefetchCoverUrls(List<VenueData> items) async {
    for (final v in items) {
      final p = (v.thumbPath?.isNotEmpty == true)
          ? v.thumbPath
          : (v.imagePaths.isNotEmpty ? v.imagePaths.first : null);
      if (p == null || p.isEmpty) continue;
      if (_imageCache.containsKey(p)) continue;
      try {
        final ref = _coversStorage.ref(p);
        final url = await ref.getDownloadURL().timeout(
          const Duration(seconds: 8),
        );
        _imageCache[p] = url;
        CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      } catch (_) {}
    }
  }

  Future<void> _fetchRating(VenueData v) async {
    try {
      final meta = await _cache
          .getMonthlyMeta(v.placeId!)
          .timeout(const Duration(seconds: 8));

      final r = (meta.rating ?? 0).toDouble();
      _ratingCache[v.placeId!] = r;

      if (!mounted) return;

      // ✅ Update rating in master list
      for (final it in _allVenues) {
        if (it.placeId == v.placeId) {
          it.rating = r;
          break;
        }
      }

      _applyLocalFilterAndSort();
    } catch (_) {}
  }

  // ✅ Client-side filtering - NO network calls, NO reload
  void _applyLocalFilterAndSort() {
    final tab = filters[selectedFilterIndex];
    List<VenueData> base = _allVenues;

    // Apply filter based on selected tab
    if (tab == 'Malls') {
      base = _allVenues.where((v) => v.category == 'malls').toList();
    } else if (tab == 'Stadiums') {
      base = _allVenues.where((v) => v.category == 'stadiums').toList();
    } else if (tab == 'Airports') {
      base = _allVenues.where((v) => v.category == 'airports').toList();
    }
    // else tab == 'All', use all venues

    // Apply search query if present
    List<VenueData> out = base;
    if (_query.isNotEmpty) {
      final ql = _query.toLowerCase();
      out = base
          .where((v) => (v.name ?? '').toLowerCase().contains(ql))
          .toList();
    }

    setState(() => _venues = out);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const SizedBox(height: 8),
          // ✅ Search bar
          _buildSearchBar(),
          const SizedBox(height: 12),

          // ✅ Filter tabs - NEW rounded design
          _buildFilterTabs(),

          const SizedBox(height: 16),

          // ✅ Main content
          Expanded(
            child: _loading
                ? const AppLoadingIndicator()
                : _error != null
                ? Center(child: Text('Error: $_error'))
                : _venues.isEmpty
                ? const Center(
                    child: Text('No results found. Try again'),
                  ) //no result in search msg
                : _buildVenueList(),
          ),
        ],
      ),
    );
  }

  // ✅ NEW search bar - identical to home page
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey.shade600, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() {
                _query = v;
                _applyLocalFilterAndSort();
              }),
              decoration: const InputDecoration(
                hintText: 'Search for a venue',
                hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW filter tabs with rounded design
  Widget _buildFilterTabs() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, idx) {
          final isSelected = idx == selectedFilterIndex;
          return GestureDetector(
            onTap: () {
              // ✅ Instant client-side filtering - NO loading, NO network
              setState(() {
                selectedFilterIndex = idx;
              });
              _applyLocalFilterAndSort();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? kPrimaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? kPrimaryGreen : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  filters[idx],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : Colors.grey.shade500, // filters font color
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVenueList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _venues.length,
      itemBuilder: (context, index) => _buildVenueCard(_venues[index]),
    );
  }

  void _openVenue(VenueData v) async {
    debugPrint('🟢 Opening venue: ${v.name}');
    if (v.placeId == null) return;

    final hasPlaces = await FirebaseFirestore.instance
        .collection('places')
        .where('venue_ID', isEqualTo: v.placeId)
        .limit(1)
        .get();

    final String? path = (v.thumbPath?.isNotEmpty == true)
        ? v.thumbPath
        : (v.imagePaths.isNotEmpty ? v.imagePaths.first : null);
    String? coverUrl = (path != null) ? _imageCache[path] : null;

    if (coverUrl == null && path != null && path.isNotEmpty) {
      try {
        final ref = _coversStorage.ref(path);
        coverUrl = await ref.getDownloadURL().timeout(
          const Duration(seconds: 5),
        );
        _imageCache[path] = coverUrl!;
      } catch (_) {}
    }

    if (hasPlaces.docs.isEmpty) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => DataFetcher(
            venueId: v.placeId!,
            venueName: v.name ?? '',
            dbAddress: v.address,
            lat: v.lat,
            lng: v.lng,
            description: v.description,
            imagePaths: v.imagePaths,
            initialCoverUrl: coverUrl,
          ),
        ),
      );
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => VenuePage(
            placeId: v.placeId!,
            name: v.name ?? '',
            description: v.description ?? '',
            dbAddress: v.address,
            initialCoverUrl: coverUrl,
            imagePaths: v.imagePaths,
            lat: v.lat,
            lng: v.lng,
            venueType: v.category,
          ),
        ),
      );
    }
  }

  Future<String?> _imageUrlFor(VenueData v) async {
    final String? storagePath = (v.thumbPath?.isNotEmpty == true)
        ? v.thumbPath
        : (v.imagePaths.isNotEmpty ? v.imagePaths.first : null);
    if (storagePath == null || storagePath.isEmpty) {
      if (kDebugMode) debugPrint('COVER: ${v.name} has no cover path.');
      return null;
    }
    final cached = _imageCache[storagePath];
    if (cached != null) return cached;
    Future<String?> _try(Duration t) async {
      final ref = _coversStorage.ref(storagePath);
      final url = await ref.getDownloadURL().timeout(t);
      _imageCache[storagePath] = url;
      CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      return url;
    }

    try {
      return await _try(const Duration(seconds: 5));
    } catch (_) {
      try {
        return await _try(const Duration(seconds: 3));
      } catch (_) {
        return null;
      }
    }
  }

  // ✅ Large venue card with image, name overlay, stars, distance
  Widget _buildVenueCard(VenueData v) {
    final distanceText = (v.distanceMeters ?? 0) < 1000
        ? '${(v.distanceMeters ?? 0).round()} m'
        : '${((v.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km';

    return GestureDetector(
      onTap: () => _openVenue(v),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // ✅ Background image
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildVenueImage(v),
            ),
            // ✅ Gradient overlay for text readability
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ),
              ),
            ),
            // ✅ Content overlay
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Venue name
                  Text(
                    v.name ?? 'Unnamed',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // ✅ Star rating
                  Row(
                    children: [
                      _buildStars(v.rating ?? 0),
                      const Spacer(),
                      // Distance
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            distanceText,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Star rating widget - filled based on actual rating
  Widget _buildStars(double rating) {
    return Row(
      children: List.generate(5, (index) {
        if (rating >= index + 1) {
          // Full star
          return const Icon(Icons.star, color: kPrimaryGreen, size: 20);
        } else if (rating > index && rating < index + 1) {
          // Half star
          return const Icon(Icons.star_half, color: kPrimaryGreen, size: 20);
        } else {
          // Empty star
          return Icon(Icons.star_border, color: Colors.grey.shade400, size: 20);
        }
      }),
    );
  }

  // ✅ Build venue image with smart caching - skips loading if already cached
  Widget _buildVenueImage(VenueData v) {
    final String? storagePath = (v.thumbPath?.isNotEmpty == true)
        ? v.thumbPath
        : (v.imagePaths.isNotEmpty ? v.imagePaths.first : null);

    if (storagePath == null || storagePath.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: Icon(
          Icons.image_not_supported,
          color: Colors.grey.shade400,
          size: 48,
        ),
      );
    }

    // ✅ If already cached, show immediately without loading indicator
    if (_imageCache.containsKey(storagePath)) {
      return CachedNetworkImage(
        imageUrl: _imageCache[storagePath]!,
        cacheKey: storagePath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey.shade200),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey.shade200,
          child: Icon(
            Icons.image_not_supported,
            color: Colors.grey.shade400,
            size: 48,
          ),
        ),
      );
    }

    // Not cached - load with indicator
    return FutureBuilder<String?>(
      future: _imageUrlFor(v),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
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
          );
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return Container(
            color: Colors.grey.shade200,
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey.shade400,
              size: 48,
            ),
          );
        }
        return CachedNetworkImage(
          imageUrl: snap.data!,
          cacheKey: storagePath,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey.shade200),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade200,
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey.shade400,
              size: 48,
            ),
          ),
        );
      },
    );
  }
}

class VenueData {
  final String? placeId;
  final String? name;
  final String? address;
  final String? description;
  final double? lat;
  final double? lng;
  double? rating;
  final String? thumbPath;
  final String? category;
  double? distanceMeters;
  final List<String> imagePaths;

  VenueData({
    this.placeId,
    this.name,
    this.address,
    this.description,
    this.lat,
    this.lng,
    this.rating,
    this.thumbPath,
    this.category,
    this.distanceMeters,
    this.imagePaths = const [],
  });
}
/////