import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:madar_app/screens/venue_page.dart';

// Firestore + Storage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;

// Debug
import 'package:flutter/foundation.dart'; // kDebugMode

// HTTP image cache
import 'package:cached_network_image/cached_network_image.dart';

/// ------------------ Categories & curated names ------------------

const double _riyadhLat = 24.7136;
const double _riyadhLng = 46.6753;

/// ------------------ Screen ------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  // firebase storage
  final storage.FirebaseStorage _coversStorage =
      storage.FirebaseStorage.instanceFor(
        bucket: 'gs://madar-database.firebasestorage.app',
      );
  final Color activeColor = const Color(0xFF787E65);
  final List<String> filters = const ['All', 'Malls', 'Stadiums', 'Airports'];

  int selectedFilterIndex = 0;
  String _query = '';

  bool _loading = true;
  String? _error;

  // live list after local filtering
  List<VenueData> _venues = [];

  // Location (fallback Riyadh center)
  double baseLat = _riyadhLat, baseLng = _riyadhLng;

  // Places service
  late final _PlacesSvc _svc = _PlacesSvc(
    dotenv.maybeGet('GOOGLE_API_KEY') ?? '',
  );

  // Concurrency guard
  int _loadToken = 0;
  bool _isLoadingNow = false;

  // in-memory cache for resolved {storage path -> downloadURL}
  final Map<String, String> _imageCache = {};

  // cache Firestore per tab
  final Map<String, List<VenueData>> _tabCache = {};

  // cache ratings
  final Map<String, double> _ratingCache = {};

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // get device location (fallback Riyadh)
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

      await _ensureTabLoaded(); // will serve from cache if present
      _applyLocalFilterAndSort(); // render
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _venues = [];
      });
    }
  }

  /// Ensures the current tab’s data exists in cache. Fetches ONCE per tab.
  Future<void> _ensureTabLoaded() async {
    final tab = filters[selectedFilterIndex];
    if (_tabCache.containsKey(tab)) return;
    await _loadTab(tab);
  }

  /// Fetch Firestore for a tab and populate cache (no Storage awaits here)
  Future<void> _loadTab(String tab) async {
    final myToken = ++_loadToken;
    if (_isLoadingNow) return;
    _isLoadingNow = true;

    try {
      // 1) read from Firestore
      final col = FirebaseFirestore.instance.collection('venues');

      Query<Map<String, dynamic>> q = col;
      // filter by venueType
      if (tab == 'Malls') {
        q = q.where('venueType', isEqualTo: 'malls');
      } else if (tab == 'Stadiums') {
        q = q.where('venueType', isEqualTo: 'stadiums');
      } else if (tab == 'Airports') {
        q = q.where('venueType', isEqualTo: 'airports');
      }

      final snap = await q.get();
      debugPrint('venues fetched: ${snap.docs.length} (tab=$tab)');

      final items = <VenueData>[];

      // 2) Build items
      for (final doc in snap.docs) {
        final d = doc.data();

        final String? name = (d['venueName'] as String?)?.trim();
        final String? address = (d['venueAddress'] as String?)?.trim();
        final String? description = (d['venueDescription'] as String?)?.trim();
        final String? categoryStr = (d['venueType'] as String?)?.trim();

        final String placeId = doc.id;

        final double? lat = (d['latitude'] as num?)?.toDouble();
        final double? lng = (d['longitude'] as num?)?.toDouble();

        // images from venueImages (string or list)
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

      // 3) sort by distance
      items.sort(
        (a, b) =>
            (a.distanceMeters ?? 1e12).compareTo(b.distanceMeters ?? 1e12),
      );

      // 4) cache + show
      if (mounted && myToken == _loadToken) {
        _tabCache[tab] = items;
        setState(() {
          _loading = false;
        });
      }

      // 5) ratings in background
      _kickOffRatings(items);

      // 6) warm first image url
      _prefetchCoverUrls(items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } finally {
      _isLoadingNow = false;
    }
  }

  // if no venue image available
  Widget _noImageBox() {
    return Container(
      color: const Color(0xFFEDEFE3),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.black45,
        size: 40,
      ),
    );
  }

  // ratings (background)
  Future<void> _kickOffRatings(List<VenueData> items) async {
    if (_svc.apiKey.isEmpty) return;
    for (final v in items) {
      final pid = v.placeId;
      if (pid == null || pid.isEmpty) continue;
      if (_ratingCache.containsKey(pid)) continue;
      _fetchRating(v);
    }
  }

  // warm image cache
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

        // warm bytes
        // ignore: unused_result
        CachedNetworkImageProvider(url).resolve(const ImageConfiguration());
      } catch (_) {}
    }
  }

  // fetch a single rating
  Future<void> _fetchRating(VenueData v) async {
    try {
      final details = await _svc
          .details(v.placeId!)
          .timeout(const Duration(seconds: 6));
      if (details == null) return;
      final r = (details['rating'] ?? 0).toDouble();

      _ratingCache[v.placeId!] = r;

      if (!mounted) return;

      final tab = filters[selectedFilterIndex];
      final list = _tabCache[tab];
      if (list != null) {
        for (final it in list) {
          if (it.placeId == v.placeId) {
            it.rating = r;
            break;
          }
        }
      }
      _applyLocalFilterAndSort();
    } catch (_) {}
  }

  // local filter + keep distance order
  void _applyLocalFilterAndSort() {
    final tab = filters[selectedFilterIndex];
    final base = _tabCache[tab] ?? [];
    List<VenueData> out = base;

    if (_query.isNotEmpty) {
      final ql = _query.toLowerCase();
      out = base
          .where((v) => (v.name ?? '').toLowerCase().contains(ql))
          .toList();
    }

    setState(() {
      _venues = out;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildFilterTabs(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildVenueList(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (q) {
          _query = q;
          _applyLocalFilterAndSort();
        },
        decoration: const InputDecoration(
          hintText: 'Search for a venue ...',
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      height: 35,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final isSelected = selectedFilterIndex == index;
          return GestureDetector(
            onTap: () async {
              setState(() => selectedFilterIndex = index);
              await _ensureTabLoaded();
              _applyLocalFilterAndSort();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.grey[200],
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Text(
                  filters[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
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
    if (_venues.isEmpty) {
      return const Center(child: Text('No items.'));
    }
    return ListView.builder(
      itemCount: _venues.length,
      itemBuilder: (context, index) => _buildVenueCard(_venues[index]),
    );
  }

  void _openVenue(VenueData v) async {
    if (v.placeId == null) return;

    // pre-resolved image URL for first image
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

    Navigator.push(
      context,
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
        ),
      ),
    );
  }

  // resolve first image url for cards
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
      // warm bytes
      // ignore: unused_result
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

  Widget _buildVenueCard(VenueData v) {
    final distanceText = (v.distanceMeters ?? 0) < 1000
        ? '${(v.distanceMeters ?? 0).round()} m'
        : '${((v.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km';

    return InkWell(
      onTap: () => _openVenue(v),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 100,
                height: 100,
                child: FutureBuilder<String?>(
                  future: _imageUrlFor(v),
                  builder: (context, snap) {
                    // steady loader
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Container(
                        color: Colors.grey[200],
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    // failed or empty
                    if (snap.hasError ||
                        (snap.data == null) ||
                        (snap.data!.isEmpty)) {
                      return _noImageBox();
                    }

                    final url = snap.data!;
                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[200],
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => _noImageBox(),
                      fadeInDuration: const Duration(milliseconds: 120),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.name ?? 'Unnamed',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v.address ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber[700], size: 18),
                        const SizedBox(width: 4),
                        Text(
                          (v.rating ?? 0).toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          distanceText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------ Data model ------------------

class VenueData {
  final String? placeId;
  final String? name;
  final String? address;
  final String? description;
  final double? lat;
  final double? lng;
  double? rating; // mutable to update after rating fetch
  final String? thumbPath; // optional small image for lists (faster)
  final String? category;
  double? distanceMeters;
  final List<String> imagePaths; // first used as cover

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

/// ------------------ Places service ------------------

class _PlacesSvc {
  final String apiKey;
  _PlacesSvc(this.apiKey);

  Uri _uri(String path, Map<String, String> q) =>
      Uri.https('maps.googleapis.com', path, {...q, 'key': apiKey});

  /// Details (only rating)
  Future<Map<String, dynamic>?> details(String placeId) async {
    if (apiKey.isEmpty) return null;
    final uri = _uri('/maps/api/place/details/json', {
      'place_id': placeId,
      'fields': ['rating', 'user_ratings_total'].join(','),
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['status'] != 'OK') return null;
    return j['result'] as Map<String, dynamic>;
  }
}
